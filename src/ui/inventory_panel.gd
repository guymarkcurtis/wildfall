## Inventory panel showing player items.
class_name InventoryPanel
extends Control

const SLOT_SIZE: int = 48
const SLOTS_PER_ROW: int = 9
const MAX_SLOTS: int = 36

@onready var grid_container: GridContainer = $MarginContainer/VBox/Slots
@onready var slot_template: Control = $MarginContainer/VBox/Slots/Slot

var inventory: Dictionary = {}  # {slot_index: {item_id: String, quantity: int}}
var selected_slot: int = -1

# Signals
signal item_clicked(item_id: String, quantity: int, slot_index: int)
signal item_removed(item_id: String, quantity: int, slot_index: int)
signal slot_selected(slot_index: int)

func _ready() -> void:
	_setup_grid()

## Setup the inventory grid.
func _setup_grid() -> void:
	# Hide template
	slot_template.visible = false
	
	# Create slots
	for i in range(MAX_SLOTS):
		var slot := slot_template.duplicate()
		slot.visible = true
		slot.name = "Slot%d" % i
		slot.index = i
		grid_container.add_child(slot)
		# React to this slot being activated (its button/click) by selecting it.
		if slot.has_signal("slot_selected"):
			slot.connect("slot_selected", _on_slot_selected)
	
	_refresh()

## A slot UI requested selection.
func _on_slot_selected(slot_index: int) -> void:
	select_slot(slot_index)

## Refresh the inventory display.
func refresh(inventory_data: Dictionary) -> void:
	inventory = inventory_data
	_refresh()

## Refresh the inventory display.
func _refresh() -> void:
	for i in range(MAX_SLOTS):
		var slot_node: Control = grid_container.get_child(i)
		if slot_node.has_method("update"):
			var item_id: String = inventory.get(i, {}).get("item_id", "")
			var quantity: int = inventory.get(i, {}).get("quantity", 0)
			slot_node.update(item_id, quantity)

## Set slot as selected.
func select_slot(slot_index: int) -> void:
	selected_slot = slot_index
	for i in range(MAX_SLOTS):
		var slot_node: Control = grid_container.get_child(i)
		if slot_node.has_method("set_selected"):
			slot_node.set_selected(i == slot_index)
	slot_selected.emit(slot_index)

## Get item in slot.
func get_slot_item(slot_index: int) -> Dictionary:
	return inventory.get(slot_index, {"item_id": "", "quantity": 0})

## Add item to inventory.
func add_item(item_id: String, quantity: int) -> bool:
	# Try to stack first
	for i in range(MAX_SLOTS):
		var slot_data: Dictionary = inventory.get(i, {})
		if slot_data.get("item_id") == item_id and slot_data.get("quantity", 0) < 64:
			var current_qty: int = slot_data.get("quantity", 0)
			var new_qty: int = current_qty + quantity
			if new_qty > 64:
				new_qty = 64
			inventory[i] = {"item_id": item_id, "quantity": new_qty}
			_refresh()
			return true
	
	# Find empty slot
	for i in range(MAX_SLOTS):
		var slot_data: Dictionary = inventory.get(i, {})
		if slot_data.is_empty():
			inventory[i] = {"item_id": item_id, "quantity": quantity}
			_refresh()
			return true
	
	return false

## Remove item from inventory.
func remove_item(item_id: String, quantity: int) -> bool:
	var remaining: int = quantity
	for i in range(MAX_SLOTS):
		if remaining <= 0:
			break
		var slot_data: Dictionary = inventory.get(i, {})
		if slot_data.get("item_id") == item_id:
			var current_qty: int = slot_data.get("quantity", 0)
			var remove_qty: int = min(current_qty, remaining)
			var new_qty: int = current_qty - remove_qty
			if new_qty <= 0:
				inventory.erase(i)
			else:
				inventory[i] = {"item_id": item_id, "quantity": new_qty}
			remaining -= remove_qty
	_refresh()
	return remaining <= 0

## Clear inventory.
func clear() -> void:
	inventory.clear()
	_refresh()
