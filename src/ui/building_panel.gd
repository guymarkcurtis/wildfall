## UI panel for placing buildings.
class_name BuildingPanel
extends Control

const MAX_BUILDINGS: int = 10

@onready var building_list: VBoxContainer = $MarginContainer/BuildingList
@onready var place_button: Button = $PlaceButton
@onready var close_button: Button = $CloseButton
@onready var status_label: Label = $StatusLabel

var current_buildings: Dictionary = {}
var selected_building: String = ""

# Signals
signal building_selected(building_id: String)
signal building_placed(building_id: String, coords: Vector2i)
signal panel_closed

func _ready() -> void:
	visible = false
	place_button.pressed.connect(_on_place_pressed)
	close_button.pressed.connect(_on_close_pressed)

## Show the building panel.
func show_panel(buildings: Dictionary) -> void:
	current_buildings = buildings
	visible = true
	_refresh_list()

## Refresh the building list.
func _refresh_list() -> void:
	# Clear existing items
	for child in building_list.get_children():
		if child != place_button and child != close_button:
			child.queue_free()
	
	# Add building options
	for building_id in current_buildings:
		var quantity := current_buildings[building_id]
		if quantity > 0:
			var item := _create_building_item(building_id, quantity)
			building_list.add_child(item)

## Create a building list item.
func _create_building_item(building_id: String, quantity: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 30)
	
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hbox)
	
	# Building name
	var name_label := Label.new()
	name_label.text = building_id.capitalize()
	hbox.add_child(name_label)
	
	# Quantity
	var qty_label := Label.new()
	qty_label.text = "x%d" % quantity
	qty_label.modulate = Color(0.8, 0.8, 0.8)
	hbox.add_child(qty_label)
	
	# Select button
	var select_btn := Button.new()
	select_btn.text = "Select"
	select_btn.pressed.connect(func(): _on_select_pressed(building_id))
	hbox.add_child(select_btn)
	
	return panel

## Handle building selection.
func _on_select_pressed(building_id: String) -> void:
	selected_building = building_id
	status_label.text = "Selected: %s (Press E to place)" % building_id.capitalize()
	building_selected.emit(building_id)

## Handle place button press.
func _on_place_pressed() -> void:
	if selected_building == "":
		status_label.text = "No building selected"
		return
	status_label.text = "Place %s near player" % selected_building.capitalize()
	building_placed.emit(selected_building, Vector2i(0, 0))

## Handle close button press.
func _on_close_pressed() -> void:
	visible = false
	panel_closed.emit()

## Hide the panel.
func hide_panel() -> void:
	visible = false

## Set status message.
func set_status(message: String) -> void:
	status_label.text = message
