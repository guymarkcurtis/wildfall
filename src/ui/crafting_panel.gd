## Crafting panel showing available recipes.
class_name CraftingPanel
extends Control

# Must be >= the recipe database size: smaller caps silently make recipes
# unreachable in the panel (there is no scroll view on the list).
const MAX_RECIPES: int = 40

@onready var recipe_list: VBoxContainer = $MarginContainer/VBox/RecipeList
@onready var recipe_template: Control = $MarginContainer/VBox/RecipeList/RecipeItem
@onready var result_label: Label = $MarginContainer/VBox/ResultLabel
@onready var station_label: Label = $MarginContainer/VBox/StationLabel

var recipes: Array[Dictionary] = []
var inventory: Dictionary = {}
var selected_recipe: int = -1
var current_station: String = ""

# Signals
signal recipe_selected(recipe_index: int)
signal recipe_crafted(result_item_id: String, quantity: int)
signal result_crafted(result_item_id: String, quantity: int)
signal craft_failed(reason: String)
# A recipe item's Craft button was pressed: the game (Main) applies the
# craft to the real player inventory, then refreshes this panel.
signal recipe_craft_requested(recipe_index: int)

func _ready() -> void:
	_setup_ui()

## Setup the UI.
func _setup_ui() -> void:
	recipe_template.visible = false

## Refresh the crafting panel.
func refresh(recipe_data: Array[Dictionary], inv: Dictionary, station: String = "") -> void:
	recipes = recipe_data
	inventory = inv
	current_station = station
	_refresh()

## Refresh the display.
func _refresh() -> void:
	# Clear existing recipes
	for child in recipe_list.get_children():
		if child != recipe_template:
			child.queue_free()
	
	# Add recipe items
	for i in range(min(recipes.size(), MAX_RECIPES)):
		var recipe: Dictionary = recipes[i]
		var can_craft: bool = _can_craft(recipe)
		var recipe_item: Control = recipe_template.duplicate()
		recipe_item.name = "Recipe%d" % i
		recipe_item.index = i
		# Enter the tree FIRST: @onready node paths inside RecipeItemUI are
		# only resolved when the node's _ready runs (on add_child). Calling
		# set_data before add_child would dereference null labels.
		recipe_list.add_child(recipe_item)
		recipe_item.visible = true
		recipe_item.set_data(recipe, can_craft)
		if recipe_item.has_signal("craft_requested"):
			recipe_item.connect("craft_requested", _on_recipe_craft_requested)
	
	# Update station label
	if station_label:
		if current_station == "":
			station_label.text = "Crafting: Anywhere"
		else:
			station_label.text = "Crafting: " + current_station.capitalize()

## Check if recipe can be crafted.
func _can_craft(recipe: Dictionary) -> bool:
	var required: Dictionary = recipe.get("required_items", {})
	for item_id in required:
		var needed: int = required[item_id]
		var available: int = inventory.get(item_id, 0)
		if available < needed:
			return false
	return true

## A recipe item UI requested crafting: update the result label and
## notify the game layer (Main) to apply the craft to the real inventory.
func _on_recipe_craft_requested(recipe_index: int) -> void:
	select_recipe(recipe_index)
	recipe_craft_requested.emit(recipe_index)

## Select a recipe.
func select_recipe(recipe_index: int) -> void:
	selected_recipe = recipe_index
	if recipe_index < 0 or recipe_index >= recipes.size():
		result_label.text = "No recipe selected"
		return
	
	var recipe: Dictionary = recipes[recipe_index]
	var can_craft: bool = _can_craft(recipe)
	var result_item_id: String = recipe.get("result_item_id", "")
	var result_qty: int = recipe.get("result_quantity", 1)
	
	if can_craft:
		result_label.text = "✓ Can craft %dx %s" % [result_qty, result_item_id]
		result_label.modulate = Color(0.3, 0.8, 0.3)
	else:
		result_label.text = "✗ Missing materials"
		result_label.modulate = Color(0.8, 0.3, 0.3)
	
	recipe_selected.emit(recipe_index)

## Craft the selected recipe.
func craft_recipe() -> bool:
	if selected_recipe < 0 or selected_recipe >= recipes.size():
		craft_failed.emit("No recipe selected")
		return false
	
	var recipe: Dictionary = recipes[selected_recipe]
	if not _can_craft(recipe):
		craft_failed.emit("Missing materials")
		return false
	
	# Remove materials
	var required: Dictionary = recipe.get("required_items", {})
	for item_id in required:
		var needed: int = required[item_id]
		inventory[item_id] = inventory.get(item_id, 0) - needed
		if inventory[item_id] <= 0:
			inventory.erase(item_id)
	
	# Add result
	var result_item_id: String = recipe.get("result_item_id", "")
	var result_qty: int = recipe.get("result_quantity", 1)
	inventory[result_item_id] = inventory.get(result_item_id, 0) + result_qty
	
	emit_signal("result_crafted", result_item_id, result_qty)
	_refresh()
	return true

## Get recipe at index.
func get_recipe(index: int) -> Dictionary:
	if index >= 0 and index < recipes.size():
		return recipes[index]
	return {}
