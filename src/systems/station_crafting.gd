## Transactional immediate crafting for a data-authored StationProfile.
## Ingredients live visibly in the record's input storage and results land in
## its output storage; there is no invisible player-inventory consumption.
class_name StationCrafting
extends RefCounted

const OK := ""

static func fill_inputs(record: BuildingRecord, player_storage: InventoryStorage,
		recipe: RecipeDefinition) -> Dictionary:
	if record == null or recipe == null or player_storage == null:
		return {"moved": 0, "reason": "invalid"}
	var inputs := record.get_station_input_storage()
	if inputs == null:
		return {"moved": 0, "reason": "no_inputs"}
	_inherit_item_rules(inputs, player_storage)
	var moved := 0
	for item_id in recipe.required_items:
		var required := int(recipe.required_items[item_id])
		var already := inputs.quantity_of(str(item_id))
		if already < required:
			moved += _move_into_storage(player_storage, inputs, str(item_id), required - already)
	return {"moved": moved, "reason": OK}

static func craft(record: BuildingRecord, player_storage: InventoryStorage,
		recipe: RecipeDefinition, technology_unlocked: bool = true) -> Dictionary:
	if record == null or recipe == null or record.definition == null \
			or record.definition.station_profile == null:
		return {"success": false, "reason": "not_a_station"}
	var profile: StationProfile = record.definition.station_profile
	if recipe.crafting_station != profile.recipe_group:
		return {"success": false, "reason": "wrong_station"}
	if not technology_unlocked:
		return {"success": false, "reason": "technology_locked"}
	if profile.requires_power and not bool(record.capability_state.get("enabled", false)):
		return {"success": false, "reason": "unpowered"}
	var inputs := record.get_station_input_storage()
	var outputs := record.get_station_output_storage()
	if inputs == null or outputs == null:
		return {"success": false, "reason": "missing_surface"}
	_inherit_item_rules(inputs, player_storage)
	_inherit_item_rules(outputs, player_storage)
	for item_id in recipe.required_items:
		if inputs.quantity_of(str(item_id)) < int(recipe.required_items[item_id]):
			return {"success": false, "reason": "missing_inputs"}
	if not _can_receive(outputs, recipe.result_item_id, recipe.result_quantity):
		return {"success": false, "reason": "output_full"}
	if outputs.add_item(recipe.result_item_id, recipe.result_quantity) != 0:
		return {"success": false, "reason": "output_full"}
	for item_id in recipe.required_items:
		inputs.remove_item(str(item_id), int(recipe.required_items[item_id]))
	return {"success": true, "reason": OK}

static func _can_receive(storage: InventoryStorage, item_id: String, quantity: int) -> bool:
	var remaining := quantity
	for index in range(storage.slot_count()):
		remaining -= storage.acceptance_at(index, item_id, remaining)
		if remaining <= 0:
			return true
	return false

static func _inherit_item_rules(storage: InventoryStorage, player_storage: InventoryStorage) -> void:
	storage.stack_sizes = player_storage.stack_sizes
	storage.max_durations = player_storage.max_durations

## Ingredient autofill must never use InventoryTransfer.transfer_between:
## that routine intentionally permits UI swaps, whereas autofill may only
## merge into a matching stack or fill an empty input slot.
static func _move_into_storage(source: InventoryStorage, target: InventoryStorage,
		item_id: String, quantity: int) -> int:
	var remaining := quantity
	var moved := 0
	while remaining > 0:
		var source_index := source.first_index_of(item_id)
		var target_index := target.find_receiving_slot_for(item_id, remaining)
		if source_index < 0 or target_index < 0:
			break
		var result := InventoryTransfer.transfer(source, source_index, target, target_index, remaining)
		var landed := int(result.get(InventoryTransfer.RESULT_MOVED, 0))
		if landed <= 0:
			break
		moved += landed
		remaining -= landed
	return moved
