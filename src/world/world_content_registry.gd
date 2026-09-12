## Automatic discovery and validation of world-content Resource assets.
## Adding a normal biome/resource/cave/POI is an asset operation, not a code
## change to the procedural engine.
##
## discover() loads every content asset below the base directory; validate()
## then checks the result. Failures are collected as "<asset path>: <problem>"
## messages — never silently skipped — so the generator can refuse to build a
## world from bad content and point the author at the exact asset to fix.
class_name WorldContentRegistry
extends RefCounted

const DEFAULT_BASE_DIR := "res://data/world"
const BIOME_SUBDIR := "biomes"
const RESOURCE_SUBDIR := "resources"
const CAVE_SUBDIR := "caves"
const POI_SUBDIR := "pois"

var biomes: Dictionary = {}
var resources: Dictionary = {}
var caves: Dictionary = {}
var pois: Dictionary = {}

## "<asset path>: <problem>" messages collected while loading and
## cross-checking the discovered content. Empty when the content is valid.
var validation_errors: Array[String] = []

## res:// path of each discovered asset, keyed by id (one map per content
## kind), so validation messages point at the file an author can open.
var biome_paths: Dictionary = {}
var resource_paths: Dictionary = {}
var cave_paths: Dictionary = {}
var poi_paths: Dictionary = {}

## True once discover() has run; re-discovering keeps the registry fresh when
## the world is (re)generated.
var discovered: bool = false


func discover(base_directory: String = DEFAULT_BASE_DIR) -> void:
	biome_paths.clear()
	resource_paths.clear()
	cave_paths.clear()
	poi_paths.clear()
	validation_errors.clear()
	biomes = _discover_directory(base_directory.path_join(BIOME_SUBDIR), BiomeDefinition, biome_paths)
	resources = _discover_directory(base_directory.path_join(RESOURCE_SUBDIR), ResourceDefinition, resource_paths)
	caves = _discover_directory(base_directory.path_join(CAVE_SUBDIR), CaveDefinition, cave_paths)
	pois = _discover_directory(base_directory.path_join(POI_SUBDIR), POIDefinition, poi_paths)
	discovered = true
	# Append (never replace): _discover_directory already reported load
	# failures, missing ids, and duplicates here; validate() adds the
	# cross-reference problems on top.
	validation_errors.append_array(validate())


func has_validation_errors() -> bool:
	return not validation_errors.is_empty()


func get_biome(id: String) -> BiomeDefinition:
	return biomes.get(id) as BiomeDefinition


func get_resource(id: String) -> ResourceDefinition:
	return resources.get(id) as ResourceDefinition


func get_cave(id: String) -> CaveDefinition:
	return caves.get(id) as CaveDefinition


func get_poi(id: String) -> POIDefinition:
	return pois.get(id) as POIDefinition


## Load every content asset below one directory, keyed by id. Assets that fail
## to load, carry the wrong script, lack an id, or duplicate an id are
## reported in validation_errors instead of being dropped silently.
func _discover_directory(directory: String, expected_script: Script, paths: Dictionary) -> Dictionary:
	var found: Dictionary = {}
	var dir := DirAccess.open(directory)
	if dir == null:
		return found
	var files := dir.get_files()
	files.sort()
	for file_name in files:
		if not file_name.ends_with(".tres") and not file_name.ends_with(".res"):
			continue
		var path := "%s/%s" % [directory, file_name]
		var definition: Resource = load(path) as Resource
		if definition == null:
			validation_errors.append("%s: failed to load this asset" % path)
		elif not is_instance_of(definition, expected_script):
			validation_errors.append(
					"%s: expected a %s asset but the resource uses a different script" % \
					[path, expected_script.get_global_name()])
		else:
			var id := str(definition.get("id"))
			if id.is_empty():
				validation_errors.append(
						"%s: missing 'id'; every content asset needs a unique stable id" % path)
			elif found.has(id):
				validation_errors.append(
						"%s: duplicate id '%s' (already defined in %s)" % [path, id, paths.get(id, "?")])
				found[id] = definition
				paths[id] = path
			else:
				found[id] = definition
				paths[id] = path
	return found


