## Manages weather conditions and effects.
class_name WeatherSystem
extends Node

# Weather types
enum WeatherType {
	CLEAR,      # No weather
	RAIN,       # Rain
	STORM,      # Heavy storm
	SNOW,       # Snow
	FOG,        # Fog
	SANDSTORM   # Sand storm
}

# Weather data
var current_weather: WeatherType = WeatherType.CLEAR
var weather_intensity: float = 0.0  # 0.0 to 1.0
var weather_duration: float = 0.0
var next_weather_change: float = 0.0

# Visual particles
var rain_particles: GPUParticles2D = null
var snow_particles: GPUParticles2D = null
var fog_overlay: ColorRect = null

# Signals
signal weather_changed(weather_type: WeatherType, intensity: float)
signal weather_started(weather_type: WeatherType)
signal weather_ended

## Initialize the weather system.
func initialize() -> void:
	_setup_particles()
	print("WeatherSystem: Initialized")

## Set up particle systems.
func _setup_particles() -> void:
	# Create rain particles
	rain_particles = GPUParticles2D.new()
	rain_particles.visible = false
	rain_particles.amount = 100
	rain_particles.process_material = _create_particle_material(Color(0.5, 0.7, 1.0), 100.0)
	add_child(rain_particles)
	
	# Create snow particles
	snow_particles = GPUParticles2D.new()
	snow_particles.visible = false
	snow_particles.amount = 80
	snow_particles.process_material = _create_particle_material(Color(0.9, 0.9, 1.0), 50.0)
	add_child(snow_particles)
	
	# Create fog overlay
	fog_overlay = ColorRect.new()
	fog_overlay.color = Color(0.5, 0.5, 0.5, 0.3)
	fog_overlay.visible = false
	add_child(fog_overlay)

## Create particle material.
func _create_particle_material(color: Color, speed: float) -> ParticlesProcessMaterial:
	var material := ParticlesProcessMaterial.new()
	material.direction = Vector3(0, -1, 0)
	material.initial_velocity = speed
	material.spread = 45.0
	material.process_material = material
	return material

## Change weather to a new type.
func set_weather(weather_type: WeatherType, intensity: float = 1.0, duration: float = 0.0) -> void:
	var old_weather := current_weather
	current_weather = weather_type
	weather_intensity = clamp(intensity, 0.0, 1.0)
	weather_duration = duration
	
	_update_visuals()
	weather_changed.emit(weather_type, weather_intensity)
	
	if weather_type != old_weather:
		weather_started.emit(weather_type)

## Update weather over time.
func _physics_process(delta: float) -> void:
	# Decrease duration if set
	if weather_duration > 0:
		weather_duration -= delta
		if weather_duration <= 0:
			# Weather expired, return to clear
			set_weather(WeatherType.CLEAR)
			return
	
	# Random weather changes
	next_weather_change -= delta
	if next_weather_change <= 0:
		_change_random_weather()
		next_weather_change = randf_range(30.0, 120.0)  # 30-120 seconds

## Change to a random weather type.
func _change_random_weather() -> void:
	var weather_types := [
		WeatherType.CLEAR,
		WeatherType.RAIN,
		WeatherType.SNOW,
		WeatherType.FOG
	]
	
	# Filter based on biome (simplified)
	var biome := _get_current_biome()
	if biome == "desert":
		weather_types = [WeatherType.CLEAR, WeatherType.SANDSTORM]
	elif biome == "arctic":
		weather_types = [WeatherType.SNOW, WeatherType.FOG]
	
	var new_weather := weather_types[randi() % weather_types.size()]
	var intensity := randf_range(0.3, 1.0)
	set_weather(new_weather, intensity)

## Get current biome.
func _get_current_biome() -> String:
	var player := get_node_or_null("/root/Main/Player")
	if player and player.has_method("get_world_position"):
		var pos := player.get_world_position()
		# Simplified biome detection
		var noise := get_node_or_null("/root/Main/WorldGenerator")
		if noise:
			# Return based on position
			if pos.y < 100:
				return "grassland"
			elif pos.y < 200:
				return "temperate_forest"
			elif pos.y < 300:
				return "mountain"
			elif pos.y < 400:
				return "desert"
			else:
				return "arctic"
	return "grassland"

## Update visual effects.
func _update_visuals() -> void:
	# Hide all particles and overlay
	rain_particles.visible = false
	snow_particles.visible = false
	fog_overlay.visible = false
	
	match current_weather:
		WeatherType.RAIN, WeatherType.STORM:
			rain_particles.visible = true
			rain_particles.amount = int(100 * weather_intensity)
			rain_particles.emitting = true
			fog_overlay.visible = true
			fog_overlay.color = Color(0.3, 0.3, 0.4, 0.2 * weather_intensity)
		
		WeatherType.SNOW:
			snow_particles.visible = true
			snow_particles.amount = int(80 * weather_intensity)
			snow_particles.emitting = true
			fog_overlay.visible = true
			fog_overlay.color = Color(0.8, 0.8, 0.9, 0.15 * weather_intensity)
		
		WeatherType.FOG:
			fog_overlay.visible = true
			fog_overlay.color = Color(0.6, 0.6, 0.6, 0.4 * weather_intensity)
		
		WeatherType.SANDSTORM:
			rain_particles.visible = true
			rain_particles.amount = int(150 * weather_intensity)
			rain_particles.emitting = true
			rain_particles.process_material = _create_particle_material(Color(0.8, 0.6, 0.4), 80.0)
			fog_overlay.visible = true
			fog_overlay.color = Color(0.7, 0.5, 0.3, 0.3 * weather_intensity)
		
		WeatherType.CLEAR:
			pass

## Get current weather type.
func get_weather_type() -> WeatherType:
	return current_weather

## Get weather intensity.
func get_weather_intensity() -> float:
	return weather_intensity

## Check if it's currently weathering.
func is_weather_active() -> bool:
	return current_weather != WeatherType.CLEAR

## Get weather description.
func get_weather_description() -> String:
	match current_weather:
		WeatherType.CLEAR:
			return "Clear"
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
			return "Unknown"

## Serialize weather data.
func serialize() -> Dictionary:
	return {
		"current_weather": current_weather,
		"weather_intensity": weather_intensity,
		"weather_duration": weather_duration
	}

## Deserialize weather data.
func deserialize(data: Dictionary) -> void:
	current_weather = data.get("current_weather", WeatherType.CLEAR)
	weather_intensity = data.get("weather_intensity", 0.0)
	weather_duration = data.get("weather_duration", 0.0)
	_update_visuals()
	weather_changed.emit(current_weather, weather_intensity)
