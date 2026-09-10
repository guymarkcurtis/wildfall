## UI element for a crafting recipe.
class_name RecipeItemUI
extends Control

var index: int = 0
var recipe: Dictionary = {}
var can_craft: bool = false

@onready var recipe_name_label: Label = $NameLabel
@onready var recipe_cost_label: Label = $CostLabel
@onready var craft_button: Button = $CraftButton
@onready var background: ColorRect = $Background

func _ready() -> void:
	visible = false
	craft_button.pressed.connect(_on_craft_pressed)

## Set recipe data.
func set_data(recipe_data: Dictionary, can_craft: bool) -> void:
	self.recipe = recipe_data
	self.can_craft = can_craft
	
	var result_id: String = recipe_data.get("result_item_id", "")
	var result_qty: int = recipe_data.get("result_quantity", 1)
	var cost: Dictionary = recipe_data.get("required_items", {})
	
	recipe_name_label.text = "%dx %s" % [result_qty, result_id]
	
	var cost_str: PackedStringArray = []
	for item_id in cost:
		cost_str.append("%dx %s" % [cost[item_id], item_id])
	recipe_cost_label.text = ", ".join(cost_str)
	
	craft_button.disabled = not can_craft
	background.color = Color(0.3, 0.3, 0.3, 0.8) if can_craft else Color(0.2, 0.2, 0.2, 0.5)

## Handle craft button press.
func _on_craft_pressed() -> void:
	if can_craft:
		$CraftButton.grab_focus()
