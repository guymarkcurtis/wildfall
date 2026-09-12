## Stable seed derivation shared by every procedural world scope.
## Do not use Godot's hash() for generated content: arithmetic mixing keeps
## output stable across engine versions and generation order.
class_name WorldGenerationContext
extends RefCounted

var world_seed: int = 0
var config: WorldGenerationConfig = null

func _init(seed: int = 0, generation_config: WorldGenerationConfig = null) -> void:
	world_seed = seed
	config = generation_config

func chunk_seed(coords: Vector2i) -> int:
	return mix_seed(world_seed, coords.x, coords.y, 0x13579BDF)

func tile_seed(tile: Vector2i, stream: int = 0) -> int:
	return mix_seed(world_seed, tile.x, tile.y, stream + 0x2468ACE)

func cave_seed(cave_id: String, entrance_tile: Vector2i, cave_type_id: String) -> int:
	var id_mix := stable_string_seed(cave_id)
	var type_mix := stable_string_seed(cave_type_id)
	return mix_seed(world_seed ^ id_mix, entrance_tile.x ^ type_mix, entrance_tile.y, 0x5F3759DF)

func cave_identity(entrance_tile: Vector2i, cave_type_id: String) -> String:
	return "%s@%d,%d" % [cave_type_id, entrance_tile.x, entrance_tile.y]

static func mix_seed(base: int, a: int, b: int, stream: int = 0) -> int:
	var mixed: int = base * 73856093
	mixed += a * 19349663
	mixed += b * 83492791
	mixed += stream * 2654435761
	return absi(mixed)

static func stable_string_seed(value: String) -> int:
	var result: int = 216613626
	for byte_value in value.to_utf8_buffer():
		result = int((result ^ int(byte_value)) * 16777619)
	return absi(result)
