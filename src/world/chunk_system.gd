## Manages chunk lifecycle: generation, loading, unloading.
class_name ChunkSystem
extends Node

const CHUNK_SIZE: int = 16
const TILE_SIZE: int = 32
const PIXELS_PER_CHUNK: int = TILE_SIZE * CHUNK_SIZE
const GENERATOR_VERSION: int = 1
const DEFAULT_VIEWPORT_RADIUS: int = 2

# Chunk data storage
var _chunks: Dictionary = {}  # str(Vector2i) -> Dictionary
var _chunk_nodes: Dictionary = {}  # str(Vector2i) -> Node

# Player tracking
var _player_position: Vector2i = Vector2i(0, 0)
var _viewport_radius: int = DEFAULT_VIEWPORT_RADIUS

# World seed
var _seed: int = 0

# Signals
signal chunk_generated(chunk_coords: Vector2i)
signal chunk_unloaded(chunk_coords: Vector2i)
signal chunks_changed
signal player_chunk_changed(old_chunk: Vector2i, new_chunk: Vector2i)

## Initialize with a world seed.
func initialize(seed: int) -> void:
	_seed = seed
	_chunks.clear()
	_chunk_nodes.clear()
	# Sentinel so the first update_player_position() call always triggers the
	# initial chunk load, even when the player starts in chunk (0, 0).
	_player_position = Vector2i(-999999, -999999)

## Update player position and manage chunk loading/unloading.
func update_player_position(world_position: Vector2) -> void:
	var new_chunk: Vector2i = world_to_chunk_coords(world_position)

	if new_chunk != _player_position:
		var old_chunk: Vector2i = _player_position
		_player_position = new_chunk
		_update_chunks()
		player_chunk_changed.emit(old_chunk, new_chunk)

## Set the viewport radius.
func set_viewport_radius(radius: int) -> void:
	_viewport_radius = max(1, radius)
	_update_chunks()

## Get the current viewport radius.
func get_viewport_radius() -> int:
	return _viewport_radius

## Get the player's current chunk coordinate.
func get_player_chunk() -> Vector2i:
	return _player_position

## Generate a chunk if it doesn't exist.
func generate_chunk(chunk_coords: Vector2i) -> Dictionary:
	var key: String = _key(chunk_coords)
	if _chunks.has(key):
		return _chunks[key]

	var world_gen := get_node_or_null("../WorldGenerator") as Node
	if world_gen:
		var data: Dictionary = world_gen.call("generate_chunk", chunk_coords, _seed)
		_chunks[key] = data
		chunk_generated.emit(chunk_coords)
		chunks_changed.emit()
		return data

	return {}

## Unload a specific chunk.
func unload_chunk(chunk_coords: Vector2i) -> void:
	var key: String = _key(chunk_coords)
	if _chunks.has(key):
		_chunks.erase(key)
		if _chunk_nodes.has(key):
			_chunk_nodes.erase(key)
		chunk_unloaded.emit(chunk_coords)
		chunks_changed.emit()

## Unload all chunks.
func unload_all() -> void:
	_chunks.clear()
	_chunk_nodes.clear()
	chunks_changed.emit()

## Get all currently loaded chunk coordinates.
func get_loaded_chunks() -> Array:
	var result: Array = []
	for k in _chunks.keys():
		result.append(_str_to_vec2i(k))
	return result

## Cheap count for diagnostics; avoids allocating an array every frame.
func get_loaded_chunk_count() -> int:
	return _chunks.size()

## Check if a chunk is loaded.
func has_chunk(chunk_coords: Vector2i) -> bool:
	return _chunks.has(_key(chunk_coords))

## Get chunk data.
func get_chunk(chunk_coords: Vector2i) -> Dictionary:
	return _chunks.get(_key(chunk_coords), {})

## Get the world seed.
func get_seed() -> int:
	return _seed

## Update chunks around the player.
func _update_chunks() -> void:
	# Generate chunks in viewport
	for dx in range(-_viewport_radius, _viewport_radius + 1):
		for dy in range(-_viewport_radius, _viewport_radius + 1):
			var chunk_coords: Vector2i = _player_position + Vector2i(dx, dy)
			generate_chunk(chunk_coords)

	# Unload chunks outside viewport
	var keys: Array = _chunks.keys()
	for key in keys:
		var coords: Vector2i = _str_to_vec2i(key)
		if abs(coords.x - _player_position.x) > _viewport_radius or abs(coords.y - _player_position.y) > _viewport_radius:
			unload_chunk(coords)

## Convert a world (pixel) position to chunk coordinates.
## Floors (not truncates) so negative coordinates land in the same chunk
## the terrain renderer draws them in: chunk c covers pixels
## [c * PIXELS_PER_CHUNK, (c + 1) * PIXELS_PER_CHUNK).
static func world_to_chunk_coords(world_position: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_position.x / float(PIXELS_PER_CHUNK))),
		int(floor(world_position.y / float(PIXELS_PER_CHUNK)))
	)

## Convert chunk coordinates to world tile start position.
static func chunk_coords_to_world_start(chunk_coords: Vector2i) -> Vector2i:
	return Vector2i(chunk_coords.x * CHUNK_SIZE, chunk_coords.y * CHUNK_SIZE)

## Internal: create a string key for a chunk coordinate.
func _key(chunk_coords: Vector2i) -> String:
	return "%d,%d" % [chunk_coords.x, chunk_coords.y]

## Internal: parse string key back to Vector2i.
func _str_to_vec2i(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
