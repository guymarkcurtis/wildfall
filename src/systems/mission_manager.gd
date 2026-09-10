## Manages all missions and quest tracking.
class_name MissionManager
extends Node

# Dictionary of mission_id -> Mission
var missions: Dictionary = {}

# Active mission IDs
var active_mission_ids: Array = []

# Completed mission IDs
var completed_mission_ids: Array = []

# Signals
signal mission_accepted(mission_id: String)
signal mission_started(mission_id: String)
signal mission_completed(mission_id: String)
signal mission_failed(mission_id: String)
signal objectives_updated(mission_id: String, progress: int, target: int)
signal missions_changed(mission_count: int)

## Initialize the mission manager.
func initialize() -> void:
	_load_default_missions()
	print("MissionManager: Initialized with %d missions" % missions.size())

## Load default missions.
func _load_default_missions() -> void:
	# Main missions
	_add_mission("main_1", "First Steps", "Gather 5 wood from trees.", 
		Mission.MissionType.MAIN, "collect", 5, 100, 
		{"wood": 0}, 100, {"wooden_axe": 1})
	
	_add_mission("main_2", "Stone Age", "Collect 10 stone.", 
		Mission.MissionType.MAIN, "collect", 10, 200,
		{"stone": 0}, 200, {"stone_pickaxe": 1})
	
	_add_mission("main_3", "Crafting Basics", "Craft a workbench.", 
		Mission.MissionType.MAIN, "craft", 1, 300,
		{}, 300, {"workbench": 1})
	
	# Side missions
	_add_mission("side_1", "Wolf Hunter", "Kill 5 wolves.", 
		Mission.MissionType.SIDE, "kill", 5, 150,
		{}, 150, {"wolf_pelt": 3})
	
	_add_mission("side_2", "Berry Collector", "Collect 20 berries.", 
		Mission.MissionType.SIDE, "collect", 20, 50,
		{}, 50, {"berry": 10})
	
	_add_mission("side_3", "Iron Finder", "Find 10 iron ore.", 
		Mission.MissionType.SIDE, "collect", 10, 250,
		{}, 250, {"iron_ore": 5})
	
	# Daily missions
	_add_mission("daily_1", "Daily Gatherer", "Collect 10 resources.", 
		Mission.MissionType.DAILY, "collect", 10, 30,
		{}, 30, {"随机资源": 5})
	
	_add_mission("daily_2", "Daily Hunter", "Kill 3 animals.", 
		Mission.MissionType.DAILY, "kill", 3, 50,
		{}, 50, {"meat": 2})

## Add a mission.
func _add_mission(mission_id: String, title: String, description: String, 
				  mission_type: int, objective_type: String, objective_target: int,
				  required_xp: int, required_items: Dictionary, 
				  reward_xp: int, reward_items: Dictionary) -> Mission:
	var mission := Mission.new()
	mission.initialize(mission_id, title, description, mission_type, 
						objective_type, objective_target, required_xp,
						required_items, reward_xp, reward_items)
	missions[mission_id] = mission
	missions_changed.emit(missions.size())
	return mission

## Accept a mission.
func accept_mission(mission_id: String) -> bool:
	var mission := missions.get(mission_id)
	if not mission:
		return false
	
	if not mission.can_accept():
		return false
	
	mission.state = Mission.MissionState.AVAILABLE
	mission.mission_accepted.emit(mission_id)
	mission_accepted.emit(mission_id)
	return true

## Start a mission.
func start_mission(mission_id: String) -> bool:
	var mission := missions.get(mission_id)
	if not mission:
		return false
	
	if mission.state != Mission.MissionState.AVAILABLE:
		return false
	
	mission.state = Mission.MissionState.IN_PROGRESS
	mission.accepted_time = Time.get_unix_time_from_system()
	active_mission_ids.append(mission_id)
	mission.mission_started.emit(mission_id)
	mission_started.emit(mission_id)
	return true

## Update mission objective progress.
func update_objective(mission_id: String, progress: int = 1) -> bool:
	var mission := missions.get(mission_id)
	if not mission:
		return false
	
	if mission.state != Mission.MissionState.IN_PROGRESS:
		return false
	
	mission.update_progress(progress)
	objectives_updated.emit(mission_id, mission.objective_progress, mission.objective_target)
	
	if mission.is_completed():
		_complete_mission(mission_id)
	
	return true

## Complete a mission.
func _complete_mission(mission_id: String) -> void:
	var mission := missions.get(mission_id)
	if not mission:
		return
	
	mission.complete_mission()
	if mission_id in active_mission_ids:
		active_mission_ids.erase(mission_id)
	completed_mission_ids.append(mission_id)
	mission.mission_completed.emit(mission_id)
	mission_completed.emit(mission_id)

## Fail a mission.
func fail_mission(mission_id: String) -> bool:
	var mission := missions.get(mission_id)
	if not mission:
		return false
	
	mission.fail_mission()
	if mission_id in active_mission_ids:
		active_mission_ids.erase(mission_id)
	mission.mission_failed.emit(mission_id)
	mission_failed.emit(mission_id)
	return true

## Get a mission.
func get_mission(mission_id: String) -> Mission:
	return missions.get(mission_id)

## Get all missions.
func get_all_missions() -> Dictionary:
	return missions.duplicate()

## Get active missions.
func get_active_missions() -> Array[Mission]:
	var active := []
	for mission_id in active_mission_ids:
		var mission := missions.get(mission_id)
		if mission:
			active.append(mission)
	return active

## Get completed missions.
func get_completed_missions() -> Array[Mission]:
	var completed := []
	for mission_id in completed_mission_ids:
		var mission := missions.get(mission_id)
		if mission:
			completed.append(mission)
	return completed

## Get mission count.
func get_mission_count() -> int:
	return missions.size()

## Get active mission count.
func get_active_count() -> int:
	return active_mission_ids.size()

## Get completed mission count.
func get_completed_count() -> int:
	return completed_mission_ids.size()

## Clear all missions.
func clear_all() -> void:
	missions.clear()
	active_mission_ids.clear()
	completed_mission_ids.clear()
	missions_changed.emit(0)

## Serialize mission data.
func serialize_all() -> Dictionary:
	var data := {}
	for mission_id in missions:
		data[mission_id] = missions[mission_id].serialize()
	return data

## Restore missions from save data.
func deserialize_all(data: Dictionary) -> void:
	clear_all()
	for mission_id in data:
		var mission_data := data[mission_id]
		var mission := Mission.new()
		mission.deserialize(mission_data)
		missions[mission_id] = mission
		if mission.state == Mission.MissionState.IN_PROGRESS:
			active_mission_ids.append(mission_id)
		elif mission.state == Mission.MissionState.COMPLETED:
			completed_mission_ids.append(mission_id)
	missions_changed.emit(missions.size())
