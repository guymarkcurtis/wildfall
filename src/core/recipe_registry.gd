## Registry for all crafting recipes.
## NOTE: legacy registry — the live game uses ItemDatabase (see
## src/systems/item_database.gd), which is what Main refreshes the crafting
## panel from. This registry is kept as future-phase scaffolding (e.g. for
## creature/building recipes) and is NOT wired into the current scene.
extends Node

signal recipe_added(recipe_id: String)
signal recipe_removed(recipe_id: String)

var _recipes: Dictionary = {}  # recipe_id -> RecipeDefinition

## Get all recipes.
func get_recipes() -> Dictionary:
	return _recipes.duplicate()

## Get a recipe by ID.
func get_recipe(recipe_id: String) -> RecipeDefinition:
	return _recipes.get(recipe_id)

## Check if a recipe exists.
func has_recipe(recipe_id: String) -> bool:
	return _recipes.has(recipe_id)

## Add a recipe.
func add_recipe(recipe: RecipeDefinition) -> void:
	if recipe != null and recipe.recipe_id != "":
		_recipes[recipe.recipe_id] = recipe
		recipe_added.emit(recipe.recipe_id)

## Remove a recipe.
func remove_recipe(recipe_id: String) -> void:
	if _recipes.has(recipe_id):
		_recipes.erase(recipe_id)
		recipe_removed.emit(recipe_id)

## Initialize with default recipes.
func initialize_defaults() -> void:
	# Basic resources
	var wood := RecipeDefinition.new()
	wood.recipe_id = "gather_wood"
	wood.required_items = {"tree": 1}
	wood.result_item_id = "wood"
	wood.result_quantity = 3
	wood.craft_time = 0.5
	add_recipe(wood)

	var stone := RecipeDefinition.new()
	stone.recipe_id = "gather_stone"
	stone.required_items = {"rock": 1}
	stone.result_item_id = "stone"
	stone.result_quantity = 2
	stone.craft_time = 0.5
	add_recipe(stone)

	# Basic tools
	var wooden_axe := RecipeDefinition.new()
	wooden_axe.recipe_id = "wooden_axe"
	wooden_axe.required_items = {"wood": 3, "stone": 2}
	wooden_axe.result_item_id = "wooden_axe"
	wooden_axe.result_quantity = 1
	wooden_axe.craft_time = 2.0
	add_recipe(wooden_axe)

	var wooden_pickaxe := RecipeDefinition.new()
	wooden_pickaxe.recipe_id = "wooden_pickaxe"
	wooden_pickaxe.required_items = {"wood": 3, "stone": 2}
	wooden_pickaxe.result_item_id = "wooden_pickaxe"
	wooden_pickaxe.result_quantity = 1
	wooden_pickaxe.craft_time = 2.0
	add_recipe(wooden_pickaxe)

	# Basic building
	var plank := RecipeDefinition.new()
	plank.recipe_id = "plank"
	plank.required_items = {"wood": 2}
	plank.result_item_id = "plank"
	plank.result_quantity = 3
	plank.craft_time = 1.0
	add_recipe(plank)

	var wall := RecipeDefinition.new()
	wall.recipe_id = "wall"
	wall.required_items = {"plank": 5}
	wall.result_item_id = "wall"
	wall.result_quantity = 1
	wall.craft_time = 1.0
	add_recipe(wall)

	# Food
	var berry := RecipeDefinition.new()
	berry.recipe_id = "gather_berry"
	berry.required_items = {"bush": 1}
	berry.result_item_id = "berry"
	berry.result_quantity = 3
	berry.craft_time = 0.5
	add_recipe(berry)

	# Advanced
	var iron_ingot := RecipeDefinition.new()
	iron_ingot.recipe_id = "iron_ingot"
	iron_ingot.required_items = {"iron_ore": 2, "charcoal": 1}
	iron_ingot.result_item_id = "iron_ingot"
	iron_ingot.result_quantity = 1
	iron_ingot.craft_time = 5.0
	add_recipe(iron_ingot)

	print("RecipeRegistry: Loaded %d recipes" % _recipes.size())
