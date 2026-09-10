## Data-driven technology/progression definition.
@icon("res://assets/icons/tech_icon.svg")
class_name TechnologyDefinition
extends Resource

## Unique stable ID.
@export var id: String = ""

## Display name.
@export var display_name: String = "Unnamed Technology"

## Description.
@export var description: String = ""

## Prerequisites: list of technology IDs that must be unlocked first.
@export var prerequisites: PackedStringArray = []

## Cost in resources to unlock. List of {item_id, quantity}.
@export var unlock_cost: Array[Dictionary] = []

## Whether this technology is unlocked by default (for starting techs).
@export var unlocked_by_default: bool = false

## Unlocks when player reaches this level.
@export var required_level: int = 0

## Associated crafting recipes this unlocks.
@export var unlocks_recipes: PackedStringArray = []

## Sprite path.
@export var icon_path: String = ""

## Custom data.
@export var custom_data: Dictionary = {}

func is_valid() -> bool:
	return id != ""
