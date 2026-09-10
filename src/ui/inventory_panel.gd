## UI panel for displaying and managing inventory.
class_name InventoryPanel
extends Control

@onready var slot_container: GridContainer = $SlotContainer
@onready var item_count_label: Label = $Panel/VBoxContainer/ItemCount
@onready var item_description_label: Label = $Panel/VBoxContainer/ItemDescription
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

var _inventory: "InventoryComponent" = null
var _selected_slot: int = -1

# Signal to close this panel
signal closed

func _ready() -> void:
	visible = false
	$Panel.self_modulate.a = 0.9
	close_button.pressed.connect(_on_close_pressed)

## Set the inventory to display.
func set_inventory(inventory: "InventoryComponent") -> void:
	_inventory = inventory
	_inventory.inventory_changed.connect(_refresh)
	_refresh()

## Show the panel.
func show_panel() -> void:
	visible = true
	_refresh()

## Hide the panel.
func hide_panel() -> void:
	visible = false
	closed.emit()

## Refresh the display.
func _refresh() -> void:
	if not _inventory:
		return

	# Clear existing slots
	for child in slot_container.get_children():
		child.queue_free()

	# Create slots
	var slots: Dictionary = _inventory.get_slots()
	var slot_index: int = 0
	for item_id in slots:
		var quantity: int = slots[item_id]["quantity"]
		var slot := _create_slot(item_id, quantity, slot_index)
		slot_container.add_child(slot)
		slot_index += 1

	# Fill empty slots up to max
	var max_slots: int = 50
	for i in range(slot_index, max_slots):
		var empty_slot := _create_empty_slot(i)
		slot_container.add_child(empty_slot)

	# Update labels
	item_count_label.text = "Items: %d/%d" % [_inventory.slot_count, _inventory._max_slots]
	item_description_label.text = ""

## Create a slot for an item.
func _create_slot(item_id: String, quantity: int, index: int) -> Control:
	var slot := PanelContainer.new()
	slot.size_flags_horizontal = Control.SIZE_FILL
	slot.size_flags_vertical = Control.SIZE_FILL
	slot.min_size = Vector2(40, 40)

	var layout := BoxContainer.new()
	layout.layout_mode = BoxContainer.BOX_HORIZONTAL
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	slot.add_child(layout)

	var icon := TextureRect.new()
	icon.size_mode = TextureRect.SIZE_FILL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_theme_exceptions = "Font"
	# Placeholder: use a colored rect instead of texture
	var color_rect := ColorRect.new()
	color_rect.color = _get_item_color(item_id)
	color_rect.size = Vector2(32, 32)
	icon.add_child(color_rect)
	layout.add_child(icon)

	var count_label := Label.new()
	count_label.text = str(quantity)
	count_label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VerticalAlignment.VERTICAL_ALIGNMENT_BOTTOM
	count_label.add_theme_color_override("font_color", Color.WHITE)
	count_label.add_theme_font_size_override("font_size", 12)
	layout.add_child(count_label)

	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	slot.gui_input.connect(func(event: InputEvent): _on_slot_input(event, item_id, index))

	return slot

## Create an empty slot.
func _create_empty_slot(index: int) -> Control:
	var slot := PanelContainer.new()
	slot.size_flags_horizontal = Control.SIZE_FILL
	slot.size_flags_vertical = Control.SIZE_FILL
	slot.min_size = Vector2(40, 40)
	slot.modulate.a = 0.3
	return slot

## Get a placeholder color for an item ID.
func _get_item_color(item_id: String) -> Color:
	match item_id:
		"wood", "log":
			return Color(0.6, 0.4, 0.2)
		"stone", "rock":
			return Color(0.5, 0.5, 0.5)
		"iron_ore":
			return Color(0.7, 0.5, 0.3)
		"food", "berry":
			return Color(0.8, 0.3, 0.3)
		_:
			return Color(0.4, 0.4, 0.6)

## Handle slot input.
func _on_slot_input(event: InputEvent, item_id: String, index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_selected_slot = index
			# Show item description
			if _inventory:
				item_description_label.text = "Selected: %s" % item_id
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Attempt to drop item
			if _inventory:
				_inventory.remove_item(item_id, 1)

## Handle close button.
func _on_close_pressed() -> void:
	hide_panel()

## Called when the game event bus signals to toggle inventory.
func _on_toggle_inventory() -> void:
	if visible:
		hide_panel()
	else:
		show_panel()
