## Data-driven item definition resource.
## Every item in the game is defined by an instance of this resource.
@icon("res://assets/icons/item_icon.svg")
class_name ItemDefinition
extends Resource

## Unique stable ID for this item (never change after creation).
@export var id: String = ""

## Display name shown to the player.
@export var display_name: String = "Unnamed Item"

## Short description shown in tooltips.
@export var description: String = ""

## Category grouping (tool, food, material, resource, etc.).
@export_enum("tool", "food", "material", "resource", "consumable", "building", "component", "seed", "weapon", "armor") var category: String = "resource"

## Stack size limit. -1 means unstackable.
@export var stack_size: int = 64

## Weight in game units.
@export var weight: float = 1.0

## Whether this item can be picked up automatically.
@export var auto_pickup: bool = false

## Whether this is a tool that can be used.
@export var is_tool: bool = false

## Whether this is a weapon.
@export var is_weapon: bool = false

## Whether this is consumable.
@export var is_consumable: bool = false

## Icon asset path (optional, falls back to default).
@export var icon_path: String = ""

## Base value in game currency.
@export var value: int = 0

## Custom data dictionary for mod support or extended properties.
@export var custom_data: Dictionary = {}

## Validate that this definition is complete.
func is_valid() -> bool:
	return id != "" and display_name != ""

## Get the icon texture, falling back to a generic icon.
func get_icon() -> Texture2D:
	if icon_path != "" and ResourceLoader.exists(icon_path):
		return ResourceLoader.load(icon_path) as Texture2D
	return null

## Create a stack of this item with the given quantity.
static func create_stack(item_id: String, quantity: int) -> Dictionary:
	return {
		"item_id": item_id,
		"quantity": quantity,
		"metadata": {}
	}
