## Always-on, low-cost performance telemetry for hands-on playtesting.
class_name PerformanceOverlay
extends CanvasLayer

const SAMPLE_INTERVAL := 0.10
const HISTORY_LENGTH := 100

var _panel: PanelContainer
var _label: Label
var _graph: FrameGraph
var _samples: Array[float] = []
var _sample_time := 0.0
var _lowest_fps := 240.0
var _current_fps := 60.0
var _last_chunk_note := "No chunk load yet"

func _ready() -> void:
	layer = 12
	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 76)
	_panel.size = Vector2(244, 158)
	_panel.modulate = Color(1.0, 1.0, 1.0, 0.94)
	add_child(_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 9)
	margin.add_theme_constant_override("margin_right", 9)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	column.add_child(_label)
	_graph = FrameGraph.new()
	_graph.custom_minimum_size = Vector2(224, 62)
	column.add_child(_graph)

func update_frame(delta: float, chunks: int, resources: int, creatures: int) -> void:
	var instant_fps := 1.0 / maxf(delta, 0.0001)
	_current_fps = instant_fps
	_lowest_fps = minf(_lowest_fps, instant_fps)
	_sample_time += delta
	if _sample_time < SAMPLE_INTERVAL:
		return
	_samples.append(_lowest_fps)
	if _samples.size() > HISTORY_LENGTH:
		_samples.pop_front()
	_graph.set_samples(_samples)
	_label.text = "FPS %3d   frame %5.1f ms\nChunks %d  Objects %d  Creatures %d\n%s" % [
		int(round(_current_fps)), delta * 1000.0, chunks, resources, creatures, _last_chunk_note
	]
	_sample_time = 0.0
	_lowest_fps = 240.0

func record_chunk_load(chunk_coords: Vector2i, elapsed_ms: float) -> void:
	_last_chunk_note = "Chunk %d, %d loaded: %.1f ms" % [chunk_coords.x, chunk_coords.y, elapsed_ms]

class FrameGraph extends Control:
	var _samples: Array[float] = []

	func set_samples(samples: Array[float]) -> void:
		_samples = samples
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#111a1d"), true)
		for level in [0.25, 0.5, 0.75]:
			var y: float = size.y * (1.0 - float(level))
			draw_line(Vector2(0, y), Vector2(size.x, y), Color("#375156"), 1.0)
		if _samples.size() < 2:
			return
		for index in range(1, _samples.size()):
			var previous := _point(index - 1)
			var current := _point(index)
			var colour := Color("#67d98a") if _samples[index] >= 55.0 else Color("#f0b35d")
			if _samples[index] < 30.0:
				colour = Color("#ed6b62")
			draw_line(previous, current, colour, 2.0, true)

	func _point(index: int) -> Vector2:
		var x: float = float(index) / float(maxi(1, HISTORY_LENGTH - 1)) * size.x
		var y: float = size.y * (1.0 - clampf(_samples[index] / 60.0, 0.0, 1.0))
		return Vector2(x, y)
