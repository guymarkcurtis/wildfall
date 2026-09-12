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
	resources_cleared.emit()

func remove_chunk(chunk_coords: Vector2i) -> void:
	if not _generated_chunks.has(chunk_coords):
		return
	var chunk_size := _chunk_size()
	var start := chunk_coords * chunk_size
	for tile in _resources.keys():
		if tile.x >= start.x and tile.x < start.x + chunk_size \
				and tile.y >= start.y and tile.y < start.y + chunk_size:
			_resources.erase(tile)
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

## Generate surface resources for one chunk. The record shape remains
## compatible with HarvestableResource/Main.
func generate_chunk_resources(chunk_coords: Vector2i, seed: int = 0, feature_candidates: Array = []) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if _generated_chunks.has(chunk_coords):
		return results
	_generated_chunks[chunk_coords] = true
	if world_generator == null or not is_instance_valid(world_generator):
		return results
	if not world_generator.is_chunk_in_bounds(chunk_coords):
		return results

	var random := RandomNumberGenerator.new()
	var world_seed := seed if seed != 0 else _seed
	random.seed = _chunk_seed(chunk_coords, world_seed)
	var config: WorldGenerationConfig = world_generator.get_configuration()
	var count := random.randi_range(config.resource_min_per_chunk, config.resource_max_per_chunk)
	var attempts := 0
	var placed := 0
	while placed < count and attempts < count * maxi(1, config.resource_attempt_multiplier):
		attempts += 1
		var tile := chunk_coords * _chunk_size() + Vector2i(
			random.randi_range(0, _chunk_size() - 1), random.randi_range(0, _chunk_size() - 1)
		)
		if _resources.has(tile) or not is_walkable_spawn_tile(tile):
			continue
		# WG-04: the terrain-feature mask carried by the chunk payload can
		# veto a tile (a feature whose influence tags include this spawner's
		# spawn-block tag covers it). Worlds with no feature assets pass an
		# empty list, so placement is unchanged. The check consumes no random
		# rolls, so allowed tiles roll exactly as before.
		if is_feature_blocked_tile(tile, feature_candidates):
			continue
		var biome_id := world_generator.get_biome_at_world(tile.x, tile.y)
		var biome := world_generator.get_biome(biome_id)
		if biome == null:
			continue
		var definition := _pick_resource_definition(biome, random)
		if definition == null or random.randf() > clampf(definition.abundance, 0.0, 1.0):
			continue
		if not _passes_distribution(tile, definition, random):
			continue
		if not _respects_spacing(tile, definition.min_spacing_tiles):
			continue
		var record := {
			"x": tile.x,
			"y": tile.y,
			"coords": "%d,%d" % [tile.x, tile.y],
			"type": definition.id,
			"health": definition.base_health,
			"yields": definition.get_yields_for_biome(biome_id)
		}
		_resources[tile] = record
		results.append(record)
		resource_placed.emit(record["coords"], definition.id)
		placed += 1
	return results

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

func _respects_spacing(tile: Vector2i, spacing: int) -> bool:
	if spacing <= 0:
		return true
	for existing in _resources:
		var other: Vector2i = existing
		if abs(other.x - tile.x) <= spacing and abs(other.y - tile.y) <= spacing:
			return false
	return true

## Reusable spatial modes. These names describe algorithms, not content; a
## designer can assign the same mode to a tree, rock, plant, or future POI.
func _passes_distribution(tile: Vector2i, definition: ResourceDefinition, random: RandomNumberGenerator) -> bool:
	match definition.distribution_mode:
		"sparse":
			return random.randf() < 0.55
		"clustered", "patch", "vein":
			var radius := maxi(1, definition.cluster_radius)
			var coarse := Vector2i(floori(float(tile.x) / radius), floori(float(tile.y) / radius))
			var field_seed := WorldGenerationContext.mix_seed(
				_seed,
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

func _chunk_seed(chunk_coords: Vector2i, world_seed: int) -> int:
	return WorldGenerationContext.mix_seed(world_seed, chunk_coords.x, chunk_coords.y, 0x7A11CE)
