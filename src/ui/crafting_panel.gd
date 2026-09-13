## Filterable crafting workbench. Recipes remain in their stable database order.
class_name CraftingPanel
extends Control

@onready var recipe_scroll: ScrollContainer = $MarginContainer/VBox/RecipeScroll
@onready var recipe_list: VBoxContainer = $MarginContainer/VBox/RecipeScroll/RecipeList
@onready var recipe_template: Control = $MarginContainer/VBox/RecipeScroll/RecipeList/RecipeItem
@onready var result_label: Label = $MarginContainer/VBox/ResultLabel
@onready var station_label: Label = $MarginContainer/VBox/StationLabel

var recipes: Array[Dictionary] = []
var inventory: Dictionary = {}
var selected_recipe := -1
var nearby_stations := PackedStringArray()
var _active_category := "All"
var _search_query := ""
var _category_buttons: Dictionary = {}
var _empty_label: Label = null

signal recipe_selected(recipe_index: int)
signal recipe_crafted(result_item_id: String, quantity: int)
signal result_crafted(result_item_id: String, quantity: int)
signal craft_failed(reason: String)
signal recipe_craft_requested(recipe_index: int)

func _ready() -> void:
	_setup_ui()

func _setup_ui() -> void:
	recipe_template.visible = false
	var backdrop := PanelContainer.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.add_theme_stylebox_override("panel", _panel_style())
	add_child(backdrop)
	move_child(backdrop, 0)
	var title := $Title as Label
	title.text = "FIELD WORKBENCH"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("e6e9b8"))
	var column := $MarginContainer/VBox as VBoxContainer
	column.add_theme_constant_override("separation", 8)
	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "Choose a discipline, inspect the cost, then build what you need.  C closes"
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color("9aa88a"))
	column.add_child(subtitle)
	column.move_child(subtitle, 0)
	var search := LineEdit.new()
	search.name = "RecipeSearch"
	search.placeholder_text = "Search known recipes…"
	search.clear_button_enabled = true
	search.custom_minimum_size.y = 38.0
	search.text_changed.connect(_on_search_changed)
	column.add_child(search)
	column.move_child(search, 1)
	var category_bar := HBoxContainer.new()
	category_bar.name = "CategoryBar"
	category_bar.add_theme_constant_override("separation", 6)
	column.add_child(category_bar)
	column.move_child(category_bar, 2)
	for category in ["All", "Gear", "Building", "Food", "Materials"]:
		var button := Button.new()
		button.text = category
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(105.0, 32.0)
		button.pressed.connect(_select_category.bind(category))
		category_bar.add_child(button)
		_category_buttons[category] = button
	_empty_label = Label.new()
	_empty_label.name = "EmptyState"
	_empty_label.text = "No known recipes match this view."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_color_override("font_color", Color("9aa88a"))
	_empty_label.visible = false
	column.add_child(_empty_label)
	column.move_child(_empty_label, 4)
	_update_category_buttons()

func refresh(recipe_data: Array[Dictionary], inv: Dictionary, nearby: PackedStringArray = PackedStringArray()) -> void:
	recipes = recipe_data
	inventory = inv
	nearby_stations = nearby
	_refresh()

func _refresh() -> void:
	var previous_scroll := recipe_scroll.scroll_vertical
	for child in recipe_list.get_children():
		if child != recipe_template:
			child.free()
	var visible_count := 0
	for i in range(recipes.size()):
		var recipe: Dictionary = recipes[i]
		if not _matches_filters(recipe):
			continue
		visible_count += 1
		var recipe_item: Control = recipe_template.duplicate()
		recipe_item.name = "Recipe%d" % i
		recipe_item.index = i
		recipe_list.add_child(recipe_item)
		recipe_item.visible = true
		recipe_item.set_data(recipe, _can_craft(recipe), inventory)
		recipe_item.craft_requested.connect(_on_recipe_craft_requested)
		recipe_item.selected.connect(select_recipe)
	recipe_list.custom_minimum_size = Vector2(700.0, float(visible_count) * 76.0)
	_empty_label.visible = visible_count == 0
	if selected_recipe >= recipes.size():
		selected_recipe = -1
	if selected_recipe >= 0:
		select_recipe(selected_recipe)
	elif result_label.text.is_empty():
		result_label.text = "Select a recipe to inspect it"
	call_deferred("_restore_scroll_position", previous_scroll)
	if nearby_stations.is_empty():
		station_label.text = "CRAFTING RANGE  •  hand tools only"
	else:
		var names := PackedStringArray()
		for station_id in nearby_stations:
			names.append(station_id.capitalize())
		station_label.text = "CRAFTING RANGE  •  " + "  •  ".join(names)

