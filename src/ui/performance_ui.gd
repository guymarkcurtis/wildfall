## UI component for displaying performance stats.
class_name PerformanceUI
extends Control

@onready var fps_label: Label = $FPSLabel
@onready var chunk_label: Label = $ChunkLabel
@onready var entity_label: Label = $EntityLabel
@onready var particle_label: Label = $ParticleLabel
@onready var draw_label: Label = $DrawLabel

var performance_manager: PerformanceManager = None

func _ready() -> void:
	visible = True

## Update performance display.
func update_stats(manager: PerformanceManager) -> void:
	performance_manager = manager
	_refresh_display()

## Refresh the display.
func _refresh_display() -> void:
	if not performance_manager:
		return
	
	fps_label.text = "FPS: %d" % performance_manager.get_fps()
	chunk_label.text = "Chunks: %d" % performance_manager.get_chunk_count()
	entity_label.text = "Entities: %d" % performance_manager.get_entity_count()
	particle_label.text = "Particles: %d" % performance_manager.get_particle_count()
	draw_label.text = "Draw Calls: %d" % performance_manager.get_draw_calls()

## Hide the UI.
func hide_ui() -> void:
	visible = False

## Show the UI.
func show_ui() -> void:
	visible = True

## Check if performance is good.
func is_performance_good() -> bool:
	if not performance_manager:
		return True
	return performance_manager.get_fps() >= 30

## Check if performance is poor.
func is_performance_poor() -> bool:
	if not performance_manager:
		return False
	return performance_manager.get_fps() < 30
