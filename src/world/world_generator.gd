## Deterministic, data-driven world-generation pipeline.
## This class defines how fields and stages are interpreted. It does not contain
## knowledge of particular biome, resource, cave, or POI names.
class_name WorldGenerator
extends Node

const CHUNK_SIZE: int = 16 # Compatibility constant for existing callers.
const GENERATOR_VERSION: int = 2
const CONFIG_PATH := "res://data/world/world_generation_config.tres"

var noise_layers: NoiseLayers = null
var current_seed: int = 0
var configuration: WorldGenerationConfig = null
var generation_context: WorldGenerationContext = null
var content_registry: WorldContentRegistry = null

signal chunk_generated(chunk_coords: Vector2i, data: Dictionary)
signal world_regenerated

func initialize(seed: int, config_override: WorldGenerationConfig = null) -> void:
	current_seed = seed
	configuration = config_override if config_override != null else _load_configuration()
	content_registry = WorldContentRegistry.new()
	content_registry.discover()
	generation_context = WorldGenerationContext.new(seed, configuration)
	if noise_layers != null and is_instance_valid(noise_layers):
		noise_layers.reinitialize(seed, configuration.noise_settings)
	else:
		noise_layers = NoiseLayers.new()
		add_child(noise_layers)
		noise_layers.initialize(seed, configuration.noise_settings)

func get_configuration() -> WorldGenerationConfig:
	if configuration == null:
		configuration = _load_configuration()
	return configuration

func get_content_registry() -> WorldContentRegistry:
	if content_registry == null:
		initialize(current_seed)
	return content_registry

func get_biome(biome_id: String) -> BiomeDefinition:
	return get_content_registry().get_biome(biome_id)

func get_biome_definition(biome_id: String) -> BiomeDefinition:
	return get_biome(biome_id)

func get_biomes() -> Dictionary:
	return get_content_registry().biomes

func register_biome(biome: BiomeDefinition) -> void:
	if content_registry == null:
		content_registry = WorldContentRegistry.new()
	content_registry.biomes[biome.id] = biome

func get_resource_definition(resource_id: String) -> ResourceDefinition:
	return get_content_registry().get_resource(resource_id)

func get_cave_definitions() -> Dictionary:
	return get_content_registry().caves

func get_cave(cave_id: String) -> CaveDefinition:
	return get_content_registry().get_cave(cave_id)

func get_poi_definitions() -> Dictionary:
	return get_content_registry().pois

## Generate one chunk through environment, water, biome, and POI stages.
## Runtime resource/creature nodes are populated by Main after this base data.
func generate_chunk(chunk_coords: Vector2i, seed: int = -1) -> Dictionary:
	if seed < 0:
		seed = current_seed
	if generation_context == null or current_seed != seed:
		initialize(seed)
	if not get_configuration().is_chunk_in_bounds(chunk_coords):
		return {}

	var fields := _generate_environmental_fields(chunk_coords)
	var water_mask := PackedByteArray()
	var biome_map := PackedStringArray()
	var water_tiles: Array[Vector2i] = []
	var size: int = get_configuration().chunk_size_tiles
	for index in range(fields["elevation"].size()):
		var world_x: int = fields["world_start"].x + (index % size)
		var world_y: int = fields["world_start"].y + (index / size)
		var elevation: float = fields["elevation"][index]
		var moisture: float = fields["moisture"][index]
		var is_water := _is_water(elevation, moisture, fields["water"][index])
		water_mask.append(1 if is_water else 0)
		if is_water:
			water_tiles.append(Vector2i(world_x, world_y))
		biome_map.append(_select_biome_at(elevation, moisture, fields["temperature"][index],
				get_regional_noise_values(world_x, world_y)))

	var data := {
		"coords": chunk_coords,
		"elevation": fields["elevation"],
		"moisture": fields["moisture"],
		"temperature": fields["temperature"],
		"water": fields["water"],
		"water_mask": water_mask,
		"water_tiles": water_tiles,
		"biome": _select_biome(fields["elevation"], fields["moisture"], fields["temperature"],
				fields["world_start"] + Vector2i(size / 2, size / 2)),
		"biomes": biome_map,
		"terrain_features": {"water_tile_count": water_tiles.size()},
		"poi_candidates": _generate_poi_candidates(chunk_coords, biome_map, water_mask),
		"seed": generation_context.chunk_seed(chunk_coords),
		"version": get_configuration().generation_version
	}
	chunk_generated.emit(chunk_coords, data)
	return data