## Validate per-asset rules, then cross-asset links. Pure data checks: the
## registry interprets generic fields and never special-cases content names.
func validate() -> Array[String]:
	var errors: Array[String] = []
	for biome_id in biome_paths:
		errors.append_array(_validate_biome(biomes.get(biome_id) as BiomeDefinition, str(biome_paths[biome_id])))
	for resource_id in resource_paths:
		errors.append_array(_validate_resource(resources.get(resource_id) as ResourceDefinition, str(resource_paths[resource_id])))
	for cave_id in cave_paths:
		errors.append_array(_validate_cave(caves.get(cave_id) as CaveDefinition, str(cave_paths[cave_id])))
	for poi_id in poi_paths:
		errors.append_array(_validate_poi(pois.get(poi_id) as POIDefinition, str(poi_paths[poi_id])))
	errors.append_array(_validate_cross_references())
	return errors


func _validate_biome(biome: BiomeDefinition, path: String) -> Array[String]:
	var errors: Array[String] = []
	if biome == null:
		return errors
	errors.append_array(_check_field_range(path, "elevation", biome.elevation_range))
	errors.append_array(_check_field_range(path, "moisture", biome.moisture_range))
	errors.append_array(_check_field_range(path, "temperature", biome.temperature_range))
	if biome.terrain_tile_id.is_empty():
		errors.append("%s: terrain_tile_id is empty; the renderer cannot pick terrain for this biome" % path)
	elif biome.terrain_tile_id == "water":
		errors.append("%s: terrain_tile_id is 'water'; water is a physical world system, not a biome terrain" % path)
	elif not TerrainRenderer.is_supported_terrain_id(biome.terrain_tile_id):
		errors.append("%s: terrain_tile_id '%s' is not supported by the terrain renderer (supported: %s)" % \
				[path, biome.terrain_tile_id, ", ".join(TerrainRenderer.TERRAIN_CONTENT_IDS)])
	if not biome.high_elevation_terrain_tile_id.is_empty() \
			and not TerrainRenderer.is_supported_terrain_id(biome.high_elevation_terrain_tile_id):
		errors.append("%s: high_elevation_terrain_tile_id '%s' is not supported by the terrain renderer (supported: %s)" % \
				[path, biome.high_elevation_terrain_tile_id, ", ".join(TerrainRenderer.TERRAIN_CONTENT_IDS)])
	if biome.cave_entrance_suitability < 0.0 or biome.cave_entrance_suitability > 1.0:
		errors.append("%s: cave_entrance_suitability %.2f is outside the 0..1 range" % \
				[path, biome.cave_entrance_suitability])
	return errors


func _validate_resource(definition: ResourceDefinition, path: String) -> Array[String]:
	var errors: Array[String] = []
	if definition == null:
		return errors
	if not ResourceSpawner.DISTRIBUTION_MODES.has(definition.distribution_mode):
		errors.append("%s: distribution_mode '%s' is not a mode the spawn engine supports (supported: %s)" % \
				[path, definition.distribution_mode, ", ".join(ResourceSpawner.DISTRIBUTION_MODES)])
	if not definition.surface_spawnable and not definition.underground_spawnable:
		errors.append("%s: neither surface_spawnable nor underground_spawnable is set; this resource can never spawn anywhere" % path)
	for index in range(definition.yields.size()):
		if str(definition.yields[index].get("item_id", "")).is_empty():
			errors.append("%s: yields[%d] has no item_id; harvesting it would drop nothing" % [path, index])
	return errors


func _validate_cave(cave: CaveDefinition, path: String) -> Array[String]:
	var errors: Array[String] = []
	if cave == null:
		return errors
	if cave.min_rooms > cave.max_rooms:
		errors.append("%s: min_rooms (%d) is greater than max_rooms (%d)" % [path, cave.min_rooms, cave.max_rooms])
	if cave.room_size.x <= 0 or cave.room_size.y <= 0:
		errors.append("%s: room_size %s must be positive" % [path, str(cave.room_size)])
	if cave.resource_min_deposits > cave.resource_max_deposits:
		errors.append("%s: resource_min_deposits (%d) is greater than resource_max_deposits (%d)" % \
				[path, cave.resource_min_deposits, cave.resource_max_deposits])
	return errors


