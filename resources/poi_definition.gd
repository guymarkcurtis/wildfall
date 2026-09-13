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
## WG-05: minimum Chebyshev (8-neighbour) tile distance from the nearest
## water tile at which this POI may place. -1 = unconstrained.
@export var min_distance_to_water: int = -1
## WG-05: maximum Chebyshev (8-neighbour) tile distance from the nearest
## water tile at which this POI may place. -1 = unconstrained; tiles with
## no water within cap - 1 read the cap value.
@export var max_distance_to_water: int = -1
@export var custom_data: Dictionary = {}

func is_valid() -> bool:
	return not id.is_empty()
