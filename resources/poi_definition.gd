## Generic point-of-interest placement content.
class_name POIDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = "Unnamed POI"
@export var category: String = "landmark"
@export var spawn_weight: float = 1.0
@export var min_spacing_tiles: int = 32
@export var allowed_biomes: PackedStringArray = []
@export var required_environment_tags: PackedStringArray = []
@export var custom_data: Dictionary = {}

func is_valid() -> bool:
	return not id.is_empty()
