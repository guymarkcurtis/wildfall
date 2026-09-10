## Central database for all items and recipes.
class_name ItemDatabase
extends Node

# Items
var items: Dictionary = {}
var recipes: Dictionary = {}

## Initialize the item database.
func initialize() -> void:
	_load_items()
	_load_recipes()
	print("ItemDatabase: Loaded %d items and %d recipes" % [items.size(), recipes.size()])

## Load all item definitions.
func _load_items() -> void:
	# Basic resources
	items["wood"] = _create_item("wood", "Wood", "resource", 64, 0.5)
	items["stone"] = _create_item("stone", "Stone", "resource", 64, 1.0)
	items["fibre"] = _create_item("fibre", "Fibre", "resource", 64, 0.3)
	items["clay"] = _create_item("clay", "Clay", "resource", 64, 0.8)
	items["sand"] = _create_item("sand", "Sand", "resource", 64, 0.5)
	items["leaf"] = _create_item("leaf", "Leaf", "resource", 64, 0.2)
	items["berry"] = _create_item("berry", "Berry", "food", 32, 0.3)
	items["bone"] = _create_item("bone", "Bone", "resource", 32, 0.5)
	items["hide"] = _create_item("hide", "Hide", "resource", 32, 0.8)
	items["feather"] = _create_item("feather", "Feather", "resource", 64, 0.1)
	
	# Ores
	items["coal"] = _create_item("coal", "Coal", "resource", 64, 1.0)
	items["iron_ore"] = _create_item("iron_ore", "Iron Ore", "resource", 32, 2.0)
	items["gold_ore"] = _create_item("gold_ore", "Gold Ore", "resource", 16, 3.0)
	items["copper_ore"] = _create_item("copper_ore", "Copper Ore", "resource", 32, 2.0)
	items["tin_ore"] = _create_item("tin_ore", "Tin Ore", "resource", 32, 2.0)
	
	# Processed materials
	items["plank"] = _create_item("plank", "Plank", "material", 64, 0.5)
	items["stone_brick"] = _create_item("stone_brick", "Stone Brick", "material", 64, 1.0)
	items["iron_ingot"] = _create_item("iron_ingot", "Iron Ingot", "material", 32, 2.0)
	items["gold_ingot"] = _create_item("gold_ingot", "Gold Ingot", "material", 16, 3.0)
	items["copper_ingot"] = _create_item("copper_ingot", "Copper Ingot", "material", 32, 2.0)
	items["bronze_ingot"] = _create_item("bronze_ingot", "Bronze Ingot", "material", 32, 2.5)
	items["charcoal"] = _create_item("charcoal", "Charcoal", "resource", 64, 0.5)
	items["glass"] = _create_item("glass", "Glass", "material", 32, 1.0)
	
	# Tools
	items["wooden_axe"] = _create_item("wooden_axe", "Wooden Axe", "tool", 1, 2.0, tool_type="axe", damage_bonus=3, durability=50)
	items["stone_axe"] = _create_item("stone_axe", "Stone Axe", "tool", 1, 2.5, tool_type="axe", damage_bonus=5, durability=100)
	items["iron_axe"] = _create_item("iron_axe", "Iron Axe", "tool", 1, 3.0, tool_type="axe", damage_bonus=8, durability=200)
	items["wooden_pickaxe"] = _create_item("wooden_pickaxe", "Wooden Pickaxe", "tool", 1, 2.0, tool_type="pickaxe", damage_bonus=3, durability=50)
	items["stone_pickaxe"] = _create_item("stone_pickaxe", "Stone Pickaxe", "tool", 1, 2.5, tool_type="pickaxe", damage_bonus=5, durability=100)
	items["iron_pickaxe"] = _create_item("iron_pickaxe", "Iron Pickaxe", "tool", 1, 3.0, tool_type="pickaxe", damage_bonus=8, durability=200)
	items["wooden_sword"] = _create_item("wooden_sword", "Wooden Sword", "weapon", 1, 1.5, tool_type="sword", damage_bonus=5, durability=50)
	items["stone_sword"] = _create_item("stone_sword", "Stone Sword", "weapon", 1, 2.0, tool_type="sword", damage_bonus=8, durability=100)
	items["iron_sword"] = _create_item("iron_sword", "Iron Sword", "weapon", 1, 2.5, tool_type="sword", damage_bonus=12, durability=200)
	items["stone_hoe"] = _create_item("stone_hoe", "Stone Hoe", "tool", 1, 2.0, tool_type="hoe", damage_bonus=2, durability=100)
	items["wooden_hammer"] = _create_item("wooden_hammer", "Wooden Hammer", "tool", 1, 2.5, tool_type="hammer", damage_bonus=4, durability=50)
	items["stone_hammer"] = _create_item("stone_hammer", "Stone Hammer", "tool", 1, 3.0, tool_type="hammer", damage_bonus=6, durability=100)
	
	# Food
	items["cooked_meat"] = _create_item("cooked_meat", "Cooked Meat", "food", 16, 0.5, hunger_bonus=20, health_bonus=5)
	items["cooked_fish"] = _create_item("cooked_fish", "Cooked Fish", "food", 16, 0.5, hunger_bonus=15, health_bonus=5)
	items["bread"] = _create_item("bread", "Bread", "food", 32, 0.3, hunger_bonus=10, health_bonus=3)
	items["soup"] = _create_item("soup", "Soup", "food", 8, 0.5, hunger_bonus=25, health_bonus=10)
	items["fish"] = _create_item("fish", "Raw Fish", "food", 16, 0.3, hunger_bonus=5)
	items["meat"] = _create_item("meat", "Raw Meat", "food", 16, 0.5, hunger_bonus=3)
	
	# Building materials
	items["torch"] = _create_item("torch", "Torch", "building", 32, 0.2)
	items["wooden_wall"] = _create_item("wooden_wall", "Wooden Wall", "building", 16, 2.0)
	items["wooden_door"] = _create_item("wooden_door", "Wooden Door", "building", 8, 1.5)
	items["stone_wall"] = _create_item("stone_wall", "Stone Wall", "building", 16, 3.0)
	items["stone_floor"] = _create_item("stone_floor", "Stone Floor", "building", 32, 2.0)
	items["campfire"] = _create_item("campfire", "Campfire", "building", 4, 1.0)
	items["furnace"] = _create_item("furnace", "Furnace", "building", 1, 10.0)
	items["workbench"] = _create_item("workbench", "Workbench", "building", 1, 5.0)
	items["anvil"] = _create_item("anvil", "Anvil", "building", 1, 15.0)
	items["chest"] = _create_item("chest", "Chest", "building", 1, 3.0)
	items["bed"] = _create_item("bed", "Bed", "building", 1, 5.0)
	items["farm_soil"] = _create_item("farm_soil", "Farm Soil", "building", 32, 0.5)
	items["fence"] = _create_item("fence", "Fence", "building", 32, 1.0)
	
	# Special
	items["seed_wheat"] = _create_item("seed_wheat", "Wheat Seed", "resource", 64, 0.1)
	items["wheat"] = _create_item("wheat", "Wheat", "resource", 64, 0.2)
	items["flour"] = _create_item("flour", "Flour", "material", 64, 0.3)
	items["apple"] = _create_item("apple", "Apple", "food", 32, 0.2, hunger_bonus=8, health_bonus=2)
	items["mushroom"] = _create_item("mushroom", "Mushroom", "food", 32, 0.1, hunger_bonus=5)
	items["herb"] = _create_item("herb", "Herb", "resource", 64, 0.1)
	items["potion_health"] = _create_item("potion_health", "Health Potion", "consumable", 16, 0.3, health_bonus=30)
	items["potion_mana"] = _create_item("potion_mana", "Mana Potion", "consumable", 16, 0.3, hunger_bonus=5)

