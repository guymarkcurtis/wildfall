## Manages chunk lifecycle: generation, loading, unloading.
class_name ChunkSystem
extends Node

const CHUNK_SIZE: int = 16
const TILE_SIZE: int = 32
const PIXELS_PER_CHUNK: int = TILE_SIZE * CHUNK_SIZE
const GENERATOR_VERSION: int = 2
const DEFAULT_VIEWPORT_RADIUS: int = 3

# Chunk data storage
var _chunks: Dictionary = {}  # str(Vector2i) -> Dictionary
var _chunk_nodes: Dictionary = {}  # str(Vector2i) -> Node
## Chunks waiting to have their deterministic data built. Keeping this queue
## separate from the loaded-data map lets streaming spread expensive field
## sampling across frames instead of freezing at each world boundary.
var _pending_generation: Array[Vector2i] = []
## A generated chunk is presented by Main on the following frame. Leaving
## that frame free of more procedural work prevents generation and node/tile
## construction from combining into a missed 60 Hz frame.
var _presentation_frame_due := false

# Player tracking
var _player_position: Vector2i = Vector2i(0, 0)
var _viewport_radius: int = DEFAULT_VIEWPORT_RADIUS

# World seed
var _seed: int = 0
var _config: WorldGenerationConfig = null

# Signals
signal chunk_generated(chunk_coords: Vector2i)
signal chunk_unloaded(chunk_coords: Vector2i)
signal chunks_changed
signal player_chunk_changed(old_chunk: Vector2i, new_chunk: Vector2i)

func _ready() -> void:
	# Main presents queued visuals first (priority 0); streaming data is built
	# afterward (priority 10), ready for the next frame's presentation pass.
	process_priority = 10

## Initialize with a world seed.
func initialize(seed: int, config: WorldGenerationConfig = null) -> void:
	_seed = seed
	_config = config
	if _config == null:
		var world_gen := get_node_or_null("../WorldGenerator") as WorldGenerator
		if world_gen != null:
			_config = world_gen.get_configuration()
	_chunks.clear()
	_chunk_nodes.clear()
	_pending_generation.clear()
	_presentation_frame_due = false
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
	if not is_chunk_in_bounds(chunk_coords):
		return {}

	var world_gen := get_node_or_null("../WorldGenerator") as Node
	if world_gen:
		var data: Dictionary = world_gen.call("generate_chunk", chunk_coords, _seed)
		_chunks[key] = data
		chunk_generated.emit(chunk_coords)
		chunks_changed.emit()
		return data

	return {}

func _process(_delta: float) -> void:
	if _presentation_frame_due:
		_presentation_frame_due = false
		return
	var pending_before := _pending_generation.size()
	_process_pending_generation()
	if _pending_generation.size() < pending_before:
		_presentation_frame_due = true

## Test/tool hook. Normal play honors the configured per-frame budget; callers
## that deliberately need a complete snapshot can drain the queue explicitly.
func flush_pending_generation() -> void:
	while not _pending_generation.is_empty():
		var next: Vector2i = _pending_generation.pop_front()
		if not _chunks.has(_key(next)) and is_chunk_in_bounds(next):
			generate_chunk(next)

func _process_pending_generation() -> void:
	if _pending_generation.is_empty():
		return
	var budget_msec: float = _config.chunk_generation_frame_budget_msec if _config != null else 4.0
	var started_usec: int = Time.get_ticks_usec()
	while not _pending_generation.is_empty():
		var next: Vector2i = _pending_generation.pop_front()
		if not _chunks.has(_key(next)) and is_chunk_in_bounds(next):
			generate_chunk(next)
		# Always finish one queued chunk so a low budget cannot starve loading.
		if float(Time.get_ticks_usec() - started_usec) / 1000.0 >= budget_msec:
			break

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
	_pending_generation.clear()
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

## Cheap queue size for development diagnostics and the headless streaming
## stress test. It intentionally exposes no mutable queue state.
func get_pending_generation_count() -> int:
	return _pending_generation.size()

## Check if a chunk is loaded.
func has_chunk(chunk_coords: Vector2i) -> bool:
	return _chunks.has(_key(chunk_coords))

## Get chunk data.
func get_chunk(chunk_coords: Vector2i) -> Dictionary:
	return _chunks.get(_key(chunk_coords), {})

## Get the world seed.
func get_seed() -> int:
	return _seed

func get_configuration() -> WorldGenerationConfig:
	return _config

func is_chunk_in_bounds(chunk_coords: Vector2i) -> bool:
	return _config == null or _config.is_chunk_in_bounds(chunk_coords)

## Update chunks around the player.
func _update_chunks() -> void:
	# Queue chunks in player-distance order. Generation happens incrementally in
	# _process so moving across a boundary never synchronously creates an entire
	# row/column of expensive environmental fields.
	var wanted: Dictionary = {}
	for dx in range(-_viewport_radius, _viewport_radius + 1):
		for dy in range(-_viewport_radius, _viewport_radius + 1):
			var chunk_coords: Vector2i = _player_position + Vector2i(dx, dy)
			if is_chunk_in_bounds(chunk_coords):
				wanted[chunk_coords] = true
				if not _chunks.has(_key(chunk_coords)) and not _pending_generation.has(chunk_coords):
					_pending_generation.append(chunk_coords)
	_pending_generation = _pending_generation.filter(func(coords: Vector2i) -> bool: return wanted.has(coords))
	_pending_generation.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ad := maxi(absi(a.x - _player_position.x), absi(a.y - _player_position.y))
		var bd := maxi(absi(b.x - _player_position.x), absi(b.y - _player_position.y))
		if ad == bd:
			return a.y < b.y if a.x == b.x else a.x < b.x
		return ad < bd
	)

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
