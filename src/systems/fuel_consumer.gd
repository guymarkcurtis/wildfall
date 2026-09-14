## Profile-driven fuel bookkeeping. The caller owns the clock; this pure
## service keeps pause behaviour correct because paused game time supplies no
## delta. It never names a particular fuel item or building.
class_name FuelConsumer
extends RefCounted

static func tick(record: BuildingRecord, delta: float, item_database: ItemDatabase) -> bool:
	if record == null or record.definition == null or record.definition.fuel_profile == null \
			or not bool(record.capability_state.get("enabled", false)) or delta <= 0.0:
		return false
	var profile: FuelProfile = record.definition.fuel_profile
	var remaining := float(record.capability_state.get("fuel_seconds_remaining", 0.0)) - delta
	var storage := record.get_fuel_storage()
	while remaining <= 0.0:
		var slot := _first_accepted_slot(storage, profile, item_database)
		if slot < 0:
			record.capability_state["fuel_seconds_remaining"] = 0.0
			record.capability_state["enabled"] = false
			return true
		storage.remove_from_slot(slot, 1)
		remaining += profile.seconds_per_unit
	record.capability_state["fuel_seconds_remaining"] = remaining
	return true

static func _first_accepted_slot(storage: InventoryStorage, profile: FuelProfile,
		item_database: ItemDatabase) -> int:
	if storage == null or item_database == null:
		return -1
	for index in range(storage.slot_count()):
		var item := item_database.get_item(storage.item_id_at(index))
		if item == null:
			continue
		for tag in profile.accepted_tags:
			if item.has_tag(tag):
				return index
	return -1
