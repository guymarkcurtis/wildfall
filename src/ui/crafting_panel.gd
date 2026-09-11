## Crafting panel showing available recipes.
class_name CraftingPanel
extends Control

@onready var recipe_scroll: ScrollContainer = $MarginContainer/VBox/RecipeScroll
@onready var recipe_list: VBoxContainer = $MarginContainer/VBox/RecipeScroll/RecipeList
@onready var recipe_template: Control = $MarginContainer/VBox/RecipeScroll/RecipeList/RecipeItem
@onready var result_label: Label = $MarginContainer/VBox/ResultLabel
@onready var station_label: Label = $MarginContainer/VBox/StationLabel

var recipes: Array[Dictionary] = []
var inventory: Dictionary = {}
var selected_recipe: int = -1
var nearby_stations := PackedStringArray()

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
func refresh(recipe_data: Array[Dictionary], inv: Dictionary, nearby: PackedStringArray = PackedStringArray()) -> void:
	recipes = recipe_data
	inventory = inv
	nearby_stations = nearby
	_refresh()

## Refresh the display.
func _refresh() -> void:
	var previous_scroll: int = recipe_scroll.scroll_vertical
	# Clear existing recipes
	for child in recipe_list.get_children():
		if child != recipe_template:
			# Refreshes can happen back-to-back when inventory or nearby-station
			# state changes. Free immediately so duplicate rows never accumulate
			# inside the scroll container before the next idle frame.
			child.free()
	
	# Add recipe items
	for i in range(recipes.size()):
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
	# ScrollContainer needs an explicit content height because its child VBox
	# is otherwise stretched to the viewport before it can report its rows.
	# Every recipe row is a fixed 48 pixels in the scene.
	recipe_list.custom_minimum_size = Vector2(450.0, float(recipes.size()) * 48.0)
	if selected_recipe >= recipes.size():
		selected_recipe = -1
	if selected_recipe >= 0:
		select_recipe(selected_recipe)
	call_deferred("_restore_scroll_position", previous_scroll)
	
	# Update station label
	if station_label:
		if nearby_stations.is_empty():
			station_label.text = "Nearby stations: none"
		else:
			var names := PackedStringArray()
			for station_id in nearby_stations:
				names.append(station_id.capitalize())
			station_label.text = "Nearby stations: " + " • ".join(names)

func _restore_scroll_position(previous_scroll: int) -> void:
	if recipe_scroll != null:
		recipe_scroll.scroll_vertical = previous_scroll

## Check if recipe can be crafted.
func _can_craft(recipe: Dictionary) -> bool:
	if GameSession.is_creative():
		return true
	var required_station := str(recipe.get("crafting_station", ""))
	if not required_station.is_empty() and not nearby_stations.has(required_station):
		return false
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
	var required_station := str(recipe.get("crafting_station", ""))
	
	if can_craft:
		result_label.text = "✓ Can craft %dx %s" % [result_qty, result_item_id]
		result_label.modulate = Color(0.3, 0.8, 0.3)
	elif not required_station.is_empty() and not nearby_stations.has(required_station):
		result_label.text = "✗ Requires nearby %s" % required_station.capitalize()
		result_label.modulate = Color(0.8, 0.55, 0.25)
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
		var required_station := str(recipe.get("crafting_station", ""))
		craft_failed.emit("Requires nearby %s" % required_station.capitalize() if not required_station.is_empty() and not nearby_stations.has(required_station) else "Missing materials")
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
