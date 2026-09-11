## Versioned, module-based save/load.
##
## Each gameplay system registers a named module with collect/apply callables.
## Unknown modules are ignored on load (forward compatible). Missing modules
## keep their runtime defaults (backward compatible). Version bumps go through
## `_migrate()` so old JSON keeps loading as the game grows.
class_name SaveSystem
extends Node

const SAVE_VERSION: int = 3
const FORMAT_ID: String = "wildfall-save"
const SAVE_DIR: String = "user://saves"
const SAVE_PATH: String = "user://saves/slot_1.json"
const SETTINGS_PATH: String = "user://settings.json"
const AUTOSAVE_INTERVAL_SEC: float = 300.0
const AUTOSAVE_KEEP: int = 2
const APPLY_ORDER: PackedStringArray = [
	"world", "time", "weather", "status", "technology", "buildings", "player", "camera"
]

static var _autosave_enabled: bool = true
static var _settings_loaded: bool = false

signal game_saved(path: String)
signal game_loaded(path: String)
signal save_failed(reason: String)

var event_bus: Node = null
var player_ref: Player = null
var world_generator_ref: WorldGenerator = null

var _collectors: Dictionary = {}
var _appliers: Dictionary = {}
var _autosave_elapsed: float = 0.0
var last_save_path: String = ""

func _ready() -> void:
	event_bus = get_node_or_null("../GameEventBus")
	_ensure_save_dir()
	load_settings()

func _process(delta: float) -> void:
	if not is_autosave_enabled():
		return
	if _collectors.is_empty():
		return
	var tree := get_tree()
	if tree != null and tree.paused:
		return
	_autosave_elapsed += delta
	if _autosave_elapsed >= AUTOSAVE_INTERVAL_SEC:
		_autosave_elapsed = 0.0
		save_autosave()

func set_player(p: Player) -> void:
	player_ref = p

func set_world_generator(world_generator: WorldGenerator) -> void:
	world_generator_ref = world_generator

## Register (or replace) a named save module. Collect must return a Dictionary
## or Array of JSON-safe values. Apply receives that payload on load.
func register_module(module_name: String, collect: Callable, apply: Callable) -> void:
	if module_name == "":
		return
	_collectors[module_name] = collect
	_appliers[module_name] = apply

func clear_modules() -> void:
	_collectors.clear()
	_appliers.clear()

func save_manual() -> bool:
	return save_game(_unique_path("manual"), "manual")

func save_autosave() -> bool:
	var ok: bool = save_game(_unique_path("autosave"), "autosave")
	if ok:
		prune_autosaves()
	return ok

func save_game(path: String = SAVE_PATH, kind: String = "manual") -> bool:
	_ensure_save_dir()
	var modules: Dictionary = {}
	for module_name in _collectors:
		var payload: Variant = _collectors[module_name].call()
		modules[str(module_name)] = payload
	# Fallback so a save still works if Main has not registered modules yet
	# (older tests / partial boots).
	if modules.is_empty():
		modules = _legacy_collect()
	var save_data: Dictionary = {
		"format": FORMAT_ID,
		"version": SAVE_VERSION,
		"kind": kind,
		"game_mode": GameSession.game_mode,
		"timestamp": Time.get_unix_time_from_system(),
		"modules": modules
	}
	var json_string: String = JSON.stringify(save_data, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		save_failed.emit("Could not open file for writing: %s" % path)
		return false
	file.store_string(json_string)
	file.close()
	print("Game saved to %s" % path)
	last_save_path = path
	game_saved.emit(path)
	return true

func load_game(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		save_failed.emit("Save file not found: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		save_failed.emit("Could not open file for reading: %s" % path)
		return false
	var json_string: String = file.get_as_text()
	file.close()
	var result: Variant = JSON.parse_string(json_string)
	if result == null or typeof(result) != TYPE_DICTIONARY:
		save_failed.emit("Invalid JSON in save file: %s" % path)
		return false
	var save_data: Dictionary = migrate(result as Dictionary)
	if not _validate_save_data(save_data):
		save_failed.emit("Save file is missing required modules")
		return false
	GameSession.set_game_mode(str(save_data.get("game_mode", GameSession.MODE_SURVIVAL)))
	_apply_save_data(save_data)
	print("Game loaded from %s" % path)
	game_loaded.emit(path)
	return true

## Public so tests and tools can inspect migrations.
func migrate(data: Dictionary) -> Dictionary:
	var version: int = int(data.get("version", 1))
	var current: Dictionary = data.duplicate(true)
	if version <= 1 or not current.has("modules"):
		current = _migrate_v1_to_v2(current)
		version = 2
	# Future: while version < SAVE_VERSION: current = _migrate_from(version, current)
	current["version"] = SAVE_VERSION
	current["format"] = FORMAT_ID
	return current

func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)

func has_any_save() -> bool:
	return not list_saves().is_empty()

func most_recent_save_path() -> String:
	var entries: Array[Dictionary] = list_save_entries()
	if entries.is_empty():
		return ""
	return str(entries[0].get("path", ""))

static func is_autosave_enabled() -> bool:
	load_settings()
	return _autosave_enabled

static func set_autosave_enabled(enabled: bool) -> void:
	_autosave_enabled = enabled
	_settings_loaded = true
	_write_settings()

static func load_settings() -> void:
	if _settings_loaded:
		return
	_settings_loaded = true
	if not FileAccess.file_exists(SETTINGS_PATH):
		_autosave_enabled = true
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	_autosave_enabled = bool(data.get("autosave_enabled", true))

static func _write_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"autosave_enabled": _autosave_enabled}, "\t"))
	file.close()

