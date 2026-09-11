## Lightweight weather cycle with a tint overlay (no particle GPU setup).
class_name WeatherSystem
extends Node

enum WeatherType {
	CLEAR,
	RAIN,
	STORM,
	SNOW,
	FOG,
	SANDSTORM
}

var current_weather: WeatherType = WeatherType.CLEAR
var weather_intensity: float = 0.0
var weather_duration: float = 45.0
var next_weather_change: float = 40.0

var world_generator: Node = null
var _overlay: ColorRect = null

signal weather_changed(weather_type: WeatherType, intensity: float)
signal weather_started(weather_type: WeatherType)
signal weather_ended

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.color = Color(1, 1, 1, 0)
	layer.add_child(_overlay)

func initialize() -> void:
	set_weather(WeatherType.CLEAR, 0.0, 40.0)
	next_weather_change = 40.0

func _process(delta: float) -> void:
	weather_duration -= delta
	next_weather_change -= delta
	if next_weather_change <= 0.0:
		_change_random_weather()
		next_weather_change = randf_range(35.0, 90.0)
	_update_overlay()

func set_weather(weather_type: WeatherType, intensity: float = 1.0, duration: float = 40.0) -> void:
	var old := current_weather
	current_weather = weather_type
	weather_intensity = clampf(intensity, 0.0, 1.0)
	weather_duration = duration
	weather_changed.emit(current_weather, weather_intensity)
	if weather_type != old:
		if weather_type == WeatherType.CLEAR:
			weather_ended.emit()
		else:
			weather_started.emit(weather_type)

func get_weather_name() -> String:
	match current_weather:
		WeatherType.RAIN:
			return "Rain"
		WeatherType.STORM:
			return "Storm"
		WeatherType.SNOW:
			return "Snow"
		WeatherType.FOG:
			return "Fog"
		WeatherType.SANDSTORM:
			return "Sandstorm"
		_:
			return "Clear"

func is_wet() -> bool:
	return current_weather == WeatherType.RAIN or current_weather == WeatherType.STORM

func is_cold_weather() -> bool:
	return current_weather == WeatherType.SNOW

func get_speed_multiplier() -> float:
	match current_weather:
		WeatherType.STORM, WeatherType.SANDSTORM:
			return 0.85
		WeatherType.SNOW:
			return 0.9
		_:
			return 1.0

func _change_random_weather() -> void:
	var biome: String = "grassland"
	if world_generator != null and world_generator.has_method("get_biome_at_world"):
		biome = str(world_generator.call("get_biome_at_world", 0, 0))
	var roll := randf()
	var next_type := WeatherType.CLEAR
	match biome:
		"desert":
			next_type = WeatherType.SANDSTORM if roll < 0.35 else WeatherType.CLEAR
		"arctic":
			next_type = WeatherType.SNOW if roll < 0.55 else WeatherType.CLEAR
		"swamp":
			next_type = WeatherType.RAIN if roll < 0.5 else (WeatherType.FOG if roll < 0.75 else WeatherType.CLEAR)
		"temperate_forest":
			next_type = WeatherType.RAIN if roll < 0.4 else (WeatherType.FOG if roll < 0.55 else WeatherType.CLEAR)
		"mountain":
			next_type = WeatherType.SNOW if roll < 0.3 else (WeatherType.STORM if roll < 0.45 else WeatherType.CLEAR)
		_:
			next_type = WeatherType.RAIN if roll < 0.3 else WeatherType.CLEAR
	var intensity: float = 0.0 if next_type == WeatherType.CLEAR else randf_range(0.4, 1.0)
	set_weather(next_type, intensity, randf_range(25.0, 70.0))

func _update_overlay() -> void:
	if _overlay == null:
		return
	var color := Color(1, 1, 1, 0)
	var a: float = weather_intensity * 0.22
	match current_weather:
		WeatherType.RAIN:
			color = Color(0.45, 0.55, 0.75, a)
		WeatherType.STORM:
			color = Color(0.25, 0.28, 0.4, a + 0.08)
		WeatherType.SNOW:
			color = Color(0.85, 0.9, 1.0, a)
		WeatherType.FOG:
			color = Color(0.7, 0.72, 0.7, a + 0.1)
		WeatherType.SANDSTORM:
			color = Color(0.72, 0.58, 0.32, a + 0.05)
		_:
			color = Color(1, 1, 1, 0)
	_overlay.color = color
