## Spawns creatures deterministically per chunk, following the chunk lifecycle.
## Mirrors ResourceSpawner: the spawner owns the spawn records and Main
## creates/frees the actual Creature nodes. Land creatures are assigned to
## the biome at each tile (via WorldGenerator); fish spawn only on water
## tiles (elevation below the terrain renderer's water threshold).
class_name CreatureSpawner
extends Node

const CHUNK_SIZE: int = 16
const MAX_LAND_CREATURES_PER_CHUNK: int = 3
const MAX_FISH_PER_CHUNK: int = 2
# Matches TerrainRenderer._get_tile_id: elevation below this is water.
const WATER_ELEVATION: float = 0.3

# Creature type id -> CreatureDefinition.
var creature_definitions: Dictionary = {}
# World tile position (Vector2i) -> creature record.
var _creatures: Dictionary = {}
# Chunk coords (Vector2i) -> true. Tracks which chunks have already been
# generated, so re-entering a chunk re-spawns it instead of skipping it.
var _generated_chunks: Dictionary = {}

# The world generator (sibling under Main) provides per-tile biome ids and
# elevation values.
var world_generator: WorldGenerator = null

# Signals
signal creature_placed(coords: String, creature_type: String)
signal creatures_cleared

func _ready() -> void:
	world_generator = get_node_or_null("../WorldGenerator")

## Initialize with world seed (clears all spawn records).
func initialize(seed: int) -> void:
	_load_creature_definitions()
	_creatures.clear()
	_generated_chunks.clear()
	creatures_cleared.emit()

## Load the Phase 3 hunting roster as CreatureDefinition resources.
## All creatures are passive or neutral: they flee when threatened but never
## attack (hostile AI is a later phase). Speed is in tiles/second and the
## detection range is in tiles, per the CreatureDefinition schema; pixel
## tuning (patrol radius, visual size) lives in custom_data.
func _load_creature_definitions() -> void:
	if creature_definitions.size() > 0:
		return
	# --- Passive game animals (one per biome, plus the shared water fish) ---
	_add_definition("rabbit", "Rabbit", "passive", 10, 3.0, 4.5, 96.0, 7.0, ["grassland"], [
		{"item_id": "meat", "min_qty": 1, "max_qty": 2, "chance": 1.0},
		{"item_id": "hide", "min_qty": 0, "max_qty": 1, "chance": 0.6}
	])
	_add_definition("deer", "Deer", "passive", 22, 3.6, 5.0, 112.0, 12.0, ["temperate_forest"], [
		{"item_id": "meat", "min_qty": 2, "max_qty": 3, "chance": 1.0},
		{"item_id": "hide", "min_qty": 1, "max_qty": 2, "chance": 0.8}
	])
	_add_definition("boar", "Boar", "predator", 28, 2.2, 4.5, 80.0, 12.0, ["swamp"], [
		{"item_id": "meat", "min_qty": 2, "max_qty": 3, "chance": 1.0},
		{"item_id": "hide", "min_qty": 1, "max_qty": 2, "chance": 0.7},
		{"item_id": "bone", "min_qty": 0, "max_qty": 1, "chance": 0.5}
	], true, 6.0, "bleed")
	_add_definition("wolf", "Wolf", "predator", 35, 4.2, 5.5, 120.0, 11.0, ["mountain", "arctic"], [
		{"item_id": "meat", "min_qty": 1, "max_qty": 2, "chance": 1.0},
		{"item_id": "hide", "min_qty": 1, "max_qty": 2, "chance": 0.8},
		{"item_id": "bone", "min_qty": 1, "max_qty": 1, "chance": 0.6}
	], true, 8.0, "")
	_add_definition("polar_bear", "Polar Bear", "predator", 60, 2.5, 6.0, 120.0, 16.0, ["arctic"], [
		{"item_id": "meat", "min_qty": 3, "max_qty": 5, "chance": 1.0},
		{"item_id": "hide", "min_qty": 2, "max_qty": 3, "chance": 1.0},
		{"item_id": "bone", "min_qty": 1, "max_qty": 2, "chance": 0.7}
	], true, 12.0, "slow")
	_add_definition("vulture", "Vulture", "passive", 8, 1.7, 4.5, 72.0, 8.0, ["desert"], [
		{"item_id": "feather", "min_qty": 1, "max_qty": 2, "chance": 1.0},
		{"item_id": "meat", "min_qty": 1, "max_qty": 1, "chance": 0.5}
	])
	# Fish are not biome creatures: the "water" sentinel is matched against
	# water tiles (elevation < WATER_ELEVATION) in any biome.
	_add_definition("fish", "Fish", "passive", 6, 1.4, 4.0, 64.0, 7.0, ["water"], [
		{"item_id": "fish", "min_qty": 1, "max_qty": 2, "chance": 1.0}
	])
	print("CreatureSpawner: Initialized with %d definitions" % creature_definitions.size())

