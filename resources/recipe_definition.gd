## Data-driven crafting recipe definition.
@icon("res://assets/icons/recipe_icon.svg")
class_name RecipeDefinition
extends Resource

## Unique stable ID for this recipe.
@export var id: String = ""

## Display name shown in crafting UI.
@export var display_name: String = "Unnamed Recipe"

## Short description.
@export var description: String = ""

## Required crafting station ID (empty = hand crafting).
@export var station_id: String = ""

## Whether this recipe requires a technology unlock.
@export var tech_id: String = ""

## Time in seconds to complete the craft.
@export var craft_time: float = 1.0

## Whether this recipe is unlocked by default.
@export var unlocked: bool = true

## Ingredients: list of {item_id, quantity} dictionaries.
@export var ingredients: Array[Dictionary] = []

## Outputs: list of {item_id, quantity} dictionaries.
@export var outputs: Array[Dictionary] = []

## Whether to consume ingredients on craft.
@export var consume_ingredients: bool = true

## Custom data for mod support.
@export var custom_data: Dictionary = {}

## Validate that this recipe is complete.
func is_valid() -> bool:
	return id != "" and len(ingredients) > 0 and len(outputs) > 0

## Check if player has enough ingredients.
func can_craft(inventory: Dictionary) -> bool:
	for ingredient in ingredients:
		var item_id: String = ingredient["item_id"]
		var needed: int = ingredient["quantity"]
		var current: int = inventory.get(item_id, 0)
		if current < needed:
			return false
	return true

## Get a human-readable failure reason if ingredients are missing.
func get_craft_failure_reason(inventory: Dictionary) -> String:
	for ingredient in ingredients:
		var item_id: String = ingredient["item_id"]
		var needed: int = ingredient["quantity"]
		var current: int = inventory.get(item_id, 0)
		if current < needed:
			return "Need %d more %s" % [needed - current, item_id]
	return ""

## Consume ingredients from inventory. Returns remaining inventory.
func consume_ingredients(inventory: Dictionary) -> Dictionary:
	var result = inventory.duplicate()
	for ingredient in ingredients:
		var item_id: String = ingredient["item_id"]
		var needed: int = ingredient["quantity"]
		result[item_id] = result.get(item_id, 0) - needed
		if result[item_id] <= 0:
			result.erase(item_id)
	return result

## Generate output items.
func generate_outputs() -> Array[Dictionary]:
	return outputs.duplicate()
