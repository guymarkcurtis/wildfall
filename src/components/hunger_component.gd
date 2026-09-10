## Manages entity hunger and its effects on health.
class_name HungerComponent
extends Node

signal hunger_changed(current: float, max_hunger: float)
signal hunger_zero
signal eating

@export var max_hunger: float = 100.0
@export var current_hunger: float = 100.0

var _starvation_rate: float = 1.0  # health lost per second when starving

## Get current hunger as a ratio (0.0 to 1.0).
var hunger_ratio: float:
	get:
		return clamp(current_hunger / max_hunger, 0.0, 1.0)

## Eat food, restoring hunger.
func eat(amount: float) -> float:
	if amount <= 0:
		return 0.0
	var old_hunger: float = current_hunger
	current_hunger = min(max_hunger, current_hunger + amount)
	var actual_eaten: float = current_hunger - old_hunger
	eating.emit()
	hunger_changed.emit(current_hunger, max_hunger)
	return actual_eaten

## Reduce hunger by amount.
func lose_hunger(amount: float) -> float:
	if amount <= 0:
		return 0.0
	current_hunger = max(0.0, current_hunger - amount)
	hunger_changed.emit(current_hunger, max_hunger)
	if current_hunger <= 0:
		hunger_zero.emit()
	return amount

## Set hunger to a specific value.
func set_hunger(value: float) -> void:
	current_hunger = clamp(value, 0.0, max_hunger)
	hunger_changed.emit(current_hunger, max_hunger)

## Apply starvation damage to a health component.
func apply_starvation(health: "HealthComponent", delta: float) -> void:
	if current_hunger <= 0:
		health.take_damage(_starvation_rate * delta)

## Serialize for saving.
func serialize() -> Dictionary:
	return {
		"max_hunger": max_hunger,
		"current_hunger": current_hunger
	}

## Deserialize for loading.
func deserialize(data: Dictionary) -> void:
	max_hunger = data.get("max_hunger", 100.0)
	current_hunger = data.get("current_hunger", max_hunger)
	hunger_changed.emit(current_hunger, max_hunger)
