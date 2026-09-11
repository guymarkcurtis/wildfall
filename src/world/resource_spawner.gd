## Places resource nodes deterministically across the world.
## Spawn positions derive from an arithmetic chunk-seed formula (deterministic
## across engine versions; the built-in hash() is stable today but engine-
## dependent), and resource types follow the terrain biome at each tile.
class_name ResourceSpawner
extends Node

const CHUNK_SIZE: int = 16

# Resource types that can spawn in any biome (fallback).
const DEFAULT_RESOURCE_TYPES: PackedStringArray = [
	"tree", "rock", "fibre", "berry_bush", "plant", "iron_ore", "coal", "gold_ore"
]

# Which resource types are plausible in each biome (WorldGenerator biome ids).
const BIOME_RESOURCE_TYPES: Dictionary = {
	"temperate_forest": ["tree", "tree", "fibre", "berry_bush", "rock", "plant"],
	"grassland": ["fibre", "berry_bush", "berry_bush", "rock", "plant"],
	"mountain": ["rock", "iron_ore", "coal", "gold_ore"],
	"desert": ["rock", "rock", "coal"],
	"arctic": ["rock", "iron_ore"],
	"swamp": ["fibre", "berry_bush", "rock", "plant"],
}

# World tile position (Vector2i) -> resource record.
var _resources: Dictionary = {}
# Chunk coords (Vector2i) -> true. Tracks which chunks have already been
# generated, so re-entering a chunk re-spawns it instead of skipping it.
# (Must be separate from _resources, which is keyed by TILE coords.)
var _generated_chunks: Dictionary = {}

# The world generator (sibling under Main) provides per-tile biome ids.
var world_generator: WorldGenerator = null

# Signals
signal resource_placed(coords: String, resource_type: String)
signal resources_cleared

func _ready() -> void:
	world_generator = get_node_or_null("../WorldGenerator")

## Initialize with world seed (clears all generated resources).
func initialize(seed: int) -> void:
	_resources.clear()
	_generated_chunks.clear()

## Drop the records of a chunk that was unloaded, so that re-entering the
## chunk regenerates its resources. Without this, the tile-keyed _resources
## records outlive the chunk and the chunk spawns nothing on re-entry.
func remove_chunk(chunk_coords: Vector2i) -> void:
	if not _generated_chunks.has(chunk_coords):
		return
	var start: Vector2i = chunk_coords * CHUNK_SIZE
	for tile in _resources.keys():
		if tile.x >= start.x and tile.x < start.x + CHUNK_SIZE \
				and tile.y >= start.y and tile.y < start.y + CHUNK_SIZE:
			_resources.erase(tile)
	_generated_chunks.erase(chunk_coords)

