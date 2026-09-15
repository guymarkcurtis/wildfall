## Crafting service for a data-authored StationProfile. Ingredients live
## visibly in the record's input storage and results land in its output
## storage; there is no invisible player-inventory consumption.
##
## `craft` stays the transactional instant path (also the completion step for
## zero-time recipes). `start_craft` + `tick` add timed crafting: the job is
## a small persisted payload in capability_state (`craft_job`), so a craft
## survives save/load, a closed panel, and pauses for free. Like
## FuelConsumer, `tick` is a pure service — the caller owns the clock, so a
## paused game supplies no delta and nothing advances.
class_name StationCrafting
extends RefCounted

const OK := ""
## capability_state key for the active timed job:
## {"recipe_id": String, "remaining": float, "total": float}.
const JOB_STATE_KEY := "craft_job"

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

## Begin a timed craft. Consumes the inputs up front and stores the job on
## the record; the result is written to the output surface by `tick` when the
## recipe's craft_time elapses. Zero-time recipes finish instantly through
## `craft`. Fails without consuming anything when the station is busy,
## unpowered, starved, or the output cannot receive the result.
static func start_craft(record: BuildingRecord, player_storage: InventoryStorage,
		recipe: RecipeDefinition, technology_unlocked: bool = true) -> Dictionary:
	var check := _validate(record, recipe, technology_unlocked)
	if check != OK:
		return {"success": false, "reason": check}
	if not job_of(record).is_empty():
		return {"success": false, "reason": "already_crafting"}
	var inputs := record.get_station_input_storage()
	var outputs := record.get_station_output_storage()
	_inherit_item_rules(inputs, player_storage)
	_inherit_item_rules(outputs, player_storage)
	for item_id in recipe.required_items:
		if inputs.quantity_of(str(item_id)) < int(recipe.required_items[item_id]):
			return {"success": false, "reason": "missing_inputs"}
	if not _can_receive(outputs, recipe.result_item_id, recipe.result_quantity):
		return {"success": false, "reason": "output_full"}
	if float(recipe.craft_time) <= 0.0:
		return craft(record, player_storage, recipe, technology_unlocked)
	for item_id in recipe.required_items:
		inputs.remove_item(str(item_id), int(recipe.required_items[item_id]))
	record.capability_state[JOB_STATE_KEY] = {
		"recipe_id": recipe.recipe_id,
		"remaining": float(recipe.craft_time),
		"total": float(recipe.craft_time),
	}
	return {"success": true, "reason": OK}

## Transactional instant crafting (the completion path for timed jobs with
## zero remaining time, and the whole flow for craft_time <= 0 recipes).
static func craft(record: BuildingRecord, player_storage: InventoryStorage,
		recipe: RecipeDefinition, technology_unlocked: bool = true) -> Dictionary:
	var check := _validate(record, recipe, technology_unlocked)
	if check != OK:
		return {"success": false, "reason": check}
	var inputs := record.get_station_input_storage()
	var outputs := record.get_station_output_storage()
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

## Advance the record's active craft job by `delta` seconds. Power loss
## pauses the job (no progress, nothing consumed); a full output holds the
## finished job at zero remaining until a slot frees up. A job whose recipe
## or station vanished from the data is dropped safely.
static func tick(record: BuildingRecord, delta: float, item_database: ItemDatabase) -> void:
	if record == null or delta <= 0.0:
		return
	var job := job_of(record)
	if job.is_empty():
		return
	var recipe: RecipeDefinition = item_database.get_recipe(str(job.get("recipe_id", ""))) \
			if item_database != null else null
	var profile: StationProfile = record.definition.station_profile \
			if record.definition != null else null
	if recipe == null or profile == null or recipe.crafting_station != profile.recipe_group:
		record.capability_state.erase(JOB_STATE_KEY)
		return
	if profile.requires_power and not bool(record.capability_state.get("enabled", false)):
		return # unpowered: the job pauses, resuming when power returns
	var remaining := float(job.get("remaining", 0.0)) - delta
	if remaining > 0.0:
		job["remaining"] = remaining
		return
	var outputs := record.get_station_output_storage()
	if outputs == null:
		record.capability_state.erase(JOB_STATE_KEY)
		return
	# Completing while the panel is closed must still produce valid stacks
	# (stack sizes and tool durability) — inherit straight from the database.
	_inherit_database_rules(outputs, item_database)
	if outputs.add_item(recipe.result_item_id, recipe.result_quantity) != 0:
		job["remaining"] = 0.0 # hold until the output surface frees up
		return
	record.capability_state.erase(JOB_STATE_KEY)

## The record's active timed job ({} when idle), read-only view.
static func job_of(record: BuildingRecord) -> Dictionary:
	if record == null:
		return {}
	var job: Variant = record.capability_state.get(JOB_STATE_KEY, null)
	return job if typeof(job) == TYPE_DICTIONARY else {}

static func _validate(record: BuildingRecord, recipe: RecipeDefinition,
		technology_unlocked: bool) -> String:
	if record == null or recipe == null or record.definition == null \
			or record.definition.station_profile == null:
		return "not_a_station"
	var profile: StationProfile = record.definition.station_profile
	if recipe.crafting_station != profile.recipe_group:
		return "wrong_station"
	if not technology_unlocked:
		return "technology_locked"
	if profile.requires_power and not bool(record.capability_state.get("enabled", false)):
		return "unpowered"
	if record.get_station_input_storage() == null or record.get_station_output_storage() == null:
		return "missing_surface"
	return OK

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

static func _inherit_database_rules(storage: InventoryStorage, item_database: ItemDatabase) -> void:
	if storage == null or item_database == null:
		return
	if storage.stack_sizes.is_empty():
		var stack_sizes: Dictionary = {}
		for item_id in item_database.items:
			stack_sizes[str(item_id)] = int(item_database.items[item_id].stack_size)
		storage.stack_sizes = stack_sizes
	if storage.max_durations.is_empty():
		storage.max_durations = item_database.get_all_durations()

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
