## Runtime texture-pack loader and export pipeline.
##
## Packs live under user://texture_packs/<pack-id>/ and mirror the asset
## paths listed in PACK_ASSETS. A pack may override only the images it edits;
## all other images fall back to the built-in stock set.
class_name TexturePackManager
extends Node

const ROOT := "user://texture_packs"
const SETTINGS_PATH := "user://texture_packs/settings.json"
const REFERENCE_PACK := "stock_reference"
const REFINEMENT_PACK := "refinement"
const CARD_PATH := "user://texture_packs/stock_texture_card.png"
const MANIFEST_NAME := "manifest.json"
const GROUND_NAMES := ["water", "sand", "grass", "forest", "dirt", "stone", "snow", "mud"]

const PACK_ASSETS: PackedStringArray = [
	"assets/ground/water.png",
	"assets/ground/sand.png",
	"assets/ground/grass.png",
	"assets/ground/forest.png",
	"assets/ground/dirt.png",
	"assets/ground/stone.png",
	"assets/ground/snow.png",
	"assets/ground/mud.png",
	"assets/tiles/wildfall-terrain-atlas.png",
	"assets/tiles/wildfall-water-animation.png",
	"assets/tiles/wildfall-resources-atlas.png",
	"assets/tiles/wildfall-ground-details.png",
	"assets/resources/wildfall-forage-plants.png",
	"assets/characters/explorer-base-walk.png",
	"assets/characters/explorer-storm-walk.png",
	"assets/creatures/alien-creature-roster.png"
]

static var _instance: TexturePackManager = null
static var _active_pack := "stock"
static var _settings_loaded := false
static var _texture_cache: Dictionary = {}

signal texture_pack_changed(pack_id: String)

func _ready() -> void:
	_instance = self
	_load_settings()

func _exit_tree() -> void:
	if _instance == self:
		_instance = null

static func get_active_pack_id() -> String:
	_load_settings()
	return _active_pack

static func get_available_pack_ids() -> PackedStringArray:
	_ensure_root()
	var ids := PackedStringArray(["stock"])
	var directory := DirAccess.open(ROOT)
	if directory == null:
		return ids
	directory.list_dir_begin()
	var name := directory.get_next()
	while name != "":
		if directory.current_is_dir() and not name.begins_with(".") and name != "stock":
			ids.append(name)
		name = directory.get_next()
	ids.sort()
	return ids

static func set_active_pack_id(pack_id: String) -> bool:
	var next := pack_id.strip_edges()
	if next.is_empty() or not get_available_pack_ids().has(next):
		return false
	_active_pack = next
	_settings_loaded = true
	_write_settings()
	_texture_cache.clear()
	if _instance != null:
		_instance.texture_pack_changed.emit(_active_pack)
	return true

static func get_texture(stock_path: String) -> Texture2D:
	_load_settings()
	var cache_key := "%s|%s" % [_active_pack, stock_path]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]
	var image: Image = get_image(stock_path)
	var texture: Texture2D = ImageTexture.create_from_image(image) if image != null and not image.is_empty() else load(stock_path)
	_texture_cache[cache_key] = texture
	return texture

static func get_image(stock_path: String) -> Image:
	_load_settings()
	var override_path := _override_path(stock_path)
	if not override_path.is_empty() and FileAccess.file_exists(override_path):
		var override_image := Image.new()
		if override_image.load(override_path) == OK and not override_image.is_empty():
			return override_image
	return get_stock_image(stock_path)

static func get_stock_image(path: String) -> Image:
	if path.begins_with("res://assets/ground/"):
		var index := GROUND_NAMES.find(path.get_file().get_basename())
		if index >= 0:
			var generator := TileSetGenerator.new()
			var image := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
			for y in range(256):
				for x in range(256):
					image.set_pixel(x, y, generator.stock_material_colour(index, x, y, 0))
			generator.free()
			return image
	var texture: Texture2D = load(path)
	return texture.get_image() if texture != null else null

## Export an unchanged reference pack plus a contact card and JSON manifest.
## The reference stays safe to overwrite; the editable refinement pack is a
## separate copy created only once.
static func export_stock_reference() -> Dictionary:
	_ensure_root()
	var pack_root := "%s/%s" % [ROOT, REFERENCE_PACK]
	_ensure_directory(pack_root)
	for relative_path in PACK_ASSETS:
		_copy_stock_asset(relative_path, pack_root)
	_write_manifest(pack_root, REFERENCE_PACK, "Unedited stock reference. Use this for comparison or as an AI-editor input.")
	_write_contact_card()
	return {
		"pack_path": ProjectSettings.globalize_path(pack_root),
		"card_path": ProjectSettings.globalize_path(CARD_PATH)
	}

