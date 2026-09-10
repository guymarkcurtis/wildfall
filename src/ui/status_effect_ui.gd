## UI component for displaying active status effects.
class_name StatusEffectUI
extends Control

@onready var effect_list: FlowContainer = $EffectList
@onready var empty_label: Label = $EmptyLabel

var status_system: StatusEffectSystem = null

func _ready() -> void:
	visible = true
	empty_label.visible = true

## Update the status effect display.
func update_effects(system: StatusEffectSystem) -> void:
	status_system = system
	_refresh_display()

## Refresh the display.
func _refresh_display() -> void:
	if not status_system:
		return
	
	# Clear existing icons
	for child in effect_list.get_children():
		if child != empty_label:
			child.queue_free()
	
	# Get all active effects
	var effects := status_system.get_all_effects()
	
	if effects.is_empty():
		empty_label.visible = true
		return
	
	empty_label.visible = false
	
	# Create effect icons
	for effect_id in effects:
		var effect := effects[effect_id]
		var icon := _create_effect_icon(effect)
		effect_list.add_child(icon)

## Create an effect icon.
func _create_effect_icon(effect: StatusEffect) -> Control:
	var container := Container.new()
	container.custom_minimum_size = Vector2(32, 32)
	
	# Create background
	var bg := ColorRect.new()
	bg.size = Vector2(32, 32)
	bg.color = effect.get_color()
	container.add_child(bg)
	
	# Create icon label
	var label := Label.new()
	label.text = effect.icon
	label.position = Vector2(8, 8)
	label.modulate = Color(1.0, 1.0, 1.0)
	container.add_child(label)
	
	# Create stack counter
	if effect.stack_count > 1:
		var stack_label := Label.new()
		stack_label.text = str(effect.stack_count)
		stack_label.position = Vector2(20, 20)
		stack_label.modulate = Color(1.0, 1.0, 1.0)
		container.add_child(stack_label)
	
	return container

## Hide the UI.
func hide_ui() -> void:
	visible = false

## Show the UI.
func show_ui() -> void:
	visible = true
