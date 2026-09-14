## The single authoritative transfer routine between InventoryStorage
## instances. Transactional by contract: the source is only reduced after
## the destination has actually accepted the quantity; overflow stays in the
## source; refusals change nothing. Merge, swap, split, filter rejection,
## stack limits, and weight limits all resolve here — UI drag/drop and any
## future transfer path must call this, never mutate slots directly.
class_name InventoryTransfer
extends RefCounted

# Result keys: "moved" (int), "swapped" (bool), "rejected" (String, "" on
# success). `moved` counts units; a swap reports moved = 0, swapped = true.
const RESULT_MOVED := "moved"
const RESULT_SWAPPED := "swapped"
const RESULT_REJECTED := "rejected"

static func transfer(source: InventoryStorage, source_slot: int,
		target: InventoryStorage, target_slot: int, requested_quantity: int) -> Dictionary:
	if source == null or target == null:
		return _result(0, false, "no_storage")
	if requested_quantity <= 0:
		return _result(0, false, "invalid_request")
	if source.item_id_at(source_slot) == "":
		return _result(0, false, "empty_source")
	var item_id := source.item_id_at(source_slot)

	# Same item: merge up to the space the target slot actually has.
	if target.item_id_at(target_slot) == item_id:
		var accepted := target.acceptance_at(target_slot, item_id, requested_quantity)
		if accepted <= 0:
			return _result(0, false, target.rejection_reason_for_slot(target_slot, item_id))
		var merged := _merge_into(source, source_slot, target, target_slot, item_id, accepted)
		if merged < accepted:
			return _result(merged, false, "partial")
		return _result(merged, false, "")

	# Empty target slot: move as much as the slot accepts (split support).
	if target.is_empty_slot(target_slot):
		var accepted := target.acceptance_at(target_slot, item_id, requested_quantity)
		if accepted <= 0:
			return _result(0, false, target.rejection_reason_for_slot(target_slot, item_id))
		var stack := source.stack_at(source_slot)
		var moved := source.remove_from_slot(source_slot, accepted)
		if moved <= 0:
			return _result(0, false, "empty_source")
		stack["quantity"] = moved
		if not target.place_slot(target_slot, stack):
			# Cannot happen (acceptance was pre-computed) — refund anyway.
			source.add_item(item_id, moved)
			return _result(0, false, "refused")
		return _result(moved, false, "")

	# Different item in the target: whole-stack swap, only when both sides
	# can hold the other's stack under filters, stack sizes, and weight.
	var target_item := target.item_id_at(target_slot)
	var target_stack := target.stack_at(target_slot)
	var source_stack := source.stack_at(source_slot)
	if not _swap_fits(source, source_slot, target_stack, target_item) \
			or not _swap_fits(target, target_slot, source_stack, item_id):
		return _result(0, false, "cannot_swap")
	if not _swap_weight_ok(source, source_stack, target_stack) \
			or not _swap_weight_ok(target, target_stack, source_stack):
		return _result(0, false, "cannot_swap")
	var taken_from_target := target.take_slot(target_slot)
	if taken_from_target.is_empty():
		return _result(0, false, "cannot_swap")
	var taken_from_source := source.take_slot(source_slot)
	if not target.place_slot(target_slot, taken_from_source):
		# Restore the exact prior state before giving up.
		target.place_slot(target_slot, taken_from_target)
		source.place_slot(source_slot, taken_from_source)
		return _result(0, false, "cannot_swap")
	source.place_slot(source_slot, taken_from_target)
	return _result(0, true, "")

## Convenience: move `quantity` of an item from the first source slot that
## holds it into the best target slots, across as many slots as needed.
## Returns the same result shape with the total in "moved".
static func transfer_between(source: InventoryStorage, target: InventoryStorage,
		item_id: String, quantity: int) -> Dictionary:
	if source == null or target == null or item_id == "" or quantity <= 0:
		return _result(0, false, "invalid_request")
	var remaining := quantity
	var moved_total := 0
	for source_index in range(source.slot_count()):
		if remaining <= 0:
			break
		if source.item_id_at(source_index) != item_id:
			continue
		for target_index in range(target.slot_count()):
			if remaining <= 0:
				break
			var outcome := transfer(source, source_index, target, target_index, remaining)
			var moved := int(outcome[RESULT_MOVED])
			if moved > 0:
				remaining -= moved
				moved_total += moved
	if moved_total <= 0:
		return _result(0, false, "no_space")
	return _result(moved_total, false, "")

static func _merge_into(source: InventoryStorage, source_slot: int, target: InventoryStorage,
		target_slot: int, item_id: String, quantity: int) -> int:
	var merged := 0
	var remaining := quantity
	while remaining > 0:
		var accepted := target.acceptance_at(target_slot, item_id, remaining)
		if accepted <= 0:
			break
		var removed := source.remove_from_slot(source_slot, accepted)
		if removed <= 0:
			break
		var landed := target.add_to_slot(target_slot, item_id, removed)
		merged += landed
		remaining -= landed
		if landed < removed:
			# Defensive: refund anything the target somehow refused.
			source.add_item(item_id, removed - landed)
			break
	return merged

static func _swap_fits(storage: InventoryStorage, slot_index: int, incoming_stack: Dictionary, incoming_item: String) -> bool:
	# The slot's current occupant is leaving in the swap, so only the
	# incoming stack's own size and the slot filter matter here; weight is
	# checked separately with both outgoing and incoming accounted.
	var incoming_qty := int(incoming_stack.get("quantity", 0))
	if incoming_qty <= 0 or incoming_qty > storage.max_stack_for(incoming_item):
		return false
	return storage.filter_accepts_item(slot_index, incoming_item)

static func _swap_weight_ok(storage: InventoryStorage, outgoing: Dictionary, incoming: Dictionary) -> bool:
	if storage.max_weight <= 0.0:
		return true
	var outgoing_weight := int(outgoing.get("quantity", 0)) * _unit(storage, str(outgoing.get("item_id", "")))
	var incoming_weight := int(incoming.get("quantity", 0)) * _unit(storage, str(incoming.get("item_id", "")))
	var projected := storage.total_weight() - outgoing_weight + incoming_weight
	return projected <= storage.max_weight + 0.001

static func _unit(storage: InventoryStorage, item_id: String) -> float:
	if storage.weight_of_item.is_valid():
		return maxf(float(storage.weight_of_item.call(item_id)), 0.0)
	return 1.0

static func _result(moved: int, swapped: bool, rejected: String) -> Dictionary:
	return {RESULT_MOVED: moved, RESULT_SWAPPED: swapped, RESULT_REJECTED: rejected}
