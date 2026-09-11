## Manages status effects on entities.
class_name StatusEffectSystem
extends Node

# Dictionary of effect_id -> StatusEffect
var active_effects: Dictionary = {}

# Effect definitions
var effect_definitions: Dictionary = {}

# Signals
signal effect_added(effect_id: String, stack_count: int)
signal effect_removed(effect_id: String)
signal effect_updated(effect_id: String, stack_count: int)
signal effect_expired(effect_id: String)
signal effect_stack_changed(effect_id: String, stack_count: int)
signal effects_changed(effect_count: int)

var target_health: HealthComponent = null
var _tick_accum: float = 0.0

## Initialize the status effect system.
func initialize() -> void:
	_load_effect_definitions()
	print("StatusEffectSystem: Initialized with %d effect definitions" % effect_definitions.size())

func _process(delta: float) -> void:
	if active_effects.is_empty():
		return
	update_effects(delta)
	_tick_accum += delta
	if _tick_accum < 1.0:
		return
	_tick_accum = 0.0
	if target_health == null:
		return
	var mods: Dictionary = get_total_modifiers()
	var heal: int = int(mods.get("heal_rate", 0))
	var poison: int = int(mods.get("poison_rate", 0))
	if heal > 0:
		target_health.heal(float(heal))
	if poison > 0:
		target_health.take_damage(float(poison))

func get_speed_bonus() -> float:
	return float(get_total_modifiers().get("speed_bonus", 0.0))

func get_effect_names() -> PackedStringArray:
	var names := PackedStringArray()
	for effect_id in active_effects:
		var effect: StatusEffect = active_effects[effect_id]
		names.append(effect.effect_name)
	return names

## Load effect definitions.
func _load_effect_definitions() -> void:
	# Positive effects (buffs)
	_add_effect_definition("haste", "Haste", StatusEffect.EffectType.POSITIVE, 
		StatusEffect.EffectCategory.SPEED, 30.0, 3, "haste", 
		0, 0, 2.0, 0, 0, 0, 0)
	
	_add_effect_definition("strength", "Strength", StatusEffect.EffectType.POSITIVE, 
		StatusEffect.EffectCategory.DAMAGE, 60.0, 5, "strength",
		0, 0, 0, 5, 0, 0, 0)
	
	_add_effect_definition("fortitude", "Fortitude", StatusEffect.EffectType.POSITIVE, 
		StatusEffect.EffectCategory.STAT_MOD, 45.0, 3, "fortitude",
		20, 20, 0, 0, 0, 0, 0)
	
	_add_effect_definition("regeneration", "Regeneration", StatusEffect.EffectType.POSITIVE, 
		StatusEffect.EffectCategory.HEAL_OVER_TIME, 20.0, 1, "regen",
		0, 0, 0, 0, 0, 5, 0)
	
	_add_effect_definition("fire_resistance", "Fire Resistance", StatusEffect.EffectType.POSITIVE, 
		StatusEffect.EffectCategory.RESISTANCE, 60.0, 1, "fire_res",
		0, 0, 0, 0, 10, 0, 0)
	
	# Negative effects (debuffs)
	_add_effect_definition("poison", "Poison", StatusEffect.EffectType.NEGATIVE, 
		StatusEffect.EffectCategory.POISON, 15.0, 3, "poison",
		0, 0, 0, 0, 0, 0, 3)
	
	_add_effect_definition("slow", "Slow", StatusEffect.EffectType.NEGATIVE, 
		StatusEffect.EffectCategory.SPEED, 20.0, 2, "slow",
		0, 0, -2.0, 0, 0, 0, 0)
	
	_add_effect_definition("weakness", "Weakness", StatusEffect.EffectType.NEGATIVE, 
		StatusEffect.EffectCategory.DAMAGE, 30.0, 3, "weakness",
		0, 0, 0, -3, 0, 0, 0)
	
	_add_effect_definition("bleed", "Bleed", StatusEffect.EffectType.NEGATIVE, 
		StatusEffect.EffectCategory.POISON, 10.0, 5, "bleed",
		0, 0, 0, 0, 0, 0, 2)
	
	_add_effect_definition("frozen", "Frozen", StatusEffect.EffectType.NEGATIVE, 
		StatusEffect.EffectCategory.SPEED, 5.0, 1, "frozen",
		0, 0, -10.0, 0, 0, 0, 0)

