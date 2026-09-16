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
	items["wooden_axe"] = _create_item("wooden_axe", "Wooden Axe", "tool", 1, 2.0, "axe", 0, 0, 3, 50)
	items["stone_axe"] = _create_item("stone_axe", "Stone Axe", "tool", 1, 2.5, "axe", 0, 0, 5, 100)
	items["iron_axe"] = _create_item("iron_axe", "Iron Axe", "tool", 1, 3.0, "axe", 0, 0, 8, 200)
	items["wooden_pickaxe"] = _create_item("wooden_pickaxe", "Wooden Pickaxe", "tool", 1, 2.0, "pickaxe", 0, 0, 3, 50)
	items["stone_pickaxe"] = _create_item("stone_pickaxe", "Stone Pickaxe", "tool", 1, 2.5, "pickaxe", 0, 0, 5, 100)
	items["iron_pickaxe"] = _create_item("iron_pickaxe", "Iron Pickaxe", "tool", 1, 3.0, "pickaxe", 0, 0, 8, 200)
	items["wooden_sword"] = _create_item("wooden_sword", "Wooden Sword", "weapon", 1, 1.5, "sword", 0, 0, 5, 50)
	items["stone_sword"] = _create_item("stone_sword", "Stone Sword", "weapon", 1, 2.0, "sword", 0, 0, 8, 100)
	items["iron_sword"] = _create_item("iron_sword", "Iron Sword", "weapon", 1, 2.5, "sword", 0, 0, 12, 200)
	items["wooden_bow"] = _create_item("wooden_bow", "Wooden Bow", "weapon", 1, 1.5, "bow", 0, 0, 7, 80)
	items["arrow"] = _create_item("arrow", "Arrow", "ammo", 64, 0.05)
	items["stone_hoe"] = _create_item("stone_hoe", "Stone Hoe", "tool", 1, 2.0, "hoe", 0, 0, 2, 100)
	items["wooden_hammer"] = _create_item("wooden_hammer", "Wooden Hammer", "tool", 1, 2.5, "hammer", 0, 0, 4, 50)
	items["stone_hammer"] = _create_item("stone_hammer", "Stone Hammer", "tool", 1, 3.0, "hammer", 0, 0, 6, 100)
	
	# Food
	items["cooked_meat"] = _create_item("cooked_meat", "Cooked Meat", "food", 16, 0.5, "", 5, 20)
	items["cooked_fish"] = _create_item("cooked_fish", "Cooked Fish", "food", 16, 0.5, "", 5, 15)
	items["bread"] = _create_item("bread", "Bread", "food", 32, 0.3, "", 3, 10)
	items["soup"] = _create_item("soup", "Soup", "food", 8, 0.5, "", 10, 25)
	items["fish"] = _create_item("fish", "Raw Fish", "food", 16, 0.3, "", 0, 5)
	items["meat"] = _create_item("meat", "Raw Meat", "food", 16, 0.5, "", 0, 3)
	
	# Building materials
	items["torch"] = _create_item("torch", "Torch", "building", 32, 0.2)
	items["wooden_foundation"] = _create_item("wooden_foundation", "Wood Foundation", "building", 32, 2.0)
	items["wooden_floor"] = _create_item("wooden_floor", "Wood Floor", "building", 32, 1.5)
	items["wooden_wall"] = _create_item("wooden_wall", "Wooden Wall", "building", 16, 2.0)
	items["wooden_window"] = _create_item("wooden_window", "Wood Window", "building", 16, 1.8)
	items["wooden_door"] = _create_item("wooden_door", "Wooden Door", "building", 8, 1.5)
	items["wooden_roof"] = _create_item("wooden_roof", "Wood Roof", "building", 24, 1.8)
	items["wooden_stairs"] = _create_item("wooden_stairs", "Wood Stairs", "building", 16, 2.0)
	# Down-stairs reuse the up-stair icon: at 32 px a 180-degree rotation reads
	# identically, so this is a deliberate decision (see the art contract).
	var wooden_stairs_down_item := _create_item("wooden_stairs_down", "Wood Stairs (down)", "building", 16, 2.0)
	wooden_stairs_down_item.texture_path = "res://assets/items/pickups/wooden_stairs.png"
	items["wooden_stairs_down"] = wooden_stairs_down_item
	items["wooden_ramp"] = _create_item("wooden_ramp", "Wood Ramp", "building", 16, 1.8)
	items["wooden_pillar"] = _create_item("wooden_pillar", "Wood Pillar", "building", 16, 2.2)
	items["stone_foundation"] = _create_item("stone_foundation", "Stone Foundation", "building", 32, 3.0)
	items["stone_wall"] = _create_item("stone_wall", "Stone Wall", "building", 16, 3.0)
	items["stone_floor"] = _create_item("stone_floor", "Stone Floor", "building", 32, 2.0)
	items["stone_window"] = _create_item("stone_window", "Stone Window", "building", 16, 2.8)
	items["stone_door"] = _create_item("stone_door", "Stone Door", "building", 8, 3.0)
	items["stone_roof"] = _create_item("stone_roof", "Stone Roof", "building", 24, 2.8)
	items["stone_stairs"] = _create_item("stone_stairs", "Stone Stairs", "building", 16, 3.2)
	var stone_stairs_down_item := _create_item("stone_stairs_down", "Stone Stairs (down)", "building", 16, 3.2)
	stone_stairs_down_item.texture_path = "res://assets/items/pickups/stone_stairs.png"
	items["stone_stairs_down"] = stone_stairs_down_item
	items["stone_ramp"] = _create_item("stone_ramp", "Stone Ramp", "building", 16, 3.0)
	items["stone_pillar"] = _create_item("stone_pillar", "Stone Pillar", "building", 16, 3.5)
	items["campfire"] = _create_item("campfire", "Campfire", "building", 4, 1.0)
	items["furnace"] = _create_item("furnace", "Furnace", "building", 1, 10.0)
	items["workbench"] = _create_item("workbench", "Workbench", "building", 1, 5.0)
	items["anvil"] = _create_item("anvil", "Anvil", "building", 1, 15.0)
	items["chest"] = _create_item("chest", "Chest", "building", 1, 3.0)
	items["bed"] = _create_item("bed", "Bed", "building", 1, 5.0)
	items["farm_soil"] = _create_item("farm_soil", "Farm Soil", "building", 32, 0.5)
	items["fence"] = _create_item("fence", "Fence", "building", 32, 1.0)
	items["fence_gate"] = _create_item("fence_gate", "Fence Gate", "building", 16, 1.5)
	items["wooden_railing"] = _create_item("wooden_railing", "Wood Railing", "building", 32, 1.0)
	items["wooden_porch"] = _create_item("wooden_porch", "Wood Porch", "building", 32, 2.0)
	items["wooden_deck"] = _create_item("wooden_deck", "Wood Deck", "building", 32, 1.5)
	items["wooden_path"] = _create_item("wooden_path", "Wood Path", "building", 32, 1.0)
	items["planter_box"] = _create_item("planter_box", "Planter Box", "building", 16, 2.0)
	items["wooden_table"] = _create_item("wooden_table", "Wood Table", "building", 8, 3.0)
	items["yard_lantern"] = _create_item("yard_lantern", "Yard Lantern", "building", 8, 1.5)
	# Handheld light tiers (the placed yard/metal lanterns stay building
	# items). Light strength and rarity scale with tier in data; consumers
	# query the light_source tag generically.
	items["stone_lantern"] = _create_item("stone_lantern", "Stone Lantern", "tool", 8, 2.0)
	items["iron_lantern"] = _create_item("iron_lantern", "Iron Lantern", "tool", 8, 2.0)
	items["stone_gate"] = _create_item("stone_gate", "Stone Gate", "building", 16, 3.0)
	items["stone_railing"] = _create_item("stone_railing", "Stone Railing", "building", 32, 2.5)
	items["stone_patio"] = _create_item("stone_patio", "Stone Patio", "building", 32, 3.0)
	items["stone_path"] = _create_item("stone_path", "Stone Path", "building", 32, 2.0)
	items["stone_planter"] = _create_item("stone_planter", "Stone Planter", "building", 16, 4.0)
	items["reinforced_floor"] = _create_item("reinforced_floor", "Reinforced Floor", "building", 32, 4.0)
	items["reinforced_wall"] = _create_item("reinforced_wall", "Reinforced Wall", "building", 16, 5.0)
	items["metal_roof"] = _create_item("metal_roof", "Metal Roof", "building", 24, 4.5)
	items["metal_gate"] = _create_item("metal_gate", "Metal Gate", "building", 16, 4.5)
	items["metal_railing"] = _create_item("metal_railing", "Metal Railing", "building", 32, 3.0)
	items["metal_grate"] = _create_item("metal_grate", "Metal Grate", "building", 32, 4.0)
	# M8 furniture: interior/yard pieces beyond the structural kit. Recipes and
	# placement rules live in data/buildings/<id>.tres (see its README).
	items["chair"] = _create_item("chair", "Wooden Chair", "building", 8, 3.0)
	items["shelf"] = _create_item("shelf", "Wood Shelf", "building", 8, 2.5)
	items["rug"] = _create_item("rug", "Woven Rug", "building", 16, 1.5)
	items["wardrobe"] = _create_item("wardrobe", "Wardrobe", "building", 4, 6.0)
	items["steps"] = _create_item("steps", "Wood Steps", "building", 16, 2.0)
	items["awning"] = _create_item("awning", "Canvas Awning", "building", 16, 2.0)
	items["corner_post"] = _create_item("corner_post", "Corner Post", "building", 16, 1.5)
	items["hearth"] = _create_item("hearth", "Stone Hearth", "building", 4, 8.0)
	items["cabinet"] = _create_item("cabinet", "Stone Cabinet", "building", 4, 5.0)
	items["bookcase"] = _create_item("bookcase", "Stone Bookcase", "building", 4, 4.5)
	items["well"] = _create_item("well", "Stone Well", "building", 1, 8.0)
	items["brazier"] = _create_item("brazier", "Iron Brazier", "building", 4, 4.0)
	items["shuttered_window"] = _create_item("shuttered_window", "Shuttered Window", "building", 16, 3.0)
	items["metal_stair"] = _create_item("metal_stair", "Metal Stair", "building", 16, 4.0)
	var metal_stair_down_item := _create_item("metal_stair_down", "Metal Stair (down)", "building", 16, 4.0)
	metal_stair_down_item.texture_path = "res://assets/items/pickups/metal_stair.png"
	items["metal_stair_down"] = metal_stair_down_item
	items["metal_fence"] = _create_item("metal_fence", "Metal Fence", "building", 32, 3.0)
	items["signal_pole"] = _create_item("signal_pole", "Signal Pole", "building", 16, 2.0)
	items["metal_lantern"] = _create_item("metal_lantern", "Metal Lantern", "building", 8, 1.5)
	items["workshop_cabinet"] = _create_item("workshop_cabinet", "Workshop Cabinet", "building", 4, 5.0)
	items["metal_locker"] = _create_item("metal_locker", "Metal Locker", "building", 8, 3.0)

	# Special
	items["seed_wheat"] = _create_item("seed_wheat", "Wheat Seed", "resource", 64, 0.1)
	items["wheat"] = _create_item("wheat", "Wheat", "resource", 64, 0.2)
	items["flour"] = _create_item("flour", "Flour", "material", 64, 0.3)
	items["apple"] = _create_item("apple", "Apple", "food", 32, 0.2, "", 2, 8)
	items["mushroom"] = _create_item("mushroom", "Mushroom", "food", 32, 0.1, "", 0, 5)
	items["herb"] = _create_item("herb", "Herb", "resource", 64, 0.1)
	items["potion_health"] = _create_item("potion_health", "Health Potion", "consumable", 16, 0.3, "", 30, 0)
	items["potion_mana"] = _create_item("potion_mana", "Mana Potion", "consumable", 16, 0.3, "", 0, 5)

	# Item tags: burnables carry the generic "fuel" tag so fuelled profiles can
	# query acceptance by tag. Handheld lights carry "light_source" so the
	# character screen's light slot queries acceptance the same generic way.
	# Never replace this with a named item list in gameplay code — see
	# docs/INTERACTABLE_AUTHORING.md.
	for fuel_item_id in ["wood", "coal", "charcoal"]:
		var fuel_item := get_item(fuel_item_id)
		if fuel_item != null:
			fuel_item.tags = PackedStringArray(["fuel"])
	# Handheld light sources: glow presentation lives here in data, tier
	# scaled — common torch, uncommon stone lantern, rare iron lantern — so
	# future lanterns need no new code. Rarities are the item tiers the
	# strength ladder is keyed to.
	var torch_item := get_item("torch")
	if torch_item != null:
		torch_item.tags.append("light_source")
		torch_item.light_color = Color(1.0, 0.82, 0.55)
		torch_item.light_energy = 1.25
		torch_item.light_radius_px = 200.0
	var stone_lantern_item := get_item("stone_lantern")
	if stone_lantern_item != null:
		stone_lantern_item.tags = PackedStringArray(["light_source"])
		stone_lantern_item.rarity = "uncommon"
		stone_lantern_item.light_color = Color(1.0, 0.78, 0.5)
		stone_lantern_item.light_energy = 1.6
		stone_lantern_item.light_radius_px = 264.0
		# Until dedicated pickup art ships, the stone lantern borrows the
		# yard lantern icon (a lantern silhouette reads at 32 px); same
		# deliberate decision the down-stairs make with the stair icon.
		stone_lantern_item.texture_path = "res://assets/items/pickups/yard_lantern.png"
	var iron_lantern_item := get_item("iron_lantern")
	if iron_lantern_item != null:
		iron_lantern_item.tags = PackedStringArray(["light_source"])
		iron_lantern_item.rarity = "rare"
		iron_lantern_item.light_color = Color(1.0, 0.88, 0.62)
		iron_lantern_item.light_energy = 2.0
		iron_lantern_item.light_radius_px = 336.0
		# The iron lantern borrows the metal lantern building icon until its
		# dedicated pickup art ships (see the stone lantern note above).
		iron_lantern_item.texture_path = "res://assets/items/pickups/metal_lantern.png"

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
	}, 14.0)
	recipes["copper_ingot"] = _create_recipe("copper_ingot", "copper_ingot", 1, "furnace", {
		"copper_ore": 2,
		"coal": 1
	}, 8.0)
	recipes["bronze_ingot"] = _create_recipe("bronze_ingot", "bronze_ingot", 1, "anvil", {
		"copper_ingot": 2,
		"tin_ore": 1
	}, 15.0)
	
	# Tools
	recipes["wooden_bow"] = _create_recipe("wooden_bow", "wooden_bow", 1, "", {
		"plank": 2,
		"fibre": 3
	})
	recipes["arrow"] = _create_recipe("arrow", "arrow", 4, "", {
		"wood": 1,
		"fibre": 1
	})
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
	recipes["wooden_hammer"] = _create_recipe("wooden_hammer", "wooden_hammer", 1, "workbench", {
		"plank": 4,
		"stone": 2
	}, 5.0)
	recipes["stone_hammer"] = _create_recipe("stone_hammer", "stone_hammer", 1, "", {
		"plank": 3,
		"stone": 5
	})
	
	# Food. Craft times scale with tier: raw cooking is quick, multi-
	# ingredient dishes and refined potions take longer.
	recipes["cooked_meat"] = _create_recipe("cooked_meat", "cooked_meat", 1, "campfire", {
		"meat": 1
	}, 4.0)
	recipes["cooked_fish"] = _create_recipe("cooked_fish", "cooked_fish", 1, "campfire", {
		"fish": 1
	}, 4.0)
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
	# Handheld light tiers: the stone lantern is a workbench craft gated by
	# stone research, the iron lantern by metalworking. Craft times scale
	# with tier, matching the furnace/food convention above.
	recipes["stone_lantern"] = _create_recipe("stone_lantern", "stone_lantern", 1, "workbench", {
		"stone_brick": 2,
		"plank": 1,
		"charcoal": 1
	}, 8.0)
	recipes["iron_lantern"] = _create_recipe("iron_lantern", "iron_lantern", 1, "workbench", {
		"iron_ingot": 2,
		"plank": 1,
		"charcoal": 1
	}, 12.0)
	recipes["wooden_wall"] = _create_recipe("wooden_wall", "wooden_wall", 1, "", {
		"plank": 5
	})
	recipes["wooden_foundation"] = _create_recipe("wooden_foundation", "wooden_foundation", 1, "", {
		"plank": 2
	})
	recipes["wooden_floor"] = _create_recipe("wooden_floor", "wooden_floor", 1, "", {
		"plank": 1
	})
	recipes["wooden_window"] = _create_recipe("wooden_window", "wooden_window", 1, "", {
		"plank": 2,
		"glass": 1
	})
	recipes["wooden_door"] = _create_recipe("wooden_door", "wooden_door", 1, "", {
		"plank": 4
	})
	recipes["wooden_roof"] = _create_recipe("wooden_roof", "wooden_roof", 1, "", {
		"plank": 2
	})
	recipes["wooden_stairs"] = _create_recipe("wooden_stairs", "wooden_stairs", 1, "", {
		"plank": 3
	})
	recipes["wooden_stairs_down"] = _create_recipe("wooden_stairs_down", "wooden_stairs_down", 1, "", {
		"plank": 3
	})
	recipes["wooden_ramp"] = _create_recipe("wooden_ramp", "wooden_ramp", 1, "", {
		"plank": 2
	})
	recipes["wooden_pillar"] = _create_recipe("wooden_pillar", "wooden_pillar", 1, "", {
		"plank": 2
	})
	recipes["stone_foundation"] = _create_recipe("stone_foundation", "stone_foundation", 1, "", {
		"stone_brick": 2
	})
	recipes["stone_wall"] = _create_recipe("stone_wall", "stone_wall", 1, "", {
		"stone_brick": 5
	})
	recipes["stone_floor"] = _create_recipe("stone_floor", "stone_floor", 4, "", {
		"stone_brick": 1
	})
	recipes["stone_window"] = _create_recipe("stone_window", "stone_window", 1, "", {
		"stone_brick": 2,
		"glass": 1
	})
	recipes["stone_door"] = _create_recipe("stone_door", "stone_door", 1, "", {
		"stone_brick": 3
	})
	recipes["stone_roof"] = _create_recipe("stone_roof", "stone_roof", 1, "", {
		"stone_brick": 2
	})
	recipes["stone_stairs"] = _create_recipe("stone_stairs", "stone_stairs", 1, "", {
		"stone_brick": 3
	})
	recipes["stone_stairs_down"] = _create_recipe("stone_stairs_down", "stone_stairs_down", 1, "", {
		"stone_brick": 3
	})
	recipes["stone_ramp"] = _create_recipe("stone_ramp", "stone_ramp", 1, "", {
		"stone_brick": 2
	})
	recipes["stone_pillar"] = _create_recipe("stone_pillar", "stone_pillar", 1, "", {
		"stone_brick": 2
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
	# "dirt" is not an obtainable item (no resource drops it), so farm soil
	# is made from sand + clay — both of which are harvestable.
	recipes["farm_soil"] = _create_recipe("farm_soil", "farm_soil", 4, "", {
		"sand": 3,
		"clay": 1
	})
	recipes["fence"] = _create_recipe("fence", "fence", 1, "", {
		"plank": 2
	})
	recipes["fence_gate"] = _create_recipe("fence_gate", "fence_gate", 1, "", {
		"plank": 3
	})
	recipes["wooden_railing"] = _create_recipe("wooden_railing", "wooden_railing", 1, "", {
		"plank": 1
	})
	recipes["wooden_porch"] = _create_recipe("wooden_porch", "wooden_porch", 1, "", {
		"plank": 3
	})
	recipes["wooden_deck"] = _create_recipe("wooden_deck", "wooden_deck", 1, "", {
		"plank": 2
	})
	recipes["wooden_path"] = _create_recipe("wooden_path", "wooden_path", 1, "", {
		"plank": 1
	})
	recipes["planter_box"] = _create_recipe("planter_box", "planter_box", 1, "", {
		"plank": 4,
		"clay": 1
	})
	recipes["wooden_table"] = _create_recipe("wooden_table", "wooden_table", 1, "", {
		"plank": 4
	})
	recipes["yard_lantern"] = _create_recipe("yard_lantern", "yard_lantern", 1, "", {
		"plank": 2,
		"charcoal": 1
	})
	recipes["stone_gate"] = _create_recipe("stone_gate", "stone_gate", 1, "", {
		"stone_brick": 3
	})
	recipes["stone_railing"] = _create_recipe("stone_railing", "stone_railing", 1, "", {
		"stone_brick": 1
	})
	recipes["stone_patio"] = _create_recipe("stone_patio", "stone_patio", 1, "", {
		"stone_brick": 2
	})
	recipes["stone_path"] = _create_recipe("stone_path", "stone_path", 1, "", {
		"stone_brick": 1
	})
	recipes["stone_planter"] = _create_recipe("stone_planter", "stone_planter", 1, "", {
		"stone_brick": 3
	})
	recipes["reinforced_floor"] = _create_recipe("reinforced_floor", "reinforced_floor", 1, "", {"iron_ingot": 2})
	recipes["reinforced_wall"] = _create_recipe("reinforced_wall", "reinforced_wall", 1, "", {"iron_ingot": 4})
	recipes["metal_roof"] = _create_recipe("metal_roof", "metal_roof", 1, "", {"iron_ingot": 3})
	recipes["metal_gate"] = _create_recipe("metal_gate", "metal_gate", 1, "", {"iron_ingot": 3})
	recipes["metal_railing"] = _create_recipe("metal_railing", "metal_railing", 1, "", {"iron_ingot": 1})
	recipes["metal_grate"] = _create_recipe("metal_grate", "metal_grate", 1, "", {"iron_ingot": 2})
	# M8 furniture recipes: costs mirror each definition's build_cost exactly.
	recipes["chair"] = _create_recipe("chair", "chair", 1, "", {"plank": 3})
	recipes["shelf"] = _create_recipe("shelf", "shelf", 1, "", {"plank": 4})
	recipes["rug"] = _create_recipe("rug", "rug", 1, "", {"plank": 2, "hide": 1})
	recipes["wardrobe"] = _create_recipe("wardrobe", "wardrobe", 1, "", {"plank": 6})
	recipes["steps"] = _create_recipe("steps", "steps", 1, "", {"plank": 3})
	recipes["awning"] = _create_recipe("awning", "awning", 1, "", {"plank": 4, "hide": 1})
	recipes["corner_post"] = _create_recipe("corner_post", "corner_post", 1, "", {"plank": 2})
	recipes["hearth"] = _create_recipe("hearth", "hearth", 1, "", {"stone_brick": 4})
	recipes["cabinet"] = _create_recipe("cabinet", "cabinet", 1, "", {"stone_brick": 4})
	recipes["bookcase"] = _create_recipe("bookcase", "bookcase", 1, "", {"stone_brick": 3, "plank": 2})
	recipes["well"] = _create_recipe("well", "well", 1, "", {"stone_brick": 8})
	recipes["brazier"] = _create_recipe("brazier", "brazier", 1, "", {"stone_brick": 2, "iron_ingot": 1})
	recipes["shuttered_window"] = _create_recipe("shuttered_window", "shuttered_window", 1, "", {"iron_ingot": 2, "plank": 2})
	recipes["metal_stair"] = _create_recipe("metal_stair", "metal_stair", 1, "", {"iron_ingot": 3})
	recipes["metal_fence"] = _create_recipe("metal_fence", "metal_fence", 1, "", {"iron_ingot": 2})
	recipes["signal_pole"] = _create_recipe("signal_pole", "signal_pole", 1, "", {"plank": 2, "iron_ingot": 1})
	recipes["metal_lantern"] = _create_recipe("metal_lantern", "metal_lantern", 1, "", {"iron_ingot": 2})
	recipes["workshop_cabinet"] = _create_recipe("workshop_cabinet", "workshop_cabinet", 1, "", {"iron_ingot": 4, "plank": 2})
	recipes["metal_locker"] = _create_recipe("metal_locker", "metal_locker", 1, "", {"iron_ingot": 3})

	# Advanced
	recipes["potion_health"] = _create_recipe("potion_health", "potion_health", 1, "furnace", {
		"herb": 3,
		"glass": 1
	}, 6.0)
	recipes["potion_mana"] = _create_recipe("potion_mana", "potion_mana", 1, "furnace", {
		"herb": 2,
		"glass": 1,
		"berry": 1
	}, 8.0)

	# Phase 3 (creatures & hunting): close the last obtainability gaps.
	# Stone brick gives stone walls a source; flour (milled from wheat,
	# which grows on grassland plants) gives bread a source. Together with
	# the creature drops (meat/fish/hide/feather/bone) and the plant drops
	# (wheat/herb/mushroom), every recipe in the database is now reachable.
	recipes["stone_brick"] = _create_recipe("stone_brick", "stone_brick", 2, "", {
		"stone": 2
	})
	recipes["flour"] = _create_recipe("flour", "flour", 2, "", {
		"wheat": 1
	})

	# Research gates are assigned after recipe construction to keep the recipe
	# definitions readable above. Wood construction is a free starting unlock;
	# stone and metal work are earned through the technology panel.
	_set_recipe_technology([
		"wooden_foundation", "wooden_floor", "wooden_wall", "wooden_window",
		"wooden_door", "wooden_roof", "wooden_stairs", "wooden_stairs_down", "wooden_ramp", "wooden_pillar",
		"fence", "fence_gate", "wooden_railing", "wooden_porch", "wooden_deck",
		"wooden_path", "planter_box", "wooden_table", "yard_lantern",
		"chair", "shelf", "rug", "wardrobe", "steps", "awning", "corner_post"
	], "wood_building")
	_set_recipe_technology([
		"stone_brick", "stone_axe", "stone_pickaxe", "stone_sword", "stone_hoe", "stone_hammer",
		"stone_foundation", "stone_floor", "stone_wall", "stone_window", "stone_door",
		"stone_roof", "stone_stairs", "stone_stairs_down", "stone_ramp", "stone_pillar", "furnace", "workbench",
		"stone_gate", "stone_railing", "stone_patio", "stone_path", "stone_planter",
		"hearth", "cabinet", "bookcase", "well", "brazier", "stone_lantern"
	], "stone_building")
	_set_recipe_technology([
		"iron_ingot", "copper_ingot", "bronze_ingot", "iron_axe", "iron_pickaxe",
		"iron_sword", "anvil", "reinforced_floor", "reinforced_wall", "metal_roof",
		"metal_gate", "metal_railing", "metal_grate",
		"shuttered_window", "metal_stair", "metal_stair_down", "metal_fence", "signal_pole",
		"metal_lantern", "workshop_cabinet", "metal_locker", "iron_lantern"
	], "metalworking")

## Create a basic item.
func _create_item(item_id: String, display_name: String, category: String, stack_size: int, weight: float, 
				 tool_type: String = "", health_bonus: int = 0, hunger_bonus: int = 0, 
				 damage_bonus: int = 0, durability: int = 0) -> ItemDefinition:
	var item := ItemDefinition.new()
	item.item_id = item_id
	item.display_name = display_name
	# Item presentation follows the same data contract as a world pickup. UI,
	# loot, and texture packs therefore all resolve one item ID to one sprite.
	item.texture_path = "res://assets/items/pickups/%s.png" % item_id
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

func _set_recipe_technology(recipe_ids: Array[String], technology_id: String) -> void:
	for recipe_id in recipe_ids:
		var recipe: RecipeDefinition = get_recipe(recipe_id)
		if recipe != null:
			recipe.technology_id = technology_id

## Get an item by ID.
func get_item(item_id: String) -> ItemDefinition:
	return items.get(item_id)

## Get the display name for an item (falls back to the item id).
func get_item_display_name(item_id: String) -> String:
	var item := get_item(item_id)
	if item == null:
		return item_id
	return item.display_name

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

## All durable items as {item_id: max durability}. Only items with
## durability > 0 are listed (tools and weapons).
func get_all_durations() -> Dictionary:
	var result: Dictionary = {}
	for item_id in items:
		var item: ItemDefinition = items[item_id]
		if item.durability > 0:
			result[str(item_id)] = int(item.durability)
	return result

## All item ids carrying a given tag (e.g. "fuel"). Data query — consumers
## decide what a tag means; the database only reports membership.
func get_items_with_tag(tag: String) -> Array[String]:
	var result: Array[String] = []
	for item_id in items:
		var item: ItemDefinition = items[item_id]
		if item != null and item.has_tag(tag):
			result.append(str(item_id))
	result.sort()
	return result
