## A compact, selectable recipe card used by CraftingPanel.
class_name RecipeItemUI
extends Control

var index := 0
var recipe: Dictionary = {}
var can_craft := false

signal craft_requested(index: int)
signal selected(index: int)

@onready var recipe_name_label: Label = $NameLabel
@onready var recipe_cost_label: Label = $CostLabel
@onready var craft_button: Button = $CraftButton
@onready var background: ColorRect = $Background
@onready var result_icon: TextureRect = $ResultIcon

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	craft_button.pressed.connect(_on_craft_pressed)
	mouse_entered.connect(func() -> void: background.color = _card_color(true))
	mouse_exited.connect(func() -> void: background.color = _card_color(false))
	gui_input.connect(_on_gui_input)

func set_data(recipe_data: Dictionary, craftable: bool, inventory: Dictionary = {}) -> void:
	recipe = recipe_data
	can_craft = craftable
	var result_id := str(recipe_data.get("result_item_id", ""))
	var result_qty := int(recipe_data.get("result_quantity", 1))
	result_icon.texture = _item_icon(result_id)
	recipe_name_label.text = "%s%s" % [str(recipe_data.get("display_name", result_id)), "  ×%d" % result_qty if result_qty > 1 else ""]
	var cost: Dictionary = recipe_data.get("required_items", {})
	var names: Dictionary = recipe_data.get("ingredient_names", {})
	var parts := PackedStringArray()
	for item_id in cost:
		var needed := int(cost[item_id])
		var owned := int(inventory.get(item_id, 0))
		parts.append("%s  %d/%d" % [str(names.get(item_id, str(item_id).capitalize())), owned, needed])
	var station := str(recipe_data.get("crafting_station", ""))
	if not station.is_empty():
		parts.append("@ %s" % station.capitalize())
	recipe_cost_label.text = "  •  ".join(parts) if not parts.is_empty() else "No materials required"
	craft_button.text = "CRAFT" if can_craft else "LOCKED"
	craft_button.disabled = not can_craft
	background.color = _card_color(false)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		selected.emit(index)

func _on_craft_pressed() -> void:
	if can_craft:
		craft_requested.emit(index)

func _card_color(hovered: bool) -> Color:
	if can_craft:
		return Color(0.15, 0.23, 0.15, 0.98) if hovered else Color(0.105, 0.155, 0.11, 0.94)
	return Color(0.13, 0.13, 0.115, 0.94) if hovered else Color(0.085, 0.09, 0.08, 0.88)

func _item_icon(item_id: String) -> Texture2D:
	var item_db := get_tree().root.get_node_or_null("Main/ItemDatabase")
	if item_db == null:
		return null
	var item: ItemDefinition = item_db.get_item(item_id)
	if item == null or item.texture_path.is_empty():
		return null
	return TexturePackManager.get_texture(item.texture_path)
