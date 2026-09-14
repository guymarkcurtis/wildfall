## Generic fixed-slot item storage: ordered indexed slots, per-slot stack
## limits from ItemDatabase stack sizes, weight capacity, optional per-slot
## filter predicates, JSON-safe serialization, and change signals.
##
## This is the storage primitive behind every container surface: the player
## inventory (InventoryComponent) hosts one with one display slot per item
## type; chests, fuel hoppers, and station inputs/outputs (M5+) host
## independent multi-slot instances of the same class. Mutation methods are
## the ONLY way contents change — callers (and InventoryTransfer) never edit
## slot dictionaries directly — so signals and weight stay consistent.
class_name InventoryStorage
extends RefCounted

signal changed
signal slot_changed(index: int)
signal rejected(item_id: String, reason: String)

## Ordered fixed slots. null = empty, otherwise
## {item_id: String, quantity: int, max_stack: int, durability?: int}.
## Treat as read-only outside this class.
var slots: Array = []

## Total weight capacity; items beyond it are refused (never silently
## discarded). 0 = no capacity.
var max_weight: float = 0.0

## Player-display compatibility: when true, all stacks of one item type keep
## merging into that item's single first slot (the compact display model).
## Containers leave this false so the same item may occupy several slots.
var merge_to_single_slot_per_item: bool = false

## Per-item max stack sizes (pushed from ItemDatabase). Unknown items use
## DEFAULT_STACK_SIZE.
var stack_sizes: Dictionary = {}

## Per-item max durabilities (pushed from ItemDatabase). Newly opened stacks
## of a durable item start at full durability (tools live one per slot).
var max_durations: Dictionary = {}

## Optional per-slot filter: index -> Callable(item_id: String) -> bool.
## A filter returning false refuses the item at that slot entirely.
var slot_filters: Dictionary = {}

## Optional weight hook: Callable(item_id: String) -> float. Default 1.0/unit
## (matching the current player inventory placeholder weights).
var weight_of_item: Callable = Callable()

const DEFAULT_STACK_SIZE: int = 64

func _init(slot_count: int = 0, weight_capacity: float = 0.0) -> void:
	configure(slot_count, weight_capacity)

func configure(slot_count: int, weight_capacity: float) -> void:
	slots.resize(maxi(slot_count, 0))
	slots.fill(null)
	max_weight = maxf(weight_capacity, 0.0)
	changed.emit()

## Accept as much of `quantity` as the slots, stack sizes, filters, and
## weight allow; return what did NOT fit (0 = everything accepted).
## Nothing is partially applied on refusal: acceptance is computed up front.
func add_item(item_id: String, quantity: int) -> int:
	if item_id == "" or quantity <= 0:
		return quantity
	var remaining := quantity
	# 1. Top up existing stacks of this item (in unique mode there is at
	# most one).
	for index in range(slots.size()):
		if remaining <= 0:
			break
		if slots[index] == null:
			continue
		var slot: Dictionary = slots[index]
		if str(slot["item_id"]) == item_id:
			remaining -= _fill_slot(index, item_id, remaining)
	# 2. Open new slots (none in unique mode when the item already has one).
	if remaining > 0:
		var unique_blocked := merge_to_single_slot_per_item and first_index_of(item_id) >= 0
		for index in range(slots.size()):
			if remaining <= 0:
				break
			if unique_blocked or slots[index] != null:
				continue
			if not _filter_accepts(index, item_id):
				continue
			var placed := _open_slot(index, item_id, remaining)
			if placed > 0:
				remaining -= placed
			if merge_to_single_slot_per_item:
				break
		if remaining > 0 and merge_to_single_slot_per_item:
			# The unique slot exists but is full: the display model has no
			# further room for this item type.
			rejected.emit(item_id, "stack_full")
	if remaining != quantity:
		changed.emit()
	return remaining

