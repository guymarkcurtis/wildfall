## Manages a collection of items with stack support.
## All item operations go through this component — no direct dictionary access.
##
## The player-facing inventory keeps its historical compact display model
## (one slot per item type, 50 types, weight-capped) while its contents now
## live in a fixed indexed-slot [InventoryStorage]. The public API, signal
## order, and save format are unchanged for callers; new container surfaces
## (chests, stations, fuel — M5+) host their own independent InventoryStorage
## and move items exclusively through InventoryTransfer.
class_name InventoryComponent
extends RefCounted

signal inventory_changed
signal item_added(item_id: String, quantity: int)
signal item_removed(item_id: String, quantity: int)
signal inventory_full
signal durability_changed(item_id: String, current: int, max: int)
signal tool_broken(item_id: String)

## Indexed-slot backing store. One display slot per item type (the compact
## model) is expressed as merge_to_single_slot_per_item on the storage.
var _storage: InventoryStorage = InventoryStorage.new(50, 100.0)
var _max_durations: Dictionary = {}  # item_id -> max durability (from ItemDatabase)

func _init() -> void:
	_storage.merge_to_single_slot_per_item = true
	_storage.changed.connect(func(): inventory_changed.emit())

## Total weight of all items.
var total_weight: float:
	get:
		return _storage.total_weight()

## Number of distinct item types currently held.
var slot_count: int:
	get:
		return _storage.occupied_count()

## Check if inventory is full.
var is_full: bool:
	get:
		return _storage.occupied_count() >= _storage.slot_count()

## Apply per-item stack sizes (typically from the ItemDatabase, so the
## inventory honours each item's defined stack size instead of a flat 64).
func set_stack_sizes(sizes: Dictionary) -> void:
	for item_id in sizes:
		_storage.stack_sizes[str(item_id)] = int(sizes[item_id])

## Apply per-item max durabilities (typically from the ItemDatabase).
## Durable items (tools/weapons) are stack-size-1, so each one occupies
## its own slot: the slot's "durability" key is that tool's durability.
## Slots of durable items that predate the key (older saves) are
## backfilled to full durability.
func set_item_durations(durations: Dictionary) -> void:
	for item_id in durations:
		_max_durations[str(item_id)] = int(durations[item_id])
		_storage.max_durations[str(item_id)] = int(durations[item_id])
	for index in range(_storage.slot_count()):
		var item_id := _storage.item_id_at(index)
		if item_id == "":
			continue
		var max_dur := _get_max_durability(item_id)
		if max_dur > 0 and _storage.durability_at(index) <= 0:
			_storage.set_durability_at(index, max_dur)

## Set maximum weight capacity.
func set_max_weight(weight: float) -> void:
	_storage.max_weight = max(weight, 0.0)

## Set maximum slot count (distinct item types).
func set_max_slots(count: int) -> void:
	var target := maxi(count, 1)
	var current := _storage.slots.duplicate()
	current.resize(target)
	_storage.load_slots(current)

## Add items to inventory. Returns the quantity that could NOT be added
## (0 when everything fit; the remainder when the inventory is full, the
## weight limit is exceeded, or the item's stack is full with no free slots).
func add_item(item_id: String, quantity: int) -> int:
	if item_id == "" or quantity <= 0:
		return quantity
	var remainder := _storage.add_item(item_id, quantity)
	var added := quantity - remainder
	if added > 0:
		item_added.emit(item_id, added)
	if remainder > 0:
		inventory_full.emit()
	return remainder

