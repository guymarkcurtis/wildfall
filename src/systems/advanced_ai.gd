## Manages advanced AI behavior for creatures.
class_name AdvancedAI
extends Node

# AI states
enum AIState {
	IDLE,
	PATROL,
	CHASE,
	ATTACK,
	FLEE,
	HUNT,
	SHADOW
}

# Behavior profiles
enum BehaviorProfile {
	PASSIVE,      # Flee from player
	NEUTRAL,      # Ignore player
	HOSTILE,      # Attack on sight
	STALKER,      # Hunt player
	SHADOWY      # Ambush predator
}

# Creature data
var creature_id: String = ""
var behavior: BehaviorProfile = BehaviorProfile.PASSIVE
var current_state: AIState = AIState.IDLE
var target_position: Vector2 = Vector2.ZERO
var patrol_center: Vector2 = Vector2.ZERO
var patrol_radius: float = 50.0
var detection_range: float = 150.0
var attack_range: float = 32.0
var flee_range: float = 100.0
var speed: float = 50.0
var aggression: float = 0.5  # 0.0 to 1.0

# Timing
var state_timer: float = 0.0
var attack_timer: float = 0.0
var patrol_timer: float = 0.0

# Pathfinding
var path: PackedVector2Array = []
var path_index: int = 0

# Signals
signal state_changed(new_state: AIState)
signal target_acquired(target_position: Vector2)
signal attack_started(target_id: String)
signal attack_ended
signal fled

## Initialize the AI.
func initialize(creature_id: String, behavior: BehaviorProfile, speed: float = 50.0) -> void:
	self.creature_id = creature_id
	self.behavior = behavior
	self.speed = speed
	_reset_state()

## Reset to initial state.
func _reset_state() -> void:
	current_state = AIState.IDLE
	state_timer = 0.0
	attack_timer = 0.0
	path = PackedVector2Array()
	path_index = 0
	state_changed.emit(current_state)

## Update AI behavior.
func _physics_process(delta: float) -> void:
	state_timer += delta
	attack_timer += delta
	patrol_timer += delta
	
	match current_state:
		AIState.IDLE:
			_idle_behavior(delta)
		AIState.PATROL:
			_patrol_behavior(delta)
		AIState.CHASE:
			_chase_behavior(delta)
		AIState.ATTACK:
			_attack_behavior(delta)
		AIState.FLEE:
			_flee_behavior(delta)
		AIState.HUNT:
			_hunt_behavior(delta)
		AIState.SHADOW:
			_shadow_behavior(delta)

## Get current state.
func get_current_state() -> AIState:
	return current_state

## Set a new state.
func set_state(new_state: AIState) -> void:
	current_state = new_state
	state_changed.emit(new_state)

## Check if creature should detect player.
func should_detect_player(player_position: Vector2, current_position: Vector2) -> bool:
	var distance := current_position.distance_to(player_position)
	
	match behavior:
		BehaviorProfile.PASSIVE:
			return distance < flee_range
		BehaviorProfile.HOSTILE, BehaviorProfile.STALKER:
			return distance < detection_range
		BehaviorProfile.SHADOWY:
			return distance < detection_range * 0.7
		_:
			return distance < detection_range * 0.5

## Change state based on player position.
func update_state(player_position: Vector2, current_position: Vector2) -> void:
	var distance := current_position.distance_to(player_position)
	
	match behavior:
		BehaviorProfile.PASSIVE:
			if distance < flee_range:
				set_state(AIState.FLEE)
			elif distance < detection_range:
				set_state(AIState.PATROL)
			else:
				set_state(AIState.IDLE)
		
		BehaviorProfile.HOSTILE:
			if distance < attack_range:
				set_state(AIState.ATTACK)
			elif distance < detection_range:
				set_state(AIState.CHASE)
			else:
				set_state(AIState.PATROL)
		
		BehaviorProfile.STALKER:
			if distance < attack_range:
				set_state(AIState.ATTACK)
			elif distance < detection_range:
				set_state(AIState.HUNT)
			else:
				set_state(AIState.PATROL)
		
		BehaviorProfile.SHADOWY:
			if distance < attack_range * 0.5:
				set_state(AIState.ATTACK)
			elif distance < detection_range * 0.5:
				set_state(AIState.CHASE)
			else:
				set_state(AIState.SHADOW)
		
		_:
			if distance < detection_range:
				set_state(AIState.PATROL)
			else:
				set_state(AIState.IDLE)

## Idle behavior.
func _idle_behavior(delta: float) -> void:
	if state_timer > randf_range(2.0, 5.0):
		state_timer = 0.0
		if randf() < 0.3:
			set_state(AIState.PATROL)
			_set_random_patrol_target()

## Patrol behavior.
func _patrol_behavior(delta: float) -> void:
	if global_position.distance_to(patrol_center) > patrol_radius:
		set_state(AIState.IDLE)
		state_timer = 0.0
		return
	
	if patrol_timer > randf_range(3.0, 6.0):
		patrol_timer = 0.0
		_set_random_patrol_target()

## Chase behavior.
func _chase_behavior(delta: float) -> void:
	# Would track player position
	pass

## Attack behavior.
func _attack_behavior(delta: float) -> void:
	if attack_timer >= 1.0:
		attack_timer = 0.0
		attack_started.emit(creature_id)
	else:
		attack_ended.emit()

## Flee behavior.
func _flee_behavior(delta: float) -> void:
	# Would move away from player
	fled.emit()

## Hunt behavior.
func _hunt_behavior(delta: float) -> void:
	# Stalk and wait for opportunity
	pass

## Shadow behavior.
func _shadow_behavior(delta: float) -> void:
	# Ambush predator, stay hidden until close
	pass

## Set random patrol target.
func _set_random_patrol_target() -> void:
	var angle := randf() * TAU
	var distance := randf_range(20.0, patrol_radius)
	patrol_center = Vector2(cos(angle), sin(angle)) * distance

## Get behavior profile.
func get_behavior() -> BehaviorProfile:
	return behavior

## Get speed.
func get_speed() -> float:
	return speed

## Serialize AI data.
func serialize() -> Dictionary:
	return {
		"creature_id": creature_id,
		"behavior": behavior,
		"current_state": current_state,
		"speed": speed,
		"aggression": aggression
	}

## Deserialize AI data.
func deserialize(data: Dictionary) -> void:
	behavior = data.get("behavior", BehaviorProfile.PASSIVE)
	speed = data.get("speed", 50.0)
	aggression = data.get("aggression", 0.5)
