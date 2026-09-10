## UI panel for interacting with crafting stations.
class_name StationPanel
extends Control

@onready var station_name_label: Label = $MarginContainer/StationNameLabel
@onready var station_desc_label: Label = $MarginContainer/StationDescLabel
@onready var recipe_list: VBoxContainer = $MarginContainer/RecipeList
@onready var craft_button: Button = $CraftButton
@onready var close_button: Button = $CloseButton

var current_station: CraftingStation = null
var inventory: Dictionary = {}

# Signals
signal station_selected(station: CraftingStation)
signal recipe_crafted(result_item_id: String, quantity: int)
signal station_closed

func _ready() -> void:
	visible = false
	craft_button.pressed.connect(_on_craft_pressed)
	close_button.pressed.connect(_on_close_pressed)

## Show the station panel.
func show_station(station: CraftingStation, inv: Dictionary) -> void:
	current_station = station
	inventory = inv
	visible = true
	
	# Update display
	if station:
		station_name_label.text = station.get_display_name()
		station_desc_label.text = station.get_description()
		_refresh_recipes()
	else:
		station_name_label.text = "No Station"
		station_desc_label.text = ""
		_refresh_recipes()

## Refresh the recipe list.
func _refresh_recipes() -> void:
	# Clear existing recipes
	for child in recipe_list.get_children():
		if child != craft_button and child != close_button:
			child.queue_free()
	
	if not current_station:
		return
	
	# Get recipes from station
	var recipes: Array[Dictionary] = current_station.get_recipes()
	
	for recipe in recipes:
		var can_craft: bool = current_station.can_craft(recipe, inventory)
		var recipe_item := _create_recipe_item(recipe, can_craft)
		recipe_list.add_child(recipe_item)
	
	# Update craft button
	craft_button.disabled = not _has_craftable_recipe()

## Check if any recipe can be crafted.
func _has_craftable_recipe() -> bool:
	if not current_station:
		return false
	
	var recipes: Array[Dictionary] = current_station.get_recipes()
	for recipe in recipes:
		if current_station.can_craft(recipe, inventory):
			return true
	return false

## Create a recipe display item.
func _create_recipe_item(recipe: Dictionary, can_craft: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 30)
	
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hbox)
	
	# Recipe name
	var name_label := Label.new()
	name_label.text = "%dx %s" % [recipe.get("result_quantity", 1), recipe.get("result_item_id", "")]
	hbox.add_child(name_label)
	
	# Cost display
	var cost_label := Label.new()
	var cost_str: PackedStringArray = []
	var cost: Dictionary = recipe.get("required_items", {})
	for item_id in cost:
		cost_str.append("%dx %s" % [cost[item_id], item_id])
	cost_label.text = ", ".join(cost_str)
	cost_label.modulate = Color(0.8, 0.8, 0.8)
	hbox.add_child(cost_label)
	
	# Can craft indicator
	var indicator := Label.new()
	if can_craft:
		indicator.text = "✓"
		indicator.modulate = Color(0.3, 0.8, 0.3)
	else:
		indicator.text = "✗"
		indicator.modulate = Color(0.8, 0.3, 0.3)
	hbox.add_child(indicator)
	
	return panel

## Handle craft button press.
func _on_craft_pressed() -> void:
	if not current_station:
		return
	
	# Find first craftable recipe
	var recipes: Array[Dictionary] = current_station.get_recipes()
	for recipe in recipes:
		if current_station.can_craft(recipe, inventory):
			# Execute craft
			var result_id: String = recipe.get("result_item_id", "")
			var result_qty: int = recipe.get("result_quantity", 1)
			
			# Remove materials
			var cost: Dictionary = recipe.get("required_items", {})
			for item_id in cost:
				inventory[item_id] = inventory.get(item_id, 0) - cost[item_id]
				if inventory[item_id] <= 0:
					inventory.erase(item_id)
			
			# Add result
			inventory[result_id] = inventory.get(result_id, 0) + result_qty
			recipe_crafted.emit(result_id, result_qty)
			_refresh_recipes()
			return

## Handle close button press.
func _on_close_pressed() -> void:
	visible = false
	station_closed.emit()

## Hide the panel.
func hide_panel() -> void:
	visible = false
