## UI component for displaying combat information.
class_name CombatUI
extends Control

@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthLabel
@onready var damage_label: Label = $DamageLabel
@onready var entity_name_label: Label = $EntityNameLabel

var target_entity: String = ""
var current_health: int = 0
var max_health: int = 0

func _ready() -> void:
	visible = false

## Update combat UI.
func update(entity_id: String, health: int, max_health: int, name: String = "") -> void:
	target_entity = entity_id
	current_health = health
	self.max_health = max_health
	
	health_bar.value = float(health) / float(max_health) * 100.0
	health_label.text = "%d/%d" % [health, max_health]
	
	if name != "":
		entity_name_label.text = name
	else:
		entity_name_label.text = entity_id.capitalize()
	
	visible = true

## Show damage number.
func show_damage(damage: int, is_critical: bool = false) -> void:
	damage_label.text = str(damage)
	damage_label.modulate = Color(1.0, 0.3, 0.3) if not is_critical else Color(1.0, 0.8, 0.3)
	damage_label.visible = true
	
	# Hide after delay
	await get_tree().create_timer(0.5).timeout
	damage_label.visible = false

## Hide the UI.
func hide_ui() -> void:
	visible = false

## Show the UI.
func show_ui() -> void:
	visible = true

## Update health bar.
func update_health(current: int, max: int) -> void:
	current_health = current
	max_health = max
	health_bar.value = float(current) / float(max) * 100.0
	health_label.text = "%d/%d" % [current, max]
	
	# Change color based on health
	if current / max < 0.3:
		health_bar.modulate = Color(0.8, 0.3, 0.3)
	elif current / max < 0.6:
		health_bar.modulate = Color(0.8, 0.8, 0.3)
	else:
		health_bar.modulate = Color(0.3, 0.8, 0.3)