## Damage a tool in the inventory by `amount` durability.
## Tools are one-per-slot (stack size 1), so the slot's "durability" key
## is the tool's own durability. Returns true if this damage broke the
## tool — the slot is removed and tool_broken() fires; the player is
## expected to fall back to bare hands and craft a replacement.
## There is no repair feature yet: a broken tool is simply gone.
func damage_tool(item_id: String, amount: int) -> bool:
	if amount <= 0:
		return false
	var max_dur := _get_max_durability(item_id)
	if max_dur <= 0:
		return false
	var index := _storage.first_index_of(item_id)
	if index < 0:
		return false
	var updated := _storage.durability_at(index) - amount
	if updated <= 0:
		remove_item(item_id, _storage.quantity_at(index))
		tool_broken.emit(item_id)
		return true
	_storage.set_durability_at(index, updated)
	durability_changed.emit(item_id, updated, max_dur)
	return false

## {current, max} durability for a tool the player carries (max = 0 if
## the item is not durable or is not in the inventory).
func get_tool_durability(item_id: String) -> Dictionary:
	var max_dur := _get_max_durability(item_id)
	if max_dur <= 0:
		return {"current": 0, "max": 0}
	var index := _storage.first_index_of(item_id)
	if index < 0:
		return {"current": 0, "max": 0}
	return {"current": _storage.durability_at(index), "max": max_dur}

## Current durability of every durable tool in the inventory
## (item_id -> current). The UI combines this with the ItemDatabase's
## max values for display.
func get_all_durations() -> Dictionary:
	var result: Dictionary = {}
	for index in range(_storage.slot_count()):
		var item_id := _storage.item_id_at(index)
		if item_id == "":
			continue
		var max_dur := _get_max_durability(item_id)
		if max_dur > 0:
			result[item_id] = _storage.durability_at(index)
	return result

## Remove items from inventory. Returns actual quantity removed.
func remove_item(item_id: String, quantity: int) -> int:
	if quantity <= 0:
		return 0
	var removed := _storage.remove_item(item_id, quantity)
	if removed > 0:
		item_removed.emit(item_id, removed)
	return removed

## Get quantity of a specific item.
func get_item_quantity(item_id: String) -> int:
	return _storage.quantity_of(item_id)

## Check if inventory contains at least `quantity` of an item.
func has_item(item_id: String, quantity: int = 1) -> bool:
	return _storage.has_item(item_id, quantity)

## Get all items as a dictionary {item_id: quantity}.
func get_all_items() -> Dictionary:
	return _storage.all_items()

## The indexed-slot backing store — for UI views that render slots directly
## (the shared StorageGridView) and for building the player side of object
## panels. All mutations still belong to this component or InventoryTransfer.
func get_storage() -> InventoryStorage:
	return _storage

## Per-item max stack sizes (for seeding container storages so their slot
## acceptance matches the ItemDatabase).
func get_stack_sizes() -> Dictionary:
	return _storage.stack_sizes.duplicate()

## Per-item max durabilities (so container storages seed full durability on
## newly opened tool stacks moved through panels).
func get_duration_caps() -> Dictionary:
	return _storage.max_durations.duplicate()

## Clear all items.
func clear() -> void:
	_storage.clear()

## Get item slots with metadata (compact projection: one entry per item
## type, exactly the shape the UI and legacy code expect).
func get_slots() -> Dictionary:
	var result: Dictionary = {}
	for index in range(_storage.slot_count()):
		var stack := _storage.stack_at(index)
		if stack.is_empty():
			continue
		var entry: Dictionary = {
			"quantity": int(stack["quantity"]),
			"max_stack": int(stack["max_stack"]),
		}
		if stack.has("durability"):
			entry["durability"] = int(stack["durability"])
		result[str(stack["item_id"])] = entry
	return result

## Transfer items to another inventory. Transactional: only the quantity the
## target actually accepts leaves the source (the remainder is never lost).
func transfer_to(target: InventoryComponent, item_id: String, quantity: int) -> int:
	if target == null:
		return 0
	var outcome := InventoryTransfer.transfer_between(_storage, target._storage, item_id, quantity)
	var moved := int(outcome[InventoryTransfer.RESULT_MOVED])
	if moved > 0:
		item_removed.emit(item_id, moved)
		target.item_added.emit(item_id, moved)
	return moved

