## Data-driven building definition.
@icon("res://assets/icons/building_icon.svg")
class_name BuildingDefinition
extends Resource

## Unique stable ID.
@export var id: String = ""

## Display name.
@export var display_name: String = "Unnamed Building"

## Width in tiles.
@export var width: int = 1

## Height in tiles.
@export var height: int = 1

## Structural role. Parts share a grid cell only across different stories;
## this makes a floor plan easy to read in Wildfall's top-down cutaway view.
@export_enum("foundation", "floor", "wall", "window", "door", "roof", "stair", "ramp", "pillar", "utility") var part_type: String = "utility"

## Progression tier and future technology gate. The building system already
## reads this metadata; the technology-tree UI will enforce the gate next.
@export_enum("primitive", "wood", "stone", "metal") var tier: String = "wood"
@export var technology_id: String = ""

## Upper stories need a structural piece directly beneath the same tile.
@export var requires_lower_support: bool = true

## Floors, ramps, and most utilities are walkable; walls/doors/pillars block.
@export var blocks_movement: bool = false

## Description.
@export var description: String = ""

## Build cost: list of {item_id, quantity}.
@export var build_cost: Array[Dictionary] = []

## Requires crafting station.
@export var station_id: String = ""

## Max HP.
@export var max_health: int = 100

## Whether this building can be picked up (returns resources).
@export var pickup_returns_resources: bool = true

## Sprite path.
@export var sprite_path: String = ""

## Custom data.
@export var custom_data: Dictionary = {}

func is_valid() -> bool:
	return id != ""
