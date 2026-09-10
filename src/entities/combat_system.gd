## Manages combat mechanics for entities.
class_name CombatSystem
extends Node

# Damage types
enum DamageType {
	MELEE,
	RANGED,
	MAGIC,
	FIRE,
	COLD,
	POISON
}

# Combat states
enum CombatState {
	IDLE,
	ATTACKING,
	TAKING_DAMAGE,
	DEAD
}

# Entity data
var entity_id: String = ""
var entity_type: String = ""
var current_health: int = 0
var max_health: int = 0
var attack_damage: int = 0
var defense: int = 0
var attack_speed: float = 1.0
var attack_range: float = 32.0
var attack_cooldown: float = 0.0
var state: CombatState = CombatState.IDLE

# Visual
var _attack_indicator: Sprite2D = null

# Signals
signal health_changed(current: int, max: int)
signal entity_attacked(target_id: String, damage: int)
signal entity_damaged(damage: int)
signal entity_died
signal combat_state_changed(state: CombatState)

## Initialize the combat system.
func initialize(entity_id: String, entity_type: String, max_health: int, 
				attack_damage: int, defense: int, attack_speed: float = 1.0) -> void:
	self.entity_id = entity_id
	self.entity_type = entity_type
	self.max_health = max_health
	self.current_health = max_health
	self.attack_damage = attack_damage
	self.defense = defense
	self.attack_speed = attack_speed
	_setup_visuals()

## Set up visual indicators.
func _setup_visuals() -> void:
	_attack_indicator = Sprite2D.new()
	_attack_indicator.visible = false
	add_child(_attack_indicator)

## Attack a target.
func attack(target_id: String, position: Vector2) -> int:
	if state == CombatState.DEAD:
		return 0
	
	if attack_cooldown > 0:
		return 0
	
	# Calculate damage
	var damage := _calculate_damage()
	
	# Apply to target
	state = CombatState.ATTACKING
	attack_cooldown = 1.0 / attack_speed
	
	entity_attacked.emit(target_id, damage)
	
	# Show attack indicator
	_show_attack_indicator(position)
	
	return damage

## Take damage.
func take_damage(amount: int, damage_type: int = DamageType.MELEE) -> bool:
	if state == CombatState.DEAD:
		return false
	
	# Apply defense
	var actual_damage := max(0, amount - defense)
	current_health = max(0, current_health - actual_damage)
	
	entity_damaged.emit(actual_damage)
	
	if current_health <= 0:
		state = CombatState.DEAD
		entity_died.emit()
		return true
	
	return false

## Calculate damage based on type.
func _calculate_damage() -> int:
	return attack_damage

## Show attack indicator.
func _show_attack_indicator(target_position: Vector2) -> void:
	if not _attack_indicator:
		return
	
	_attack_indicator.visible = true
	_attack_indicator.position = target_position - global_position
	_attack_indicator.modulate = Color(1.0, 0.3, 0.3)
	
	# Hide after delay
	await get_tree().create_timer(0.2).timeout
	_attack_indicator.visible = false

## Update combat system.
func _process(delta: float) -> void:
	if attack_cooldown > 0:
		attack_cooldown -= delta

## Get health ratio.
func get_health_ratio() -> float:
	return float(current_health) / float(max_health)

## Check if entity is dead.
func is_dead() -> bool:
	return state == CombatState.DEAD

## Check if entity can attack.
func can_attack() -> bool:
	return state != CombatState.DEAD and attack_cooldown <= 0

## Get attack cooldown.
func get_attack_cooldown() -> float:
	return attack_cooldown

## Serialize combat data.
func serialize() -> Dictionary:
	return {
		"entity_id": entity_id,
		"entity_type": entity_type,
		"current_health": current_health,
		"max_health": max_health,
		"attack_damage": attack_damage,
		"defense": defense,
		"state": state
	}

## Deserialize combat data.
func deserialize(data: Dictionary) -> void:
	current_health = data.get("current_health", max_health)
	state = data.get("state", CombatState.IDLE)
	health_changed.emit(current_health, max_health)