## Build and register one CreatureDefinition.
func _add_definition(id: String, display_name: String, ctype: String, health: int,
		speed_tiles: float, detection_tiles: float, patrol_radius_px: float,
		size_px: float, biomes: Array, loot: Array[Dictionary],
		hostile: bool = false, attack_damage: float = 0.0, hit_status: String = "") -> void:
	var def := CreatureDefinition.new()
	def.id = id
	def.display_name = display_name
	def.type = ctype
	def.health = health
	def.speed = speed_tiles
	def.detection_range = detection_tiles
	def.aggression_range = detection_tiles * 0.7
	def.attack_damage = attack_damage
	def.attack_cooldown = 1.1
	def.hostile = hostile
	def.loot_table = loot
	def.allowed_biomes = PackedStringArray(biomes)
	def.custom_data = {"patrol_radius": patrol_radius_px, "size": size_px, "hit_status": hit_status}
	creature_definitions[id] = def

## Spawn creatures for a chunk and return their records.
## Each record: {x, y, type, biome} in world tile coords. Deterministic:
## positions and types derive from the chunk seed and the seeded noise.
func generate_chunk_creatures(chunk_coords: Vector2i, seed: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if _generated_chunks.has(chunk_coords):
		return results  # already generated for this chunk
	if world_generator == null or not is_instance_valid(world_generator):
		_generated_chunks[chunk_coords] = true
		return results
	_generated_chunks[chunk_coords] = true

	var random := RandomNumberGenerator.new()
	random.seed = _get_chunk_seed(chunk_coords, seed)

	# Land creatures: 1-3 per chunk. Each attempt draws a random tile
	# (skipping water and occupied tiles) and picks a creature that matches
	# the biome at that tile. Every biome has at least one land creature, so
	# any chunk with land tiles spawns at least one.
	var land_count: int = 1 + int(random.randf() * MAX_LAND_CREATURES_PER_CHUNK)
	var land_spawned: int = 0
	for _i in range(land_count * 4):
		if land_spawned >= land_count:
			break
		var x: int = chunk_coords.x * CHUNK_SIZE + int(random.randf_range(0, CHUNK_SIZE))
		var y: int = chunk_coords.y * CHUNK_SIZE + int(random.randf_range(0, CHUNK_SIZE))
		var tile: Vector2i = Vector2i(x, y)
		if _creatures.has(tile):
			continue
		if _get_elevation(x, y) < WATER_ELEVATION:
			continue
		var biome_id: String = _get_biome_at(x, y)
		var eligible: PackedStringArray = _eligible_types(biome_id)
		if eligible.is_empty():
			continue
		var creature_type: String = eligible[int(random.randf_range(0, eligible.size()))]
		_creatures[tile] = {
			"x": x,
			"y": y,
			"type": creature_type,
			"biome": biome_id
		}
		results.append(_creatures[tile])
		land_spawned += 1
		creature_placed.emit("%d,%d" % [x, y], creature_type)

	# Fish: 1-2 per chunk, only on water tiles. Sample random tiles for the
	# water candidates (also keeps the RNG stream deterministic per seed).
	var water_tiles: Array[Vector2i] = []
	for _i in range(48):
		var x: int = chunk_coords.x * CHUNK_SIZE + int(random.randf_range(0, CHUNK_SIZE))
		var y: int = chunk_coords.y * CHUNK_SIZE + int(random.randf_range(0, CHUNK_SIZE))
		if _get_elevation(x, y) < WATER_ELEVATION and not _creatures.has(Vector2i(x, y)):
			water_tiles.append(Vector2i(x, y))
			if water_tiles.size() >= 8:
				break
	var fish_count: int = mini(1 + int(random.randf() * MAX_FISH_PER_CHUNK), water_tiles.size())
	for i in range(fish_count):
		var tile: Vector2i = water_tiles[i]
		_creatures[tile] = {
			"x": tile.x,
			"y": tile.y,
			"type": "fish",
			"biome": "water"
		}
		results.append(_creatures[tile])
		creature_placed.emit("%d,%d" % [tile.x, tile.y], "fish")

	return results

## Drop the records of a chunk that was unloaded, so that re-entering the
## chunk regenerates its creatures (same guard problem as the resource
## spawner: tile-keyed records would otherwise outlive the chunk).
func remove_chunk(chunk_coords: Vector2i) -> void:
	if not _generated_chunks.has(chunk_coords):
		return
	var start: Vector2i = chunk_coords * CHUNK_SIZE
	for tile in _creatures.keys():
		var t: Vector2i = tile
		if t.x >= start.x and t.x < start.x + CHUNK_SIZE \
				and t.y >= start.y and t.y < start.y + CHUNK_SIZE:
			_creatures.erase(t)
	_generated_chunks.erase(chunk_coords)

## Get a specific creature record.
func get_creature(coords: Vector2i) -> Dictionary:
	return _creatures.get(coords, {})

## Remove a creature record after it dies. Main also stores the same tile in
## its save mutation ledger so deterministic regeneration cannot restore it.
func remove_creature(coords: Vector2i) -> bool:
	if _creatures.has(coords):
		_creatures.erase(coords)
		return true
	return false

## All creature records, keyed by world tile position.
func get_all_creatures() -> Dictionary:
	return _creatures.duplicate(true)

## Get the CreatureDefinition for a creature type (null if unknown).
func get_definition(creature_type: String) -> CreatureDefinition:
	return creature_definitions.get(creature_type, null) as CreatureDefinition

## Get creature count (records, i.e. planned spawns; Main owns the nodes).
func get_creature_count() -> int:
	return _creatures.size()

## Clear all spawn records (e.g. before a full world regeneration).
func clear_all() -> void:
	_creatures.clear()
	_generated_chunks.clear()
	creatures_cleared.emit()

## All item ids creatures can drop (across the whole roster). Main uses
## this, together with the resource spawner's drops, to decide which
## crafting recipes are obtainable (and therefore visible in the panel).
func get_all_droppable_items() -> Dictionary:
	var item_ids: Dictionary = {}
	for creature_type in creature_definitions:
		var def: CreatureDefinition = creature_definitions[creature_type]
		for entry in def.loot_table:
			item_ids[str(entry["item_id"])] = true
	return item_ids

## Creature types eligible for a biome (fish are excluded from land biomes
## because their allowed biome is the "water" sentinel, never a real biome).
func _eligible_types(biome_id: String) -> PackedStringArray:
	var eligible: PackedStringArray = []
	for creature_type in creature_definitions:
		var def: CreatureDefinition = creature_definitions[creature_type]
		if def.allowed_biomes.has(biome_id):
			eligible.append(creature_type)
	return eligible

## Normalized elevation at a world tile (matches the terrain renderer's
## water threshold). Falls back to 0.5 (mid, i.e. land) if the generator is
## unavailable.
func _get_elevation(world_x: int, world_y: int) -> float:
	if world_generator == null or not is_instance_valid(world_generator):
		return 0.5
	var values: Dictionary = world_generator.get_noise_values(float(world_x), float(world_y))
	return float(values.get("elevation", 0.5))

## Per-tile biome at a world tile (same source the terrain renderer uses).
func _get_biome_at(world_x: int, world_y: int) -> String:
	if world_generator == null or not is_instance_valid(world_generator):
		return ""
	return world_generator.get_biome_at_world(world_x, world_y)

## Get a deterministic seed for a chunk (arithmetic mix — no engine hash).
## Same mix as ResourceSpawner plus a salt so the creature stream does not
## mirror the resource stream.
func _get_chunk_seed(chunk_coords: Vector2i, world_seed: int) -> int:
	var mixed: int = world_seed * 73856093
	mixed = mixed + chunk_coords.x * 19349663
	mixed = mixed + chunk_coords.y * 83492791
	mixed = mixed + 734537
	return abs(mixed)
