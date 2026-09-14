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
## WG-12 presence guarantee: ensure at least this many world region cells are
## "eligible" for this POI (the cell's dominant biome carries every tag in
## required_environment_tags). When the world has fewer, the generator forces
## the nearest-to-centre land candidate cell onto the fallback biome so the
## required terrain type always exists. 0 = dormant (no presence guarantee).
@export_range(0, 4096) var guarantee_min_eligible_cells: int = 0
## WG-12 coverage guarantee: ensure at least this many placements of this POI
## in every spacing cell that contains an eligible region cell. When the cell's
## nominal anchor would not naturally place one (anchor not eligible, or the
## deterministic spawn roll fails), the anchor is forced onto the fallback
## biome and its roll is forced to pass. 0 = dormant (pure probabilistic).
@export_range(0, 16) var guarantee_per_spacing_cell: int = 0
## Biome id forced onto override tiles by the guarantees above. Empty derives
## it from data: the eligible-tag biome with the highest cave_entrance_suitability.
@export var guarantee_fallback_biome: String = ""
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
