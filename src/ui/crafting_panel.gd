## Crafting panel showing available recipes.
class_name CraftingPanel
extends Control

const MAX_RECIPES: int = 20

@onready var recipe_list: VBoxContainer = $MarginContainer/RecipeList
@onready var recipe_template: Control = $MarginContainer/RecipeList/RecipeItem
@onready var result_label: Label = $MarginContainer/ResultPanel/ResultLabel
@onready var station_label: Label = $MarginContainer/StationLabel

var recipes: Array[Dictionary] = []
var inventory: Dictionary = {}
var selected_recipe: int = -1
var current_station: String = ""

# Signals
signal recipe_selected(recipe_index: int)
signal recipe_crafted(result_item_id: String, quantity: int)
signal craft_failed(reason: String)

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
		recipe_item.visible = true
		recipe_item.name = "Recipe%d" % i
		recipe_item.index = i
		recipe_item.set_data(recipe, can_craft)
		recipe_list.add_child(recipe_item)
	
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
	
	result_crafted.emit(result_item_id, result_qty)
	_refresh()
	return true

## Get recipe at index.
func get_recipe(index: int) -> Dictionary:
	if 0 <= index < recipes.size():
		return recipes[index]
	return {}
