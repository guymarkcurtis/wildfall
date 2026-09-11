## Owns the mission catalog and its runtime state, and keeps mission
## progress in sync with real gameplay.
##
## Mission is a plain data object; this node is the only part of the
## mission system that touches the scene tree. It resolves its peers
## (event bus, player, item database, technology system) in _ready,
## wires live signals into the progress counters, and relays mission
## state changes back out on the GameEventBus for the UI. The catalog
## itself is code-defined in _load_missions(), matching the project
## convention that data lives in code, not .tres files.
##
## On a new world the first main-chain mission is auto-accepted. On a
## loaded game the save's missions module (v5+) overrides that; older
## saves lack the module entirely and simply keep the fresh defaults.
class_name MissionManager
extends Node

var event_bus: Node = null
var item_database_ref: ItemDatabase = null
var player_ref: Player = null
var technology_system_ref: TechnologySystem = null

var _missions: Dictionary = {} # mission_id -> Mission
var _active: Array[String] = []
var _completed: Array[String] = []

func _ready() -> void:
	event_bus = get_node_or_null("../GameEventBus")
	item_database_ref = get_node_or_null("../ItemDatabase")
	player_ref = get_node_or_null("../Player")
	technology_system_ref = get_node_or_null("../TechnologySystem")
	_connect_signals()
	_load_missions()
	# New world: arm the guided chain immediately. apply_missions() runs
	# later from Main's load flow and overrides this when a save exists.
	start_new_world()

func _connect_signals() -> void:
	if player_ref != null and player_ref.inventory != null:
		if not player_ref.inventory.item_added.is_connected(_on_item_added):
			player_ref.inventory.item_added.connect(_on_item_added)
	if event_bus == null:
		return
	if not event_bus.entity_died.is_connected(_on_entity_died):
		event_bus.entity_died.connect(_on_entity_died)
	if not event_bus.building_placed.is_connected(_on_building_placed):
		event_bus.building_placed.connect(_on_building_placed)
	if technology_system_ref != null:
		if not technology_system_ref.technology_unlocked.is_connected(_on_technology_unlocked):
			technology_system_ref.technology_unlocked.connect(_on_technology_unlocked)

## The code-defined mission catalog: a four-step guided main chain
## (collect -> collect + research -> hunt -> build + research) plus three
## optional side objectives.
func _load_missions() -> void:
	_missions.clear()
	_define("main_1", "First Steps",
			"Gather 15 wood by chopping trees. Every settlement starts with a little timber.",
			Mission.MissionKind.MAIN, "collect", "wood", 15, [], {"stone": 10})
	_define("main_2", "Foundations",
			"Mine 20 stone from the rocks. Solid stone is the base of any real building.",
			Mission.MissionKind.MAIN, "collect", "stone", 20, ["main_1"], {"clay": 15}, ["stone_building"])
	_define("main_3", "Hunt & Gather",
			"Hunt down 3 rabbits. Their hides make fine materials and their meat keeps you fed.",
			Mission.MissionKind.MAIN, "kill", "rabbit", 3, ["main_2"], {"hide": 5, "berry": 10})
	_define("main_4", "Light in the Wild",
			"Build a campfire and claim a patch of the wild. Fire is what makes a camp a home.",
			Mission.MissionKind.MAIN, "build", "campfire", 1, ["main_3"], {"coal": 5}, ["metalworking"])
	_define("side_forage", "Fibre Forager",
			"Collect 10 fibre from the tall grass. It weaves into rope and thread.",
			Mission.MissionKind.SIDE, "collect", "fibre", 10)
	_define("side_ore", "Prospector",
			"Dig up 5 copper ore. The first step down the metalworking road.",
			Mission.MissionKind.SIDE, "collect", "copper_ore", 5)
	_define("side_fish", "Angler",
			"Land 3 fish from the water. A dependable source of fresh food.",
			Mission.MissionKind.SIDE, "kill", "fish", 3)
	_sync_lists()

func _define(
	id: String,
	title: String,
	description: String,
	kind: int,
	objective_type: String,
	objective_item: String,
	objective_count: int,
	prerequisite_ids: Array = [],
	reward_items: Dictionary = {},
	reward_technology_ids: Array = []
) -> void:
	var mission := Mission.new()
	mission.initialize(id, title, description, kind, objective_type, objective_item, objective_count,
			prerequisite_ids, reward_items, reward_technology_ids)
	_missions[id] = mission

## Start a fresh world: brand-new mission states, first main mission
## already accepted so the player has a goal immediately.
func start_new_world() -> void:
	_load_missions()
	_sync_lists()
	accept_mission("main_1")

func get_mission(mission_id: String) -> Mission:
	return _missions.get(mission_id)

func get_active_missions() -> Array[Mission]:
	return _collect_by_state(Mission.MissionState.IN_PROGRESS)

func get_available_missions() -> Array[Mission]:
	return _collect_by_state(Mission.MissionState.AVAILABLE)

func get_completed_missions() -> Array[Mission]:
	return _collect_by_state(Mission.MissionState.COMPLETED)

func _collect_by_state(target_state: int) -> Array[Mission]:
	var result: Array[Mission] = []
	for mission_id in _missions:
		var mission: Mission = _missions[mission_id]
		if mission.state == target_state:
			result.append(mission)
	return result

