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
var _stack_sizes: Dictionary = {}  # item_id -> max stack size (from ItemDatabase)

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

## Apply per-item stack sizes (typically from the ItemDatabase, so the
## inventory honours each item's defined stack size instead of a flat 64).
func set_stack_sizes(sizes: Dictionary) -> void:
	for item_id in sizes:
		_stack_sizes[str(item_id)] = int(sizes[item_id])

## Set maximum weight capacity.
func set_max_weight(weight: float) -> void:
	_max_weight = max(weight, 0.0)

## Set maximum slot count.
func set_max_slots(count: int) -> void:
	_max_slots = max(count, 1)

## Add items to inventory. Returns the quantity that could NOT be added
## (0 when everything fit; the remainder when the inventory is full, the
## weight limit is exceeded, or the item's stack is full with no free slots).
func add_item(item_id: String, quantity: int) -> int:
	if item_id == "" or quantity <= 0:
		return quantity

	var max_stack: int = _get_max_stack(item_id)
	var added: int = 0

	# 1. Stack into the item's existing slot.
	if _slots.has(item_id):
		var existing: int = _slots[item_id]["quantity"]
		var to_add: int = min(quantity, max(0, max_stack - existing))
		if to_add > 0:
			_slots[item_id]["quantity"] = existing + to_add
			added += to_add
			quantity -= to_add

	# 2. No slot yet: open one if there is room. Never overwrite an
	# existing (full) slot — that would silently discard the old stack.
	if quantity > 0 and not _slots.has(item_id) and _slots.size() < _max_slots:
		var new_qty: int = min(quantity, max_stack)
		_slots[item_id] = {"quantity": new_qty, "max_stack": max_stack}
		added += new_qty
		quantity -= new_qty

	# 3. Weight check: roll back exactly what we just added if over capacity.
	if added > 0:
		_calculate_weight()
		if total_weight > _max_weight:
			_remove_item(item_id, added)
			inventory_full.emit()
			return quantity + added

	if quantity > 0:
		# A slot for this item exists but is full: the display model keeps
		# one slot per item, so there is no room for more of it.
		inventory_full.emit()

	if added > 0:
		inventory_changed.emit()
		item_added.emit(item_id, added)
	return quantity

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

## Internal: remove up to `quantity` of an item without emitting signals.
## Used for rollback inside add_item() so a failed add emits nothing.
func _remove_item(item_id: String, quantity: int) -> void:
	if quantity <= 0:
		return
	var current: int = _slots.get(item_id, {}).get("quantity", 0)
	var to_remove: int = min(quantity, current)
	if to_remove <= 0:
		return
	if current - to_remove <= 0:
		_slots.erase(item_id)
	else:
		_slots[item_id]["quantity"] = current - to_remove
	_calculate_weight()

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
func transfer_to(target: InventoryComponent, item_id: String, quantity: int) -> int:
	var available: int = get_item_quantity(item_id)
	var to_transfer: int = min(quantity, available)
	if to_transfer <= 0:
		return 0
	remove_item(item_id, to_transfer)
	target.add_item(item_id, to_transfer)
	return to_transfer

## Split a stack: move `quantity` from source to target.
func split_to(source_item_id: String, target: InventoryComponent, target_item_id: String, quantity: int) -> int:
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
## (Explicit coercions: JSON round-trips can deliver ints as floats.)
func deserialize(data: Dictionary) -> void:
	_slots = data.get("slots", {})
	_max_weight = float(data.get("max_weight", 100.0))
	_max_slots = int(data.get("max_slots", 50))
	_calculate_weight()
	inventory_changed.emit()

## Internal: calculate total weight.
func _calculate_weight() -> void:
	total_weight = 0.0
	for item_id in _slots:
		var qty: int = _slots[item_id]["quantity"]
		# Weight would come from ItemDefinition in a full implementation
		total_weight += qty * 1.0  # placeholder weight

## Internal: get max stack size for an item (ItemDatabase size if known,
## otherwise the default of 64).
func _get_max_stack(item_id: String) -> int:
	return int(_stack_sizes.get(item_id, 64))
