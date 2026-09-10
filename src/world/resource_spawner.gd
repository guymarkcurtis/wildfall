## Places resource nodes deterministically across the world.
class_name ResourceSpawner
extends Node

const RESOURCE_TYPES: PackedStringArray = [
	"tree", "rock", "fibre", "berry_bush", "iron_ore", "coal", "gold_ore"
]

var _resources: Dictionary = {}  # str(Vector2i) -> Dictionary

# Signals
signal resource_placed(coords: Vector2i, resource_type: String)
signal resources_cleared

## Initialize with world seed.
func initialize(seed: int) -> void:
	_resources.clear()

## Get all resources in a range.
func get_resources_in_range(center: Vector2i, radius: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for key in _resources:
		var coords: Vector2i = _str_to_vec2i(key)
		if coords.distance_to(center) <= radius:
			results.append(_resources[key])
	return results

## Get a specific resource.
func get_resource(coords: Vector2i) -> Dictionary:
	return _resources.get(_str_to_vec2i(coords))

## Check if a resource exists at a location.
func has_resource(coords: Vector2i) -> bool:
	return _resources.has(_str_to_vec2i(coords))

## Remove a resource.
func remove_resource(coords: Vector2i) -> bool:
	if _resources.has(_str_to_vec2i(coords)):
		_resources.erase(_str_to_vec2i(coords))
		return true
	return false

## Get all resources as a dictionary.
func get_all_resources() -> Dictionary:
	return _resources.duplicate()

## Serialize for saving.
func serialize() -> Dictionary:
	return _resources.duplicate()

## Deserialize for loading.
func deserialize(data: Dictionary) -> void:
	_resources = data

## Generate resources for a chunk.
func generate_chunk_resources(chunk_coords: Vector2i, seed: int) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = _get_chunk_seed(chunk_coords, seed)

	# Generate 5-15 resources per chunk
	var count: int = int(random.randf_range(5, 15))
	for i in range(count):
		var x: int = chunk_coords.x * 16 + int(random.randf_range(0, 15))
		var y: int = chunk_coords.y * 16 + int(random.randf_range(0, 15))
		var coords: Vector2i = Vector2i(x, y)
		if not _resources.has(_str_to_vec2i(coords)):
			var resource_type: String = RESOURCE_TYPES[int(random.randf_range(0, RESOURCE_TYPES.size()))]
			_resources[_str_to_vec2i(coords)] = {
				"coords": coords,
				"type": resource_type,
				"health": _get_resource_health(resource_type),
				"max_health": _get_resource_health(resource_type)
			}
			resource_placed.emit(coords, resource_type)

## Get the health of a resource type.
func _get_resource_health(resource_type: String) -> int:
	match resource_type:
		"tree": return 5
		"rock": return 8
		"fibre": return 3
		"berry_bush": return 2
		"iron_ore": return 10
		"coal": return 6
		"gold_ore": return 12
		_: return 5

## Get deterministic seed for a chunk.
func _get_chunk_seed(chunk_coords: Vector2i, world_seed: int) -> int:
	var hasher := HashingContext.new()
	hasher.start()
	hasher.hash_int(world_seed)
	hasher.hash_int(chunk_coords.x)
	hasher.hash_int(chunk_coords.y)
	var bytes := hasher.finish()
	return bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24)

## Convert Vector2i to string key.
func _str_to_vec2i(key: Vector2i) -> String:
	return "%d,%d" % [key.x, key.y]

## Parse string key back to Vector2i.
func _vec2i_from_str(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