## Get all resources within a Chebyshev radius of a tile.
func get_resources_in_range(center: Vector2i, radius: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for key in _resources:
		var tile: Vector2i = key
		if abs(tile.x - center.x) <= radius and abs(tile.y - center.y) <= radius:
			results.append(_resources[key])
	return results

## Get a specific resource record.
func get_resource(coords: Vector2i) -> Dictionary:
	return _resources.get(coords, {})

## Check if a resource exists at a location.
func has_resource(coords: Vector2i) -> bool:
	return _resources.has(coords)

## Remove a resource.
func remove_resource(coords: Vector2i) -> bool:
	if _resources.has(coords):
		_resources.erase(coords)
		return true
	return false

## Get all resources as a dictionary.
func get_all_resources() -> Dictionary:
	return _resources.duplicate(true)

## All item ids this spawner can drop (across every biome and resource
## type). Main uses this to hide "ghost" crafting recipes whose ingredients
## only exist in creature/crop code from future, not-yet-wired phases.
func get_all_droppable_items() -> Dictionary:
	var item_ids: Dictionary = {}
	for biome_id in BIOME_RESOURCE_TYPES:
		for res_type in BIOME_RESOURCE_TYPES[biome_id]:
			for entry in _get_resource_yields(str(res_type), str(biome_id)):
				item_ids[str(entry["item_id"])] = true
	for res_type in DEFAULT_RESOURCE_TYPES:
		for entry in _get_resource_yields(str(res_type), ""):
			item_ids[str(entry["item_id"])] = true
	return item_ids

## Serialize for saving.
func serialize() -> Dictionary:
	return _resources.duplicate(true)

## Deserialize for loading.
func deserialize(data: Dictionary) -> void:
	_resources = data

## Generate resources for a chunk and return their records.
## Each record: {x, y, coords, type, health, yields} in world tile coords.
func generate_chunk_resources(chunk_coords: Vector2i, seed: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if _generated_chunks.has(chunk_coords):
		return results  # already generated for this chunk
	_generated_chunks[chunk_coords] = true

	var random := RandomNumberGenerator.new()
	random.seed = _get_chunk_seed(chunk_coords, seed)

	# Generate 5-15 resources per chunk. Candidate attempts are capped so a
	# water-heavy chunk cannot loop forever while still placing its resources on
	# terrain the player can actually stand on.
	var count: int = int(random.randf_range(5, 15))
	var placed: int = 0
	var attempts: int = 0
	while placed < count and attempts < count * 8:
		attempts += 1
		var x: int = chunk_coords.x * CHUNK_SIZE + int(random.randf_range(0, 16))
		var y: int = chunk_coords.y * CHUNK_SIZE + int(random.randf_range(0, 16))
		var tile: Vector2i = Vector2i(x, y)
		if _resources.has(tile) or not is_walkable_spawn_tile(tile):
			continue

		var biome_id: String = ""
		if world_generator != null and is_instance_valid(world_generator) \
				and world_generator.has_method("get_biome_at_world"):
			biome_id = world_generator.get_biome_at_world(x, y)
		var resource_type: String = _pick_resource_type(biome_id, random)
		var health: float = _get_resource_health(resource_type)
		var yields: Array[Dictionary] = _get_resource_yields(resource_type, biome_id)
		_resources[tile] = {
			"x": x,
			"y": y,
			"coords": "%d,%d" % [x, y],
			"type": resource_type,
			"health": health,
			"yields": yields
		}
		resource_placed.emit("%d,%d" % [x, y], resource_type)
		results.append(_resources[tile])
		placed += 1

	return results

## Resource nodes only appear where the player can stand. Stone remains valid
## (it is rough but walkable); the only generated impassable terrain is water.
func is_walkable_spawn_tile(tile: Vector2i) -> bool:
	if world_generator == null or not is_instance_valid(world_generator):
		return true
	if not world_generator.has_method("get_noise_values"):
		return true
	var noise: Dictionary = world_generator.get_noise_values(tile.x, tile.y)
	return float(noise.get("elevation", 0.5)) >= 0.3

## Pick a resource type that fits the given biome (fallback: default set).
func _pick_resource_type(biome_id: String, random: RandomNumberGenerator) -> String:
	var types: PackedStringArray = DEFAULT_RESOURCE_TYPES
	if biome_id != "":
		var biome_types: PackedStringArray = BIOME_RESOURCE_TYPES.get(biome_id)
		if biome_types.size() > 0:
			types = biome_types
	return types[int(random.randf_range(0, types.size()))]

## Get the health of a resource type.
func _get_resource_health(resource_type: String) -> float:
	match resource_type:
		"tree": return 5.0
		"rock": return 8.0
		"fibre": return 3.0
		"berry_bush": return 2.0
		"iron_ore": return 10.0
		"coal": return 6.0
		"gold_ore": return 12.0
		_: return 5.0

## Get yields for a resource type. Biome-flavoured drops make otherwise
## unreachable crafting chains possible: desert rock also drops sand (glass),
## mountain rock can drop copper ore, arctic rock can drop tin ore
## (copper/bronze ingots).
func _get_resource_yields(resource_type: String, biome_id: String = "") -> Array[Dictionary]:
	match resource_type:
		"tree":
			return [
				{"item_id": "wood", "min_qty": 2, "max_qty": 5, "chance": 1.0},
				{"item_id": "fibre", "min_qty": 1, "max_qty": 3, "chance": 0.5}
			]
		"rock":
			var rock_yields: Array[Dictionary] = [
				{"item_id": "stone", "min_qty": 2, "max_qty": 4, "chance": 1.0},
			]
			if biome_id == "desert":
				rock_yields.append({"item_id": "sand", "min_qty": 2, "max_qty": 4, "chance": 1.0})
			else:
				rock_yields.append({"item_id": "clay", "min_qty": 1, "max_qty": 2, "chance": 0.3})
			if biome_id == "mountain":
				rock_yields.append({"item_id": "copper_ore", "min_qty": 1, "max_qty": 2, "chance": 0.25})
			if biome_id == "arctic":
				rock_yields.append({"item_id": "tin_ore", "min_qty": 1, "max_qty": 2, "chance": 0.25})
			return rock_yields
		"fibre":
			return [
				{"item_id": "fibre", "min_qty": 3, "max_qty": 6, "chance": 1.0}
			]
		"berry_bush":
			return [
				{"item_id": "berry", "min_qty": 2, "max_qty": 5, "chance": 1.0}
			]
		# Phase 3 vegetation: plants feed the food chains that were
		# previously unreachable. Grassland plants are wheat (bread, via the
		# new flour recipe); swamp plants are mushrooms (soup); herbs grow
		# everywhere plants grow (soup, potions).
		"plant":
			if biome_id == "grassland":
				return [
					{"item_id": "wheat", "min_qty": 2, "max_qty": 4, "chance": 1.0},
					{"item_id": "herb", "min_qty": 1, "max_qty": 2, "chance": 0.5}
				]
			if biome_id == "swamp":
				return [
					{"item_id": "mushroom", "min_qty": 1, "max_qty": 2, "chance": 1.0},
					{"item_id": "herb", "min_qty": 1, "max_qty": 2, "chance": 0.5}
				]
			return [
				{"item_id": "herb", "min_qty": 1, "max_qty": 2, "chance": 0.8},
				{"item_id": "mushroom", "min_qty": 1, "max_qty": 2, "chance": 0.4}
			]
		"iron_ore":
			return [
				{"item_id": "iron_ore", "min_qty": 1, "max_qty": 3, "chance": 1.0},
				{"item_id": "stone", "min_qty": 1, "max_qty": 2, "chance": 0.5}
			]
		"coal":
			return [
				{"item_id": "coal", "min_qty": 1, "max_qty": 3, "chance": 1.0}
			]
		"gold_ore":
			return [
				{"item_id": "gold_ore", "min_qty": 1, "max_qty": 2, "chance": 1.0},
				{"item_id": "stone", "min_qty": 1, "max_qty": 2, "chance": 0.5}
			]
		_:
			return [
				{"item_id": resource_type, "min_qty": 1, "max_qty": 2, "chance": 1.0}
			]

## Get a deterministic seed for a chunk (arithmetic mix — no engine hash).
func _get_chunk_seed(chunk_coords: Vector2i, world_seed: int) -> int:
	var mixed: int = world_seed * 73856093
	mixed = mixed + chunk_coords.x * 19349663
	mixed = mixed + chunk_coords.y * 83492791
	return abs(mixed)