## Load all recipe definitions.
func _load_recipes() -> void:
	# Basic crafting
	recipes["plank"] = _create_recipe("plank", "plank", 4, "", {
		"wood": 1
	})
	recipes["charcoal"] = _create_recipe("charcoal", "charcoal", 1, "", {
		"wood": 1
	}, 10.0)
	recipes["glass"] = _create_recipe("glass", "glass", 1, "furnace", {
		"sand": 2,
		"coal": 1
	}, 5.0)
	recipes["iron_ingot"] = _create_recipe("iron_ingot", "iron_ingot", 1, "furnace", {
		"iron_ore": 2,
		"coal": 1
	}, 10.0)
	recipes["gold_ingot"] = _create_recipe("gold_ingot", "gold_ingot", 1, "furnace", {
		"gold_ore": 2,
		"coal": 1
	}, 10.0)
	recipes["copper_ingot"] = _create_recipe("copper_ingot", "copper_ingot", 1, "furnace", {
		"copper_ore": 2,
		"coal": 1
	}, 8.0)
	recipes["bronze_ingot"] = _create_recipe("bronze_ingot", "bronze_ingot", 1, "anvil", {
		"copper_ingot": 2,
		"tin_ore": 1
	}, 15.0)
	
	# Tools
	recipes["wooden_axe"] = _create_recipe("wooden_axe", "wooden_axe", 1, "", {
		"plank": 3,
		"fibre": 2
	})
	recipes["stone_axe"] = _create_recipe("stone_axe", "stone_axe", 1, "", {
		"plank": 2,
		"stone": 3,
		"fibre": 2
	})
	recipes["iron_axe"] = _create_recipe("iron_axe", "iron_axe", 1, "", {
		"plank": 2,
		"iron_ingot": 3
	})
	recipes["wooden_pickaxe"] = _create_recipe("wooden_pickaxe", "wooden_pickaxe", 1, "", {
		"plank": 3,
		"fibre": 2
	})
	recipes["stone_pickaxe"] = _create_recipe("stone_pickaxe", "stone_pickaxe", 1, "", {
		"plank": 2,
		"stone": 3,
		"fibre": 2
	})
	recipes["iron_pickaxe"] = _create_recipe("iron_pickaxe", "iron_pickaxe", 1, "", {
		"plank": 2,
		"iron_ingot": 3
	})
	recipes["wooden_sword"] = _create_recipe("wooden_sword", "wooden_sword", 1, "", {
		"plank": 4,
		"fibre": 2
	})
	recipes["stone_sword"] = _create_recipe("stone_sword", "stone_sword", 1, "", {
		"plank": 3,
		"stone": 4,
		"fibre": 2
	})
	recipes["iron_sword"] = _create_recipe("iron_sword", "iron_sword", 1, "", {
		"plank": 2,
		"iron_ingot": 4
	})
	recipes["stone_hoe"] = _create_recipe("stone_hoe", "stone_hoe", 1, "", {
		"plank": 2,
		"stone": 3,
		"fibre": 2
	})
	recipes["wooden_hammer"] = _create_recipe("wooden_hammer", "wooden_hammer", 1, "", {
		"plank": 4,
		"stone": 2
	})
	recipes["stone_hammer"] = _create_recipe("stone_hammer", "stone_hammer", 1, "", {
		"plank": 3,
		"stone": 5
	})
	
	# Food
	recipes["cooked_meat"] = _create_recipe("cooked_meat", "cooked_meat", 1, "campfire", {
		"meat": 1
	}, 5.0)
	recipes["cooked_fish"] = _create_recipe("cooked_fish", "cooked_fish", 1, "campfire", {
		"fish": 1
	}, 5.0)
	recipes["bread"] = _create_recipe("bread", "bread", 2, "", {
		"flour": 2,
		"berry": 1
	})
	recipes["soup"] = _create_recipe("soup", "soup", 1, "campfire", {
		"meat": 1,
		"mushroom": 2,
		"herb": 1
	}, 8.0)
	
	# Building
	recipes["torch"] = _create_recipe("torch", "torch", 4, "", {
		"plank": 1,
		"charcoal": 1,
		"fibre": 1
	})
	recipes["wooden_wall"] = _create_recipe("wooden_wall", "wooden_wall", 1, "", {
		"plank": 5
	})
	recipes["wooden_door"] = _create_recipe("wooden_door", "wooden_door", 1, "", {
		"plank": 4
	})
	recipes["stone_wall"] = _create_recipe("stone_wall", "stone_wall", 1, "", {
		"stone_brick": 5
	})
	recipes["stone_floor"] = _create_recipe("stone_floor", "stone_floor", 4, "", {
		"stone": 4
	})
	recipes["campfire"] = _create_recipe("campfire", "campfire", 1, "", {
		"stone": 5,
		"wood": 3,
		"charcoal": 2
	})
	recipes["furnace"] = _create_recipe("furnace", "furnace", 1, "", {
		"stone": 10,
		"charcoal": 5
	})
	recipes["workbench"] = _create_recipe("workbench", "workbench", 1, "", {
		"plank": 10,
		"stone": 5
	})
	recipes["anvil"] = _create_recipe("anvil", "anvil", 1, "", {
		"iron_ingot": 10,
		"stone": 5
	})
	recipes["chest"] = _create_recipe("chest", "chest", 1, "", {
		"plank": 8
	})
	recipes["bed"] = _create_recipe("bed", "bed", 1, "", {
		"plank": 5,
		"hide": 3,
		"fibre": 5
	})
	recipes["farm_soil"] = _create_recipe("farm_soil", "farm_soil", 4, "", {
		"dirt": 4
	})
	recipes["fence"] = _create_recipe("fence", "fence", 1, "", {
		"plank": 3
	})
	
	# Advanced
	recipes["potion_health"] = _create_recipe("potion_health", "potion_health", 1, "furnace", {
		"herb": 3,
		"glass": 1
	}, 5.0)
	recipes["potion_mana"] = _create_recipe("potion_mana", "potion_mana", 1, "furnace", {
		"herb": 2,
		"glass": 1,
		"berry": 1
	}, 5.0)