static func create_refinement_pack() -> Dictionary:
	_ensure_root()
	var pack_root := "%s/%s" % [ROOT, REFINEMENT_PACK]
	var is_new: bool = DirAccess.open(pack_root) == null
	_ensure_directory(pack_root)
	for relative_path in PACK_ASSETS:
		if not FileAccess.file_exists("%s/%s" % [pack_root, relative_path]):
			_copy_stock_asset(relative_path, pack_root)
	_write_manifest(pack_root, REFINEMENT_PACK, "Editable override pack. Keep atlas dimensions and cell layout unchanged.")
	return {"pack_path": ProjectSettings.globalize_path(pack_root), "created": is_new}

static func open_pack_folder() -> void:
	_ensure_root()
	OS.shell_open(ProjectSettings.globalize_path(ROOT))

static func _override_path(stock_path: String) -> String:
	if _active_pack == "stock":
		return ""
	var relative := stock_path.trim_prefix("res://")
	return "%s/%s/%s" % [ROOT, _active_pack, relative]

static func _load_settings() -> void:
	if _settings_loaded:
		return
	_settings_loaded = true
	_ensure_root()
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		var requested := str((parsed as Dictionary).get("active_pack", "stock"))
		if get_available_pack_ids().has(requested):
			_active_pack = requested

static func _write_settings() -> void:
	_ensure_root()
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"active_pack": _active_pack}, "\t"))
		file.close()

static func _ensure_root() -> void:
	_ensure_directory(ROOT)

static func _ensure_directory(path: String) -> void:
	if DirAccess.open(path) != null:
		return
	var root := DirAccess.open("user://")
	if root != null:
		root.make_dir_recursive(path.trim_prefix("user://"))

static func _copy_stock_asset(relative_path: String, pack_root: String) -> void:
	var source := "res://%s" % relative_path
	var image := get_stock_image(source)
	if image == null or image.is_empty():
		return
	var destination := "%s/%s" % [pack_root, relative_path]
	_ensure_directory(destination.get_base_dir())
	image.save_png(destination)

static func _write_manifest(pack_root: String, pack_id: String, description: String) -> void:
	var file := FileAccess.open("%s/%s" % [pack_root, MANIFEST_NAME], FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"schema": "riftwake.texture-pack",
		"schema_version": 2,
		"id": pack_id,
		"description": description,
		"assets": _asset_metadata(),
		"rules": [
			"Keep image dimensions and atlas cell layouts unchanged.",
			"You can omit untouched files; the game falls back to stock textures.",
			"Texture packs only affect presentation, never terrain collision or save data."
		]
	}, "\t"))
	file.close()

