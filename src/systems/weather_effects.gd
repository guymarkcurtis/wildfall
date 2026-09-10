## Manages weather effects on gameplay.
class_name WeatherEffects
extends Node

var weather_system: WeatherSystem = null

# Signals
signal weather_affecting_player(effect_type: String, intensity: float)

## Initialize the weather effects system.
func initialize(weather_system_ref: WeatherSystem) -> void:
	weather_system = weather_system_ref
	print("WeatherEffects: Initialized")

## Update weather effects.
func _process(delta: float) -> void:
	if not weather_system:
		return
	
	var weather_type := weather_system.get_weather_type()
	var intensity := weather_system.get_weather_intensity()
	
	# Apply weather effects to player
	_apply_weather_effects(weather_type, intensity)

## Apply weather effects.
func _apply_weather_effects(weather_type: int, intensity: float) -> void:
	var player := get_node_or_null("/root/Main/Player")
	if not player:
		return
	
	match weather_type:
		WeatherSystem.WeatherType.RAIN, WeatherSystem.WeatherType.STORM:
			# Reduce visibility
			var camera := get_node_or_null("/root/Main/CameraController")
			if camera:
				camera.modulate.a = 1.0 - intensity * 0.3
			
			# Slow movement slightly
			weather_affecting_player.emit("rain_slow", intensity * 0.1)
		
		WeatherType.SNOW:
			# Reduce movement speed
			weather_affecting_player.emit("snow_slow", intensity * 0.2)
			
			# Frost damage over time
			if intensity > 0.5:
				weather_affecting_player.emit("frost_damage", intensity * 0.5)
		
		WeatherType.FOG:
			# Significantly reduce visibility
			var camera := get_node_or_null("/root/Main/CameraController")
			if camera:
				camera.modulate.a = 1.0 - intensity * 0.5
		
		WeatherType.SANDSTORM:
			# Reduce movement and visibility
			weather_affecting_player.emit("sand_slow", intensity * 0.3)
			weather_affecting_player.emit("sand_damage", intensity * 0.2)
		
		WeatherType.CLEAR:
			# No effects
			pass

## Get weather effect description.
func get_weather_effect_description() -> String:
	if not weather_system:
		return ""
	
	var weather_type := weather_system.get_weather_type()
	var intensity := weather_system.get_weather_intensity()
	
	match weather_type:
		WeatherSystem.WeatherType.RAIN:
			return "Rain slows movement slightly"
		WeatherSystem.WeatherType.STORM:
			return "Storm reduces visibility and slows movement"
		WeatherSystem.WeatherType.SNOW:
			return "Snow reduces speed and may cause frostbite"
		WeatherSystem.WeatherType.FOG:
			return "Fog significantly reduces visibility"
		WeatherSystem.WeatherType.SANDSTORM:
			return "Sandstorm reduces visibility and damages"
		_:
			return ""