## Create a basic item.
func _create_item(item_id: String, display_name: String, category: String, stack_size: int, weight: float, 
				 tool_type: String = "", health_bonus: int = 0, hunger_bonus: int = 0, 
				 damage_bonus: int = 0, durability: int = 0) -> ItemDefinition:
	var item := ItemDefinition.new()
	item.item_id = item_id
	item.display_name = display_name
	item.category = category
	item.stack_size = stack_size
	item.weight = weight
	item.tool_type = tool_type
	item.health_bonus = health_bonus
	item.hunger_bonus = hunger_bonus
	item.damage_bonus = damage_bonus
	item.durability = durability
	return item

## Create a basic recipe.
func _create_recipe(recipe_id: String, result_item_id: String, result_quantity: int, 
					crafting_station: String, required_items: Dictionary, craft_time: float = 0.0) -> RecipeDefinition:
	var recipe := RecipeDefinition.new()
	recipe.recipe_id = recipe_id
	recipe.result_item_id = result_item_id
	recipe.result_quantity = result_quantity
	recipe.crafting_station = crafting_station
	recipe.required_items = required_items
	recipe.craft_time = craft_time
	return recipe

## Get an item by ID.
func get_item(item_id: String) -> ItemDefinition:
	return items.get(item_id)

## Get a recipe by ID.
func get_recipe(recipe_id: String) -> RecipeDefinition:
	return recipes.get(recipe_id)

## Get all recipes for a crafting station.
func get_recipes_for_station(station: String) -> Array[RecipeDefinition]:
	var result: Array[RecipeDefinition] = []
	for recipe_id in recipes:
		var recipe: RecipeDefinition = recipes[recipe_id]
		if recipe.crafting_station == station or station == "":
			result.append(recipe)
	return result

## Check if item exists.
func has_item(item_id: String) -> bool:
	return items.has(item_id)

## Check if recipe exists.
func has_recipe(recipe_id: String) -> bool:
	return recipes.has(recipe_id)