## A deliberately plain JSON contract for image editors and external tools.
## Each item points to one exported PNG and explains both what it depicts and
## how the game reads its pixels. Keep this ordering aligned with PACK_ASSETS.
static func _asset_metadata() -> Array[Dictionary]:
	var assets: Array[Dictionary] = []
	var surface_descriptions := {
		"water": "Water surface used for oceans, rivers, lakes, and swamp pools.",
		"sand": "Sandy ground used across beach and desert areas.",
		"grass": "Open grassy ground used across temperate plains.",
		"forest": "Leafy forest-floor ground used beneath wooded areas.",
		"dirt": "Packed earth used in temperate, volcanic, and worn terrain.",
		"stone": "Bare rocky ground used in mountains, desert rock, and volcanic terrain.",
		"snow": "Snow-covered ground used throughout arctic areas.",
		"mud": "Wet muddy ground used in swamp areas."
	}
	for surface in GROUND_NAMES:
		assets.append({
			"path": "assets/ground/%s.png" % surface,
			"name": "%s surface" % surface.capitalize(),
			"purpose": surface_descriptions[surface],
			"used_for": ["biome background", "world ground rendering"],
			"layout": {
				"kind": "seamless_surface",
				"width": 256,
				"height": 256,
				"repeat": "world-space; tile seamlessly on all four edges"
			},
			"editor_note": "Keep this at 256 x 256 pixels and make opposite edges tile seamlessly."
		})
	assets.append_array([
		{
			"path": "assets/tiles/wildfall-terrain-atlas.png",
			"name": "Terrain atlas",
			"purpose": "Logical terrain tiles used by Godot's automatic terrain-edge and corner blending.",
			"used_for": ["terrain TileSet", "water collision reference"],
			"layout": {"kind": "atlas", "columns": 4, "rows": 2, "cell_order": "row 1: water, sand, grass, forest; row 2: dirt, stone, snow, mud"},
			"editor_note": "Do not move, add, or remove cells. Artwork can change, but cell positions are game data."
		},
		{
			"path": "assets/tiles/wildfall-water-animation.png",
			"name": "Water animation atlas",
			"purpose": "Animated water overlay frames.",
			"used_for": ["water animation"],
			"layout": {"kind": "animation_strip", "columns": 4, "rows": 1, "frame_order": "left to right, frames 1 through 4"},
			"editor_note": "Keep all four frames the same size and in their current left-to-right order."
		},
		{
			"path": "assets/tiles/wildfall-resources-atlas.png",
			"name": "Resource-node atlas",
			"purpose": "World resource nodes the player harvests.",
			"used_for": ["trees", "rocks", "fibre", "berries", "ore nodes"],
			"layout": {"kind": "atlas", "columns": 4, "rows": 2, "cell_order": "row 1: tree, rock, fibre, berry; row 2: iron ore, coal, gold ore, crystal"},
			"editor_note": "Keep each resource in its assigned cell so harvesting visuals continue to match the resource type."
		},
		{
			"path": "assets/tiles/wildfall-ground-details.png",
			"name": "Ground-detail atlas",
			"purpose": "Small decorative details scattered over biome ground.",
			"used_for": ["grass tufts", "pebbles", "ambient ground decoration"],
			"layout": {"kind": "atlas", "columns": 4, "rows": 2, "cell_order": "eight decorative variants, read left to right then top to bottom"},
			"editor_note": "Keep the 4 by 2 grid and transparent backgrounds."
		},
		{
			"path": "assets/resources/wildfall-forage-plants.png",
			"name": "Forage-plant atlas",
			"purpose": "Small harvestable and decorative plant variants.",
			"used_for": ["forage visuals", "ground vegetation"],
			"layout": {"kind": "atlas", "columns": 2, "rows": 2, "cell_order": "four variants, read left to right then top to bottom"},
			"editor_note": "Keep the 2 by 2 grid and transparent backgrounds."
		},
		{
			"path": "assets/characters/explorer-base-walk.png",
			"name": "Explorer base walk sheet",
			"purpose": "Player explorer appearance in regular conditions.",
			"used_for": ["player walking animation"],
			"layout": {"kind": "sprite_sheet", "columns": 4, "rows": 2, "frame_order": "four walking frames left to right; male row first, female row second"},
			"editor_note": "Keep the frame grid, facing, and transparent background."
		},
		{
			"path": "assets/characters/explorer-storm-walk.png",
			"name": "Explorer storm walk sheet",
			"purpose": "Player explorer appearance during storm conditions.",
			"used_for": ["player storm walking animation"],
			"layout": {"kind": "sprite_sheet", "columns": 4, "rows": 2, "frame_order": "four walking frames left to right; male row first, female row second"},
			"editor_note": "Keep the frame grid, facing, and transparent background."
		},
		{
			"path": "assets/creatures/alien-creature-roster.png",
			"name": "Creature roster sheet",
			"purpose": "Creature appearance variants used by the streamed wildlife system.",
			"used_for": ["boar", "wolf", "deer", "polar bear", "alien wildlife"],
			"layout": {"kind": "sprite_sheet", "columns": 4, "rows": 2, "frame_order": "idle row first, movement row second; variants read left to right"},
			"editor_note": "Keep the 4 by 2 grid, variant positions, and transparent background."
		}
	])
	return assets

static func _write_contact_card() -> void:
	var columns := 2
	var cell_size := Vector2i(480, 300)
	var rows := ceili(float(PACK_ASSETS.size()) / float(columns))
	var card := Image.create_empty(columns * cell_size.x, rows * cell_size.y, false, Image.FORMAT_RGBA8)
	card.fill(Color(0.055, 0.075, 0.055, 1.0))
	for index in range(PACK_ASSETS.size()):
		var image := get_stock_image("res://%s" % PACK_ASSETS[index])
		if image == null or image.is_empty():
			continue
		var copy := image.duplicate()
		if copy.get_format() != card.get_format():
			copy.convert(card.get_format())
		copy.resize(cell_size.x - 24, cell_size.y - 24, Image.INTERPOLATE_LANCZOS)
		var x := (index % columns) * cell_size.x + 12
		var y := (index / columns) * cell_size.y + 12
		card.blit_rect(copy, Rect2i(Vector2i.ZERO, copy.get_size()), Vector2i(x, y))
	card.save_png(CARD_PATH)
