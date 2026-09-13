## Deterministic, data-driven world-generation pipeline.
## This class defines how fields and stages are interpreted. It does not contain
## knowledge of particular biome, resource, cave, POI, or terrain-feature
## names.
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
## True while the most recent content discovery reported validation errors.
## Guards the error report so a world that fails validation logs its
## problems once per broken state instead of on every re-initialization.
var content_validation_reported: bool = false
## Memo of coherent-region cell decisions (WG-03). Keys are world-aligned
## cell coordinates; values carry the cell's dominant biome plus its keep or
## merge decision. Cleared whenever the world is (re)initialized, so a new
## seed never reuses decisions computed under an old field.
var _region_cell_cache: Dictionary = {}
## WG-05 memo for the on-demand shore-distance path. The cached instance of
## the content registry whose distance constraints were scanned, plus the
## scan result. On-demand queries only run a BFS when some content asset
## actually constrains its distance to water; a live world where every
## asset keeps the -1 sentinel pays zero distance cost. The registry is
## compared by instance, so initialize() (which creates a new registry) and
## any later registry swap invalidate the memo automatically.
var _distance_constraint_registry: WorldContentRegistry = null
var _distance_constrained_content: bool = false

signal chunk_generated(chunk_coords: Vector2i, data: Dictionary)
signal world_regenerated

func initialize(seed: int, config_override: WorldGenerationConfig = null) -> void:
	current_seed = seed
	configuration = config_override if config_override != null else _load_configuration()
	content_registry = WorldContentRegistry.new()
	content_registry.discover()
	if content_registry.has_validation_errors():
		# Content that fails validation must not silently shape a broken
		# world. Report every offending asset path once, keep the engine up
		# (query APIs still work), and let generate_chunk refuse to emit
		# chunks until the assets are fixed and the world is regenerated.
		if not content_validation_reported:
			content_validation_reported = true
			push_error("[WorldContentRegistry] World content failed validation (%d problem%s) — no chunks will be generated until the assets below are fixed:" % \
					[content_registry.validation_errors.size(), "" if content_registry.validation_errors.size() == 1 else "s"])
			for validation_error in content_registry.validation_errors:
				push_error("[WorldContentRegistry] %s" % validation_error)
	else:
		content_validation_reported = false
	_region_cell_cache.clear()
	_distance_constraint_registry = null
	_distance_constrained_content = false
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

func get_terrain_feature_definitions() -> Dictionary:
	return get_content_registry().terrain_features

