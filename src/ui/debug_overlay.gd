## Debug overlay showing world generation information.
class_name DebugOverlay
extends CanvasLayer

@onready var debug_label: Label = $DebugPanel/DebugLabel

var _enabled: bool = false
var _world_position: Vector2 = Vector2.ZERO
var _diagnostics: Dictionary = {}
var _fps: int = 0

## Enable or disable the debug overlay.
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	$DebugPanel.visible = enabled

## Update debug information.
func update_debug(world_pos: Vector2, diagnostics: Dictionary, fps: int) -> void:
	_world_position = world_pos
	_diagnostics = diagnostics
	_fps = fps
	_refresh()

## Refresh the debug display.
func _refresh() -> void:
	if not _enabled:
		return

	var fields: Dictionary = _diagnostics.get("fields", {})
	var water: Dictionary = _diagnostics.get("water", {})
	var tile: Vector2i = _diagnostics.get("tile", Vector2i.ZERO)
	var chunk: Vector2i = _diagnostics.get("chunk", Vector2i.ZERO)
	var tile_bounds: Rect2i = _diagnostics.get("chunk_tile_bounds", Rect2i())
	var pixel_bounds: Rect2i = _diagnostics.get("chunk_pixel_bounds", Rect2i())
	var text: String = ""
	text += "FPS: %d\n" % _fps
	text += "\nWorld Position: %.1f, %.1f\n" % [_world_position.x, _world_position.y]
	text += "Tile: %d, %d  Chunk: %d, %d\n" % [tile.x, tile.y, chunk.x, chunk.y]
	text += "Chunk bounds: tiles %s..%s\n" % [str(tile_bounds.position), str(tile_bounds.end - Vector2i.ONE)]
	text += "              pixels %s..%s\n" % [str(pixel_bounds.position), str(pixel_bounds.end - Vector2i.ONE)]
	text += "\nSeed: %d  Config: %s v%d\n" % [_diagnostics.get("seed", 0),
			_diagnostics.get("config_id", "unknown"), _diagnostics.get("generation_version", 0)]
	text += "Biome: %s  Region cell: %s\n" % [_diagnostics.get("biome", "unknown"),
			str(_diagnostics.get("region_cell", Vector2i.ZERO))]
	text += "Water: %s (%s), dist %d, river %s\n" % [water.get("class", "land"),
			water.get("origin", ""), water.get("distance", -1), "yes" if water.get("river", -1) == 1 else "no"]
	text += "\nFields: elevation %.3f  moisture %.3f\n" % [fields.get("elevation", 0.0), fields.get("moisture", 0.0)]
	text += "        temperature %.3f  water %.3f\n" % [fields.get("temperature", 0.0), fields.get("water", 0.0)]

	debug_label.text = text

## Whether the debug overlay is currently shown.
func is_enabled() -> bool:
	return _enabled

## Called when debug toggle is pressed.
func toggle() -> void:
	_enabled = not _enabled
	$DebugPanel.visible = _enabled
