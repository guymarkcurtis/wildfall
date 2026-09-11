## Debug overlay showing world generation information.
class_name DebugOverlay
extends CanvasLayer

@onready var debug_label: Label = $DebugPanel/DebugLabel

var _enabled: bool = false
var _world_position: Vector2 = Vector2.ZERO
var _tile_position: Vector2i = Vector2i(0, 0)
var _chunk_position: Vector2i = Vector2i(0, 0)
var _world_seed: int = 0
var _current_biome: String = "unknown"
var _noise_values: Dictionary = {}
var _fps: int = 0

## Enable or disable the debug overlay.
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	$DebugPanel.visible = enabled

## Update debug information.
func update_debug(world_pos: Vector2, tile_pos: Vector2i, chunk_pos: Vector2i,
		seed: int, biome: String, noise: Dictionary, fps: int) -> void:
	_world_position = world_pos
	_tile_position = tile_pos
	_chunk_position = chunk_pos
	_world_seed = seed
	_current_biome = biome
	_noise_values = noise
	_fps = fps
	_refresh()

## Refresh the debug display.
func _refresh() -> void:
	if not _enabled:
		return

	var text: String = ""
	text += "FPS: %d\n" % _fps
	text += "\nWorld Position: %.1f, %.1f\n" % [_world_position.x, _world_position.y]
	text += "Tile Position: %d, %d\n" % [_tile_position.x, _tile_position.y]
	text += "Chunk Position: %d, %d\n" % [_chunk_position.x, _chunk_position.y]
	text += "\nWorld Seed: %d\n" % _world_seed
	text += "Current Biome: %s\n" % _current_biome
	text += "\nNoise Values:\n"
	text += "  Elevation: %.3f\n" % _noise_values.get("elevation", 0.0)
	text += "  Moisture: %.3f\n" % _noise_values.get("moisture", 0.0)
	text += "  Temperature: %.3f\n" % _noise_values.get("temperature", 0.0)

	debug_label.text = text

## Whether the debug overlay is currently shown.
func is_enabled() -> bool:
	return _enabled

## Called when debug toggle is pressed.
func toggle() -> void:
	_enabled = not _enabled
	$DebugPanel.visible = _enabled
