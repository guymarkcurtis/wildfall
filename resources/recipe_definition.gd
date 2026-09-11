## Defines a crafting recipe.
class_name RecipeDefinition
extends Resource

@export var recipe_id: String = ""
@export var result_item_id: String = ""
@export var result_quantity: int = 1
@export var crafting_station: String = ""  # empty, workbench, furnace, anvil
@export var required_items: Dictionary = {}  # {item_id: quantity}
@export var craft_time: float = 0.0  # seconds, 0 = instant
@export var unlocked: bool = true
## Empty means the recipe is available without research. Otherwise this must
## match a TechnologyDefinition.id that the player has unlocked.
@export var technology_id: String = ""

## Check if recipe can be crafted with given inventory.
func can_craft(inventory: Dictionary) -> bool:
	for item_id in required_items:
		var required: int = required_items[item_id]
		var available: int = inventory.get(item_id, 0)
		if available < required:
			return false
	return true

## Get the cost as a formatted string.
func get_cost_string() -> String:
	var parts: PackedStringArray = []
	for item_id in required_items:
		var qty: int = required_items[item_id]
		parts.append("%dx %s" % [qty, item_id])
	return ", ".join(parts)

## Get recipe rarity based on result.
func get_rarity() -> String:
	if result_quantity >= 5:
		return "common"
	elif result_quantity >= 3:
		return "uncommon"
	elif craft_time > 5.0:
		return "rare"
	return "common"
