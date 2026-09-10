## Manages performance optimization for the game.
class_name PerformanceManager
extends Node

# Performance settings
var settings := {
	"max_chunks": 9,
	"render_distance": 3,
	"draw_distance": 256,
	"max_particles": 100,
	"shadow_quality": "low",
	"anti_aliasing": false,
	"v_sync": false,
	"frame_limit": 60
}

# Stats
var fps: int = 60
var chunk_count: int = 0
var entity_count: int = 0
var particle_count: int = 0
var draw_calls: int = 0

# Optimization flags
var culling_enabled: bool = True
var LOD_enabled: bool = True
var occlusion_culling: bool = True

# Signals
signal fps_changed(new_fps: int)
signal settings_changed
signal stats_updated

## Initialize the performance manager.
func initialize() -> void:
	_load_settings()
	print("PerformanceManager: Initialized")

## Load settings from config.
func _load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load("user://performance.cfg")
	if error == OK:
		settings["max_chunks"] = config.get_value("graphics", "max_chunks", 9)
		settings["render_distance"] = config.get_value("graphics", "render_distance", 3)
		settings["draw_distance"] = config.get_value("graphics", "draw_distance", 256)
		settings["max_particles"] = config.get_value("graphics", "max_particles", 100)
		settings["shadow_quality"] = config.get_value("graphics", "shadow_quality", "low")
		settings["anti_aliasing"] = config.get_value("graphics", "anti_aliasing", False)
		settings["v_sync"] = config.get_value("graphics", "v_sync", False)
		settings["frame_limit"] = config.get_value("graphics", "frame_limit", 60)

## Save settings to config.
func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", "max_chunks", settings["max_chunks"])
	config.set_value("graphics", "render_distance", settings["render_distance"])
	config.set_value("graphics", "draw_distance", settings["draw_distance"])
	config.set_value("graphics", "max_particles", settings["max_particles"])
	config.set_value("graphics", "shadow_quality", settings["shadow_quality"])
	config.set_value("graphics", "anti_aliasing", settings["anti_aliasing"])
	config.set_value("graphics", "v_sync", settings["v_sync"])
	config.set_value("graphics", "frame_limit", settings["frame_limit"])
	config.save("user://performance.cfg")

## Update performance stats.
func _process(delta: float) -> void:
	# Update FPS
	fps = Engine.get_frames_per_second()
	fps_changed.emit(fps)
	
	# Update counts
	chunk_count = _get_chunk_count()
	entity_count = _get_entity_count()
	particle_count = _get_particle_count()
	draw_calls = RenderingServer.get_render_info(RenderingServer.RENDER_INFO_DRAW_CALLS)
	stats_updated.emit()
	
	# Auto-optimize if FPS drops
	if fps < 30:
		_auto_optimize()

## Get chunk count.
func _get_chunk_count() -> int:
	var chunk_system := get_node_or_null("/root/Main/ChunkSystem")
	if chunk_system:
		return chunk_system.get_chunk_count()
	return 0

## Get entity count.
func _get_entity_count() -> int:
	var creature_spawner := get_node_or_null("/root/Main/CreatureSpawner")
	if creature_spawner:
		return creature_spawner.get_creature_count()
	return 0

## Get particle count.
func _get_particle_count() -> int:
	var count := 0
	for child in get_tree().get_root().get_children():
		if child is GPUParticles2D:
			count += 1
	return count

## Auto-optimize settings.
func _auto_optimize() -> void:
	# Reduce settings to improve FPS
	if settings["shadow_quality"] != "off":
		settings["shadow_quality"] = "off"
	if settings["render_distance"] > 1:
		settings["render_distance"] -= 1
	if settings["max_particles"] > 50:
		settings["max_particles"] -= 25
	_save_settings()
	print("PerformanceManager: Auto-optimized settings")

## Apply graphics settings.
func apply_settings() -> void:
	# Apply render settings
	RenderingServer.set_viewport_draw_pass_count_2d(settings["render_distance"] + 1)
	RenderingServer.set_canvas_cache_limit(settings["draw_distance"] * 1000)
	
	# Apply VSync
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if not settings["v_sync"] else DisplayServer.VSYNC_ENABLED)
	
	# Apply frame limit
	Engine.max_fps = settings["frame_limit"] if settings["frame_limit"] > 0 else Engine.MAX_FPS
	
	# Apply anti-aliasing
	RenderingServer.set_2d_antialiasing_mode(RenderingServer.ANTIALIAS_2D_OFF if not settings["anti_aliasing"] else RenderingServer.ANTIALIAS_2D_MSAA)
	
	settings_changed.emit()

## Get current FPS.
func get_fps() -> int:
	return fps

## Get current chunk count.
func get_chunk_count() -> int:
	return chunk_count

## Get current entity count.
func get_entity_count() -> int:
	return entity_count

## Get current particle count.
func get_particle_count() -> int:
	return particle_count

## Get current draw calls.
func get_draw_calls() -> int:
	return draw_calls

## Get settings.
func get_settings() -> Dictionary:
	return settings.duplicate()

## Set a setting.
func set_setting(key: String, value) -> void:
	settings[key] = value
	_save_settings()
	settings_changed.emit()

## Reset to default settings.
func reset_to_defaults() -> void:
	settings = {
		"max_chunks": 9,
		"render_distance": 3,
		"draw_distance": 256,
		"max_particles": 100,
		"shadow_quality": "low",
		"anti_aliasing": False,
		"v_sync": False,
		"frame_limit": 60
	}
	_save_settings()
	apply_settings()
	settings_changed.emit()

## Serialize settings.
func serialize() -> Dictionary:
	return settings.duplicate()

## Deserialize settings.
func deserialize(data: Dictionary) -> void:
	settings = data
	apply_settings()
	settings_changed.emit()
