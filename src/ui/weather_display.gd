## UI component for displaying weather information.
class_name WeatherDisplay
extends Control

@onready var weather_icon: Label = $WeatherIcon
@onready var weather_label: Label = $WeatherLabel
@onready var intensity_bar: ProgressBar = $IntensityBar

var weather_system: WeatherSystem = null

func _ready() -> void:
	visible = true
	_update_display()

## Update the weather display.
func update_weather(system: WeatherSystem) -> void:
	weather_system = system
	_update_display()

## Update display with current weather.
func _update_display() -> void:
	if not weather_system:
		return
	
	var weather_type := weather_system.get_weather_type()
	var intensity := weather_system.get_weather_intensity()
	var description := weather_system.get_weather_description()
	
	# Update icon and label
	match weather_type:
		WeatherSystem.WeatherType.CLEAR:
			weather_icon.text = "☀"
			weather_label.text = "Clear"
			weather_icon.modulate = Color(1.0, 0.9, 0.3)
		WeatherSystem.WeatherType.RAIN:
			weather_icon.text = "🌧"
			weather_label.text = "Rain"
			weather_icon.modulate = Color(0.5, 0.7, 1.0)
		WeatherSystem.WeatherType.STORM:
			weather_icon.text = "⛈"
			weather_label.text = "Storm"
			weather_icon.modulate = Color(0.4, 0.4, 0.6)
		WeatherSystem.WeatherType.SNOW:
			weather_icon.text = "❄"
			weather_label.text = "Snow"
			weather_icon.modulate = Color(0.8, 0.9, 1.0)
		WeatherSystem.WeatherType.FOG:
			weather_icon.text = "☁"
			weather_label.text = "Fog"
			weather_icon.modulate = Color(0.7, 0.7, 0.7)
		WeatherSystem.WeatherType.SANDSTORM:
			weather_icon.text = "🌪"
			weather_label.text = "Sandstorm"
			weather_icon.modulate = Color(0.8, 0.6, 0.4)
		_:
			weather_icon.text = "?"
			weather_label.text = "Unknown"
			weather_icon.modulate = Color(1.0, 1.0, 1.0)
	
	# Update intensity bar
	intensity_bar.value = intensity * 100.0

## Refresh the display.
func refresh() -> void:
	_update_display()

## Hide the display.
func hide_display() -> void:
	visible = false

## Show the display.
func show_display() -> void:
	visible = true