func delete_save(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var abs_path: String = ProjectSettings.globalize_path(path)
	var err: Error = DirAccess.remove_absolute(abs_path)
	if err != OK:
		push_warning("SaveSystem: failed to delete %s (error %d)" % [path, err])
		return false
	return true

func list_saves() -> Array[String]:
	var saves: Array[String] = []
	for entry in list_save_entries():
		saves.append(str(entry.get("path", "")))
	return saves

## Newest first. Each entry: path, kind, timestamp, seed, day, when.
static func list_save_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return entries
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var path: String = "%s/%s" % [SAVE_DIR, file_name]
			var summary: Dictionary = peek_save_summary(path)
			if not summary.is_empty():
				entries.append(summary)
		file_name = dir.get_next()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("timestamp", 0)) > int(b.get("timestamp", 0))
	)
	return entries

func prune_autosaves() -> void:
	var autos: Array[Dictionary] = []
	for entry in list_save_entries():
		if str(entry.get("kind", "")) == "autosave":
			autos.append(entry)
	for i in range(AUTOSAVE_KEEP, autos.size()):
		delete_save(str(autos[i].get("path", "")))

func _unique_path(prefix: String) -> String:
	_ensure_save_dir()
	var stamp: int = int(Time.get_unix_time_from_system())
	var path: String = "%s/%s_%d.json" % [SAVE_DIR, prefix, stamp]
	var extra: int = 1
	while FileAccess.file_exists(path):
		path = "%s/%s_%d_%d.json" % [SAVE_DIR, prefix, stamp, extra]
		extra += 1
	return path

func get_save_summary(path: String = SAVE_PATH) -> Dictionary:
	return peek_save_summary(path)

static func peek_save_summary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var raw: Dictionary = parsed
	var kind: String = str(raw.get("kind", ""))
	if kind == "":
		var file_name: String = path.get_file()
		if file_name.begins_with("autosave_"):
			kind = "autosave"
		else:
			kind = "manual"
	var stamp: int = int(raw.get("timestamp", 0))
	var modules: Dictionary = raw.get("modules", {})
	if modules.is_empty() and raw.has("world"):
		modules = {"world": raw.get("world", {}), "time": {}, "player": raw.get("player", {})}
	var world: Dictionary = modules.get("world", {})
	var time_mod: Dictionary = modules.get("time", {})
	var mode: String = str(raw.get("game_mode", ""))
	if mode == "":
		mode = str(world.get("game_mode", GameSession.MODE_SURVIVAL))
	if mode != GameSession.MODE_CREATIVE:
		mode = GameSession.MODE_SURVIVAL
	return {
		"path": path,
		"kind": kind,
		"game_mode": mode,
		"version": int(raw.get("version", 0)),
		"timestamp": stamp,
		"seed": int(world.get("seed", 0)),
		"day": int(time_mod.get("current_day", 1)),
		"when": _format_time(stamp)
	}

static func _format_time(unix_ts: int) -> String:
	if unix_ts <= 0:
		return "unknown time"
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(unix_ts)
	return "%04d-%02d-%02d  %02d:%02d" % [
		int(d.get("year", 0)), int(d.get("month", 0)), int(d.get("day", 0)),
		int(d.get("hour", 0)), int(d.get("minute", 0))
	]

func _migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	var player: Dictionary = data.get("player", {})
	var world: Dictionary = data.get("world", {})
	return {
		"format": FORMAT_ID,
		"version": 2,
		"game_mode": GameSession.MODE_SURVIVAL,
		"timestamp": data.get("timestamp", Time.get_unix_time_from_system()),
		"modules": {
			"player": player,
			"world": {"seed": int(world.get("seed", 0))},
			"time": {
				"current_hour": float(data.get("game_time", 6.0)),
				"current_day": int(data.get("day_number", 1))
			},
			"weather": {},
			"status": {},
			"buildings": [],
			"camera": {"rotation": 0.0}
		}
	}

func _validate_save_data(data: Dictionary) -> bool:
	if not data.has("modules"):
		return false
	var modules: Dictionary = data["modules"]
	return modules.has("player") and modules.has("world")

func _apply_save_data(data: Dictionary) -> void:
	var modules: Dictionary = data.get("modules", {})
	var applied: Dictionary = {}
	for module_name in APPLY_ORDER:
		if modules.has(module_name) and _appliers.has(module_name):
			_appliers[module_name].call(modules[module_name])
			applied[module_name] = true
	for module_name in modules:
		if applied.has(module_name):
			continue
		if _appliers.has(module_name):
			_appliers[module_name].call(modules[module_name])

func _legacy_collect() -> Dictionary:
	var data: Dictionary = {
		"player": {
			"position": {"x": 0.0, "y": 0.0},
			"health": {},
			"hunger": {},
			"inventory": {},
			"equipped_tool": "hand"
		},
		"world": {"seed": 0}
	}
	if player_ref != null:
		var pos: Vector2 = player_ref.get_world_position()
		data["player"]["position"] = {"x": pos.x, "y": pos.y}
		if player_ref.health_component != null:
			data["player"]["health"] = player_ref.health_component.serialize()
		if player_ref.hunger_component != null:
			data["player"]["hunger"] = player_ref.hunger_component.serialize()
		if player_ref.inventory != null:
			data["player"]["inventory"] = player_ref.inventory.serialize()
		data["player"]["equipped_tool"] = player_ref.equipped_tool
	if world_generator_ref != null:
		data["world"]["seed"] = world_generator_ref.get_seed()
	return data

func _ensure_save_dir() -> void:
	if DirAccess.open(SAVE_DIR) != null:
		return
	var root := DirAccess.open("user://")
	if root == null:
		push_warning("SaveSystem: could not open user://")
		return
	var err: Error = root.make_dir_recursive("saves")
	if err != OK:
		push_warning("SaveSystem: could not create %s (error %d)" % [SAVE_DIR, err])
