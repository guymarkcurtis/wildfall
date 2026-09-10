## Registry for all crafting recipes.
## Load this as a child of Main and populate with recipes.
extends Node

signal recipe_added(recipe_id: String)
signal recipe_removed(recipe_id: String)

var _recipes: Dictionary = {}

## Get all recipes.
func get_recipes() -> Dictionary:
	return _recipes.duplicate()

## Get a recipe by ID.
func get_recipe(recipe_id: String) -> "RecipeDefinition":
	return _recipes.get(recipe_id)

## Check if a recipe exists.
func has_recipe(recipe_id: String) -> bool:
	return _recipes.has(recipe_id)

## Add a recipe.
func add_recipe(recipe: "RecipeDefinition") -> void:
	if recipe.is_valid():
		_recipes[recipe.id] = recipe
		recipe_added.emit(recipe.id)

## Remove a recipe.
func remove_recipe(recipe_id: String) -> void:
	if _recipes.has(recipe_id):
		_recipes.erase(recipe_id)
		recipe_removed.emit(recipe_id)

## Initialize with default recipes.
func initialize_defaults() -> void:
	# Basic resources
	var wood := RecipeDefinition.new()
	wood.id = "gather_wood"
	wood.display_name = "Gather Wood"
	wood.ingredients = [{"item_id": "tree", "quantity": 1}]
	wood.outputs = [{"item_id": "wood", "quantity": 3}]
	wood.craft_time = 0.5
	add_recipe(wood)

	var stone := RecipeDefinition.new()
	stone.id = "gather_stone"
	stone.display_name = "Gather Stone"
	stone.ingredients = [{"item_id": "rock", "quantity": 1}]
	stone.outputs = [{"item_id": "stone", "quantity": 2}]
	stone.craft_time = 0.5
	add_recipe(stone)

	# Basic tools
	var wooden_axe := RecipeDefinition.new()
	wooden_axe.id = "wooden_axe"
	wooden_axe.display_name = "Wooden Axe"
	wooden_axe.ingredients = [
		{"item_id": "wood", "quantity": 3},
		{"item_id": "stone", "quantity": 2}
	]
	wooden_axe.outputs = [{"item_id": "wooden_axe", "quantity": 1}]
	wooden_axe.craft_time = 2.0
	add_recipe(wooden_axe)

	var wooden_pickaxe := RecipeDefinition.new()
	wooden_pickaxe.id = "wooden_pickaxe"
	wooden_pickaxe.display_name = "Wooden Pickaxe"
	wooden_pickaxe.ingredients = [
		{"item_id": "wood", "quantity": 3},
		{"item_id": "stone", "quantity": 2}
	]
	wooden_pickaxe.outputs = [{"item_id": "wooden_pickaxe", "quantity": 1}]
	wooden_pickaxe.craft_time = 2.0
	add_recipe(wooden_pickaxe)

	# Basic building
	var plank := RecipeDefinition.new()
	plank.id = "plank"
	plank.display_name = "Wooden Plank"
	plank.ingredients = [{"item_id": "wood", "quantity": 2}]
	plank.outputs = [{"item_id": "plank", "quantity": 3}]
	plank.craft_time = 1.0
	add_recipe(plank)

	var wall := RecipeDefinition.new()
	wall.id = "wall"
	wall.display_name = "Wooden Wall"
	wall.ingredients = [{"item_id": "plank", "quantity": 5}]
	wall.outputs = [{"item_id": "wall", "quantity": 1}]
	wall.craft_time = 1.0
	add_recipe(wall)

	# Food
	var berry := RecipeDefinition.new()
	berry.id = "gather_berry"
	berry.display_name = "Gather Berries"
	berry.ingredients = [{"item_id": "bush", "quantity": 1}]
	berry.outputs = [{"item_id": "berry", "quantity": 3}]
	berry.craft_time = 0.5
	add_recipe(berry)

	# Advanced
	var iron_ingot := RecipeDefinition.new()
	iron_ingot.id = "iron_ingot"
	iron_ingot.display_name = "Iron Ingot"
	iron_ingot.ingredients = [
		{"item_id": "iron_ore", "quantity": 2},
		{"item_id": "charcoal", "quantity": 1}
	]
	iron_ingot.outputs = [{"item_id": "iron_ingot", "quantity": 1}]
	iron_ingot.craft_time = 5.0
	add_recipe(iron_ingot)

	print("RecipeRegistry: Loaded %d recipes" % _recipes.size())
