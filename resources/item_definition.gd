## Defines an item with its properties.
class_name ItemDefinition
extends Resource

@export var item_id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var category: String = "misc"  # resource, tool, weapon, food, building, material
@export var stack_size: int = 64
@export var weight: float = 1.0
@export var rarity: String = "common"  # common, uncommon, rare, epic
@export var texture_path: String = ""
@export var health_bonus: int = 0
@export var hunger_bonus: int = 0
@export var damage_bonus: int = 0
@export var durability: int = 0
@export var tool_type: String = ""  # axe, pickaxe, sword, etc.

## Create a basic item definition.
static func create_basic(item_id: String, display_name: String, category: String) -> ItemDefinition:
	var item := ItemDefinition.new()
	item.item_id = item_id
	item.display_name = display_name
	item.category = category
	item.stack_size = 64
	item.weight = 1.0
	item.rarity = "common"
	return item

## Check if item is a tool.
func is_tool() -> bool:
	return tool_type != "" and tool_type != "hand"

## Check if item is consumable.
func is_consumable() -> bool:
	return health_bonus > 0 or hunger_bonus > 0

## Get item rarity color.
func get_rarity_color() -> Color:
	match rarity:
		"common": return Color(0.8, 0.8, 0.8)
		"uncommon": return Color(0.2, 0.8, 0.2)
		"rare": return Color(0.2, 0.4, 0.9)
		"epic": return Color(0.7, 0.2, 0.8)
		_: return Color(1.0, 1.0, 1.0)