## Add up to `quantity` into the EXISTING stack at `index` (the merge target
## of a slot-to-slot transfer). Returns the amount placed; 0 when the slot is
## not a stack of `item_id` with room (or the filter refuses the item).
## Never opens new slots.
func add_to_slot(index: int, item_id: String, quantity: int) -> int:
	if quantity <= 0 or not _valid_index(index) or slots[index] == null:
		return 0
	var slot: Dictionary = slots[index]
	if str(slot["item_id"]) != item_id or not _filter_accepts(index, item_id):
		return 0
	var placed := _fill_slot(index, item_id, quantity)
	if placed > 0:
		changed.emit()
	return placed

## Remove up to `quantity` from the slot at `index`; return what was removed.
func remove_from_slot(index: int, quantity: int) -> int:
	var removed := _remove_at(index, quantity)
	if removed > 0:
		changed.emit()
	return removed

## Remove up to `quantity` of an item across all slots (first-slot first).
func remove_item(item_id: String, quantity: int) -> int:
	if item_id == "" or quantity <= 0:
		return 0
	var remaining := quantity
	var removed := 0
	for index in range(slots.size()):
		if remaining <= 0:
			break
		if slots[index] == null:
			continue
		var slot: Dictionary = slots[index]
		if str(slot["item_id"]) == item_id:
			var taken := _remove_at(index, remaining)
			removed += taken
			remaining -= taken
	if removed > 0:
		changed.emit()
	return removed

## Remove the ENTIRE slot contents at `index` (stack moves, not splits).
## Returns {item_id, quantity, durability?} or an empty dictionary.
func take_slot(index: int) -> Dictionary:
	if not _valid_index(index) or slots[index] == null:
		return {}
	var slot: Dictionary = slots[index]
	slots[index] = null
	changed.emit()
	return slot

## Place a full stack into an empty slot (the receive half of a swap).
## Returns false when the slot is occupied or the filter refuses the item.
func place_slot(index: int, stack: Dictionary) -> bool:
	if not _valid_index(index) or slots[index] != null:
		return false
	var item_id := str(stack.get("item_id", ""))
	if item_id == "" or not _filter_accepts(index, item_id):
		return false
	var placed := _open_slot(index, item_id, int(stack.get("quantity", 0)))
	if placed < int(stack.get("quantity", 0)):
		# Stack exceeded its own max or the weight limit: refuse whole.
		_remove_at(index, placed)
		return false
	var durability := int(stack.get("durability", 0))
	if durability > 0:
		slots[index]["durability"] = durability
	changed.emit()
	return true

## Max quantity of `item_id` that could land in `target_slot` right now,
## considering occupancy, item match, filter, stack size, and weight.
## 0 = this slot cannot receive the item (the reason distinguishes via
## rejection_reason_for_slot).
func acceptance_at(target_slot: int, item_id: String, request_hint: int = 1 << 30) -> int:
	if item_id == "" or not _valid_index(target_slot):
		return 0
	if not _filter_accepts(target_slot, item_id):
		return 0
	var stack_room := 0
	if slots[target_slot] == null:
		stack_room = max_stack_for(item_id)
	else:
		var slot: Dictionary = slots[target_slot]
		if str(slot["item_id"]) == item_id:
			stack_room = int(slot["max_stack"]) - int(slot["quantity"])
		else:
			return 0
	if stack_room <= 0:
		return 0
	var weight_room := _weight_room(item_id)
	return maxi(0, mini(mini(request_hint, stack_room), weight_room))

func weight_would_accept(item_id: String, quantity: int) -> bool:
	return quantity <= _weight_room(item_id)

func rejection_reason_for_slot(target_slot: int, item_id: String) -> String:
	if not _valid_index(target_slot):
		return "no_slot"
	if not _filter_accepts(target_slot, item_id):
		return "filtered"
	if slots[target_slot] == null:
		return "full"
	var slot: Dictionary = slots[target_slot]
	if str(slot["item_id"]) != item_id:
		return "occupied"
	return "full"

