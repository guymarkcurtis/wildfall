## Generic runtime node for one terrain-feature candidate (WG-04).
## A minimal generic placeholder: it carries the candidate's identity and
## footprint so consumers (the player, future systems) can query a feature's
## location and extent, and it draws a neutral ground outline. Presentation
## per feature category is deliberately NOT done here — that is data/scene
## content to be added later, exactly like POI markers, without touching
## placement or generation.
class_name TerrainFeatureMarker
extends Node2D

const TILE_SIZE: int = 32

var feature_id: String = ""
var feature_category: String = "structure"
var display_name: String = "Feature"
## "id@x,y" — the stable identity the runtime books the marker under.
var feature_identity: String = ""
var footprint_radius_tiles: int = 0
var marker_tile: Vector2i = Vector2i.ZERO
var _name_label: Label = null


func setup(candidate: Dictionary) -> void:
	feature_id = str(candidate.get("feature_id", ""))
	feature_category = str(candidate.get("feature_category", "structure"))
	display_name = str(candidate.get("feature_name", "Feature"))
	feature_identity = str(candidate.get("feature_identity", ""))
	footprint_radius_tiles = int(candidate.get("footprint_radius_tiles", 0))
	marker_tile = Vector2i(int(candidate.get("x", 0)), int(candidate.get("y", 0)))
	if not is_instance_valid(_name_label):
		_name_label = Label.new()
		_name_label.add_theme_font_size_override("font_size", 10)
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_label.position = Vector2(-64, -26)
		_name_label.size = Vector2(128, 16)
		_name_label.modulate = Color(0.75, 0.85, 0.6, 0.85)
		add_child(_name_label)
	_name_label.text = display_name
	queue_redraw()

func _draw() -> void:
	# A deliberately simple placeholder: a flat ground-patch outline sized to
	# the feature's footprint. Content art can replace this node later without
	# changing identity or placement.
	if footprint_radius_tiles > 0:
		draw_arc(Vector2.ZERO, (footprint_radius_tiles + 0.5) * TILE_SIZE, 0.0, TAU, 48,
				Color(0.45, 0.5, 0.4, 0.9), 2.0)
	draw_circle(Vector2.ZERO, 3.0, Color(0.6, 0.65, 0.55, 0.9))