## Generate one chunk through environment, water, biome, coherent-region,
## terrain-feature, and POI stages.
## Runtime resource/creature nodes are populated by Main after this base data.
func generate_chunk(chunk_coords: Vector2i, seed: int = -1) -> Dictionary:
	if seed < 0:
		seed = current_seed
	if generation_context == null or current_seed != seed:
		initialize(seed)
	# A world whose content assets failed startup validation is not
	# trustworthy; refuse to emit chunks the same way out-of-bounds chunks
	# are refused. Fixing the assets and regenerating re-runs discovery.
	if content_registry != null and content_registry.has_validation_errors():
		return {}
	if not get_configuration().is_chunk_in_bounds(chunk_coords):
		return {}

	var fields := _generate_environmental_fields(chunk_coords)
	var water_mask := PackedByteArray()
	var biome_map := PackedStringArray()
	var water_tiles: Array[Vector2i] = []
	var size: int = get_configuration().chunk_size_tiles
	# WG-05: the shore distance field, chunk slice (saturated to the cap)
	# and full rect, as sampled around this chunk.
	var chunk_dist: PackedInt32Array = fields["water_dist"]
	var dist_rect: PackedInt32Array = fields["water_dist_rect"]
	var dist_rect_start: Vector2i = fields["water_dist_rect_start"]
	var dist_rect_side: int = int(fields["water_dist_rect_side"])
	for index in range(fields["elevation"].size()):
		var world_x: int = fields["world_start"].x + (index % size)
		var world_y: int = fields["world_start"].y + (index / size)
		var elevation: float = fields["elevation"][index]
		var moisture: float = fields["moisture"][index]
		var is_water := _is_water(elevation, moisture, fields["water"][index])
		water_mask.append(1 if is_water else 0)
		if is_water:
			water_tiles.append(Vector2i(world_x, world_y))
		# WG-05: land tiles pass their precomputed shore distance into
		# selection; water tiles keep the -1 sentinel, which only vetoes
		# distance-constrained biomes (live worlds define none, so raw
		# selection is unchanged when the field is absent).
		var shore_distance: int = -1
		if chunk_dist.size() == size * size and water_mask[index] == 0:
			shore_distance = chunk_dist[index]
		biome_map.append(_select_biome_at(elevation, moisture, fields["temperature"][index],
				get_regional_noise_values(world_x, world_y), shore_distance))
	# Coherent-region stage (WG-03): merge raw biome fragments that are too
	# small for the region sizes the data declares, and record the per-cell
	# decisions so adjacent chunks provably agree at shared boundaries.
	# Dormant (no-op, byte-identical map) for worlds whose biomes keep the
	# default minimum_region_size of 0. The POI stage below sees the
	# smoothed map.
	var region_cells := _apply_region_coherence(chunk_coords, fields["world_start"],
			biome_map, water_mask)
	var data := {
		"coords": chunk_coords,
		"elevation": fields["elevation"],
		"moisture": fields["moisture"],
		"temperature": fields["temperature"],
		"water": fields["water"],
		"water_mask": water_mask,
		"water_tiles": water_tiles,
		# WG-05: physical water classification, kept out of the biome
		# system on purpose. water_class is one of "land" / "shore" (a land
		# tile with a water 8-neighbor) / "coast" (a water tile with a land
		# 8-neighbor) / "deep_water". water_origin is "ocean" (water at or
		# below water_level), "lake" (water above it), or "" on land.
		# distance_to_water is the Chebyshev distance to the nearest water
		# tile: 0 on water, 1..cap - 1 exact, and the cap value meaning "no
		# water within cap - 1 tiles". All three new payload keys; arrays are
		# empty when the config cap is 0.
		"water_class": fields["water_class"],
		"water_origin": fields["water_origin"],
		"distance_to_water": chunk_dist,
		"biome": _select_biome(fields["elevation"], fields["moisture"], fields["temperature"],
				fields["world_start"] + Vector2i(size / 2, size / 2),
				chunk_dist[size / 2 * size + size / 2]
						if chunk_dist.size() == size * size and water_mask[size / 2 * size + size / 2] == 0 else -1),
		"biomes": biome_map,
		"region_cells": region_cells,
		"feature_candidates": _generate_feature_candidates(chunk_coords, biome_map, water_mask,
				chunk_dist, dist_rect, dist_rect_start, dist_rect_side),
		"terrain_features": {"water_tile_count": water_tiles.size()},
		"poi_candidates": _generate_poi_candidates(chunk_coords, biome_map, water_mask, chunk_dist),
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

## Biome at a tile after the coherent-region stage: the raw selection unless
## the tile's region cell was merged into a neighbouring biome (WG-03).
## On-demand queries share the same memoised cell decisions that chunk
## payloads carry, so queried and rendered biomes never disagree. Water
## tiles keep their raw biome in both paths: the stage rewrites land tiles
## only, because water is a physical system carried by the water mask.
func get_biome_at_world(world_x: int, world_y: int) -> String:
	if noise_layers == null or not is_instance_valid(noise_layers):
		initialize(current_seed)
	var biome_id := _raw_biome_at_world(world_x, world_y)
	if get_configuration().region_cell_size_tiles > 0 and not _region_minimum_sizes().is_empty() \
			and not is_water_at_world(world_x, world_y):
		var entry := _region_decision_for_cell(_cell_coords_for_tile(world_x, world_y))
		if str(entry.get("source", "")) == "merged":
			biome_id = str(entry.get("biome", biome_id))
	return biome_id

## Raw per-tile biome selection from the environmental fields, before the
## coherent-region stage. Chunk generation and the deterministic halo around
## a chunk both use this, so region decisions rest on one shared raw map.
func _raw_biome_at_world(world_x: int, world_y: int) -> String:
	var values := get_noise_values(float(world_x), float(world_y))
	# Water tiles keep the -1 sentinel (mirroring the chunk payload): a
	# distance-to-water constraint binds land placement, so raw (unconstrained)
	# selection applies on water in both paths.
	var shore_distance: int = -1
	if not _is_water(values["elevation"], values["moisture"], values["water"]):
		shore_distance = _on_demand_shore_distance(world_x, world_y)
	return _select_biome_at(values["elevation"], values["moisture"], values["temperature"],
			get_regional_noise_values(world_x, world_y), shore_distance)

func is_water_at_world(world_x: int, world_y: int) -> bool:
	var values := get_noise_values(float(world_x), float(world_y))
	return _is_water(values["elevation"], values["moisture"], values["water"])

## WG-05: physical water class of a world tile: "land" (no water in its
## 8-neighborhood), "shore" (land with a water 8-neighbor), "coast" (water
## with a land 8-neighbor), or "deep_water" (water ringed by water).
## Mirrors the per-chunk water_class payload, so on-demand queries and
## rendered chunks never disagree.
func get_water_class_at_world(world_x: int, world_y: int) -> String:
	var values := get_noise_values(float(world_x), float(world_y))
	var is_water_tile := _is_water(values["elevation"], values["moisture"], values["water"])
	var adjacent_water := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if is_water_at_world(world_x + dx, world_y + dy):
				adjacent_water += 1
	if is_water_tile:
		return "coast" if adjacent_water < 8 else "deep_water"
	return "shore" if adjacent_water > 0 else "land"

## WG-05: water origin of a world tile: "ocean" for water at or below
## water_level, "lake" for water above it, "" for land tiles. Whether the
## lake path is reachable at all is a config decision (lake_level vs
## water_level).
func get_water_origin_at_world(world_x: int, world_y: int) -> String:
	var values := get_noise_values(float(world_x), float(world_y))
	if not _is_water(values["elevation"], values["moisture"], values["water"]):
		return ""
	return "ocean" if values["elevation"] < get_configuration().water_level else "lake"

## WG-05: on-demand shore distance for a world tile: Chebyshev distance
## (8-neighbor tiles) to the nearest water tile. 0 on a water tile,
## 1..cap - 1 exact, and the cap value meaning "no water within cap - 1
## tiles". Returns -1 when the field is disabled (config cap 0). Shares the
## BFS helper with the chunk payload, so both paths agree at shared tiles.
## Worlds where no content constrains its distance to water pay only the
## per-tile water query: the BFS runs only behind the registry-instance
## memo, so an unconstrained world stays at zero distance cost.
func get_distance_to_water_at_world(world_x: int, world_y: int) -> int:
	if noise_layers == null or not is_instance_valid(noise_layers):
		initialize(current_seed)
	return _on_demand_shore_distance(world_x, world_y)

## WG-05: BFS-backed shore distance for one tile. Gated on the memo: the
## scan for distance-constrained content is re-run only when the registry
## instance changes (initialize() creates a new one, and the harness may
## install a fixture registry after initialization).
func _on_demand_shore_distance(world_x: int, world_y: int) -> int:
	if not _any_content_distance_constrained():
		return -1
	var water_cap: int = get_configuration().distance_to_water_cap_tiles
	if water_cap <= 0:
		return -1
	var rect_start := Vector2i(world_x, world_y) - Vector2i(water_cap, water_cap)
	var rect_side: int = 2 * water_cap + 1
	var rect_elevation := PackedFloat32Array()
	var rect_moisture := PackedFloat32Array()
	var rect_water := PackedFloat32Array()
	rect_elevation.resize(rect_side * rect_side)
	rect_moisture.resize(rect_side * rect_side)
	rect_water.resize(rect_side * rect_side)
	for y in range(rect_side):
		for x in range(rect_side):
			var tile_x: int = rect_start.x + x
			var tile_y: int = rect_start.y + y
			var values := get_noise_values(float(tile_x), float(tile_y))
			rect_elevation[y * rect_side + x] = values["elevation"]
			rect_moisture[y * rect_side + x] = values["moisture"]
			rect_water[y * rect_side + x] = values["water"]
	var dist_rect := _build_water_distance_rect(rect_start, rect_side, water_cap,
			rect_elevation, rect_moisture, rect_water)
	return _distance_from_rect(world_x, world_y, dist_rect, rect_start, rect_side)

## WG-05: true when any registered content kind (biomes, POIs, terrain
## features, resources) declares a min or max distance to water. The result
## is memoized per registry instance, so the on-demand BFS runs only for
## worlds whose content actually uses the distance field; a live world where
## every asset keeps the -1 sentinel never pays the BFS cost.
func _any_content_distance_constrained() -> bool:
	if _distance_constraint_registry != null and _distance_constraint_registry == content_registry:
		return _distance_constrained_content
	_distance_constraint_registry = content_registry
	_distance_constrained_content = false
	if content_registry != null:
		for biome_id in content_registry.biomes.keys():
			var biome := content_registry.get_biome(str(biome_id))
			if biome != null and (biome.min_distance_to_water != -1 or biome.max_distance_to_water != -1):
				_distance_constrained_content = true
				break
		if not _distance_constrained_content:
			for poi_id in content_registry.pois.keys():
				var poi := content_registry.get_poi(str(poi_id))
				if poi != null and (poi.min_distance_to_water != -1 or poi.max_distance_to_water != -1):
					_distance_constrained_content = true
					break
		if not _distance_constrained_content:
			for feature_id in content_registry.terrain_features.keys():
				var feature := content_registry.get_terrain_feature(str(feature_id))
				if feature != null and (feature.min_distance_to_water != -1
						or feature.max_distance_to_water != -1):
					_distance_constrained_content = true
					break
		if not _distance_constrained_content:
			for resource_id in content_registry.resources.keys():
				var resource := content_registry.get_resource(str(resource_id))
				if resource != null and (resource.min_distance_to_water != -1
						or resource.max_distance_to_water != -1):
					_distance_constrained_content = true
					break
	return _distance_constrained_content

## WG-05: shared distance-to-water gate for every content kind (biomes,
## POIs, terrain features, resources) and for the resource spawner. A -1 on
## a side means "no constraint on that side"; both -1 vetoes nothing, which
## is the default for every live asset and keeps existing worlds
## byte-identical. A -1 measured distance (field disabled, or a caller that
## did not saturate) vetoes every constrained asset rather than guessing.
func definition_within_distance(min_distance: int, max_distance: int, shore_distance: int) -> bool:
	if min_distance < 0 and max_distance < 0:
		return true
	if shore_distance < 0:
		return false
	if min_distance >= 0 and shore_distance < min_distance:
		return false
	if max_distance >= 0 and shore_distance > max_distance:
		return false
	return true

## WG-05: read the shore distance a tile holds in a precomputed rect, with
## the same saturation as the chunk payload: -1 (no water within cap - 1)
## reads as the cap. A tile outside the rect, or a missing/mis-sized rect
## (field disabled), reads as -1 so any distance-constrained asset vetoes
## it rather than guessing.
func _distance_from_rect(world_x: int, world_y: int, dist_rect: PackedInt32Array,
		rect_start: Vector2i, rect_side: int) -> int:
	if dist_rect.size() != rect_side * rect_side:
		return -1
	var local := Vector2i(world_x, world_y) - rect_start
	if local.x < 0 or local.y < 0 or local.x >= rect_side or local.y >= rect_side:
		return -1
	var raw_dist: int = dist_rect[local.y * rect_side + local.x]
	return get_configuration().distance_to_water_cap_tiles if raw_dist < 0 else raw_dist

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
	# WG-05: sample one rectangle grown by the shore-distance cap around the
	# chunk (UNCLAMPED: the fields are pure coordinate functions, so water
	# beyond the finite world is real water) and slice the chunk core out
	# of it. The sliced core is byte-identical to the pre-WG-05 chunk-only
	# sampling; the halo is what makes the per-chunk distance field exact
	# for every core tile without a second BFS.
	var water_cap: int = get_configuration().distance_to_water_cap_tiles
	var rect_start := world_start - Vector2i(water_cap, water_cap)
	var rect_side: int = size + 2 * water_cap
	var rect_elevation := PackedFloat32Array()
	var rect_moisture := PackedFloat32Array()
	var rect_temperature := PackedFloat32Array()
	var rect_water := PackedFloat32Array()
	rect_elevation.resize(rect_side * rect_side)
	rect_moisture.resize(rect_side * rect_side)
	rect_temperature.resize(rect_side * rect_side)
	rect_water.resize(rect_side * rect_side)
	for y in range(rect_side):
		for x in range(rect_side):
			var world_x := float(rect_start.x + x)
			var world_y := float(rect_start.y + y)
			rect_elevation[y * rect_side + x] = _normalized(noise_layers.get_elevation(world_x, world_y))
			rect_moisture[y * rect_side + x] = _normalized(noise_layers.get_moisture(world_x, world_y))
			rect_temperature[y * rect_side + x] = _normalized(noise_layers.get_temperature(world_x, world_y))
			rect_water[y * rect_side + x] = _normalized(noise_layers.get_water(world_x, world_y))
	var elevation := PackedFloat32Array()
	var moisture := PackedFloat32Array()
	var temperature := PackedFloat32Array()
	var water := PackedFloat32Array()
	for y in range(size):
		var row_base: int = (y + water_cap) * rect_side + water_cap
		elevation.append_array(rect_elevation.slice(row_base, row_base + size))
		moisture.append_array(rect_moisture.slice(row_base, row_base + size))
		temperature.append_array(rect_temperature.slice(row_base, row_base + size))
		water.append_array(rect_water.slice(row_base, row_base + size))
	var water_dist := PackedInt32Array()
	var water_dist_rect := PackedInt32Array()
	var water_class := PackedStringArray()
	var water_origin := PackedStringArray()
	if water_cap > 0:
		water_dist_rect = _build_water_distance_rect(rect_start, rect_side, water_cap,
				rect_elevation, rect_moisture, rect_water)
		water_dist.resize(size * size)
		for y in range(size):
			var row_base: int = (y + water_cap) * rect_side + water_cap
			for x in range(size):
				var raw_dist: int = water_dist_rect[row_base + x]
				# Saturated: tiles at or beyond the cap read the cap, i.e.
				# "no water within cap - 1 tiles".
				water_dist[y * size + x] = water_cap if raw_dist < 0 else raw_dist
		# Class/origin per core tile reads the rect's water mask: with
		# cap > 0 the core's 3x3 neighbourhood always fits inside the rect,
		# so no extra sampling is needed. A water tile is "coast" when any
		# of its 8 neighbours is land, else "deep_water"; a land tile is
		# "shore" when any neighbour is water, else "land". A water
		# tile's origin is "ocean" at or below water_level, "lake" above
		# it (the config decides whether the lake path is reachable); land
		# tiles carry an empty origin.
		var water_level: float = get_configuration().water_level
		for y in range(size):
			for x in range(size):
				_tile_water_class_origin(y, x, water_cap, rect_side,
						rect_elevation, rect_moisture, rect_water, water_level,
						water_class, water_origin)
	return {
		"world_start": world_start,
		"elevation": elevation,
		"moisture": moisture,
		"temperature": temperature,
		"water": water,
		"water_dist": water_dist,
		"water_dist_rect": water_dist_rect,
		"water_dist_rect_start": rect_start,
		"water_dist_rect_side": rect_side,
		"water_class": water_class,
		"water_origin": water_origin
	}

## WG-05: fill the per-tile water class and origin of the rect core into
## the payload arrays. The 3x3 neighbourhood of every core tile is read
## from the surrounding rect arrays, so the values agree with the
## on-demand queries that sample the same unclamped fields.
func _tile_water_class_origin(core_y: int, core_x: int, water_cap: int, rect_side: int,
		rect_elevation: PackedFloat32Array, rect_moisture: PackedFloat32Array,
		rect_water: PackedFloat32Array, water_level: float,
		water_class: PackedStringArray, water_origin: PackedStringArray) -> void:
	var ry: int = core_y + water_cap
	var rx: int = core_x + water_cap
	var center: int = ry * rect_side + rx
	var tile_is_water := _is_water(rect_elevation[center], rect_moisture[center], rect_water[center])
	var adjacent_water := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var ny: int = ry + dy
			var nx: int = rx + dx
			if ny < 0 or ny >= rect_side or nx < 0 or nx >= rect_side:
				continue
			var neighbour: int = ny * rect_side + nx
			if _is_water(rect_elevation[neighbour], rect_moisture[neighbour], rect_water[neighbour]):
				adjacent_water += 1
	if tile_is_water:
		water_class.append("coast" if adjacent_water < 8 else "deep_water")
		water_origin.append("ocean" if rect_elevation[center] < water_level else "lake")
	elif adjacent_water > 0:
		water_class.append("shore")
		water_origin.append("")
	else:
		water_class.append("land")
		water_origin.append("")

## WG-05: multi-source 8-neighbour (Chebyshev) BFS over a rect of the
## water field. Every water tile in the rect is a source at distance 0;
## the result holds the exact distance to the nearest water tile for every
## tile within cap - 1 and -1 beyond (the chunk slice and the on-demand
## queries saturate those to the cap). The rect is never clamped to the
## finite world: water outside the world is real water and must count
## toward shore distance.
func _build_water_distance_rect(rect_start: Vector2i, rect_side: int, cap: int,
		rect_elevation: PackedFloat32Array, rect_moisture: PackedFloat32Array,
		rect_water: PackedFloat32Array) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(rect_side * rect_side)
	# resize() zero-fills, but the expansion guard below tests for -1, so
	# the unvisited sentinel must be written explicitly: without it every
	# land tile reads 0 instead of its real (or saturated) distance.
	dist.fill(-1)
	var queue := PackedInt32Array()
	for y in range(rect_side):
		for x in range(rect_side):
			var i: int = y * rect_side + x
			if _is_water(rect_elevation[i], rect_moisture[i], rect_water[i]):
				dist[i] = 0
				queue.append(i)
	var head: int = 0
	while head < queue.size():
		var qi: int = int(queue[head])
		head += 1
		var qy: int = qi / rect_side
		var qx: int = qi % rect_side
		for dy in range(-1, 2):
			var ny: int = qy + dy
			if ny < 0 or ny >= rect_side:
				continue
			for dx in range(-1, 2):
				var nx: int = qx + dx
				if nx < 0 or nx >= rect_side:
					continue
				var j: int = ny * rect_side + nx
				if dist[j] == -1:
					dist[j] = dist[qi] + 1
					# Stop the wavefront at the cap: tiles at exactly the
					# cap are set (and read as the cap) but never
					# expanded, so everything beyond stays -1.
					if dist[j] < cap:
						queue.append(j)
	return dist

func _is_water(elevation: float, moisture: float, water_value: float) -> bool:
	var config := get_configuration()
	return elevation < config.water_level \
		or (elevation < config.lake_level and moisture >= config.lake_moisture_threshold \
		and water_value >= config.lake_noise_threshold)

## Generic POI candidate stage. Every discovered POIDefinition contributes
## candidates: anchors come from the POI's own spacing grid, eligibility from
## its biome/environment constraints, and placement probability from its own
## spawn_weight. Caves are one consumer of this stage, not the stage itself:
## when a cave definition links to the POI, the candidate additionally scales
## the chance by the biome's cave-entrance suitability and carries the stable
## cave identity that CaveEntrance runtime nodes are built from. POIs with no
## cave link get plain candidates (empty cave fields) that generic POI
## runtime nodes load. No content name is special here; adding a POI asset is
## all it takes for it to be discovered, generated, and loaded.
func _generate_poi_candidates(chunk_coords: Vector2i, biome_map: PackedStringArray, water_mask: PackedByteArray,
		chunk_dist: PackedInt32Array = PackedInt32Array()) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if get_poi_definitions().is_empty():
		return candidates
	var size := get_configuration().chunk_size_tiles
	var world_start := chunk_coords * size
	var poi_ids := get_poi_definitions().keys()
	poi_ids.sort()
	for poi_id_variant in poi_ids:
		var poi := get_content_registry().get_poi(str(poi_id_variant))
		if poi == null:
			continue
		var cave_linked := _has_cave_for_poi(poi.id)
		for tile in _poi_anchor_tiles_in_chunk(poi, world_start, size):
			var local := tile - world_start
			var index := local.y * size + local.x
			if index < 0 or index >= water_mask.size() or water_mask[index] != 0:
				continue
			# WG-05: distance-constrained POIs veto anchors outside their
			# [min, max] shore distance BEFORE the spawn roll, so the veto
			# consumes no RNG and placement stays deterministic. An anchor
			# the chunk's distance field does not cover keeps the -1
			# sentinel, which vetoes any constraint.
			var anchor_distance: int = -1
			if index < chunk_dist.size():
				anchor_distance = chunk_dist[index]
			if not definition_within_distance(poi.min_distance_to_water, poi.max_distance_to_water,
					anchor_distance):
				continue
			var biome_id := str(biome_map[index])
			var biome := get_biome(biome_id)
			if biome == null or not _poi_allows_biome(poi, biome):
				continue
			var random := RandomNumberGenerator.new()
			random.seed = generation_context.tile_seed(tile,
					WorldGenerationContext.stable_string_seed(poi.id) ^ 0x45D9F3B)
			if cave_linked:
				var chance := clampf(biome.cave_entrance_suitability * maxf(0.0, poi.spawn_weight), 0.0, 1.0)
				if random.randf() > chance:
					continue
				var cave := _choose_cave_for_biome(biome, random, poi.id)
				if cave == null:
					continue
				candidates.append({
					"poi_id": poi.id,
					"poi_category": poi.category,
					"poi_name": poi.display_name,
					"cave_type_id": cave.id,
					"cave_id": generation_context.cave_identity(tile, cave.id),
					"x": tile.x,
					"y": tile.y,
					"biome": biome_id
				})
			else:
				var chance := clampf(poi.spawn_weight, 0.0, 1.0)
				if random.randf() > chance:
					continue
				candidates.append({
					"poi_id": poi.id,
					"poi_category": poi.category,
					"poi_name": poi.display_name,
					"cave_type_id": "",
					"cave_id": "",
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

## ---------------------------------------------------------------------------
## Terrain-feature candidate stage (WG-04)
## ---------------------------------------------------------------------------
## Terrain features (cliffs, clearings, scree, ...) are content: each
## TerrainFeatureDefinition asset declares its own spacing grid, spawn
## probability, biome/environment eligibility, a footprint radius, and
## influence tags. This stage turns every discovered asset into deterministic
## per-tile candidates — the generic seam for larger ground structure.
##
## A feature's footprint may extend past the chunk the anchor sits in, so a
## chunk's payload also carries halo candidates anchored in neighbouring
## chunks (each candidate marks which chunk owns the anchor). The runtime
## spawns one marker per feature, only in the owning chunk, so every feature
## exists exactly once; mask consumers (e.g. the resource spawner's
## spawn-block tag) read every entry.
##
## Candidates are world-pure: anchor, eligibility, and roll depend on the
## anchor tile and the asset's data alone, so chunks generated in any order
## agree everywhere, including at boundaries. Out-of-world anchors are
## skipped (features exist only inside the finite world). With no feature
## assets the stage emits nothing and payloads are unchanged apart from an
## empty feature_candidates key.
func _generate_feature_candidates(chunk_coords: Vector2i, biome_map: PackedStringArray, water_mask: PackedByteArray,
		chunk_dist: PackedInt32Array = PackedInt32Array(), dist_rect: PackedInt32Array = PackedInt32Array(),
		dist_rect_start: Vector2i = Vector2i.ZERO, dist_rect_side: int = 0) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if get_terrain_feature_definitions().is_empty():
		return candidates
	var size := get_configuration().chunk_size_tiles
	var world_start := chunk_coords * size
	var feature_ids := get_terrain_feature_definitions().keys()
	feature_ids.sort()
	for feature_id_variant in feature_ids:
		var feature := get_content_registry().get_terrain_feature(str(feature_id_variant))
		if feature == null:
			continue
		for tile in _feature_anchor_tiles_in_chunk(feature, world_start, size):
			if not _is_tile_in_bounds(tile.x, tile.y):
				continue
			var radius := maxi(0, feature.footprint_radius_tiles)
			if tile.x + radius < world_start.x or tile.x - radius > world_start.x + size - 1 \
					or tile.y + radius < world_start.y or tile.y - radius > world_start.y + size - 1:
				continue
			var in_chunk := tile.x >= world_start.x and tile.x < world_start.x + size \
					and tile.y >= world_start.y and tile.y < world_start.y + size
			var biome_id := ""
			# WG-05: the anchor's shore distance. In-chunk anchors read the
			# chunk's precomputed slice; halo anchors read the same rect
			# (saturated). Anchors outside the rect keep the -1 sentinel,
			# which vetoes any distance constraint (documented: halo
			# anchors beyond the field radius are skipped when constrained).
			var anchor_distance: int = -1
			if in_chunk:
				var index := (tile.y - world_start.y) * size + (tile.x - world_start.x)
				if index < 0 or index >= water_mask.size() or water_mask[index] != 0:
					continue
				biome_id = str(biome_map[index])
				if index < chunk_dist.size():
					anchor_distance = chunk_dist[index]
			else:
				if is_water_at_world(tile.x, tile.y):
					continue
				biome_id = get_biome_at_world(tile.x, tile.y)
				anchor_distance = _distance_from_rect(tile.x, tile.y, dist_rect, dist_rect_start, dist_rect_side)
			if not definition_within_distance(feature.min_distance_to_water, feature.max_distance_to_water,
					anchor_distance):
				continue
			var biome := get_biome(biome_id)
			if biome == null or not _feature_allows_biome(feature, biome):
				continue
			var random := RandomNumberGenerator.new()
			random.seed = generation_context.tile_seed(tile,
					WorldGenerationContext.stable_string_seed(feature.id) ^ 0x9C3B6F1E)
			if random.randf() > clampf(feature.spawn_weight, 0.0, 1.0):
				continue
			candidates.append({
				"feature_id": feature.id,
				"feature_category": feature.category,
				"feature_name": feature.display_name,
				"feature_identity": "%s@%d,%d" % [feature.id, tile.x, tile.y],
				"footprint_radius_tiles": radius,
				"in_chunk": in_chunk,
				"influence_tags": feature.influence_tags.duplicate(),
				"x": tile.x,
				"y": tile.y,
				"biome": biome_id
			})
	return candidates

## Each feature uses a deterministic grid offset derived from its data ID so
## anchors from different features do not align. Because a feature's
## footprint can cross a chunk boundary, the grid is sampled over the chunk
## expanded by the footprint radius; the caller keeps only anchors whose
## footprint actually touches the chunk.
func _feature_anchor_tiles_in_chunk(feature: TerrainFeatureDefinition, world_start: Vector2i, size: int) -> Array[Vector2i]:
	var spacing := maxi(1, feature.min_spacing_tiles)
	var radius := maxi(0, feature.footprint_radius_tiles)
	var offset_random := RandomNumberGenerator.new()
	offset_random.seed = generation_context.tile_seed(Vector2i.ZERO,
			WorldGenerationContext.stable_string_seed(feature.id) ^ 0x5A7D2E94)
	var offset := Vector2i(offset_random.randi_range(0, spacing - 1), offset_random.randi_range(0, spacing - 1))
	var scan_start := world_start - Vector2i(radius, radius)
	var scan_end := world_start + Vector2i(size - 1, size - 1) + Vector2i(radius, radius)
	var first_cell := Vector2i(
		floori(float(scan_start.x - offset.x) / float(spacing)),
		floori(float(scan_start.y - offset.y) / float(spacing))
	)
	var last_cell := Vector2i(
		floori(float(scan_end.x - offset.x) / float(spacing)),
		floori(float(scan_end.y - offset.y) / float(spacing))
	)
	var anchors: Array[Vector2i] = []
	for cell_y in range(first_cell.y, last_cell.y + 1):
		for cell_x in range(first_cell.x, last_cell.x + 1):
			var anchor := Vector2i(cell_x * spacing, cell_y * spacing) + offset
			if anchor.x >= scan_start.x and anchor.x <= scan_end.x \
					and anchor.y >= scan_start.y and anchor.y <= scan_end.y:
				anchors.append(anchor)
	return anchors

func _feature_allows_biome(feature: TerrainFeatureDefinition, biome: BiomeDefinition) -> bool:
	if not feature.allowed_biomes.is_empty() and not feature.allowed_biomes.has(biome.id):
		return false
	for required_tag in feature.required_environment_tags:
		if not biome.environment_tags.has(required_tag):
			return false
	return true

## Query for the cave consumer: true when any discovered cave definition
## declares this POI as its entrance. Routing only — POIs no cave references
## are still discovered, generated, and loaded as plain POIs.
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
		world_position: Vector2i = Vector2i.ZERO, shore_distance: int = -1) -> String:
	return _select_biome_at(_array_average(elevation), _array_average(moisture), _array_average(temperature),
			get_regional_noise_values(world_position.x, world_position.y), shore_distance)

func _select_biome_at(elevation: float, moisture: float, temperature: float,
		regional_values: Dictionary = {}, shore_distance: int = -1) -> String:
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
		# WG-05: distance-constrained biomes are vetoed by the tile's
		# precomputed shore distance (land tiles), or by the -1 sentinel
		# (water tiles, or the field disabled). Every live asset keeps -1
		# on both sides, so for an unconstrained world this gate vetoes
		# nothing and selection is byte-identical to pre-WG-05.
		if not definition_within_distance(biome.min_distance_to_water, biome.max_distance_to_water,
				shore_distance):
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

## ---------------------------------------------------------------------------
## Coherent-region stage (WG-03)
## ---------------------------------------------------------------------------
## Biome data may declare minimum_region_size: the fewest tiles a coherent
## fragment of that biome should cover. This stage turns that metadata into
## measurable geography. It works on a world-aligned grid of square cells
## (WorldGenerationConfig.region_cell_size_tiles). Because that side divides
## the chunk size, cells never straddle chunk boundaries: every chunk and
## every on-demand biome query computes the same decisions from its own
## coordinates alone, sampling a small deterministic halo of neighbouring
## cells without loading neighbouring chunks.
##
## Per cell, the stage records the dominant biome among the cell's land
## tiles (water tiles never count — water is a physical system, not a
## biome). A cell whose dominant biome's connected cell window is smaller
## than the cells that biome's minimum_region_size requires is infeasible:
## a raw island of a biome the data says needs more room. Infeasible cells
## are merged into a neighbouring cell's biome, preferring receivers the raw
## biome lists in preferred_neighbors, then transition_biome_ids, then
## adjacency count, then id order. The transition band the data allows a
## biome to bleed across a border is derived from the same number:
## minimum_region_size / 2 tiles.
##
## Decisions are single-pass and pure: every cell depends on the raw biome
## field only, so chunks generated in any order agree at shared boundaries,
## and (re)initializing the generator clears the memo. Worlds whose biomes
## all keep the default minimum_region_size of 0 run the stage as a no-op
## and keep byte-identical biome maps.

func _tile_chunk_coords(world_x: int, world_y: int) -> Vector2i:
	var size: int = get_configuration().chunk_size_tiles
	return Vector2i(floori(float(world_x) / float(size)),
			floori(float(world_y) / float(size)))

func _cell_coords_for_tile(world_x: int, world_y: int) -> Vector2i:
	var cell_size: int = get_configuration().region_cell_size_tiles
	return Vector2i(floori(float(world_x) / float(cell_size)),
			floori(float(world_y) / float(cell_size)))

func _cell_axis_for_tile(tile_coord: int) -> int:
	return floori(float(tile_coord) / float(get_configuration().region_cell_size_tiles))

## Per-biome minimum region sizes read from the live content registry.
## An empty map means no biome opts into the coherent-region stage, so it
## stays dormant and biome maps remain byte-identical to raw selection.
func _region_minimum_sizes() -> Dictionary:
	var result: Dictionary = {}
	if content_registry == null or not is_instance_valid(content_registry):
		return result
	for biome_id in get_biomes().keys():
		var biome := get_biome(str(biome_id))
		if biome != null and biome.minimum_region_size > 0:
			result[str(biome_id)] = int(biome.minimum_region_size)
	return result

## Square window radius, in cells, around a cell that is large enough to
## hold that cell's minimum fragment count.
func _region_window_radius(min_region_size: int, cell_size: int) -> int:
	var cells_needed: int = ceili(float(min_region_size) / float(cell_size * cell_size))
	return maxi(1, ceili(sqrt(float(maxi(cells_needed, 1))) / 2.0))

## Chunk-level coordinates of the world-aligned cell a tile belongs to, via
## the tile's chunk. Used to skip cells entirely outside the finite world.
func _is_tile_in_bounds(world_x: int, world_y: int) -> bool:
	return get_configuration().is_chunk_in_bounds(_tile_chunk_coords(world_x, world_y))

## Dominant biome of a world-aligned cell, counted over its land tiles.
## Tiles inside an already-generated chunk reuse that chunk's raw map; every
## other tile (the deterministic halo around the chunk) is sampled directly
## from the field. Either way the answer is a pure function of tile
## coordinates, so it is identical no matter which chunk or on-demand query
## asked for it first. Water-only cells report the empty id.
func _cell_dominant_biome(cell: Vector2i,
		local_biome_map: PackedStringArray = PackedStringArray(),
		local_water_mask: PackedByteArray = PackedByteArray(),
		local_world_start: Vector2i = Vector2i.ZERO,
		local_size: int = 0) -> String:
	if _region_cell_cache.has(cell):
		return str(_region_cell_cache[cell].get("dominant", ""))
	var cell_size: int = get_configuration().region_cell_size_tiles
	var origin := cell * cell_size
	var counts: Dictionary = {}
	for dy in range(cell_size):
		for dx in range(cell_size):
			var world_x: int = origin.x + dx
			var world_y: int = origin.y + dy
			if not _is_tile_in_bounds(world_x, world_y):
				continue
			var biome_id := ""
			var is_water := false
			if local_size > 0 \
					and world_x >= local_world_start.x \
					and world_x < local_world_start.x + local_size \
					and world_y >= local_world_start.y \
					and world_y < local_world_start.y + local_size:
				var index: int = (world_y - local_world_start.y) * local_size \
						+ (world_x - local_world_start.x)
				if index >= 0 and index < local_biome_map.size():
					biome_id = str(local_biome_map[index])
					is_water = index < local_water_mask.size() \
							and local_water_mask[index] != 0
			else:
				biome_id = _raw_biome_at_world(world_x, world_y)
				is_water = is_water_at_world(world_x, world_y)
			if is_water:
				continue
			counts[biome_id] = int(counts.get(biome_id, 0)) + 1
	if counts.is_empty():
		# Same key set as every other decision entry (including "raw"), so
		# payload entries are schema-uniform no matter which path cached
		# them first (this halo path or the decision path).
		_region_cell_cache[cell] = {"cell": cell, "dominant": "", "raw": "", "biome": "", "source": "water"}
		return ""
	var best_count := -1
	var tied: PackedStringArray = PackedStringArray()
	for biome_id in counts:
		var count := int(counts[biome_id])
		if count > best_count:
			best_count = count
			tied.clear()
			tied.append(str(biome_id))
		elif count == best_count:
			tied.append(str(biome_id))
	var dominant := str(tied[0])
	if tied.size() > 1:
		# Ties fall back to the regional biome at the cell centre (the
		# data-defined regional context), then to id order.
		var regional_values := get_regional_noise_values(
				origin.x + cell_size / 2, origin.y + cell_size / 2)
		var regional := _select_biome_from_fields(
				float(regional_values.get("elevation", 0.5)),
				float(regional_values.get("moisture", 0.5)),
				float(regional_values.get("temperature", 0.5)))
		if regional != "" and regional in tied:
			dominant = regional
		else:
			var sorted_tied := tied
			sorted_tied.sort()
			dominant = str(sorted_tied[0])
	_region_cell_cache[cell] = {"cell": cell, "dominant": dominant}
	return dominant

## Complete the coherent-region decision for one cell: keep its dominant
## biome, or merge the cell into a neighbouring cell's biome when the raw
## fragment is smaller than that biome's data-defined minimum region size.
## The returned entry (and the cached one it updates) carries:
##   cell     — the world-aligned cell coordinate
##   raw      — the dominant biome of the cell's land tiles
##   biome    — the biome tiles in this cell should use after the stage
##   source   — "kept", "merged", or "water" (no land tiles)
func _region_decision_for_cell(cell: Vector2i,
		local_biome_map: PackedStringArray = PackedStringArray(),
		local_water_mask: PackedByteArray = PackedByteArray(),
		local_world_start: Vector2i = Vector2i.ZERO,
		local_size: int = 0) -> Dictionary:
	if _region_cell_cache.has(cell) and _region_cell_cache[cell].has("source"):
		var cached: Dictionary = _region_cell_cache[cell]
		cached["cell"] = cell
		return cached
	var cell_size: int = get_configuration().region_cell_size_tiles
	var dominant := _cell_dominant_biome(cell, local_biome_map, local_water_mask,
			local_world_start, local_size)
	var entry: Dictionary = _region_cell_cache.get(cell, {"dominant": dominant})
	entry["cell"] = cell
	if str(entry.get("dominant", "")) == "" or dominant == "":
		entry["raw"] = ""
		entry["biome"] = ""
		entry["source"] = "water"
		return entry
	entry["raw"] = dominant
	var biome := get_biome(dominant)
	var min_size: int = biome.minimum_region_size if biome != null else 0
	if min_size <= 0:
		entry["biome"] = dominant
		entry["source"] = "kept"
		return entry
	var window := _region_window_radius(min_size, cell_size)
	# The window's dominants, each computed once and memoised, so the
	# fragment measurement is a pure local function of the raw field.
	var window_cells: Dictionary = {}
	for dy in range(-window, window + 1):
		for dx in range(-window, window + 1):
			var neighbour := cell + Vector2i(dx, dy)
			window_cells[neighbour] = _cell_dominant_biome(neighbour,
					local_biome_map, local_water_mask, local_world_start, local_size)
	# 8-connected component of the dominant biome, clipped to the window.
	var visited: Dictionary = {cell: true}
	var stack: Array[Vector2i] = [cell]
	while not stack.is_empty():
		var current: Vector2i = stack.pop_back()
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var next_cell := current + Vector2i(dx, dy)
				if visited.has(next_cell):
					continue
				if absi(next_cell.x - cell.x) > window or absi(next_cell.y - cell.y) > window:
					continue
				if str(window_cells.get(next_cell, "")) != dominant:
					continue
				visited[next_cell] = true
				stack.append(next_cell)
	if visited.size() * cell_size * cell_size >= min_size:
		entry["biome"] = dominant
		entry["source"] = "kept"
		return entry
	# The raw fragment is smaller than the data allows: merge into a
	# neighbouring cell's biome. Preference follows the raw biome's
	# neighbour metadata, then adjacency count, then id order.
	var candidates: Dictionary = {}
	for key in window_cells:
		var offset: Vector2i = key - cell
		if absi(offset.x) + absi(offset.y) != 1:
			continue
		var candidate := str(window_cells[key])
		if candidate == "" or candidate == dominant:
			continue
		candidates[candidate] = int(candidates.get(candidate, 0)) + 1
	if candidates.is_empty():
		entry["biome"] = dominant
		entry["source"] = "kept"
		return entry
	var best_candidate := ""
	var best_score := -INF
	for candidate_id in candidates:
		var candidate_name := str(candidate_id)
		var score := 0.0
		if biome != null:
			if biome.preferred_neighbors.has(candidate_name):
				score += 2.0
			elif biome.transition_biome_ids.has(candidate_name):
				score += 1.0
		score += 0.1 * float(candidates[candidate_name])
		if score > best_score or (score == best_score and candidate_name < best_candidate):
			best_score = score
			best_candidate = candidate_name
	entry["biome"] = best_candidate
	entry["source"] = "merged"
	return entry

## Apply the coherent-region stage to one chunk: compute the decisions for
## the cells the chunk intersects, rewrite the chunk's per-tile biome map
## where a cell was merged, and return the per-cell decision records that
## ride along in the chunk payload. Adjacent chunks compute the same records
## for shared cells, so boundaries cannot disagree. A merged cell rewrites
## its land tiles only — water tiles keep their raw biome in both the
## payload and on-demand queries. Dormant (returns an empty array, leaves
## the map untouched) when no biome opts in.
func _apply_region_coherence(chunk_coords: Vector2i, world_start: Vector2i,
		biome_map: PackedStringArray, water_mask: PackedByteArray) -> Array:
	var config := get_configuration()
	var cell_size: int = config.region_cell_size_tiles
	if cell_size <= 0 or _region_minimum_sizes().is_empty():
		return []
	var size: int = config.chunk_size_tiles
	var x_end: int = world_start.x + size - 1
	var y_end: int = world_start.y + size - 1
	var x0 := _cell_axis_for_tile(world_start.x)
	var x1 := _cell_axis_for_tile(x_end)
	var y0 := _cell_axis_for_tile(world_start.y)
	var y1 := _cell_axis_for_tile(y_end)
	var entries: Array = []
	var merged_cells: Dictionary = {}
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var cell := Vector2i(cx, cy)
			var entry := _region_decision_for_cell(cell, biome_map, water_mask,
					world_start, size)
			entries.append(entry)
			if str(entry.get("source", "")) == "merged" and str(entry.get("biome", "")) != "":
				merged_cells[cell] = str(entry["biome"])
	if not merged_cells.is_empty():
		for index in range(size * size):
			# Water tiles are never rewritten: their water-ness travels in
			# the water mask, and on-demand queries keep the raw biome for
			# water tiles too, so payload and query stay in agreement.
			if water_mask[index] != 0:
				continue
			var tx: int = world_start.x + (index % size)
			var ty: int = world_start.y + (index / size)
			var cell := _cell_coords_for_tile(tx, ty)
			if merged_cells.has(cell):
				biome_map[index] = merged_cells[cell]
	return entries
