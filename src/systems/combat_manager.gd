## Manages all combat in the game.
class_name CombatManager
extends Node

# Dictionary of entity_id -> CombatSystem
var combats: Dictionary = {}

# Signals
signal entity_attacked(entity_id: String, target_id: String, damage: int)
signal entity_damaged(entity_id: String, damage: int)
signal entity_died(entity_id: String)
signal combat_started(entity_id: String)
signal combat_ended(entity_id: String)

## Initialize the combat manager.
func initialize() -> void:
	print("CombatManager: Initialized")

## Register an entity for combat.
func register_entity(entity_id: String, entity_type: String, 
					max_health: int, attack_damage: int, defense: int,
					attack_speed: float = 1.0) -> CombatSystem:
	if combats.has(entity_id):
		return combats[entity_id]
	
	var combat := CombatSystem.new()
	combat.initialize(entity_id, entity_type, max_health, attack_damage, defense, attack_speed)
	combats[entity_id] = combat
	return combat

## Get combat system for an entity.
func get_combat(entity_id: String) -> CombatSystem:
	return combats.get(entity_id)

## Attack an entity.
func attack_entity(attacker_id: String, target_id: String, position: Vector2) -> int:
	var attacker := combats.get(attacker_id)
	var target := combats.get(target_id)
	
	if not attacker or not target:
		return 0
	
	# Attack
	var damage := attacker.attack(target_id, position)
	if damage > 0:
		target.take_damage(damage)
		entity_attacked.emit(attacker_id, target_id, damage)
		entity_damaged.emit(target_id, damage)
		
		if target.is_dead():
			entity_died.emit(target_id)
			combat_ended.emit(target_id)
	
	return damage

## Damage an entity directly.
func damage_entity(entity_id: String, amount: int, damage_type: int = 0) -> bool:
	var combat := combats.get(entity_id)
	if not combat:
		return false
	
	var died := combat.take_damage(amount, damage_type)
	if died:
		entity_died.emit(entity_id)
		combat_ended.emit(entity_id)
	return died

## Get all entities.
func get_all_entities() -> Dictionary:
	return combats.duplicate()

## Get entities near a position.
func get_entities_near(position: Vector2, range: float = 100.0) -> Array:
	var nearby := []
	for entity_id in combats:
		# Simplified - would check actual positions
		nearby.append(entity_id)
	return nearby

## Get entity count.
func get_entity_count() -> int:
	return combats.size()

## Remove an entity.
func remove_entity(entity_id: String) -> bool:
	if not combats.has(entity_id):
		return false
	
	combats.erase(entity_id)
	return true

## Clear all entities.
func clear_all() -> void:
	combats.clear()

## Serialize combat data.
func serialize_all() -> Dictionary:
	var data := {}
	for entity_id in combats:
		data[entity_id] = combats[entity_id].serialize()
	return data

## Restore combat data from save.
func deserialize_all(data: Dictionary) -> void:
	for entity_id in data:
		var combat_data := data[entity_id]
		var entity_type := combat_data.get("entity_type", "unknown")
		var max_health := combat_data.get("max_health", 100)
		var attack_damage := combat_data.get("attack_damage", 10)
		var defense := combat_data.get("defense", 0)
		
		var combat := register_entity(entity_id, entity_type, max_health, attack_damage, defense)
		combat.deserialize(combat_data)
