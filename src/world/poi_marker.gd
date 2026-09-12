## Generic runtime surface node for a POI that no cave definition links to.
## Like CaveEntrance it carries only stable identity/content metadata; any
## future gameplay behavior for a POI category attaches here or to a
## category-specific runtime without changing placement or generation.
class_name PoiMarker
extends Node2D

var poi_id: String = ""
var poi_category: String = ""
var display_name: String = ""
var marker_tile: Vector2i = Vector2i.ZERO
var _name_label: Label = null

func setup(candidate: Dictionary) -> void:
	poi_id = str(candidate.get("poi_id", ""))
	poi_category = str(candidate.get("poi_category", ""))
	display_name = str(candidate.get("poi_name", ""))
	marker_tile = Vector2i(int(candidate.get("x", 0)), int(candidate.get("y", 0)))
	if not is_instance_valid(_name_label):
		_name_label = Label.new()
		_name_label.add_theme_font_size_override("font_size", 10)
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_label.position = Vector2(-64, -26)
		_name_label.size = Vector2(128, 16)
		_name_label.modulate = Color(1.0, 0.95, 0.6, 0.85)
		add_child(_name_label)
	_name_label.text = display_name
	queue_redraw()

func _draw() -> void:
	# A deliberately simple placeholder: a small survey-stake diamond. Content
	# art can replace this node later without changing identity or placement.
	var diamond := PackedVector2Array([
		Vector2(0, -9), Vector2(7, 0), Vector2(0, 9), Vector2(-7, 0)
	])
	draw_colored_polygon(diamond, Color(0.78, 0.68, 0.30, 0.9))
	draw_polyline(diamond, Color(0.35, 0.3, 0.14, 1.0), 2.0, true)
