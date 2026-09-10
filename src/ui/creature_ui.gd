## UI for displaying creature information.
class_name CreatureUI
extends Control

@onready var creature_name_label: Label = $NameLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthLabel
@onready var type_label: Label = $TypeLabel

var creature: Node = null

func _ready() -> void:
	visible = false

## Update creature display.
func update(creature_node: Node) -> void:
	creature = creature_node
	if not creature:
		visible = false
		return
	
	visible = true
	
	if creature.has_method("get_creature_type"):
		creature_name_label.text = creature.get_creature_type().capitalize()
	if creature.has_method("get_health_ratio"):
		health_bar.value = creature.get_health_ratio() * 100
	if creature.has_method("health") and creature.has_method("max_health"):
		health_label.text = "%d/%d" % [creature.health, creature.max_health]
	if creature.has_method("get_creature_type"):
		var is_hostile := false
		if creature.has_method("is_hostile"):
			is_hostile = creature.is_hostile
		type_label.text = "Hostile" if is_hostile else "Passive"
		type_label.modulate = Color(0.8, 0.3, 0.3) if is_hostile else Color(0.3, 0.8, 0.3)

## Hide the UI.
func hide_ui() -> void:
	visible = false

## Show the UI.
func show_ui() -> void:
	visible = true
