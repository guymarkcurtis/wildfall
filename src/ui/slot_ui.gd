## UI element for a single inventory slot.
class_name SlotUI
extends Control

var index: int = 0
var item_id: String = ""
var quantity: int = 0
var selected: bool = false

## Emitted when the slot is activated (button click or mouse click).
signal slot_selected(index: int)

@onready var item_label: Label = $ItemLabel
@onready var quantity_label: Label = $QuantityLabel
@onready var selected_overlay: ColorRect = $SelectedOverlay

## Update alias used by InventoryPanel.refresh().
func update(new_item_id: String, new_quantity: int) -> void:
	set_item(new_item_id, new_quantity)

## Update the slot display for an item.
func set_item(new_item_id: String, new_quantity: int) -> void:
	item_id = new_item_id
	quantity = new_quantity
	if item_id == "":
		item_label.text = ""
		quantity_label.text = ""
	else:
		# Look up item name from ItemDatabase if available
		var item_db = get_tree().root.get_node_or_null("Main/ItemDatabase")
		if item_db:
			item_label.text = item_db.get_item_display_name(item_id)
		else:
			item_label.text = item_id
		if quantity > 1:
			quantity_label.text = str(quantity)
		else:
			quantity_label.text = ""

## Clear the slot.
func clear_slot() -> void:
	item_id = ""
	quantity = 0
	item_label.text = ""
	quantity_label.text = ""

## Set the slot's selected state.
func set_selected(is_selected: bool) -> void:
	selected = is_selected
	selected_overlay.visible = selected

## Check if a slot has an item.
func has_item() -> bool:
	return item_id != ""

## Select this slot.
func select_slot(index: int) -> void:
	self.index = index
	set_selected(true)
	slot_selected.emit(index)

## Handle input on the slot.
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			slot_selected.emit(index)

## Handle the slot's button being pressed (button covers the whole slot).
func _on_button_pressed() -> void:
	set_selected(true)
	slot_selected.emit(index)
