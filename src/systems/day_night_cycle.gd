## Manages the day/night cycle with time-based lighting.
class_name DayNightCycle
extends Node

# Time constants
const HOURS_IN_DAY: float = 24.0
const SECONDS_PER_HOUR: float = 4.0  # Real seconds per game hour (~96s day)
const DAY_START: float = 6.0  # 6 AM
const DAY_END: float = 20.0  # 8 PM

# Time of day
var current_hour: float = 6.0
var current_day: int = 1
var total_hours_passed: float = 0.0

# Light settings
var ambient_light: float = 1.0
var sun_color: Color = Color(1.0, 0.95, 0.8)
var moon_color: Color = Color(0.55, 0.62, 0.95)
var night_overlay: Color = Color(0.1, 0.1, 0.2, 0.6)
var modulate_node: CanvasModulate = null
var _was_daytime: bool = true

# Signals
signal hour_changed(hour: float, day: int)
signal day_started(day: int)
signal night_started
signal sunrise
signal sunset
signal time_changed(hour: float, day: int)

## Initialize the day/night cycle.
func initialize(hours_per_day: float = SECONDS_PER_HOUR) -> void:
	current_hour = DAY_START
	current_day = 1
	_was_daytime = true
	_apply_modulate()
	print("DayNightCycle: Initialized with %.1f seconds per hour" % hours_per_day)

## Get the current time of day.
func get_time_of_day() -> String:
	var hour := int(current_hour)
	var period := "AM" if hour < 12 else "PM"
	var display_hour := hour % 12
	if display_hour == 0:
		display_hour = 12
	return "%d:%02d %s" % [display_hour, int((current_hour - hour) * 60), period]

## Get the current hour as a float.
func get_current_hour() -> float:
	return current_hour

## Get the current day.
func get_current_day() -> int:
	return current_day

## Check if it's daytime.
func is_daytime() -> bool:
	return current_hour >= DAY_START and current_hour < DAY_END

## Check if it's nighttime.
func is_nighttime() -> bool:
	return not is_daytime()

## Check if it's dawn.
func is_dawn() -> bool:
	return current_hour >= 5.0 and current_hour < 7.0

## Check if it's dusk.
func is_dusk() -> bool:
	return current_hour >= 19.0 and current_hour < 21.0

## Get ambient light level (0.0 to 1.0).
func get_ambient_light() -> float:
	if is_daytime():
		if is_dawn() or is_dusk():
			# Interpolate between day and night
			var progress := 0.0
			if is_dawn():
				progress = (current_hour - 5.0) / 2.0
			else:
				progress = 1.0 - (current_hour - 19.0) / 2.0
			return 0.3 + progress * 0.7
		return 1.0
	else:
		if is_dawn() or is_dusk():
			var progress := 0.0
			if is_dawn():
				progress = (current_hour - 5.0) / 2.0
			else:
				progress = 1.0 - (current_hour - 19.0) / 2.0
			return 0.3 + progress * 0.7
		return 0.3

## Get sun/moon color.
func get_celestial_color() -> Color:
	if is_daytime():
		if is_dawn():
			var progress := (current_hour - 5.0) / 2.0
			return sun_color.lerp(Color(1.0, 0.6, 0.3), 1.0 - progress)
		elif is_dusk():
			var progress := 1.0 - (current_hour - 19.0) / 2.0
			return sun_color.lerp(Color(1.0, 0.6, 0.3), progress)
		return sun_color
	else:
		if is_dawn() or is_dusk():
			var progress := 0.0
			if is_dawn():
				progress = (current_hour - 5.0) / 2.0
			else:
				progress = 1.0 - (current_hour - 19.0) / 2.0
			return moon_color.lerp(sun_color, 1.0 - progress)
		return moon_color

## Update the day/night cycle and world lighting.
func _process(delta: float) -> void:
	var previous_hour := current_hour
	var hours_passed := delta / SECONDS_PER_HOUR
	current_hour += hours_passed
	total_hours_passed += hours_passed

	if current_hour >= HOURS_IN_DAY:
		current_hour -= HOURS_IN_DAY
		current_day += 1
		day_started.emit(current_day)

	var now_day := is_daytime()
	if previous_hour < DAY_START and current_hour >= DAY_START:
		sunrise.emit()
	if previous_hour < DAY_END and current_hour >= DAY_END:
		sunset.emit()
		night_started.emit()
	if now_day and not _was_daytime:
		day_started.emit(current_day)
	_was_daytime = now_day

	ambient_light = get_ambient_light()
	time_changed.emit(current_hour, current_day)
	_apply_modulate()

func _apply_modulate() -> void:
	if modulate_node == null or not is_instance_valid(modulate_node):
		return
	var light := get_ambient_light()
	var tint := get_celestial_color()
	modulate_node.color = Color(tint.r * light, tint.g * light, tint.b * light, 1.0)

## Get daylight percentage (0.0 to 1.0).
func get_daylight_percentage() -> float:
	if is_daytime():
		return get_ambient_light()
	return 1.0 - get_ambient_light()

## Force set the time.
func set_time(hour: float, day: int = -1) -> void:
	if day >= 0:
		current_day = day
	current_hour = clamp(hour, 0.0, HOURS_IN_DAY - 0.001)
	time_changed.emit(current_hour, current_day)

## Get the sun position (0 to 1, where 0 is horizon, 1 is zenith).
func get_sun_position() -> float:
	if is_daytime():
		return (current_hour - DAY_START) / (DAY_END - DAY_START)
	return 0.0

## Get the moon position.
func get_moon_position() -> float:
	if is_nighttime():
		var night_progress := (current_hour - DAY_END) / (HOURS_IN_DAY - DAY_END + DAY_START)
		return night_progress
	return 0.0

## Serialize time data.
func serialize() -> Dictionary:
	return {
		"current_hour": current_hour,
		"current_day": current_day,
		"total_hours_passed": total_hours_passed
	}

## Deserialize time data.
func deserialize(data: Dictionary) -> void:
	current_hour = data.get("current_hour", DAY_START)
	current_day = data.get("current_day", 1)
	total_hours_passed = data.get("total_hours_passed", 0.0)
	time_changed.emit(current_hour, current_day)
