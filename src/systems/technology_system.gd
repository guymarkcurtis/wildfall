## Data-driven player research progression. Technologies consume resources,
## unlock recipes and building tiers, and persist with the world save.
class_name TechnologySystem
extends Node

var technologies: Dictionary = {} # id -> TechnologyDefinition
var unlocked: Dictionary = {} # id -> true
var technology_order: PackedStringArray = []
var player: Player = null

signal technology_unlocked(technology_id: String)
signal technology_unlock_failed(technology_id: String, reason: String)

func initialize(player_ref: Player) -> void:
	player = player_ref
	_load_technologies()
	_reset_to_defaults()

func _load_technologies() -> void:
	technologies.clear()
	technology_order = PackedStringArray()
	_define("wood_building", "Wood Construction",
		"A dependable first structural kit: foundations, floors, walls, roofs, and access pieces.",
		[], [], true,
		["wooden_foundation", "wooden_floor", "wooden_wall", "wooden_window", "wooden_door", "wooden_roof", "wooden_stairs", "wooden_ramp", "wooden_pillar"])
	_define("stone_building", "Stone Construction",
		"Shape harvested stone into durable, multi-level stone structures and stone tools.",
		["wood_building"], [{"item_id": "wood", "quantity": 20}, {"item_id": "stone", "quantity": 30}], false,
		["stone_brick", "stone_foundation", "stone_floor", "stone_wall", "stone_window", "stone_door", "stone_roof", "stone_stairs", "stone_ramp", "stone_pillar"])
	_define("metalworking", "Metalworking",
		"Smelt and forge iron, copper, and bronze equipment for the next survival tier.",
		["stone_building"], [{"item_id": "stone", "quantity": 25}, {"item_id": "coal", "quantity": 8}, {"item_id": "iron_ore", "quantity": 12}], false,
		["iron_ingot", "copper_ingot", "bronze_ingot", "iron_axe", "iron_pickaxe", "iron_sword", "anvil"])

func _define(id: String, display_name: String, description: String, prerequisites: Array[String], cost: Array[Dictionary], unlocked_by_default: bool, recipe_ids: Array[String]) -> void:
	var definition := TechnologyDefinition.new()
	definition.id = id
	definition.display_name = display_name
	definition.description = description
	definition.prerequisites = PackedStringArray(prerequisites)
	definition.unlock_cost = cost.duplicate(true)
	definition.unlocked_by_default = unlocked_by_default
	definition.unlocks_recipes = PackedStringArray(recipe_ids)
	technologies[id] = definition
	technology_order.append(id)

func _reset_to_defaults() -> void:
	unlocked.clear()
	for technology_id in technology_order:
		var definition: TechnologyDefinition = get_definition(technology_id)
		if definition != null and definition.unlocked_by_default:
			unlocked[technology_id] = true

func get_definition(technology_id: String) -> TechnologyDefinition:
	return technologies.get(technology_id) as TechnologyDefinition

func is_unlocked(technology_id: String) -> bool:
	return technology_id.is_empty() or unlocked.has(technology_id)

func get_unlocked_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for technology_id in technology_order:
		if unlocked.has(technology_id):
			ids.append(technology_id)
	return ids

func can_unlock(technology_id: String, inventory: InventoryComponent = null) -> bool:
	return get_unlock_failure_reason(technology_id, inventory).is_empty()

func get_unlock_failure_reason(technology_id: String, inventory: InventoryComponent = null) -> String:
	var definition: TechnologyDefinition = get_definition(technology_id)
	if definition == null:
		return "Unknown technology"
	if is_unlocked(technology_id):
		return "Already researched"
	for prerequisite in definition.prerequisites:
		if not is_unlocked(prerequisite):
			var prerequisite_definition: TechnologyDefinition = get_definition(prerequisite)
			return "Requires %s" % (prerequisite_definition.display_name if prerequisite_definition != null else prerequisite)
	var source: InventoryComponent = inventory if inventory != null else (player.inventory if player != null else null)
	if source == null:
		return "No inventory available"
	for entry in definition.unlock_cost:
		var item_id := str(entry.get("item_id", ""))
		var quantity := int(entry.get("quantity", 0))
		if source.get_item_quantity(item_id) < quantity:
			return "Need %d more %s" % [quantity - source.get_item_quantity(item_id), item_id.replace("_", " ")]
	return ""

func try_unlock(technology_id: String, inventory: InventoryComponent = null) -> bool:
	var source: InventoryComponent = inventory if inventory != null else (player.inventory if player != null else null)
	var reason := get_unlock_failure_reason(technology_id, source)
	if not reason.is_empty():
		technology_unlock_failed.emit(technology_id, reason)
		return false
	var definition: TechnologyDefinition = get_definition(technology_id)
	if not GameSession.is_creative():
		for entry in definition.unlock_cost:
			source.remove_item(str(entry.get("item_id", "")), int(entry.get("quantity", 0)))
	unlocked[technology_id] = true
	technology_unlocked.emit(technology_id)
	return true

## Unlock a technology without charging the research cost (used by
## mission rewards). Prerequisites are unlocked for free as well so a
## reward never points at a locked line.
func unlock_free(technology_id: String) -> bool:
	var definition: TechnologyDefinition = get_definition(technology_id)
	if definition == null or is_unlocked(technology_id):
		return is_unlocked(technology_id)
	for prerequisite in definition.prerequisites:
		unlock_free(str(prerequisite))
	unlocked[technology_id] = true
	technology_unlocked.emit(technology_id)
	return true

func serialize() -> Dictionary:
	return {"unlocked": Array(get_unlocked_ids())}

func deserialize(data: Variant) -> void:
	_reset_to_defaults()
	if typeof(data) != TYPE_DICTIONARY:
		return
	for technology_id in data.get("unlocked", []):
		var id := str(technology_id)
		if technologies.has(id):
			unlocked[id] = true
