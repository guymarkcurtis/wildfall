## Places data-defined surface resources deterministically across chunks.
## The engine understands distribution rules; content IDs and yields live in
## ResourceDefinition assets discovered by WorldContentRegistry.
class_name ResourceSpawner
extends Node

const CHUNK_SIZE: int = 16

## Distribution modes the spawn engine understands. Resource assets are
## validated against this list at startup by WorldContentRegistry; adding a
## mode here is what makes it legal in content (an unknown mode would spawn
## silently as uniform instead of failing).
const DISTRIBUTION_MODES: Array[String] = ["uniform", "sparse", "clustered", "patch", "vein", "edge-biased", "elevation-biased"]

## Tag vocabulary owned by this system (see docs/WORLD_CONTENT_AUTHORING.md):
## a terrain-feature definition that lists this influence tag declares its
## footprint not to be a valid surface-resource spawn site. The spawner is
## the consumer; feature assets opt in by data, and adding a new feature is
## an asset-only change.
const NO_SPAWN_FEATURE_TAG := "no_spawn"

var _resources: Dictionary = {}
var _generated_chunks: Dictionary = {}
## Chunk-local key index makes unload O(resources in that chunk), rather than
## an O(all loaded resources) scan every time a streamed chunk leaves view.
var _resource_tiles_by_chunk: Dictionary = {}
var _seed: int = 0
var world_generator: WorldGenerator = null

signal resource_placed(coords: String, resource_type: String)
signal resources_cleared

func _ready() -> void:
	world_generator = get_node_or_null("../WorldGenerator") as WorldGenerator

func initialize(seed: int) -> void:
	_seed = seed
	_resources.clear()
	_generated_chunks.clear()
	_resource_tiles_by_chunk.clear()
	resources_cleared.emit()

func remove_chunk(chunk_coords: Vector2i) -> void:
	if not _generated_chunks.has(chunk_coords):
		return
	for tile in _resource_tiles_by_chunk.get(chunk_coords, []):
		_resources.erase(tile)
	_resource_tiles_by_chunk.erase(chunk_coords)
	_generated_chunks.erase(chunk_coords)

