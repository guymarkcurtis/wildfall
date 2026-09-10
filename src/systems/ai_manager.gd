## Manages AI for all creatures in the world.
class_name AIManager
extends Node

# Dictionary of creature_id -> AdvancedAI
var ai_systems: Dictionary = {}

# Creature definitions with AI profiles
var creature_ai_definitions: Dictionary = {}

# Signals
signal ai_updated(creature_id: String, state: int)
signal ai_state_changed(creature_id: String, new_state: int)

## Initialize the AI manager.
func initialize() -> void:
	_load_ai_definitions()
	print("AIManager: Initialized")

## Load AI definitions.
func _load_ai_definitions() -> void:
	# Passive creatures
	creature_ai_definitions["slime"] = {
		"behavior": AdvancedAI.BehaviorProfile.PASSIVE,
		"speed": 30.0,
		"detection_range": 100.0,
		"flee_range": 80.0
	}
	
	creature_ai_definitions["rat"] = {
		"behavior": AdvancedAI.BehaviorProfile.PASSIVE,
		"speed": 60.0,
		"detection_range": 120.0,
		"flee_range": 100.0
	}
	
	creature_ai_definitions["slime_poison"] = {
		"behavior": AdvancedAI.BehaviorProfile.PASSIVE,
		"speed": 25.0,
		"detection_range": 80.0,
		"flee_range": 60.0
	}
	
	# Hostile creatures
	creature_ai_definitions["wolf"] = {
		"behavior": AdvancedAI.BehaviorProfile.HOSTILE,
		"speed": 70.0,
		"detection_range": 200.0,
		"attack_range": 32.0
	}
	
	creature_ai_definitions["bear"] = {
		"behavior": AdvancedAI.BehaviorProfile.HOSTILE,
		"speed": 40.0,
		"detection_range": 180.0,
		"attack_range": 40.0
	}
	
	creature_ai_definitions["zombie"] = {
		"behavior": AdvancedAI.BehaviorProfile.STALKER,
		"speed": 35.0,
		"detection_range": 150.0,
		"attack_range": 32.0
	}
	
	creature_ai_definitions["skeleton"] = {
		"behavior": AdvancedAI.BehaviorProfile.HOSTILE,
		"speed": 45.0,
		"detection_range": 160.0,
		"attack_range": 36.0
	}
	
	creature_ai_definitions["slime_fire"] = {
		"behavior": AdvancedAI.BehaviorProfile.SHADOWY,
		"speed": 35.0,
		"detection_range": 120.0,
		"attack_range": 28.0
	}

## Register AI for a creature.
func register_ai(creature_id: String, creature_type: String) -> AdvancedAI:
	if ai_systems.has(creature_id):
		return ai_systems[creature_id]
	
	var definition := creature_ai_definitions.get(creature_type, {})
	var behavior := definition.get("behavior", AdvancedAI.BehaviorProfile.PASSIVE)
	var speed := definition.get("speed", 50.0)
	
	var ai := AdvancedAI.new()
	ai.initialize(creature_id, behavior, speed)
	ai_systems[creature_id] = ai
	return ai

## Get AI for a creature.
func get_ai(creature_id: String) -> AdvancedAI:
	return ai_systems.get(creature_id)

## Update all AI.
func update_all_ai(player_position: Vector2) -> void:
	for creature_id in ai_systems:
		var ai := ai_systems[creature_id]
		# Would get creature position from creature node
		var current_position := Vector2.ZERO  # Would get from creature
		ai.update_state(player_position, current_position)
		ai_updated.emit(creature_id, ai.get_current_state())

## Get all AI systems.
func get_all_ai() -> Dictionary:
	return ai_systems.duplicate()

## Get AI count.
func get_ai_count() -> int:
	return ai_systems.size()

## Clear all AI.
func clear_all() -> void:
	ai_systems.clear()

## Serialize AI data.
func serialize_all() -> Dictionary:
	var data := {}
	for creature_id in ai_systems:
		data[creature_id] = ai_systems[creature_id].serialize()
	return data

## Restore AI data from save.
func deserialize_all(data: Dictionary) -> void:
	for creature_id in data:
		var ai_data := data[creature_id]
		var creature_type := ai_data.get("creature_type", "slime")
		var ai := register_ai(creature_id, creature_type)
		ai.deserialize(ai_data)