## Add an effect definition.
func _add_effect_definition(effect_id: String, effect_name: String, effect_type: int, 
							effect_category: int, duration: float, stack_max: int,
							icon: String, health_bonus: int, max_health_bonus: int,
							speed_bonus: float, damage_bonus: int,
							resistance_bonus: int, heal_rate: int, poison_rate: int) -> void:
	effect_definitions[effect_id] = {
		"effect_id": effect_id,
		"effect_name": effect_name,
		"effect_type": effect_type,
		"effect_category": effect_category,
		"duration": duration,
		"stack_max": stack_max,
		"icon": icon,
		"health_bonus": health_bonus,
		"max_health_bonus": max_health_bonus,
		"speed_bonus": speed_bonus,
		"damage_bonus": damage_bonus,
		"resistance_bonus": resistance_bonus,
		"heal_rate": heal_rate,
		"poison_rate": poison_rate
	}

## Apply a status effect to an entity.
func apply_effect(effect_id: String) -> StatusEffect:
	if not effect_definitions.has(effect_id):
		return null
	var definition: Dictionary = effect_definitions[effect_id]
	
	var effect := StatusEffect.new()
	effect.initialize(
		str(definition["effect_id"]),
		str(definition["effect_name"]),
		definition["effect_type"] as StatusEffect.EffectType,
		definition["effect_category"] as StatusEffect.EffectCategory,
		float(definition["duration"]),
		int(definition["stack_max"]),
		str(definition["icon"]),
		int(definition["health_bonus"]),
		int(definition["max_health_bonus"]),
		float(definition["speed_bonus"]),
		int(definition["damage_bonus"]),
		int(definition["resistance_bonus"]),
		int(definition["heal_rate"]),
		int(definition["poison_rate"])
	)
	
	# Check if effect already exists
	if active_effects.has(effect_id):
		var existing: StatusEffect = active_effects[effect_id]
		if existing.stack_count < existing.stack_max:
			existing.stack_count += 1
			active_effects[effect_id] = existing
			effect_stack_changed.emit(effect_id, existing.stack_count)
			effect_updated.emit(effect_id, existing.stack_count)
		return existing
	else:
		active_effects[effect_id] = effect
		effect_added.emit(effect_id, 1)
		return effect

## Remove a status effect.
func remove_effect(effect_id: String) -> bool:
	if not active_effects.has(effect_id):
		return false
	
	active_effects[effect_id].effect_removed.emit(effect_id)
	active_effects.erase(effect_id)
	effect_removed.emit(effect_id)
	return true

## Remove all status effects.
func clear_all_effects() -> void:
	for effect_id in active_effects:
		active_effects[effect_id].effect_removed.emit(effect_id)
	active_effects.clear()
	effects_changed.emit(0)

## Update all active effects.
func update_effects(delta: float) -> void:
	var expired: Array = []
	for effect_id in active_effects:
		var effect: StatusEffect = active_effects[effect_id]
		effect.update(delta)
		if effect.is_expired:
			expired.append(effect_id)
	
	for effect_id in expired:
		remove_effect(effect_id)
	
	effects_changed.emit(active_effects.size())

## Get an active effect.
func get_effect(effect_id: String) -> StatusEffect:
	return active_effects.get(effect_id) as StatusEffect

## Get all active effects.
func get_all_effects() -> Dictionary:
	return active_effects.duplicate()

## Check if an effect is active.
func has_effect(effect_id: String) -> bool:
	return active_effects.has(effect_id)

## Get total stat modifiers from all active effects.
func get_total_modifiers() -> Dictionary:
	var modifiers := {
		"health_bonus": 0,
		"max_health_bonus": 0,
		"speed_bonus": 0.0,
		"damage_bonus": 0,
		"resistance_bonus": 0,
		"heal_rate": 0,
		"poison_rate": 0
	}
	
	for effect_id in active_effects:
		var effect: StatusEffect = active_effects[effect_id]
		modifiers["health_bonus"] += effect.health_bonus * effect.stack_count
		modifiers["max_health_bonus"] += effect.max_health_bonus * effect.stack_count
		modifiers["speed_bonus"] += effect.speed_bonus * effect.stack_count
		modifiers["damage_bonus"] += effect.damage_bonus * effect.stack_count
		modifiers["resistance_bonus"] += effect.resistance_bonus * effect.stack_count
		modifiers["heal_rate"] += effect.heal_rate * effect.stack_count
		modifiers["poison_rate"] += effect.poison_rate * effect.stack_count
	
	return modifiers

## Get effect count.
func get_effect_count() -> int:
	return active_effects.size()

## Serialize all effects.
func serialize_all() -> Dictionary:
	var data := {}
	for effect_id in active_effects:
		data[effect_id] = active_effects[effect_id].serialize()
	return data

## Restore effects from save data.
func deserialize_all(data: Dictionary) -> void:
	clear_all_effects()
	for effect_id in data:
		var effect_data: Dictionary = data[effect_id]
		var effect := StatusEffect.new()
		effect.deserialize(effect_data)
		active_effects[effect_id] = effect
		effect_added.emit(effect_id, effect.stack_count)
	effects_changed.emit(active_effects.size())