func regenerate_world(seed: int) -> Dictionary:
	initialize(seed)
	world_regenerated.emit()
	return {"seed": seed, "chunks": {}, "version": get_configuration().generation_version}

func get_seed() -> int:
	return current_seed

func is_chunk_in_bounds(coords: Vector2i) -> bool:
	return get_configuration().is_chunk_in_bounds(coords)

func get_noise_values(x: float, y: float) -> Dictionary:
	if noise_layers == null or not is_instance_valid(noise_layers):
		initialize(current_seed)
	return {
		"elevation": _normalized(noise_layers.get_elevation(x, y)),
		"moisture": _normalized(noise_layers.get_moisture(x, y)),
		"temperature": _normalized(noise_layers.get_temperature(x, y)),
		"water": _normalized(noise_layers.get_water(x, y))
	}

## Low-frequency environmental values used to establish coherent biome regions.
## They sample the same deterministic field family at a configurable larger
## scale, so no chunk-generation history is needed to know a region's context.
func get_regional_noise_values(world_x: int, world_y: int) -> Dictionary:
	if noise_layers == null or not is_instance_valid(noise_layers):
		initialize(current_seed)
	var scale := get_configuration().regional_field_coordinate_scale
	return {
		"elevation": _normalized(noise_layers.get_elevation(float(world_x) * scale, float(world_y) * scale)),
		"moisture": _normalized(noise_layers.get_moisture(float(world_x) * scale, float(world_y) * scale)),
		"temperature": _normalized(noise_layers.get_temperature(float(world_x) * scale, float(world_y) * scale))
	}

func get_biome_at_world(world_x: int, world_y: int) -> String:
	var values := get_noise_values(float(world_x), float(world_y))
	return _select_biome_at(values["elevation"], values["moisture"], values["temperature"],
			get_regional_noise_values(world_x, world_y))

func is_water_at_world(world_x: int, world_y: int) -> bool:
	var values := get_noise_values(float(world_x), float(world_y))
	return _is_water(values["elevation"], values["moisture"], values["water"])

func get_biome_environment_tags(biome_id: String) -> PackedStringArray:
	var biome := get_biome(biome_id)
	return biome.environment_tags if biome != null else PackedStringArray()

func get_surface_state_at_world(world_x: int, world_y: int) -> Dictionary:
	var values := get_noise_values(float(world_x), float(world_y))
	var biome_id := get_biome_at_world(world_x, world_y)
	return {
		"biome": biome_id,
		"environment_tags": get_biome_environment_tags(biome_id),
		"is_water": _is_water(values["elevation"], values["moisture"], values["water"]),
		"values": values
	}

func _load_configuration() -> WorldGenerationConfig:
	var loaded := load(CONFIG_PATH) as WorldGenerationConfig
	return loaded if loaded != null else WorldGenerationConfig.new()

func _generate_environmental_fields(chunk_coords: Vector2i) -> Dictionary:
	var size: int = get_configuration().chunk_size_tiles
	var world_start := chunk_coords * size
	var elevation := PackedFloat32Array()
	var moisture := PackedFloat32Array()
	var temperature := PackedFloat32Array()
	var water := PackedFloat32Array()
	for y in range(size):
		for x in range(size):
			var world_x := float(world_start.x + x)
			var world_y := float(world_start.y + y)
			elevation.append(_normalized(noise_layers.get_elevation(world_x, world_y)))
			moisture.append(_normalized(noise_layers.get_moisture(world_x, world_y)))
			temperature.append(_normalized(noise_layers.get_temperature(world_x, world_y)))
			water.append(_normalized(noise_layers.get_water(world_x, world_y)))
	return {"world_start": world_start, "elevation": elevation, "moisture": moisture, "temperature": temperature, "water": water}