## Accept a mission: it must still be AVAILABLE and every one of its
## prerequisites must be COMPLETED.
func accept_mission(mission_id: String) -> bool:
	var mission: Mission = _missions.get(mission_id)
	if mission == null:
		return false
	for prerequisite_id in mission.prerequisites:
		var prerequisite: Mission = _missions.get(prerequisite_id)
		if prerequisite == null or prerequisite.state != Mission.MissionState.COMPLETED:
			return false
	if not mission.start():
		return false
	_sync_lists()
	if event_bus != null:
		event_bus.mission_accepted.emit(mission_id)
		event_bus.missions_changed.emit()
	return true

## Titles of the prerequisites that still keep this mission locked.
func get_unmet_prerequisites(mission_id: String) -> Array[String]:
	var titles: Array[String] = []
	var mission: Mission = _missions.get(mission_id)
	if mission == null:
		return titles
	for prerequisite_id in mission.prerequisites:
		var prerequisite: Mission = _missions.get(prerequisite_id)
		if prerequisite == null or prerequisite.state != Mission.MissionState.COMPLETED:
			titles.append(prerequisite.title if prerequisite != null else str(prerequisite_id))
	return titles

## ------------------------------------------------------------------
## Live progress: gameplay signals routed into matching missions.
## ------------------------------------------------------------------

func _on_item_added(item_id: String, quantity: int) -> void:
	if quantity <= 0:
		return
	_notify_progress("collect", str(item_id), quantity)

func _on_entity_died(entity_id: String) -> void:
	_notify_progress("kill", str(entity_id), 1)

func _on_building_placed(building_id: String, _coords: Vector2i) -> void:
	_notify_progress("build", str(building_id), 1)

func _on_technology_unlocked(technology_id: String) -> void:
	_notify_progress("research", str(technology_id), 1)

## Route a gameplay event into every active mission whose objective
## matches. Missions that are not IN_PROGRESS never gain progress — the
## state gate lives here, not in the event emitters.
func _notify_progress(objective_type: String, target: String, amount: int) -> void:
	var any_changed: bool = false
	for mission_id in _active:
		var mission: Mission = _missions.get(mission_id)
		if mission == null or mission.state != Mission.MissionState.IN_PROGRESS:
			continue
		if mission.objective_type != objective_type or mission.objective_item != target:
			continue
		if mission.update_progress(amount):
			_complete_mission(mission)
		else:
			any_changed = true
	if any_changed and event_bus != null:
		event_bus.missions_changed.emit()

func _complete_mission(mission: Mission) -> void:
	_sync_lists()
	# Rewards are granted before mission_completed fires so reward items
	# never bleed into a follow-up mission that is already active.
	if player_ref != null and player_ref.inventory != null and not mission.reward_items.is_empty():
		for item_id in mission.reward_items:
			player_ref.inventory.add_item(str(item_id), int(mission.reward_items[item_id]))
	if technology_system_ref != null:
		for technology_id in mission.reward_research:
			technology_system_ref.unlock_free(str(technology_id))
	if event_bus != null:
		event_bus.mission_completed.emit(mission.mission_id)
		event_bus.missions_changed.emit()

## Rebuild the helper lists from the mission states.
func _sync_lists() -> void:
	_active.clear()
	_completed.clear()
	for mission_id in _missions:
		var mission: Mission = _missions[mission_id]
		if mission.state == Mission.MissionState.IN_PROGRESS:
			_active.append(mission_id)
		elif mission.state == Mission.MissionState.COMPLETED:
			_completed.append(mission_id)

## ------------------------------------------------------------------
## Save/load.
## ------------------------------------------------------------------

func serialize() -> Dictionary:
	var data: Dictionary = {}
	for mission_id in _missions:
		var mission: Mission = _missions[mission_id]
		if mission.state != Mission.MissionState.AVAILABLE:
			data[mission_id] = mission.serialize()
	return {"missions": data}

## Restore mission states from a save. Missions missing from the save
## (for example ones added in a newer version) keep their current state.
func apply_missions(save_data: Variant) -> void:
	if typeof(save_data) != TYPE_DICTIONARY:
		return
	var data: Variant = (save_data as Dictionary).get("missions", {})
	if typeof(data) != TYPE_DICTIONARY:
		return
	for mission_id in data:
		var mission: Mission = _missions.get(str(mission_id))
		if mission != null:
			mission.restore(data[mission_id])
	_sync_lists()
	if event_bus != null:
		event_bus.missions_changed.emit()

## ------------------------------------------------------------------
## Display helpers for the mission panel.
## ------------------------------------------------------------------

func get_objective_display(mission_id: String) -> String:
	var mission: Mission = _missions.get(mission_id)
	if mission == null:
		return ""
	return "%d / %d %s" % [mission.progress, mission.objective_count, _target_display(mission.objective_item)]

func get_reward_display(mission_id: String) -> String:
	var mission: Mission = _missions.get(mission_id)
	if mission == null:
		return ""
	var parts: Array[String] = []
	for item_id in mission.reward_items:
		parts.append("%dx %s" % [int(mission.reward_items[item_id]), _target_display(str(item_id))])
	for technology_id in mission.reward_research:
		parts.append("Research: %s" % _target_display(str(technology_id)))
	return ", ".join(parts)

## Item database name when the id is an item, otherwise a capitalized
## id (creature types and technology ids are not items).
func _target_display(item_id: String) -> String:
	if item_database_ref != null and item_database_ref.has_item(item_id):
		return item_database_ref.get_item_display_name(item_id)
	return str(item_id).capitalize().replace("_", " ")
