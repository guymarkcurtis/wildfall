## UI component for displaying time of day.
class_name TimeDisplay
extends Control

@onready var time_label: Label = $TimeLabel
@onready var day_label: Label = $DayLabel
@onready var sun_icon: Sprite2D = $SunIcon
@onready var moon_icon: Sprite2D = $MoonIcon
@onready var cycle_bar: ProgressBar = $CycleBar

var day_night_cycle: DayNightCycle = null

func _ready() -> void:
	visible = true
	_update_display()

## Update the time display.
func update_cycle(cycle: DayNightCycle) -> void:
	day_night_cycle = cycle
	_update_display()

## Update display with current time.
func _update_display() -> void:
	if not day_night_cycle:
		return
	
	var time_str := day_night_cycle.get_time_of_day()
	var day := day_night_cycle.get_current_day()
	
	time_label.text = time_str
	day_label.text = "Day %d" % day
	
	# Update sun/moon icons
	if day_night_cycle.is_daytime():
		sun_icon.visible = true
		moon_icon.visible = false
	else:
		sun_icon.visible = false
		moon_icon.visible = true
	
	# Update cycle bar (0 to 1)
	var cycle_position := day_night_cycle.get_sun_position()
	if day_night_cycle.is_nighttime():
		cycle_position = day_night_cycle.get_moon_position()
	cycle_bar.value = cycle_position * 100.0

## Refresh the display.
func refresh() -> void:
	_update_display()