func _is_water(elevation: float, moisture: float, water_value: float) -> bool:
	var config := get_configuration()
	return elevation < config.water_level \
		or (elevation < config.lake_level and moisture >= config.lake_moisture_threshold \
		and water_value >= config.lake_noise_threshold)

func _generate_poi_candidates(chunk_coords: Vector2i, biome_map: PackedStringArray, water_mask: PackedByteArray) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if get_cave_definitions().is_empty() or get_poi_definitions().is_empty():
		return candidates
	var size := get_configuration().chunk_size_tiles
	var world_start := chunk_coords * size
	var poi_ids := get_poi_definitions().keys()
	poi_ids.sort()
	for poi_id_variant in poi_ids:
		var poi := get_content_registry().get_poi(str(poi_id_variant))
		if poi == null or not _has_cave_for_poi(poi.id):
			continue
		for tile in _poi_anchor_tiles_in_chunk(poi, world_start, size):
			var local := tile - world_start
			var index := local.y * size + local.x
			if index < 0 or index >= water_mask.size() or water_mask[index] != 0:
				continue
			var biome_id := str(biome_map[index])
			var biome := get_biome(biome_id)
			if biome == null or not _poi_allows_biome(poi, biome):
				continue
			var random := RandomNumberGenerator.new()
			random.seed = generation_context.tile_seed(tile,
					WorldGenerationContext.stable_string_seed(poi.id) ^ 0x45D9F3B)
			var chance := clampf(biome.cave_entrance_suitability * maxf(0.0, poi.spawn_weight), 0.0, 1.0)
			if random.randf() > chance:
				continue
			var cave := _choose_cave_for_biome(biome, random, poi.id)
			if cave == null:
				continue
			candidates.append({
				"poi_id": poi.id,
				"poi_category": poi.category,
				"cave_type_id": cave.id,
				"cave_id": generation_context.cave_identity(tile, cave.id),
				"x": tile.x,
				"y": tile.y,
				"biome": biome_id
			})
	return candidates

## Each POI uses a deterministic grid offset derived from its data ID. Anchor
## cells give it a real cross-chunk spacing guarantee without retaining global
## generation state, so chunks remain safe to generate in any order.
func _poi_anchor_tiles_in_chunk(poi: POIDefinition, world_start: Vector2i, size: int) -> Array[Vector2i]:
	var spacing := maxi(1, poi.min_spacing_tiles)
	var offset_random := RandomNumberGenerator.new()
	offset_random.seed = generation_context.tile_seed(Vector2i.ZERO,
			WorldGenerationContext.stable_string_seed(poi.id) ^ 0x2C1B3C6D)
	var offset := Vector2i(offset_random.randi_range(0, spacing - 1), offset_random.randi_range(0, spacing - 1))
	var world_end := world_start + Vector2i(size - 1, size - 1)
	var first_cell := Vector2i(
		floori(float(world_start.x - offset.x) / float(spacing)),
		floori(float(world_start.y - offset.y) / float(spacing))
	)
	var last_cell := Vector2i(
		floori(float(world_end.x - offset.x) / float(spacing)),
		floori(float(world_end.y - offset.y) / float(spacing))
	)
	var anchors: Array[Vector2i] = []
	for cell_y in range(first_cell.y, last_cell.y + 1):
		for cell_x in range(first_cell.x, last_cell.x + 1):
			var anchor := Vector2i(cell_x * spacing, cell_y * spacing) + offset
			if anchor.x >= world_start.x and anchor.x <= world_end.x \
					and anchor.y >= world_start.y and anchor.y <= world_end.y:
				anchors.append(anchor)
	return anchors

func _has_cave_for_poi(poi_id: String) -> bool:
	for cave_id in get_cave_definitions():
		var cave := get_cave(str(cave_id))
		if cave != null and cave.entrance_poi_id == poi_id:
			return true
	return false

func _poi_allows_biome(poi: POIDefinition, biome: BiomeDefinition) -> bool:
	if not poi.allowed_biomes.is_empty() and not poi.allowed_biomes.has(biome.id):
		return false
	for required_tag in poi.required_environment_tags:
		if not biome.environment_tags.has(required_tag):
			return false
	return true

