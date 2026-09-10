## Base class for all status effects (buffs and debuffs).
class_name StatusEffect
extends RefCounted

# Effect types
enum EffectType {
	POSITIVE,    # Buff
	NEGATIVE    # Debuff
}

# Effect categories
enum EffectCategory {
	STAT_MOD,      # Stat modification
	HEAL_OVER_TIME, # Regeneration
	POISON,        # Damage over time
	SPEED,         # Movement speed
	DAMAGE,        # Damage modification
	RESISTANCE     # Damage resistance
}

# Status effect data
var effect_id: String = ""
var effect_name: String = ""
var effect_type: EffectType = EffectType.POSITIVE
var effect_category: EffectCategory = EffectCategory.STAT_MOD
var duration: float = 0.0  # Seconds (0 = infinite)
var stack_count: int = 1
var stack_max: int = 5
var icon: String = ""

# Stat modifiers
var health_bonus: int = 0
var max_health_bonus: int = 0
var speed_bonus: float = 0.0
var damage_bonus: int = 0
var resistance_bonus: int = 0
var heal_rate: int = 0  # HP per second
var poison_rate: int = 0  # HP damage per second

# Timers
var elapsed_time: float = 0.0
var is_expired: bool = false

# Signals
signal effect_applied(effect_id: String, stack_count: int)
signal effect_removed(effect_id: String)
signal effect_expired(effect_id: String)
signal effect_stack_changed(effect_id: String, stack_count: int)

## Initialize the status effect.
func initialize(effect_id: String, effect_name: String, effect_type: EffectType, 
				effect_category: EffectCategory, duration: float, stack_max: int,
				icon: String = "", health_bonus: int = 0, max_health_bonus: int = 0,
				speed_bonus: float = 0.0, damage_bonus: int = 0,
				resistance_bonus: int = 0, heal_rate: int = 0, poison_rate: int = 0) -> void:
	self.effect_id = effect_id
	self.effect_name = effect_name
	self.effect_type = effect_type
	self.effect_category = effect_category
	self.duration = duration
	self.stack_max = stack_max
	self.icon = icon
	self.health_bonus = health_bonus
	self.max_health_bonus = max_health_bonus
	self.speed_bonus = speed_bonus
	self.damage_bonus = damage_bonus
	self.resistance_bonus = resistance_bonus
	self.heal_rate = heal_rate
	self.poison_rate = poison_rate
	self.stack_count = 1
	self.elapsed_time = 0.0
	self.is_expired = false
	effect_applied.emit(effect_id, stack_count)

## Update the status effect.
func update(delta: float) -> void:
	if duration > 0:
		elapsed_time += delta
		if elapsed_time >= duration:
			is_expired = true
			effect_expired.emit(effect_id)

## Check if effect is active.
func is_active() -> bool:
	return not is_expired

## Check if effect is a buff.
func is_buff() -> bool:
	return effect_type == EffectType.POSITIVE

## Check if effect is a debuff.
func is_debuff() -> bool:
	return effect_type == EffectType.NEGATIVE

## Get effect color.
func get_color() -> Color:
	if is_buff():
		return Color(0.3, 0.8, 0.3)
	else:
		return Color(0.8, 0.3, 0.3)

## Get effect icon.
func get_icon() -> String:
	return icon

## Serialize effect data.
func serialize() -> Dictionary:
	return {
		"effect_id": effect_id,
		"effect_name": effect_name,
		"effect_type": effect_type,
		"effect_category": effect_category,
		"duration": duration,
		"stack_count": stack_count,
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

## Deserialize effect data.
func deserialize(data: Dictionary) -> void:
	effect_id = data.get("effect_id", "")
	effect_name = data.get("effect_name", "")
	effect_type = data.get("effect_type", 0)
	effect_category = data.get("effect_category", 0)
	duration = data.get("duration", 0.0)
	stack_count = data.get("stack_count", 1)
	stack_max = data.get("stack_max", 5)
	icon = data.get("icon", "")
	health_bonus = data.get("health_bonus", 0)
	max_health_bonus = data.get("max_health_bonus", 0)
	speed_bonus = data.get("speed_bonus", 0.0)
	damage_bonus = data.get("damage_bonus", 0)
	resistance_bonus = data.get("resistance_bonus", 0)
	heal_rate = data.get("heal_rate", 0)
	poison_rate = data.get("poison_rate", 0)
	elapsed_time = 0.0
	is_expired = false
