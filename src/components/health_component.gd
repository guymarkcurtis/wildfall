## Manages entity health with damage, healing, and death.
class_name HealthComponent
extends Node

signal health_changed(current: float, max_health: int)
signal damage_taken(amount: float)
signal healed(amount: float)
signal died

@export var max_health: int = 100
@export var current_health: float = 100.0

var _is_dead: bool = false

## Check if entity is dead.
var is_dead: bool:
	get:
		return _is_dead

## Get current health as a ratio (0.0 to 1.0).
var health_ratio: float:
	get:
		return clamp(current_health / max_health, 0.0, 1.0)

## Take damage. Returns actual damage dealt.
func take_damage(amount: float) -> float:
	if _is_dead or amount <= 0:
		return 0.0

	current_health = max(0.0, current_health - amount)
	damage_taken.emit(amount)
	health_changed.emit(int(current_health), max_health)

	if current_health <= 0:
		_is_dead = true
		died.emit()

	return amount

## Heal entity. Returns actual healing applied.
func heal(amount: float) -> float:
	if _is_dead or amount <= 0:
		return 0.0

	var old_health: float = current_health
	current_health = min(float(max_health), current_health + amount)
	var actual_heal: float = current_health - old_health
	healed.emit(actual_heal)
	health_changed.emit(int(current_health), max_health)
	return actual_heal

## Set health to a specific value.
func set_health(value: float) -> void:
	current_health = clamp(value, 0.0, float(max_health))
	health_changed.emit(int(current_health), max_health)
	if current_health <= 0:
		_is_dead = true
		died.emit()

## Reset entity to full health.
func reset() -> void:
	current_health = float(max_health)
	_is_dead = false
	health_changed.emit(max_health, max_health)

## Serialize for saving.
func serialize() -> Dictionary:
	return {
		"max_health": max_health,
		"current_health": current_health,
		"is_dead": _is_dead
	}

## Deserialize for loading.
func deserialize(data: Dictionary) -> void:
	max_health = data.get("max_health", 100)
	current_health = data.get("current_health", float(max_health))
	_is_dead = data.get("is_dead", false)
	health_changed.emit(int(current_health), max_health)
