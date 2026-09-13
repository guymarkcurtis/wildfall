## Generic terrain-feature placement content (WG-04).
## A terrain feature is a patch of larger ground structure — a cliff base, a
## clearing, a scree slope — placed by the same generic candidate machinery
## as POIs: anchors from the feature's own spacing grid, eligibility from its
## biome/environment constraints, placement probability from spawn_weight.
##
## The footprint radius turns a candidate into a mask (a square of
## footprint_radius_tiles around the anchor) so feature masks can cover more
## than one tile. influence_tags is the seam into other systems: consumer
## systems (the resource spawner, later the terrain renderer) own small tag
## vocabularies and read them from the payload; a feature opts in by listing
## the tag here. No consumer branch may key on feature names.
class_name TerrainFeatureDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = "Unnamed Feature"
@export var category: String = "structure"
@export var spawn_weight: float = 1.0
@export var min_spacing_tiles: int = 32
## Square half-extent, in tiles, of the mask this feature claims around its
## anchor. 0 keeps the candidate a single-tile marker.
@export var footprint_radius_tiles: int = 0
@export var allowed_biomes: PackedStringArray = []
@export var required_environment_tags: PackedStringArray = []
## Generic modifier tags that consumer systems may interpret (for example the
## resource spawner's spawn-block tag). The vocabulary belongs to the
## consumers; this list is pure data.
@export var influence_tags: PackedStringArray = []
## WG-05: minimum Chebyshev (8-neighbour) tile distance from the nearest
## water tile at which this feature may place. -1 = unconstrained.
@export var min_distance_to_water: int = -1
## WG-05: maximum Chebyshev (8-neighbour) tile distance from the nearest
## water tile at which this feature may place. -1 = unconstrained; tiles
## with no water within cap - 1 read the cap value.
@export var max_distance_to_water: int = -1
@export var custom_data: Dictionary = {}

func is_valid() -> bool:
	return not id.is_empty()