func _validate_poi(poi: POIDefinition, path: String) -> Array[String]:
	var errors: Array[String] = []
	if poi == null:
		return errors
	if poi.min_spacing_tiles < 0:
		errors.append("%s: min_spacing_tiles (%d) is negative" % [path, poi.min_spacing_tiles])
	return errors


## Cross-asset link checks: every reference between content assets must
## resolve. Dangling references are authoring mistakes the engine would
## otherwise skip silently.
func _validate_cross_references() -> Array[String]:
	var errors: Array[String] = []
	for biome_id in biome_paths:
		var biome := biomes.get(biome_id) as BiomeDefinition
		if biome == null:
			continue
		var path := str(biome_paths[biome_id])
		for neighbor in biome.preferred_neighbors:
			if not biomes.has(neighbor):
				errors.append("%s: preferred_neighbors references unknown biome '%s'" % [path, neighbor])
		for neighbor in biome.transition_biome_ids:
			if not biomes.has(neighbor):
				errors.append("%s: transition_biome_ids references unknown biome '%s'" % [path, neighbor])
		for resource_id in biome.resource_types:
			if not resources.has(resource_id):
				errors.append("%s: resource_types references unknown resource '%s'" % [path, resource_id])
			else:
				var surface_def := resources.get(resource_id) as ResourceDefinition
				if surface_def != null and not surface_def.surface_spawnable:
					errors.append("%s: resource_types lists '%s' but that resource is not surface_spawnable, so it can never spawn from this biome" % [path, resource_id])
	for cave_id in cave_paths:
		var cave := caves.get(cave_id) as CaveDefinition
		if cave == null:
			continue
		var path := str(cave_paths[cave_id])
		if cave.entrance_poi_id.is_empty():
			errors.append("%s: entrance_poi_id is empty; the cave has no surface entrance" % path)
		elif not pois.has(cave.entrance_poi_id):
			errors.append("%s: entrance_poi_id references unknown POI '%s'" % [path, cave.entrance_poi_id])
		for biome_id in cave.allowed_biomes:
			if not biomes.has(biome_id):
				errors.append("%s: allowed_biomes references unknown biome '%s'" % [path, biome_id])
		for resource_id in cave.resource_ids:
			if not resources.has(resource_id):
				errors.append("%s: resource_ids references unknown resource '%s'" % [path, resource_id])
			else:
				var cave_def := resources.get(resource_id) as ResourceDefinition
				if cave_def != null and not cave_def.underground_spawnable:
					errors.append("%s: resource_ids lists '%s' but that resource is not underground_spawnable, so deposits can never appear in this cave" % [path, resource_id])
		for poi_id in cave.poi_ids:
			if not pois.has(poi_id):
				errors.append("%s: poi_ids references unknown POI '%s'" % [path, poi_id])
	for poi_id in poi_paths:
		var poi := pois.get(poi_id) as POIDefinition
		if poi == null:
			continue
		var path := str(poi_paths[poi_id])
		for biome_id in poi.allowed_biomes:
			if not biomes.has(biome_id):
				errors.append("%s: allowed_biomes references unknown biome '%s'" % [path, biome_id])
	return errors


## Biome environment ranges are normalized 0..1 field values. An inverted
## range (min > max) can never match; a range outside 0..1 can never match
## either. Vector2(0, 0) is the documented "any value" sentinel and is valid.
func _check_field_range(path: String, field_name: String, range_value: Vector2) -> Array[String]:
	var errors: Array[String] = []
	if range_value.x > range_value.y:
		errors.append("%s: %s_range (%.2f, %.2f) is inverted; min exceeds max so the biome can never appear" % \
				[path, field_name, range_value.x, range_value.y])
	elif range_value.x < 0.0 or range_value.y > 1.0:
		errors.append("%s: %s_range (%.2f, %.2f) is outside the normalized 0..1 field" % \
				[path, field_name, range_value.x, range_value.y])
	return errors
