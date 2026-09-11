## Handles saving and loading game state as JSON in user://.
## Collects and applies real game state: player position, health, hunger,
## inventory, and the world seed. There are no autoloads in this project,
## so typed references are injected by Main.
class_name SaveSystem
extends Node

const SAVE_VERSION: int = 1
const SAVE_PATH: String = "user://savegame.json"

# Signals
signal game_saved(path: String)
signal game_loaded(path: String)
signal save_failed(reason: String)

# References (injected by Main; resolved from the scene tree)
var event_bus: Node = null
var player_ref: Player = null
var world_generator_ref: WorldGenerator = null

func _ready() -> void:
	event_bus = get_node_or_null("../GameEventBus")

## Give the save system a typed reference to the player.
func set_player(p: Player) -> void:
	player_ref = p

## Give the save system a typed reference to the world generator.
func set_world_generator(world_generator: WorldGenerator) -> void:
	world_generator_ref = world_generator

## Save game state to disk. Returns true on success.
func save_game(path: String = SAVE_PATH) -> bool:
	var save_data: Dictionary = _collect_save_data()
	save_data["version"] = SAVE_VERSION
	save_data["timestamp"] = Time.get_unix_time_from_system()

	var json_string: String = JSON.stringify(save_data, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		save_failed.emit("Could not open file for writing: %s" % path)
		return false

	file.store_string(json_string)
	file.close()
	print("Game saved to %s" % path)
	game_saved.emit(path)
	return true

## Load game state from disk. Returns true on success.
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
	if result == null:
		save_failed.emit("Invalid JSON in save file: %s" % path)
		return false

	var save_data: Dictionary = result as Dictionary
	if not _validate_save_data(save_data):
		save_failed.emit("Save file version mismatch or invalid data")
		return false

	_apply_save_data(save_data)
	print("Game loaded from %s" % path)
	game_loaded.emit(path)
	return true

## Collect all game state for saving (JSON-safe values only).
func _collect_save_data() -> Dictionary:
	var data: Dictionary = {
		"player": {
			"position": {"x": 0.0, "y": 0.0},
			"health": {},
			"hunger": {},
			"inventory": {}
		},
		"world": {
			"seed": 0,
			"chunks": {}
		},
		"game_time": 0.0,
		"day_number": 0
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

	if world_generator_ref != null:
		data["world"]["seed"] = world_generator_ref.get_seed()

	return data

## Validate save data structure.
func _validate_save_data(data: Dictionary) -> bool:
	return data.get("version") == SAVE_VERSION and data.has("player") and data.has("world")

## Apply loaded save data to game state.
func _apply_save_data(data: Dictionary) -> void:
	# If the save belongs to a different world, regenerate first: the event
	# bus routes this to Main, which rebuilds chunks/resources synchronously
	# (and teleports the player back to the spawn point).
	var world: Dictionary = data.get("world", {})
	var saved_seed: int = int(world.get("seed", 0))
	if world_generator_ref != null and event_bus != null \
			and saved_seed != world_generator_ref.get_seed():
		event_bus.world_seed_set.emit(saved_seed)

	if player_ref == null or not data.has("player"):
		return

	# Restore player state (after any world regeneration above).
	var player_data: Dictionary = data["player"]
	var pos: Dictionary = player_data.get("position", {"x": 0.0, "y": 0.0})
	player_ref.global_position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))

	if player_ref.health_component != null and player_data.has("health"):
		player_ref.health_component.deserialize(player_data["health"])
	if player_ref.hunger_component != null and player_data.has("hunger"):
		player_ref.hunger_component.deserialize(player_data["hunger"])
	if player_ref.inventory != null and player_data.has("inventory"):
		player_ref.inventory.deserialize(player_data["inventory"])

## Delete a save file.
## (DirAccess has no remove_absolute() in Godot 4; remove_file() takes a
## path relative to the opened directory.)
func delete_save(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	var err: Error = dir.remove_file(path)
	if err != OK:
		push_warning("SaveSystem: failed to delete %s (error %d)" % [path, err])
		return false
	return true

## Check if a save file exists.
func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)

## List all save files in user://.
func list_saves() -> Array[String]:
	var saves: Array[String] = []
	var dir := DirAccess.open("user://")
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if file_name.begins_with("save") and file_name.ends_with(".json"):
				saves.append(file_name)
			file_name = dir.get_next()
	return saves