## Whether this slot's filter would admit `item_id` (public form for the
## transfer routine's swap path, where the slot's occupant is leaving).
func filter_accepts_item(index: int, item_id: String) -> bool:
	return _filter_accepts(index, item_id)

# --- Queries ---

func slot_count() -> int:
	return slots.size()

func occupied_count() -> int:
	var count := 0
	for slot in slots:
		if slot != null:
			count += 1
	return count

func is_empty_slot(index: int) -> bool:
	return _valid_index(index) and slots[index] == null

func item_id_at(index: int) -> String:
	if not _valid_index(index) or slots[index] == null:
		return ""
	return str(slots[index]["item_id"])

func quantity_at(index: int) -> int:
	if not _valid_index(index) or slots[index] == null:
		return 0
	return int(slots[index]["quantity"])

func stack_at(index: int) -> Dictionary:
	if not _valid_index(index) or slots[index] == null:
		return {}
	return (slots[index] as Dictionary).duplicate()

func first_index_of(item_id: String) -> int:
	for index in range(slots.size()):
		if slots[index] == null:
			continue
		var slot: Dictionary = slots[index]
		if str(slot["item_id"]) == item_id:
			return index
	return -1

## First slot that could receive up to `quantity` of `item_id` right now
## (matching stack with room, or a filter-passing empty slot). -1 = none.
func find_receiving_slot_for(item_id: String, quantity: int) -> int:
	for index in range(slots.size()):
		if acceptance_at(index, item_id, quantity) > 0:
			return index
	return -1

func quantity_of(item_id: String) -> int:
	var total := 0
	for slot in slots:
		if slot != null and str(slot["item_id"]) == item_id:
			total += int(slot["quantity"])
	return total

func has_item(item_id: String, quantity: int = 1) -> bool:
	return quantity_of(item_id) >= quantity

func all_items() -> Dictionary:
	var result: Dictionary = {}
	for slot in slots:
		if slot != null:
			var item_id := str(slot["item_id"])
			result[item_id] = int(result.get(item_id, 0)) + int(slot["quantity"])
	return result

func durability_at(index: int) -> int:
	if not _valid_index(index) or slots[index] == null:
		return 0
	return int(slots[index].get("durability", 0))

func total_weight() -> float:
	var weight := 0.0
	for slot in slots:
		if slot != null:
			weight += int(slot["quantity"]) * _unit_weight(str(slot["item_id"]))
	return weight

func max_stack_for(item_id: String) -> int:
	return int(stack_sizes.get(item_id, DEFAULT_STACK_SIZE))

## Write a durable tool's remaining durability on its stack (tools live one
## per slot with stack size 1). No-op on empty slots or non-positive values.
func set_durability_at(index: int, value: int) -> void:
	if not _valid_index(index) or slots[index] == null or value <= 0:
		return
	slots[index]["durability"] = value
	changed.emit()

func clear() -> void:
	slots.fill(null)
	changed.emit()

# --- Serialization (JSON-safe) ---

## Indexed form: {slots: [null | {item_id, quantity, durability?}], max_weight}.
## Compact-keyed save formats are migrated by the owning component, which
## knows the legacy shape.
func serialize() -> Dictionary:
	var out_slots: Array = []
	for slot in slots:
		if slot == null:
			out_slots.append(null)
		else:
			var entry: Dictionary = {
				"item_id": str(slot["item_id"]),
				"quantity": int(slot["quantity"]),
			}
			if slot.has("durability"):
				entry["durability"] = int(slot["durability"])
			out_slots.append(entry)
	return {"slots": out_slots, "max_weight": max_weight}

## Accepts the indexed form only; load_slots() is the migration entry point
## for legacy shapes. Malformed entries are dropped, never invented.
func deserialize(data: Dictionary) -> void:
	var incoming: Variant = data.get("slots", [])
	if typeof(incoming) != TYPE_ARRAY:
		incoming = []
	slots.resize(maxi(incoming.size(), 0))
	for index in range(slots.size()):
		var entry: Variant = incoming[index] if index < incoming.size() else null
		slots[index] = _validated_stack(entry)
	max_weight = maxf(float(data.get("max_weight", max_weight)), 0.0)
	changed.emit()

