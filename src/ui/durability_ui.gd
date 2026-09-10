## UI component for displaying tool durability.
class_name DurabilityUI
extends Control

const BAR_HEIGHT: int = 8

@onready var durability_bar: ProgressBar = $DurabilityBar
@onready var durability_label: Label = $DurabilityLabel
@onready var background: ColorRect = $Background
@onready var state_indicator: ColorRect = $StateIndicator

var tool_id: String = ""
var current_durability: int = 0
var max_durability: int = 100

# Signals
signal durability_changed(current: int, max: int)
signal tool_broken

func _ready() -> void:
	_update_visuals()

## Update durability display.
func update(tool_id: String, current: int, max: int) -> void:
	self.tool_id = tool_id
	self.current_durability = current
	self.max_durability = max
	
	durability_bar.value = float(current) / float(max) * 100.0
	durability_label.text = "%d/%d" % [current, max]
	
	_update_visuals()
	durability_changed.emit(current, max)

## Update visual appearance based on state.
func _update_visuals() -> void:
	var ratio: float = float(current_durability) / float(max_durability)
	
	# Update bar color
	if ratio >= 0.8:
		durability_bar.modulate = Color(0.3, 0.8, 0.3)
		state_indicator.color = Color(0.3, 0.8, 0.3)
	elif ratio >= 0.5:
		durability_bar.modulate = Color(0.8, 0.8, 0.3)
		state_indicator.color = Color(0.8, 0.8, 0.3)
	elif ratio >= 0.2:
		durability_bar.modulate = Color(0.9, 0.5, 0.2)
		state_indicator.color = Color(0.9, 0.5, 0.2)
	else:
		durability_bar.modulate = Color(0.8, 0.3, 0.3)
		state_indicator.color = Color(0.8, 0.3, 0.3)
	
	# Update label
	if current_durability <= 0:
		durability_label.text = "BROKEN"
		durability_label.modulate = Color(1.0, 0.3, 0.3)
	elif ratio < 0.2:
		durability_label.text = "WORN"
		durability_label.modulate = Color(1.0, 0.6, 0.3)
	else:
		durability_label.text = "%d/%d" % [current_durability, max_durability]
		durability_label.modulate = Color(1.0, 1.0, 1.0)

## Check if tool is broken.
func is_broken() -> bool:
	return current_durability <= 0

## Get durability percentage.
func get_percentage() -> float:
	return float(current_durability) / float(max_durability) * 100.0