## Split a stack: move up to `quantity` from this item to the target,
## optionally under a different item id. Overflow is refunded to the source.
func split_to(source_item_id: String, target: InventoryComponent, target_item_id: String, quantity: int) -> int:
	if target == null or quantity <= 0:
		return 0
	var wanted := mini(quantity, get_item_quantity(source_item_id))
	if wanted <= 0:
		return 0
	var accepted := 0
	var remaining := wanted
	for index in range(target._storage.slot_count()):
		if remaining <= 0:
			break
		var can := target._storage.acceptance_at(index, target_item_id, remaining)
		accepted += can
		remaining -= can
	if accepted <= 0:
		return 0
	remove_item(source_item_id, accepted)
	var leftover := target.add_item(target_item_id, accepted)
	if leftover > 0:
		add_item(source_item_id, leftover)
		accepted -= leftover
	return accepted

## Get total weight of inventory.
func get_total_weight() -> float:
	return total_weight

## Serialize inventory to a saveable dictionary. Format is UNCHANGED from
## the pre-M1 compact shape, so v7 (and older) saves keep loading; the
## indexed form is written by the v8 milestone, not here.
func serialize() -> Dictionary:
	var compact: Dictionary = {}
	for index in range(_storage.slot_count()):
		var stack := _storage.stack_at(index)
		if stack.is_empty():
			continue
		var entry: Dictionary = {
			"quantity": int(stack["quantity"]),
			"max_stack": int(stack["max_stack"]),
		}
		if stack.has("durability"):
			entry["durability"] = int(stack["durability"])
		compact[str(stack["item_id"])] = entry
	return {
		"slots": compact,
		"max_weight": _storage.max_weight,
		"max_slots": _storage.slot_count()
	}

## Deserialize inventory from a saved dictionary. Accepts BOTH the legacy
## compact shape ({slots: {item_id: {...}}}) — migrating it into
## deterministic indexed slots, with full durability backfilled for pre-v5
## durable tools — and the future indexed shape. Explicit coercions guard
## against JSON round-trips delivering ints as floats.
func deserialize(data: Dictionary) -> void:
	var incoming: Variant = data.get("slots", {})
	var max_weight := maxf(float(data.get("max_weight", 100.0)), 0.0)
	if typeof(incoming) == TYPE_ARRAY:
		# Indexed form (v8+): the storage validates each entry itself.
		var indexed: Dictionary = {"slots": incoming, "max_weight": max_weight}
		_storage.deserialize(indexed)
	else:
		# Legacy compact form: sorted item ids make the slot order
		# deterministic, and durable tools start at full durability when the
		# payload predates the durability key.
		if typeof(incoming) != TYPE_DICTIONARY:
			incoming = {}
		var ordered: Array = []
		var item_ids: Array = incoming.keys()
		item_ids.sort()
		for item_id in item_ids:
			var entry: Variant = incoming[item_id]
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var stack: Dictionary = {
				"item_id": str(item_id),
				"quantity": int(entry.get("quantity", 0)),
				"max_stack": int(entry.get("max_stack", _get_max_stack(str(item_id)))),
			}
			var max_dur := _get_max_durability(str(item_id))
			if max_dur > 0:
				stack["durability"] = int(entry.get("durability", max_dur))
			ordered.append(stack)
		_storage.load_slots(ordered, max_weight)
		var max_slots := int(data.get("max_slots", 0))
		if max_slots > _storage.slot_count():
			var resized := _storage.slots.duplicate()
			resized.resize(max_slots)
			_storage.load_slots(resized, max_weight)
	# inventory_changed fires from the storage signal.

## Internal: get max stack size for an item (ItemDatabase size if known,
## otherwise the default of 64).
func _get_max_stack(item_id: String) -> int:
	return _storage.max_stack_for(item_id)

## Internal: max durability of an item (0 = not durable).
func _get_max_durability(item_id: String) -> int:
	return int(_max_durations.get(item_id, 0))