## Migration entry: takes a prebuilt array of validated slot dictionaries
## (or nulls) in deterministic order — the owner converts legacy shapes.
func load_slots(incoming: Array, weight_capacity: float = -1.0) -> void:
	slots.resize(incoming.size())
	for index in range(incoming.size()):
		slots[index] = _validated_stack(incoming[index])
	if weight_capacity >= 0.0:
		max_weight = weight_capacity
	changed.emit()

func set_slot_filter(index: int, filter: Callable) -> void:
	slot_filters[index] = filter

func clear_slot_filter(index: int) -> void:
	slot_filters.erase(index)

# --- Internals ---

## Fill the existing stack at `index`; returns the amount placed.
func _fill_slot(index: int, item_id: String, quantity: int) -> int:
	var slot: Dictionary = slots[index]
	var room := int(slot["max_stack"]) - int(slot["quantity"])
	var by_weight := _weight_room(item_id)
	var placed := maxi(0, mini(mini(quantity, room), by_weight))
	if placed > 0:
		slot["quantity"] = int(slot["quantity"]) + placed
		slot_changed.emit(index)
	return placed

## Open a fresh stack at an empty `index`; returns the amount placed.
func _open_slot(index: int, item_id: String, quantity: int) -> int:
	var by_weight := _weight_room(item_id)
	var placed := maxi(0, mini(mini(quantity, max_stack_for(item_id)), by_weight))
	if placed <= 0:
		return 0
	var slot: Dictionary = {"item_id": item_id, "quantity": placed, "max_stack": max_stack_for(item_id)}
	var max_dur := int(max_durations.get(item_id, 0))
	if max_dur > 0:
		slot["durability"] = max_dur
	slots[index] = slot
	slot_changed.emit(index)
	return placed

func _remove_at(index: int, quantity: int) -> int:
	if not _valid_index(index) or slots[index] == null or quantity <= 0:
		return 0
	var slot: Dictionary = slots[index]
	var taken := mini(quantity, int(slot["quantity"]))
	if taken <= 0:
		return 0
	slot["quantity"] = int(slot["quantity"]) - taken
	if int(slot["quantity"]) <= 0:
		slots[index] = null
	slot_changed.emit(index)
	return taken

func _filter_accepts(index: int, item_id: String) -> bool:
	if not slot_filters.has(index):
		return true
	var filter: Callable = slot_filters[index]
	return bool(filter.call(item_id))

## How many units of `item_id` still fit under the weight capacity.
func _weight_room(item_id: String) -> int:
	if max_weight <= 0.0:
		return 1 << 30
	var unit := _unit_weight(item_id)
	if unit <= 0.0:
		return 1 << 30
	return int(floor(maxf(0.0, max_weight - total_weight()) / unit))

func _unit_weight(item_id: String) -> float:
	if weight_of_item.is_valid():
		return maxf(float(weight_of_item.call(item_id)), 0.0)
	return 1.0

func _valid_index(index: int) -> bool:
	return index >= 0 and index < slots.size()

## Coerce an incoming serialized entry to a safe stack (or null). Malformed
## payloads lose the bad entry but never crash the load.
func _validated_stack(entry: Variant) -> Variant:
	if entry == null:
		return null
	if typeof(entry) != TYPE_DICTIONARY:
		return null
	var item_id := str(entry.get("item_id", ""))
	var quantity := int(entry.get("quantity", 0))
	if item_id == "" or quantity <= 0:
		return null
	var max_stack := int(entry.get("max_stack", max_stack_for(item_id)))
	if max_stack <= 0:
		max_stack = max_stack_for(item_id)
	var stack: Dictionary = {
		"item_id": item_id,
		"quantity": mini(quantity, max_stack),
		"max_stack": max_stack,
	}
	var durability := int(entry.get("durability", 0))
	if durability > 0:
		stack["durability"] = durability
	return stack
