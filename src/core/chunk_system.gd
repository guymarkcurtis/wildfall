## Manages chunk-based world generation and loading.
## Each chunk is a fixed-size tile area that can be generated, loaded, and unloaded.
extends Node

const CHUNK_SIZE: int = 16  ## tiles per chunk side
const GENERATOR_VERSION: int = 1

# Chunk data storage: chunk_coords -> ChunkData
var _chunks: Dictionary = {}
var _loaded_chunks: Array[Vector2i] = []
var _seed: int = 0

# Signals
signal chunk_generated(chunk_coords: Vector2i)
signal chunk_unloaded(chunk_coords: Vector2i)
signal chunks_changed

func _ready() -> void:
	seed(get_tree().get_root().get_process_time())

## Set the world seed deterministically.
func set_seed(new_seed: int) -> void:
	_seed = new_seed
	_generate_chunk_seed(Vector2i(0, 0))  # prime the stream

## Get a deterministic random seed for a given chunk coordinate.
func get_chunk_random_seed(chunk_coords: Vector2i) -> int:
	var hasher = HashingContext.new()
	hasher.start()
	hasher.hash_int(_seed)
	hasher.hash_int(chunk_coords.x)
	hasher.hash_int(chunk_coords.y)
	hasher.hash_int(GENERATOR_VERSION)
	var hash_bytes = hasher.finish()
	return hash_bytes[0] | (hash_bytes[1] << 8) | (hash_bytes[2] << 16) | (hash_bytes[3] << 24)

## Get chunk coordinates from world tile position.
static func world_to_chunk_coords(tile_pos: Vector2i) -> Vector2i:
	return Vector2i(tile_pos.x / CHUNK_SIZE, tile_pos.y / CHUNK_SIZE)

## Get world tile position from chunk coordinates.
static func chunk_coords_to_world_start(chunk_coords: Vector2i) -> Vector2i:
	return Vector2i(chunk_coords.x * CHUNK_SIZE, chunk_coords.y * CHUNK_SIZE)

## Generate and store chunk data for a given coordinate.
func generate_chunk(chunk_coords: Vector2i) -> Variant:
	if _chunks.has(chunk_coords):
		return _chunks[chunk_coords]

	var random_seed := get_chunk_random_seed(chunk_coords)
	var chunk_data := _generate_chunk_data(chunk_coords, random_seed)
	_chunks[chunk_coords] = chunk_data
	chunk_generated.emit(chunk_coords)
	chunks_changed.emit()
	return chunk_data

## Unload a chunk and free its data.
func unload_chunk(chunk_coords: Vector2i) -> void:
	if _chunks.has(chunk_coords):
		_chunks.erase(chunk_coords)
		if chunk_coords in _loaded_chunks:
			_loaded_chunks.erase(chunk_coords)
		chunk_unloaded.emit(chunk_coords)
		chunks_changed.emit()

## Unload all chunks.
func unload_all_chunks() -> void:
	_chunks.clear()
	_loaded_chunks.clear()
	chunks_changed.emit()

## Get all currently loaded chunk coordinates.
func get_loaded_chunks() -> Array[Vector2i]:
	return _loaded_chunks.duplicate()

## Check if a chunk has been generated.
func has_chunk(chunk_coords: Vector2i) -> bool:
	return _chunks.has(chunk_coords)

## Get the seed used for this world.
func get_seed() -> int:
	return _seed

## Placeholder: generate chunk data structure.
## Override or replace with actual world generation logic.
func _generate_chunk_data(chunk_coords: Vector2i, random_seed: int) -> Dictionary:
	return {
		"coords": chunk_coords,
		"elevation": [],
		"moisture": [],
		"temperature": [],
		"biome": "",
		"terrain": [],
		"vegetation": [],
		"resources": [],
		"entities": [],
		"generated": true
	}
