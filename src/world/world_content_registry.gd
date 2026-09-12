## Automatic discovery of world-content Resource assets.
## Adding a normal biome/resource/cave/POI is an asset operation, not a code
## change to the procedural engine.
class_name WorldContentRegistry
extends RefCounted

const BIOME_DIR := "res://data/world/biomes"
const RESOURCE_DIR := "res://data/world/resources"
const CAVE_DIR := "res://data/world/caves"
const POI_DIR := "res://data/world/pois"

var biomes: Dictionary = {}
var resources: Dictionary = {}
var caves: Dictionary = {}
var pois: Dictionary = {}

func discover() -> void:
	biomes = _discover_directory(BIOME_DIR, BiomeDefinition)
	resources = _discover_directory(RESOURCE_DIR, ResourceDefinition)
	caves = _discover_directory(CAVE_DIR, CaveDefinition)
	pois = _discover_directory(POI_DIR, POIDefinition)

func get_biome(id: String) -> BiomeDefinition:
	return biomes.get(id) as BiomeDefinition

func get_resource(id: String) -> ResourceDefinition:
	return resources.get(id) as ResourceDefinition

func get_cave(id: String) -> CaveDefinition:
	return caves.get(id) as CaveDefinition

func get_poi(id: String) -> POIDefinition:
	return pois.get(id) as POIDefinition

func _discover_directory(directory: String, expected_script: Script) -> Dictionary:
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
		if definition == null or not is_instance_of(definition, expected_script):
			continue
		var id := str(definition.get("id"))
		if not id.is_empty():
			found[id] = definition
	return found
