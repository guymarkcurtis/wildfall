## Handles saving and loading game state.
class_name SaveSystem
extends Node

const SAVE_VERSION: int = 1
const SAVE_PATH: String = "user://savegame.json"

# Signals
signal game_saved(path: String)
signal game_loaded(path: String)
signal save_failed(reason: String)

## Save game state to disk.
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
	game_saved.emit(path)
	return true

## Load game state from disk.
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
	game_loaded.emit(path)
	return true

## Collect all game state for saving.
func _collect_save_data() -> Dictionary:
	var data: Dictionary = {
		"player": {
			"position": Vector2(0, 0),
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

	# Save player state (placeholder - would connect to actual player)
	var player := get_node_or_null("/root/Main/Player") as Node
	if player:
		data["player"]["position"] = player.global_position

	# Save world state (placeholder)
	var world_gen := get_node_or_null("/root/WorldGenerator") as Node
	if world_gen:
		data["world"]["seed"] = world_gen.get("seed", 0)

	return data

## Validate save data structure.
func _validate_save_data(data: Dictionary) -> bool:
	return data.get("version") == SAVE_VERSION and data.has("player") and data.has("world")

## Apply loaded save data to game state.
func _apply_save_data(data: Dictionary) -> void:
	# Restore player position
	var player := get_node_or_null("/root/Main/Player") as Node
	if player and data.get("player"):
		var pos: Vector2 = data["player"].get("position", Vector2(0, 0))
		player.global_position = pos

	# Restore world (placeholder)
	var world_gen := get_node_or_null("/root/WorldGenerator") as Node
	if world_gen and data.get("world"):
		# Would regenerate world from saved seed and modifications

## Delete a save file.
func delete_save(path: String = SAVE_PATH) -> bool:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return true
	return false

## Check if a save file exists.
func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)

## List all save files.
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
