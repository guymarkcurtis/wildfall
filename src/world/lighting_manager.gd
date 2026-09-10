## Manages dynamic lighting based on day/night cycle.
class_name LightingManager
extends Node

const AMBIENT_LIGHT_MAX: float = 1.0
const AMBIENT_LIGHT_MIN: float = 0.3

var day_night_cycle: DayNightCycle = null
var current_ambient: float = 1.0

# Signals
signal ambient_changed(level: float)

## Initialize the lighting manager.
func initialize(cycle: DayNightCycle) -> void:
	day_night_cycle = cycle
	current_ambient = cycle.get_ambient_light()
	print("LightingManager: Initialized")

## Update lighting based on current time.
func _process(delta: float) -> void:
	if not day_night_cycle:
		return
	
	var target_ambient := day_night_cycle.get_ambient_light()
	current_ambient = lerp(current_ambient, target_ambient, delta * 2.0)
	_update_lighting()

## Update lighting settings.
func _update_lighting() -> void:
	# Update global canvas light
	var canvas_light := get_node_or_null("/root/Main/CanvasLayer/Light") as CanvasItem
	if canvas_light:
		# Apply tint based on time of day
		if day_night_cycle.is_daytime():
			canvas_light.modulate = Color(1.0, 0.95, 0.8, 1.0 - current_ambient)
		else:
			canvas_light.modulate = Color(0.3, 0.4, 0.6, 1.0 - current_ambient)
	
	# Emit signal
	ambient_changed.emit(current_ambient)

## Get current ambient light level.
func get_ambient_light() -> float:
	return current_ambient

## Get the day/night cycle.
func get_cycle() -> DayNightCycle:
	return day_night_cycle

## Force update lighting.
func force_update() -> void:
	if day_night_cycle:
		current_ambient = day_night_cycle.get_ambient_light()
		_update_lighting()
