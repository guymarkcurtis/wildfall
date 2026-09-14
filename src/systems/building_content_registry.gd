## Discovery and validation of building-content Resource assets
## (data/buildings/ definitions plus shared data/interactables/ profiles).
## Mirrors WorldContentRegistry's contract: loading and cross-check failures
## are collected as "<asset path>: <problem>" messages — never silently
## skipped — so an author's mistake points at the exact file. Adding a normal
## placeable part or interactable is an asset-only change.
##
## On validation errors the registry still returns the definitions that
## loaded cleanly (dropping only the errored ones); building placement is
## player-facing UI, so one bad asset must not blank the whole palette. The
## errors are logged loudly at startup.
class_name BuildingContentRegistry
extends RefCounted

const DEFAULT_BUILDINGS_DIR := "res://data/buildings"
const DEFAULT_PROFILES_DIR := "res://data/interactables"

const PLACEMENT_LAYERS := ["ground", "floor", "edge", "object", "overhead", "connector"]

var definitions: Dictionary = {} # id -> BuildingDefinition
var definition_paths: Dictionary = {} # id -> res:// path

## Definitions that loaded but failed validation, keyed by id. They are NOT
## in `definitions`; consumers must not offer them for placement.
var errored_definitions: Dictionary = {}

## "<asset path>: <problem>" messages; empty when the content is valid.
var validation_errors: Array[String] = []

var discovered: bool = false

func discover(buildings_directory: String = DEFAULT_BUILDINGS_DIR,
		profiles_directory: String = DEFAULT_PROFILES_DIR) -> void:
	definitions.clear()
	definition_paths.clear()
	errored_definitions.clear()
	validation_errors.clear()
	# Shared profiles are validated standalone (definitions may also carry
	# inline sub-resource profiles, which need no separate discovery).
	_validate_profile_directory(profiles_directory)
	var found := _discover_directory(buildings_directory, BuildingDefinition, definition_paths)
	for id in found:
		var path := str(definition_paths[id])
		var definition := found[id] as BuildingDefinition
		var problems := _prefix_errors(path, definition.validate())
		if problems.is_empty():
			definitions[id] = definition
		else:
			errored_definitions[id] = definition
			validation_errors.append_array(problems)
	discovered = true

func get_definition(id: String) -> BuildingDefinition:
	return definitions.get(id) as BuildingDefinition

func has_validation_errors() -> bool:
	return not validation_errors.is_empty()

## Load every BuildingDefinition below one directory, keyed by id. Load
## failures, wrong scripts, missing ids, and duplicate ids are reported.
func _discover_directory(directory: String, expected_script: Script, paths: Dictionary) -> Dictionary:
	var found: Dictionary = {}
	var dir := DirAccess.open(directory)
	if dir == null:
		validation_errors.append("%s: directory is missing; building content cannot be discovered" % directory)
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
			validation_errors.append("%s: expected a %s asset but the resource uses a different script" % \
					[path, expected_script.get_global_name()])
		else:
			var id := str(definition.get("id"))
			if id.is_empty():
				validation_errors.append("%s: missing 'id'; every building definition needs a unique stable id" % path)
			elif found.has(id):
				validation_errors.append("%s: duplicate id '%s' (already defined in %s)" % [path, id, paths.get(id, "?")])
			else:
				found[id] = definition
				paths[id] = path
	return found

## Validate standalone profile assets under data/interactables/. Any Resource
## carrying one of the known capability scripts is checked with its own
## validate(); other resources are reported as unexpected content.
func _validate_profile_directory(directory: String) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return # The directory only exists once shared profiles are authored.
	var files := dir.get_files()
	files.sort()
	for file_name in files:
		if not file_name.ends_with(".tres") and not file_name.ends_with(".res"):
			continue
		var path := "%s/%s" % [directory, file_name]
		var profile: Resource = load(path) as Resource
		if profile == null:
			validation_errors.append("%s: failed to load this asset" % path)
			continue
		var script: Script = profile.get_script()
		var known := script != null and script.get_global_name() in [
				"InteractionProfile", "ContainerProfile", "StationProfile",
				"FuelProfile", "LightProfile", "AppearanceProfile"]
		if not known:
			validation_errors.append("%s: not a recognised capability profile script" % path)
		elif profile.has_method("validate"):
			validation_errors.append_array(_prefix_errors(path, profile.validate()))

func _prefix_errors(path: String, errors: Array[String]) -> Array[String]:
	var prefixed: Array[String] = []
	for message in errors:
		prefixed.append("%s: %s" % [path, message])
	return prefixed
