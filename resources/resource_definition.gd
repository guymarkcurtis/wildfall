## Generic data definition for a generated resource or vegetation node.
## The spawner interprets these fields; it does not know individual resource IDs.
class_name ResourceDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = "Unnamed Resource"
@export var spawn_weight: float = 1.0
@export_range(0.0, 1.0) var abundance: float = 1.0
@export var distribution_mode: String = "uniform"
@export var min_spacing_tiles: int = 0
@export var cluster_radius: int = 2
@export var surface_spawnable: bool = true
@export var underground_spawnable: bool = false
@export var allowed_biomes: PackedStringArray = []
@export var required_environment_tags: PackedStringArray = []
@export var progression_tier: int = 0
@export var base_health: float = 5.0
@export var yields: Array[Dictionary] = []
@export var biome_yields: Dictionary = {}
@export var custom_data: Dictionary = {}

func is_valid() -> bool:
	return not id.is_empty()

func can_spawn_on_surface(biome_id: String, environment_tags: PackedStringArray) -> bool:
	if not surface_spawnable:
		return false
	if not allowed_biomes.is_empty() and not allowed_biomes.has(biome_id):
		return false
	for required_tag in required_environment_tags:
		if not environment_tags.has(required_tag):
			return false
	return true

func can_spawn_underground(environment_tags: PackedStringArray) -> bool:
	if not underground_spawnable:
		return false
	for required_tag in required_environment_tags:
		if not environment_tags.has(required_tag):
			return false
	return true

func get_yields_for_biome(biome_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in yields:
		result.append(entry.duplicate(true))
	var additions: Variant = biome_yields.get(biome_id, [])
	if typeof(additions) == TYPE_ARRAY:
		for entry in additions:
			if typeof(entry) == TYPE_DICTIONARY:
				result.append((entry as Dictionary).duplicate(true))
	return result
