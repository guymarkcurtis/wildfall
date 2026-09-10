## Manages a collection of items with stack support.
## All item operations go through this component — no direct dictionary access.
class_name InventoryComponent
extends RefCounted

signal inventory_changed
signal item_added(item_id: String, quantity: int)
signal item_removed(item_id: String, quantity: int)
signal inventory_full

var _slots: Dictionary = {}  # item_id -> Dictionary {quantity, max_stack}
var _max_weight: float = 100.0
var _max_slots: int = 50

## Total weight of all items.
var total_weight: float = 0.0

## Get the number of distinct item types.
var slot_count: int:
	get:
		return _slots.size()

## Check if inventory is full.
var is_full: bool:
	get:
		return _slots.size() >= _max_slots

## Set maximum weight capacity.
func set_max_weight(weight: float) -> void:
	_max_weight = max(weight, 0.0)

## Set maximum slot count.
func set_max_slots(count: int) -> void:
	_max_slots = max(count, 1)

## Add items to inventory. Returns actual quantity added.
func add_item(item_id: String, quantity: int) -> int:
	if quantity <= 0:
		return 0

	var existing: int = _slots.get(item_id, {}).get("quantity", 0)
	var max_stack: int = _get_max_stack(item_id)

	# Try to stack into existing
	var space_in_existing: int = max(0, max_stack - existing)
	var to_add: int = min(quantity, space_in_existing)
	if to_add > 0:
		_slots[item_id]["quantity"] = existing + to_add
		quantity -= to_add

	# Try to create new stack if there's room
	if quantity > 0 and _slots.size() < _max_slots:
		var new_qty: int = min(quantity, max_stack)
		_slots[item_id] = {"quantity": new_qty, "max_stack": max_stack}
		quantity -= new_qty

	# Check weight
	_calculate_weight()
	if total_weight > _max_weight:
		# Revert: remove what we just added
		_remove_item(item_id, _slots.get(item_id, {}).get("quantity", 0))
		_inventory_full.emit()
		return 0

	if quantity > 0:
		_inventory_full.emit()

	inventory_changed.emit()
	return quantity  # returned = amount that couldn't be added

## Remove items from inventory. Returns actual quantity removed.
func remove_item(item_id: String, quantity: int) -> int:
	if quantity <= 0:
		return 0

	var current: int = _slots.get(item_id, {}).get("quantity", 0)
	var to_remove: int = min(quantity, current)
	if to_remove == 0:
		return 0

	_slots[item_id]["quantity"] -= to_remove
	if _slots[item_id]["quantity"] <= 0:
		_slots.erase(item_id)

	_calculate_weight()
	inventory_changed.emit()
	item_removed.emit(item_id, to_remove)
	return to_remove

## Get quantity of a specific item.
func get_item_quantity(item_id: String) -> int:
	return _slots.get(item_id, {}).get("quantity", 0)

## Check if inventory contains at least `quantity` of an item.
func has_item(item_id: String, quantity: int = 1) -> bool:
	return _slots.get(item_id, {}).get("quantity", 0) >= quantity

## Get all items as a dictionary {item_id: quantity}.
func get_all_items() -> Dictionary:
	var result: Dictionary = {}
	for item_id in _slots:
		result[item_id] = _slots[item_id]["quantity"]
	return result

## Clear all items.
func clear() -> void:
	_slots.clear()
	total_weight = 0.0
	inventory_changed.emit()

## Get item slots with metadata.
func get_slots() -> Dictionary:
	return _slots.duplicate()

## Transfer items to another inventory.
func transfer_to(target: "InventoryComponent", item_id: String, quantity: int) -> int:
	var available: int = get_item_quantity(item_id)
	var to_transfer: int = min(quantity, available)
	if to_transfer <= 0:
		return 0
	remove_item(item_id, to_transfer)
	target.add_item(item_id, to_transfer)
	return to_transfer

## Split a stack: move `quantity` from source to target.
func split_to(source_item_id: String, target: "InventoryComponent", target_item_id: String, quantity: int) -> int:
	var available: int = get_item_quantity(source_item_id)
	var to_split: int = min(quantity, available)
	if to_split <= 0:
		return 0
	remove_item(source_item_id, to_split)
	target.add_item(target_item_id, to_split)
	return to_split

## Get total weight of inventory.
func get_total_weight() -> float:
	return total_weight

## Serialize inventory to a saveable dictionary.
func serialize() -> Dictionary:
	return {
		"slots": _slots.duplicate(),
		"max_weight": _max_weight,
		"max_slots": _max_slots
	}

## Deserialize inventory from a saved dictionary.
func deserialize(data: Dictionary) -> void:
	_slots = data.get("slots", {})
	_max_weight = data.get("max_weight", 100.0)
	_max_slots = data.get("max_slots", 50)
	_calculate_weight()
	inventory_changed.emit()

## Internal: calculate total weight.
func _calculate_weight() -> void:
	total_weight = 0.0
	for item_id in _slots:
		var qty: int = _slots[item_id]["quantity"]
		# Weight would come from ItemDefinition in a full implementation
		total_weight += qty * 1.0  # placeholder weight

## Internal: get max stack size for an item.
func _get_max_stack(item_id: String) -> int:
	# In a full implementation, this would look up ItemDefinition
	return 64
