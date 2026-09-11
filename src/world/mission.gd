## A single mission: code-defined objective plus runtime state.
##
## Mission is deliberately a plain RefCounted value object — no signals,
## no scene-tree access. MissionManager owns the collection, feeds live
## gameplay events (item pickups, kills, buildings, research) into the
## progress counters, and relays state changes back through the
## GameEventBus so the UI can react (see docs/MISSION_SYSTEM.md).
class_name Mission
extends RefCounted

## Main-chain missions guide the player step by step; side missions are
## optional detours with no prerequisites.
enum MissionKind { MAIN, SIDE }

enum MissionState { AVAILABLE, IN_PROGRESS, COMPLETED, FAILED }

var mission_id: String = ""
var title: String = ""
var description: String = ""
var kind: int = MissionKind.SIDE
var state: int = MissionState.AVAILABLE
## Which gameplay event feeds progress: "collect" (inventory item id),
## "kill" (creature type id), "build" (building id) or "research"
## (technology id).
var objective_type: String = ""
var objective_item: String = ""
var objective_count: int = 1
var progress: int = 0
## Main-chain ordering: every listed mission must be COMPLETED before
## this one can be accepted.
var prerequisites: Array[String] = []
## item_id -> quantity, granted to the player on completion.
var reward_items: Dictionary = {}
## Technology ids unlocked (for free) on completion.
var reward_research: Array[String] = []

## Fill every field from the code-defined mission table.
func initialize(
	id: String,
	title_in: String,
	description_in: String,
	kind_in: int,
	objective_type_in: String,
	objective_item_in: String,
	objective_count_in: int,
	prerequisite_ids: Array,
	reward_items_in: Dictionary = {},
	reward_technology_ids: Array = []
) -> void:
	mission_id = id
	title = title_in
	description = description_in
	kind = kind_in
	objective_type = objective_type_in
	objective_item = objective_item_in
	objective_count = objective_count_in
	progress = 0
	state = MissionState.AVAILABLE
	prerequisites.clear()
	for entry in prerequisite_ids:
		prerequisites.append(str(entry))
	reward_items.clear()
	for entry in reward_items_in:
		reward_items[str(entry)] = int(reward_items_in[entry])
	reward_research.clear()
	for entry in reward_technology_ids:
		reward_research.append(str(entry))

## AVAILABLE -> IN_PROGRESS. Progress only counts while a mission is
## IN_PROGRESS, so accepting the mission is what "arms" it.
func start() -> bool:
	if state != MissionState.AVAILABLE:
		return false
	state = MissionState.IN_PROGRESS
	return true

## Add progress while the mission is active. Returns true when this
## update reaches the objective (state becomes COMPLETED).
func update_progress(amount: int) -> bool:
	if state != MissionState.IN_PROGRESS or amount <= 0:
		return false
	progress += amount
	if progress >= objective_count:
		progress = objective_count
		state = MissionState.COMPLETED
		return true
	return false

func is_active() -> bool:
	return state == MissionState.IN_PROGRESS

func is_completed() -> bool:
	return state == MissionState.COMPLETED

## Persist just the runtime state; the definition lives in code.
func serialize() -> Dictionary:
	return {"state": state, "progress": progress}

## Restore runtime state from a save. Older saves simply lack an entry,
## which leaves the mission at its fresh default.
func restore(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	state = int(data.get("state", MissionState.AVAILABLE))
	progress = int(data.get("progress", 0))
	if state == MissionState.COMPLETED:
		progress = objective_count