func _choose_cave_for_biome(biome: BiomeDefinition, random: RandomNumberGenerator, poi_id: String = "") -> CaveDefinition:
	var eligible: Array[CaveDefinition] = []
	for cave_id in get_cave_definitions():
		var cave := get_cave(str(cave_id))
		if cave == null:
			continue
		if not poi_id.is_empty() and cave.entrance_poi_id != poi_id:
			continue
		if not cave.allowed_biomes.is_empty() and not cave.allowed_biomes.has(biome.id):
			continue
		var tags_match := cave.allowed_environment_tags.is_empty()
		for tag in cave.allowed_environment_tags:
			if biome.environment_tags.has(tag):
				tags_match = true
		if tags_match:
			eligible.append(cave)
	if eligible.is_empty():
		return null
	var total := 0.0
	for cave in eligible:
		total += maxf(0.0, cave.entrance_weight)
	var roll := random.randf() * total
	for cave in eligible:
		roll -= maxf(0.0, cave.entrance_weight)
		if roll <= 0.0:
			return cave
	return eligible.back()

func _select_biome(elevation: PackedFloat32Array, moisture: PackedFloat32Array, temperature: PackedFloat32Array,
		world_position: Vector2i = Vector2i.ZERO) -> String:
	return _select_biome_at(_array_average(elevation), _array_average(moisture), _array_average(temperature),
			get_regional_noise_values(world_position.x, world_position.y))

func _select_biome_at(elevation: float, moisture: float, temperature: float, regional_values: Dictionary = {}) -> String:
	var regional_biome_id := ""
	if not regional_values.is_empty():
		regional_biome_id = _select_biome_from_fields(
			float(regional_values.get("elevation", elevation)),
			float(regional_values.get("moisture", moisture)),
			float(regional_values.get("temperature", temperature))
		)
	var regional_biome := get_biome(regional_biome_id)
	var config := get_configuration()
	var best_biome := ""
	var best_score := -INF
	var ids := get_biomes().keys()
	ids.sort()
	for biome_id in ids:
		var biome := get_biome(str(biome_id))
		if biome == null:
			continue
		var score := _biome_match_score(biome, elevation, moisture, temperature) * maxf(0.01, biome.rarity_weight)
		if regional_biome != null:
			if biome.id == regional_biome.id:
				score += config.regional_biome_weight
			elif regional_biome.transition_biome_ids.has(biome.id):
				score += config.transition_biome_weight
			elif regional_biome.preferred_neighbors.has(biome.id):
				score += config.preferred_neighbor_weight
		if score > best_score:
			best_score = score
			best_biome = biome.id
	if best_biome.is_empty() and not ids.is_empty():
		best_biome = str(ids[0])
	return best_biome

func _select_biome_from_fields(elevation: float, moisture: float, temperature: float) -> String:
	var best_biome := ""
	var best_score := -INF
	var ids := get_biomes().keys()
	ids.sort()
	for biome_id in ids:
		var biome := get_biome(str(biome_id))
		if biome == null:
			continue
		var score := _biome_match_score(biome, elevation, moisture, temperature) * maxf(0.01, biome.rarity_weight)
		if score > best_score:
			best_score = score
			best_biome = biome.id
	if best_biome.is_empty() and not ids.is_empty():
		best_biome = str(ids[0])
	return best_biome

func _biome_match_score(biome: BiomeDefinition, elevation: float, moisture: float, temperature: float) -> float:
	return _range_score(elevation, biome.elevation_range, 3.0) \
		+ _range_score(moisture, biome.moisture_range, 2.0) \
		+ _range_score(temperature, biome.temperature_range, 2.0)

func _range_score(value: float, range_value: Vector2, weight: float) -> float:
	var bounds := range_value if range_value != Vector2.ZERO else Vector2(0.0, 1.0)
	if value >= bounds.x and value <= bounds.y:
		return weight
	return maxf(0.0, weight - minf(absf(value - bounds.x), absf(value - bounds.y)) * weight)

func _array_average(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.5
	var total := 0.0
	for value in values:
		total += value
	return total / values.size()

func _normalized(value: float) -> float:
	return clampf((value + 1.0) / 2.0, 0.0, 1.0)
