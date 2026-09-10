## Base class for all missions/quests.
class_name Mission
extends RefCounted

# Mission types
enum MissionType {
	MAIN,       # Main storyline
	SIDE,       # Side quest
	DAILY,      # Daily repeatable
	MAX        # Internal use
}

# Mission states
enum MissionState {
	AVAILABLE,    # Can be accepted
	IN_PROGRESS,  # Currently active
	COMPLETED,    # Finished
	FAILED        # Failed/abandoned
}

# Mission data
var mission_id: String = ""
var title: String = ""
var description: String = ""
var mission_type: MissionType = MissionType.SIDE
var state: MissionState = MissionState.AVAILABLE
var required_xp: int = 0
var required_items: Dictionary = {}
var reward_xp: int = 0
var reward_items: Dictionary = {}
var objective_type: String = ""
var objective_target: int = 0
var objective_progress: int = 0
var prerequisites: Array[String] = []

# Timestamps
var accepted_time: float = 0.0
var completed_time: float = 0.0

# Signals
signal mission_accepted(mission_id: String)
signal mission_started(mission_id: String)
signal mission_completed(mission_id: String)
signal mission_failed(mission_id: String)
signal objective_updated(mission_id: String, progress: int, target: int)

## Initialize the mission.
func initialize(mission_id: String, title: String, description: String, 
				mission_type: MissionType, objective_type: String, 
				objective_target: int, required_xp: int = 0,
				required_items: Dictionary = {}, reward_xp: int = 0,
				reward_items: Dictionary = {}, prerequisites: Array[String] = []) -> void:
	self.mission_id = mission_id
	self.title = title
	self.description = description
	self.mission_type = mission_type
	self.objective_type = objective_type
	self.objective_target = objective_target
	self.required_xp = required_xp
	self.required_items = required_items
	self.reward_xp = reward_xp
	self.reward_items = reward_items
	self.prerequisites = prerequisites
	self.state = MissionState.AVAILABLE
	self.objective_progress = 0

## Update objective progress.
func update_progress(amount: int = 1) -> bool:
	if state != MissionState.IN_PROGRESS:
		return false
	
	objective_progress += amount
	if objective_progress >= objective_target:
		objective_progress = objective_target
	complete_mission()
	return true

## Complete the mission.
func complete_mission() -> void:
	state = MissionState.COMPLETED
	completed_time = Time.get_unix_time_from_system()
	mission_completed.emit(mission_id)

## Mark mission as failed.
func fail_mission() -> void:
	state = MissionState.FAILED
	mission_failed.emit(mission_id)

## Check if mission can be accepted.
func can_accept() -> bool:
	if state != MissionState.AVAILABLE:
		return false
	
	# Check prerequisites
	for prerequisite in prerequisites:
		if not _check_prerequisite(prerequisite):
			return false
	return true

## Check if prerequisites are met.
func _check_prerequisite(prerequisite_id: String) -> bool:
	# Simplified - would check completed missions
	return true

## Check if mission is active.
func is_active() -> bool:
	return state == MissionState.IN_PROGRESS

## Check if mission is completed.
func is_completed() -> bool:
	return state == MissionState.COMPLETED

## Get progress percentage.
func get_progress_percentage() -> float:
	if objective_target == 0:
		return 1.0
	return float(objective_progress) / float(objective_target) * 100.0

## Get objective string.
func get_objective_string() -> String:
	match objective_type:
		"kill":
			return "Kill %d enemies" % objective_target
		"collect":
			return "Collect %d %s" % [objective_target, objective_type]
		"defend":
			return "Defend for %d seconds" % objective_target
		"reach":
			return "Reach location %d" % objective_target
		_:
			return "Complete objective"

## Serialize mission data.
func serialize() -> Dictionary:
	return {
		"mission_id": mission_id,
		"title": title,
		"description": description,
		"mission_type": mission_type,
		"state": state,
		"objective_type": objective_type,
		"objective_target": objective_target,
		"objective_progress": objective_progress,
		"required_xp": required_xp,
		"required_items": required_items,
		"reward_xp": reward_xp,
		"reward_items": reward_items,
		"prerequisites": prerequisites,
		"accepted_time": accepted_time,
		"completed_time": completed_time
	}

## Deserialize mission data.
func deserialize(data: Dictionary) -> void:
	mission_id = data.get("mission_id", "")
	title = data.get("title", "")
	description = data.get("description", "")
	mission_type = data.get("mission_type", 0)
	state = data.get("state", 0)
	objective_type = data.get("objective_type", "")
	objective_target = data.get("objective_target", 0)
	objective_progress = data.get("objective_progress", 0)
	required_xp = data.get("required_xp", 0)
	required_items = data.get("required_items", {})
	reward_xp = data.get("reward_xp", 0)
	reward_items = data.get("reward_items", {})
	prerequisites = data.get("prerequisites", [])
	accepted_time = data.get("accepted_time", 0.0)
	completed_time = data.get("completed_time", 0.0)
