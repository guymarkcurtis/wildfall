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