func get_resources_in_range(center: Vector2i, radius: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for key in _resources:
		var tile: Vector2i = key
		if abs(tile.x - center.x) <= radius and abs(tile.y - center.y) <= radius:
			results.append(_resources[key])
	return results

func get_resource(coords: Vector2i) -> Dictionary:
	return _resources.get(coords, {})

func has_resource(coords: Vector2i) -> bool:
	return _resources.has(coords)

func remove_resource(coords: Vector2i) -> bool:
	if _resources.has(coords):
		_resources.erase(coords)
		var chunk_coords := Vector2i(floori(float(coords.x) / _chunk_size()), floori(float(coords.y) / _chunk_size()))
		var chunk_tiles: Array = _resource_tiles_by_chunk.get(chunk_coords, [])
		chunk_tiles.erase(coords)
		if chunk_tiles.is_empty():
			_resource_tiles_by_chunk.erase(chunk_coords)
		else:
			_resource_tiles_by_chunk[chunk_coords] = chunk_tiles
		return true
	return false

func get_all_resources() -> Dictionary:
	return _resources.duplicate(true)

## Used by crafting availability. This includes underground definitions because
## they are valid future loot sources even though surface generation filters
## them out today.
func get_all_droppable_items() -> Dictionary:
	var item_ids: Dictionary = {}
	if world_generator == null or not is_instance_valid(world_generator):
		return item_ids
	for resource_id in world_generator.get_content_registry().resources:
		var definition := world_generator.get_resource_definition(str(resource_id))
		if definition == null:
			continue
		for biome_id in world_generator.get_biomes():
			for entry in definition.get_yields_for_biome(str(biome_id)):
				item_ids[str(entry.get("item_id", ""))] = true
		for entry in definition.get_yields_for_biome(""):
			item_ids[str(entry.get("item_id", ""))] = true
	return item_ids

func serialize() -> Dictionary:
	return _resources.duplicate(true)

func deserialize(data: Dictionary) -> void:
	_resources = data
	_resource_tiles_by_chunk.clear()
	for tile_variant in _resources:
		var tile: Vector2i = tile_variant
		var chunk_coords := Vector2i(floori(float(tile.x) / _chunk_size()), floori(float(tile.y) / _chunk_size()))
		if not _resource_tiles_by_chunk.has(chunk_coords):
			_resource_tiles_by_chunk[chunk_coords] = []
		_resource_tiles_by_chunk[chunk_coords].append(tile)

## WG-07: generate surface resources from a deterministic density/candidate
## field. Every tile has one coordinate-derived candidate (or none), then a
## bounded neighbour comparison applies data-provided spacing. This replaces
## the old random retry loop and global `_resources` spacing scan: results are
## independent of chunk generation order and the work per chunk is bounded by
## its tile area plus a small local spacing window.
##
## The record shape remains compatible with HarvestableResource/Main. Payload
## biome/water/distance arrays are still preferred, avoiding on-demand field
## sampling for the chunk's own tiles.
func generate_chunk_resources(chunk_coords: Vector2i, seed: int = 0, feature_candidates: Array = [],
		biome_map: PackedStringArray = PackedStringArray(),
		water_mask: PackedByteArray = PackedByteArray(),
		distance_to_water: PackedInt32Array = PackedInt32Array()) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if _generated_chunks.has(chunk_coords):
		return results
	_generated_chunks[chunk_coords] = true
	if world_generator == null or not is_instance_valid(world_generator):
		return results
	if not world_generator.is_chunk_in_bounds(chunk_coords):
		return results

	var world_seed := seed if seed != 0 else _seed
	var size := _chunk_size()
	var chunk_origin := chunk_coords * size
	var maximum_spacing := _maximum_surface_spacing()
	# Spacing windows overlap heavily. Memoizing the coordinate-pure raw
	# candidate cuts thousands of duplicate biome/water/resource calculations
	# from every presented chunk without changing a single placement result.
	var candidate_cache: Dictionary = {}
	for local_y in range(size):
		for local_x in range(size):
			var local_index: int = local_y * size + local_x
			var tile := chunk_origin + Vector2i(local_x, local_y)
			var known_biome := str(biome_map[local_index]) if biome_map.size() == size * size else ""
			var known_water: int = int(water_mask[local_index]) if water_mask.size() == size * size else -1
			var known_distance: int = int(distance_to_water[local_index]) if distance_to_water.size() == size * size else -2
			var candidate := _cached_surface_candidate(tile, world_seed, candidate_cache,
					feature_candidates, known_biome, known_water, known_distance)
			if candidate.is_empty() or not _candidate_wins_spacing(candidate, world_seed,
					maximum_spacing, candidate_cache, feature_candidates):
				continue
			var definition: ResourceDefinition = candidate["definition"] as ResourceDefinition
			var record := {
				"x": tile.x,
				"y": tile.y,
				"coords": "%d,%d" % [tile.x, tile.y],
				"type": definition.id,
				"display_name": definition.display_name,
				"harvest_group": definition.harvest_group,
				"visual_texture_path": definition.visual_texture_path,
				"visual_ground_anchor": definition.visual_ground_anchor,
				"visual_hit_animation_paths": definition.visual_hit_animation_paths,
				"health": definition.base_health,
				"yields": definition.get_yields_for_biome(str(candidate["biome_id"]))
			}
			_resources[tile] = record
			if not _resource_tiles_by_chunk.has(chunk_coords):
				_resource_tiles_by_chunk[chunk_coords] = []
			_resource_tiles_by_chunk[chunk_coords].append(tile)
			results.append(record)
			resource_placed.emit(record["coords"], definition.id)
	return results

func _cached_surface_candidate(tile: Vector2i, world_seed: int, cache: Dictionary,
		feature_candidates: Array = [], known_biome_id: String = "", known_water: int = -1,
		known_distance: int = -2) -> Dictionary:
	if cache.has(tile):
		return cache[tile]
	var candidate := _surface_candidate(tile, world_seed, feature_candidates,
			known_biome_id, known_water, known_distance)
	cache[tile] = candidate
	return candidate

## Returns the raw coordinate-defined resource candidate for a tile. This has
## no mutable placement state, which makes it safe to call for adjacent chunks
## during the spacing comparison.
func _surface_candidate(tile: Vector2i, world_seed: int, feature_candidates: Array = [],
		known_biome_id: String = "", known_water: int = -1, known_distance: int = -2) -> Dictionary:
	var water: bool = known_water != 0 if known_water != -1 else not is_walkable_spawn_tile(tile)
	if water or is_feature_blocked_tile(tile, feature_candidates):
		return {}
	var biome_id := known_biome_id if not known_biome_id.is_empty() else world_generator.get_biome_at_world(tile.x, tile.y)
	var biome := world_generator.get_biome(biome_id)
	if biome == null:
		return {}
	var random := RandomNumberGenerator.new()
	random.seed = WorldGenerationContext.mix_seed(world_seed, tile.x, tile.y, 0x57A7C3)
	var definition := _pick_resource_definition(biome, random)
	if definition == null:
		return {}
	var distance: int = known_distance if known_distance != -2 else world_generator.get_distance_to_water_at_world(tile.x, tile.y)
	if not world_generator.definition_within_distance(definition.min_distance_to_water,
			definition.max_distance_to_water, distance):
		return {}
	var config := world_generator.get_configuration()
	var density := clampf(config.surface_resource_density * definition.density_multiplier
			* clampf(definition.abundance, 0.0, 1.0), 0.0, 1.0)
	if _unit_field(world_seed, tile, WorldGenerationContext.stable_string_seed(definition.id) ^ 0xD3A517) > density:
		return {}
	if not _passes_density_distribution(tile, definition, world_seed):
		return {}
	return {
		"tile": tile,
		"definition": definition,
		"biome_id": biome_id,
		"priority": WorldGenerationContext.mix_seed(world_seed, tile.x, tile.y,
				WorldGenerationContext.stable_string_seed(definition.id) ^ 0x51A7)
	}

## The bounded neighbour comparison replaces the old global `_resources`
## scan. A stable priority decides conflicting candidates, so a pair crossing
## a chunk edge resolves identically no matter which chunk happened to load
## first.
func _candidate_wins_spacing(candidate: Dictionary, world_seed: int, maximum_spacing: int,
		candidate_cache: Dictionary, feature_candidates: Array) -> bool:
	var definition: ResourceDefinition = candidate["definition"] as ResourceDefinition
	if maximum_spacing <= 0:
		return true
	var tile: Vector2i = candidate["tile"]
	for offset_y in range(-maximum_spacing, maximum_spacing + 1):
		for offset_x in range(-maximum_spacing, maximum_spacing + 1):
			if offset_x == 0 and offset_y == 0:
				continue
			var other_tile := tile + Vector2i(offset_x, offset_y)
			var other := _cached_surface_candidate(other_tile, world_seed, candidate_cache,
					feature_candidates)
			if other.is_empty():
				continue
			var other_definition: ResourceDefinition = other["definition"] as ResourceDefinition
			var required_spacing := maxi(definition.min_spacing_tiles, other_definition.min_spacing_tiles)
			if required_spacing <= 0 or maxi(absi(offset_x), absi(offset_y)) > required_spacing:
				continue
			if int(other["priority"]) > int(candidate["priority"]):
				return false
			if int(other["priority"]) == int(candidate["priority"]) \
					and (other_tile.y < tile.y or (other_tile.y == tile.y and other_tile.x < tile.x)):
				return false
	return true

func _maximum_surface_spacing() -> int:
	var maximum := 0
	if world_generator == null or not is_instance_valid(world_generator):
		return maximum
	for resource_id in world_generator.get_content_registry().resources:
		var definition := world_generator.get_resource_definition(str(resource_id))
		if definition != null and definition.surface_spawnable:
			maximum = maxi(maximum, definition.min_spacing_tiles)
	return maximum

static func _unit_field(world_seed: int, tile: Vector2i, stream: int) -> float:
	return fposmod(float(WorldGenerationContext.mix_seed(world_seed, tile.x, tile.y, stream)), 1000000.0) / 1000000.0

func is_walkable_spawn_tile(tile: Vector2i) -> bool:
	return world_generator == null or not is_instance_valid(world_generator) \
		or not world_generator.is_water_at_world(tile.x, tile.y)

func _pick_resource_definition(biome: BiomeDefinition, random: RandomNumberGenerator) -> ResourceDefinition:
	var eligible: Array[ResourceDefinition] = []
	for resource_id in biome.resource_types:
		var definition := world_generator.get_resource_definition(str(resource_id))
		if definition == null or not definition.can_spawn_on_surface(biome.id, biome.environment_tags):
			continue
		if not eligible.has(definition):
			eligible.append(definition)
	if eligible.is_empty():
		return null
	var total := 0.0
	for definition in eligible:
		total += maxf(0.0, definition.spawn_weight)
	if total <= 0.0:
		return eligible[0]
	var roll := random.randf() * total
	for definition in eligible:
		roll -= maxf(0.0, definition.spawn_weight)
		if roll <= 0.0:
			return definition
	return eligible.back()

## Pure mask query: true when any feature candidate whose footprint covers
## `tile` declares this spawner's spawn-block tag. Consumers pass the
## feature_candidates array of the chunk being populated — the payload
## includes halo candidates anchored in neighbouring chunks whose footprints
## cross into it, so the per-chunk view is complete.
static func is_feature_blocked_tile(tile: Vector2i, feature_candidates: Array) -> bool:
	for candidate in feature_candidates:
		var radius := int(candidate.get("footprint_radius_tiles", 0))
		if absi(int(candidate.get("x", 0)) - tile.x) > radius:
			continue
		if absi(int(candidate.get("y", 0)) - tile.y) > radius:
			continue
		var tags = candidate.get("influence_tags", PackedStringArray())
		if tags is PackedStringArray and (tags as PackedStringArray).has(NO_SPAWN_FEATURE_TAG):
			return true
	return false

## Reusable spatial modes. These names describe algorithms, not content; a
## designer can assign the same mode to a tree, rock, plant, or future POI.
func _passes_density_distribution(tile: Vector2i, definition: ResourceDefinition, world_seed: int) -> bool:
	match definition.distribution_mode:
		"sparse":
			return _unit_field(world_seed, tile, WorldGenerationContext.stable_string_seed(definition.id) ^ 0x5FA25E) < 0.55
		"clustered", "patch", "vein":
			var radius := maxi(1, definition.cluster_radius)
			var coarse := Vector2i(floori(float(tile.x) / radius), floori(float(tile.y) / radius))
			var field_seed := WorldGenerationContext.mix_seed(
				world_seed,
				coarse.x,
				coarse.y,
				WorldGenerationContext.stable_string_seed(definition.id)
			)
			return fposmod(float(field_seed), 100.0) >= (32.0 if definition.distribution_mode == "vein" else 48.0)
		"edge-biased":
			var local := posmod(tile.x, _chunk_size())
			var local_y := posmod(tile.y, _chunk_size())
			return local <= 2 or local >= _chunk_size() - 3 or local_y <= 2 or local_y >= _chunk_size() - 3
		"elevation-biased":
			return world_generator == null or world_generator.get_noise_values(tile.x, tile.y)["elevation"] >= 0.55
		_:
			return true

func _chunk_size() -> int:
	if world_generator != null and is_instance_valid(world_generator):
		return world_generator.get_configuration().chunk_size_tiles
	return CHUNK_SIZE
