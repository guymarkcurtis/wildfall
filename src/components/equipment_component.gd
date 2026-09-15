## Character equipment: a fixed set of named single-slot surfaces (armour,
## clothing, light source) behind the same InventoryStorage primitive as
## every other container, so transfers, stack/weight rules, and saves stay
## generic. Slot acceptance is a data query over ItemDefinition tags — never
## a named item list — via the `tag_checker` callable the owner binds to the
## ItemDatabase (the project has no autoloads). The light slot drives the
## player's held light; `light_enabled` is the persisted L-toggle state.
class_name EquipmentComponent
extends RefCounted

## Emitted whenever any slot's contents change (equip, unequip, swap).
signal changed
## Emitted when the lit state flips or the equipped light item changes.
signal light_changed

const SLOT_ORDER: Array[String] = ["armor", "clothing", "light"]
## The item tag each slot accepts; the character screen labels mirror it.
const SLOT_TAGS: Dictionary = {
	"armor": "armor",
	"clothing": "clothing",
	"light": "light_source",
}

var light_enabled := false

## Callable(item_id: String, tag: String) -> bool.
var tag_checker: Callable = Callable()

var _slots: Dictionary = {} # slot name -> InventoryStorage (exactly 1 slot)

func _init() -> void:
	for slot_name in SLOT_ORDER:
		var storage := InventoryStorage.new(1, 0.0) # no weight cap: carried on the body
		storage.changed.connect(func(): changed.emit())
		_slots[slot_name] = storage

## Install the per-slot tag filters. Runtime-only (filters never save), so
## the owner re-runs this after deserialize and after binding tag_checker.
func apply_filters() -> void:
	for slot_name in SLOT_ORDER:
		var wanted := str(SLOT_TAGS[slot_name])
		(_slots[slot_name] as InventoryStorage).set_slot_filter(0, func(item_id: String) -> bool:
			if item_id == "":
				return true
			if not tag_checker.is_valid():
				return true
			return bool(tag_checker.call(item_id, wanted)))

func get_slot_storage(slot_name: String) -> InventoryStorage:
	return _slots.get(slot_name)

## Reverse lookup for UI grids that report a storage-backed grid id.
func slot_name_for_storage(storage: InventoryStorage) -> String:
	for slot_name in SLOT_ORDER:
		if _slots[slot_name] == storage:
			return slot_name
	return ""

## The equipped light source's item id, or "" when the slot is empty.
func light_item_id() -> String:
	var storage := get_slot_storage("light")
	return storage.item_id_at(0) if storage != null else ""

## Flip the L-toggle. Refused (and left unchanged) with no light equipped.
## Returns the new enabled state.
func toggle_light() -> bool:
	if light_item_id() == "":
		return false
	light_enabled = not light_enabled
	light_changed.emit()
	return light_enabled

func set_light_enabled(enabled: bool) -> void:
	if light_enabled == enabled:
		return
	light_enabled = enabled
	light_changed.emit()

## JSON-safe: indexed slot payloads per slot name plus the persisted toggle.
func serialize() -> Dictionary:
	var slots_payload: Dictionary = {}
	for slot_name in SLOT_ORDER:
		var storage: InventoryStorage = _slots[slot_name]
		if storage.occupied_count() > 0:
			slots_payload[slot_name] = storage.serialize()
	return {"slots": slots_payload, "light_enabled": light_enabled}

## Tolerant to missing/unknown keys so older saves load unchanged. Callers
## re-apply filters afterwards (filters are runtime-only).
func deserialize(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var slots_payload: Variant = data.get("slots", {})
	if typeof(slots_payload) == TYPE_DICTIONARY:
		for slot_name in SLOT_ORDER:
			var storage: InventoryStorage = _slots[slot_name]
			storage.clear()
			var saved: Variant = (slots_payload as Dictionary).get(slot_name, null)
			if typeof(saved) == TYPE_DICTIONARY:
				storage.deserialize(saved)
	set_light_enabled(bool(data.get("light_enabled", false)))