func _matches_filters(recipe: Dictionary) -> bool:
	if _active_category != "All" and _category_for(recipe) != _active_category:
		return false
	if _search_query.is_empty():
		return true
	var haystack := "%s %s %s" % [recipe.get("display_name", ""), recipe.get("description", ""), recipe.get("result_item_id", "")]
	return haystack.to_lower().contains(_search_query)

func _category_for(recipe: Dictionary) -> String:
	var category := str(recipe.get("category", "")).to_lower()
	if category in ["tool", "tools", "weapon", "weapons", "equipment", "ammo"]:
		return "Gear"
	if category in ["building", "construction", "structure"]:
		return "Building"
	if category in ["food", "consumable", "cooking"]:
		return "Food"
	return "Materials"

func _select_category(category: String) -> void:
	_active_category = category
	_update_category_buttons()
	recipe_scroll.scroll_vertical = 0
	_refresh()

func _update_category_buttons() -> void:
	for category in _category_buttons:
		(_category_buttons[category] as Button).button_pressed = category == _active_category

func _on_search_changed(value: String) -> void:
	_search_query = value.strip_edges().to_lower()
	recipe_scroll.scroll_vertical = 0
	_refresh()

func _restore_scroll_position(previous_scroll: int) -> void:
	if recipe_scroll != null:
		recipe_scroll.scroll_vertical = previous_scroll

func _can_craft(recipe: Dictionary) -> bool:
	if GameSession.is_creative():
		return true
	var station := str(recipe.get("crafting_station", ""))
	if not station.is_empty() and not nearby_stations.has(station):
		return false
	for item_id in recipe.get("required_items", {}):
		if int(inventory.get(item_id, 0)) < int(recipe.required_items[item_id]):
			return false
	return true

func _on_recipe_craft_requested(recipe_index: int) -> void:
	select_recipe(recipe_index)
	recipe_craft_requested.emit(recipe_index)

func select_recipe(recipe_index: int) -> void:
	selected_recipe = recipe_index
	if recipe_index < 0 or recipe_index >= recipes.size():
		result_label.text = "No recipe selected"
		return
	var recipe := recipes[recipe_index]
	var display := str(recipe.get("display_name", recipe.get("result_item_id", "")))
	var station := str(recipe.get("crafting_station", ""))
	if _can_craft(recipe):
		result_label.text = "READY  •  %dx %s" % [int(recipe.get("result_quantity", 1)), display]
		result_label.modulate = Color("83c878")
	elif not station.is_empty() and not nearby_stations.has(station):
		result_label.text = "NEEDS STATION  •  %s" % station.capitalize()
		result_label.modulate = Color("daa85e")
	else:
		result_label.text = "MATERIALS MISSING  •  %s" % display
		result_label.modulate = Color("d57968")
	recipe_selected.emit(recipe_index)

func craft_recipe() -> bool:
	if selected_recipe < 0 or selected_recipe >= recipes.size():
		craft_failed.emit("No recipe selected")
		return false
	var recipe := recipes[selected_recipe]
	if not _can_craft(recipe):
		craft_failed.emit("Missing materials or station")
		return false
	for item_id in recipe.get("required_items", {}):
		inventory[item_id] = inventory.get(item_id, 0) - recipe.required_items[item_id]
		if inventory[item_id] <= 0:
			inventory.erase(item_id)
	var result_item_id := str(recipe.get("result_item_id", ""))
	var result_qty := int(recipe.get("result_quantity", 1))
	inventory[result_item_id] = inventory.get(result_item_id, 0) + result_qty
	result_crafted.emit(result_item_id, result_qty)
	_refresh()
	return true

func get_recipe(index: int) -> Dictionary:
	return recipes[index] if index >= 0 and index < recipes.size() else {}

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.060, 0.048, 0.985)
	style.border_color = Color(0.43, 0.51, 0.28, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 14
	return style
