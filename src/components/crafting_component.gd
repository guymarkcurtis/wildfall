## Manages crafting operations using recipe definitions and inventory.
class_name CraftingComponent
extends RefCounted

signal recipe_crafted(recipe_id: String)
signal recipe_failed(recipe_id: String, reason: String)

var _recipes: Dictionary = {}  # recipe_id -> RecipeDefinition
var _crafting_queue: Array[Dictionary] = []
var _current_crafting: Dictionary = {}

## Register a recipe.
func add_recipe(recipe: RecipeDefinition) -> void:
	if recipe != null and recipe.recipe_id != "":
		_recipes[recipe.recipe_id] = recipe

## Remove a recipe.
func remove_recipe(recipe_id: String) -> void:
	_recipes.erase(recipe_id)

## Get all registered recipes.
func get_recipes() -> Dictionary:
	return _recipes.duplicate()

## Check if a recipe exists.
func has_recipe(recipe_id: String) -> bool:
	return _recipes.has(recipe_id)

## Get recipe by ID.
func get_recipe(recipe_id: String) -> RecipeDefinition:
	return _recipes.get(recipe_id)

## Check if a recipe can be crafted with the given inventory.
func can_craft(recipe_id: String, inventory: InventoryComponent) -> bool:
	var recipe: RecipeDefinition = _recipes.get(recipe_id)
	if not recipe:
		return false
	return recipe.can_craft(inventory.get_all_items())

## Get failure reason for a recipe (first missing ingredient, if any).
func get_failure_reason(recipe_id: String, inventory: InventoryComponent) -> String:
	var recipe: RecipeDefinition = _recipes.get(recipe_id)
	if recipe == null:
		return "Recipe not found: %s" % recipe_id
	for item_id in recipe.required_items:
		if inventory.get_item_quantity(str(item_id)) < int(recipe.required_items[item_id]):
			return "Missing %dx %s" % [int(recipe.required_items[item_id]), str(item_id)]
	return ""

## Craft a recipe immediately (consume ingredients, produce output).
func craft_recipe(recipe_id: String, inventory: InventoryComponent) -> Array[Dictionary]:
	var recipe: RecipeDefinition = _recipes.get(recipe_id)
	if recipe == null:
		recipe_failed.emit(recipe_id, "Recipe not found")
		return []

	var inv_data: Dictionary = inventory.get_all_items()
	if not recipe.can_craft(inv_data):
		var reason: String = get_failure_reason(recipe_id, inventory)
		recipe_failed.emit(recipe_id, reason)
		return []

	# Consume ingredients.
	for item_id in recipe.required_items:
		inventory.remove_item(str(item_id), int(recipe.required_items[item_id]))

	# Produce output.
	var outputs: Array[Dictionary] = [
		{"item_id": recipe.result_item_id, "quantity": recipe.result_quantity}
	]
	for output in outputs:
		inventory.add_item(str(output["item_id"]), int(output["quantity"]))

	recipe_crafted.emit(recipe_id)
	return outputs

## Start a timed craft (for stations with craft_time > 0).
func start_craft(recipe_id: String, inventory: InventoryComponent, duration: float = 0.0) -> bool:
	var recipe: RecipeDefinition = _recipes.get(recipe_id)
	if not recipe:
		return false
	if not recipe.can_craft(inventory.get_all_items()):
		return false

	_current_crafting = {
		"recipe_id": recipe_id,
		"inventory": inventory,
		"elapsed": 0.0,
		"duration": max(duration, recipe.craft_time),
		"started": true
	}
	return true

## Update crafting progress.
func update_craft(delta: float) -> Array[Dictionary]:
	if not _current_crafting.get("started", false):
		return []

	_current_crafting["elapsed"] += delta
	if _current_crafting["elapsed"] >= _current_crafting["duration"]:
		var recipe_id: String = _current_crafting["recipe_id"]
		var inventory: InventoryComponent = _current_crafting["inventory"]
		_current_crafting = {}
		return craft_recipe(recipe_id, inventory)
	return []

## Cancel current craft.
func cancel_craft() -> bool:
	if not _current_crafting.get("started", false):
		return false
	_current_crafting = {}
	return true

## Get current crafting progress (0.0 to 1.0).
func get_progress() -> float:
	if not _current_crafting.get("started", false):
		return 0.0
	var elapsed: float = _current_crafting["elapsed"]
	var duration: float = _current_crafting["duration"]
	return clamp(elapsed / duration, 0.0, 1.0)

## Serialize for saving.
func serialize() -> Dictionary:
	return {
		"recipes": list_recipe_ids(),
		"crafting": _current_crafting if _current_crafting.get("started", false) else {}
	}

## List all recipe IDs.
func list_recipe_ids() -> PackedStringArray:
	return PackedStringArray(_recipes.keys())
