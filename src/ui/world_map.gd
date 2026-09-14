## Lightweight finite-world map: an always-visible minimap plus a filterable
## full-screen POI map. It reveals deterministic POIs only for chunks around
## the player, then saves that explored knowledge with the world.
class_name WorldMap
extends Control

const TILE_SIZE := 32.0
const INVALID_TILE := Vector2i(999999999, 999999999)
## Reveal a compact five-by-five chunk neighbourhood. This follows the player
## through already-streamed chunk payloads, never by scanning the whole map.
const POI_REVEAL_RADIUS_CHUNKS := 2

var _world_generator: WorldGenerator = null
var _player: Player = null
var _chunk_system: ChunkSystem = null
var _markers: Array[Dictionary] = []
var _marker_keys: Dictionary = {}
var _filters: Dictionary = {}
## Chunks are recorded even when they contain no POIs, so revisiting them does
## not repeat map discovery work after a save/load.
var _revealed_chunk_keys: Dictionary = {}
var _waypoint := INVALID_TILE
var _waypoint_label := ""
## The maps use tile-level positions, so redrawing only when this changes
## preserves their visual behaviour without issuing canvas work every frame.
var _last_player_tile := INVALID_TILE

var _minimap: MapSurface
var _window: Panel
var _full_map: MapSurface
var _legend: VBoxContainer
var _status: Label

signal waypoint_changed(tile: Vector2i, label: String)

func _ready() -> void:
	anchors_preset = Control.LayoutPreset.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_minimap()
	_build_full_map()

func configure(generator: WorldGenerator, player_ref: Player, chunk_system_ref: ChunkSystem = null) -> void:
	if _chunk_system != null:
		if _chunk_system.chunks_changed.is_connected(_on_chunks_changed):
			_chunk_system.chunks_changed.disconnect(_on_chunks_changed)
		if _chunk_system.player_chunk_changed.is_connected(_on_player_chunk_changed):
			_chunk_system.player_chunk_changed.disconnect(_on_player_chunk_changed)
	_world_generator = generator
	_player = player_ref
	_chunk_system = chunk_system_ref
	if _chunk_system != null:
		_chunk_system.chunks_changed.connect(_on_chunks_changed)
		_chunk_system.player_chunk_changed.connect(_on_player_chunk_changed)
	_last_player_tile = INVALID_TILE
	_sync_nearby_loaded_chunks()
	queue_redraws()

## A new world starts with no explored map knowledge. Saved knowledge is
## restored afterward through deserialize_exploration().
func set_world_seed(seed: int) -> void:
	_markers.clear()
	_marker_keys.clear()
	_filters.clear()
	_revealed_chunk_keys.clear()
	if has_waypoint():
		clear_waypoint()
	queue_redraws()

func toggle() -> void:
	if _window == null:
		return
	_window.visible = not _window.visible
	if _window.visible:
		_sync_nearby_loaded_chunks()
		_refresh_legend()
		_refresh_status()
		queue_redraws()

func is_open() -> bool:
	return _window != null and _window.visible

func has_waypoint() -> bool:
	return _waypoint != INVALID_TILE

func get_waypoint() -> Vector2i:
	return _waypoint

func set_waypoint(tile: Vector2i, label: String = "Waypoint") -> void:
	if not _tile_in_world(tile):
		return
	_waypoint = tile
	_waypoint_label = label
	waypoint_changed.emit(_waypoint, _waypoint_label)
	_refresh_status()
	queue_redraws()

func clear_waypoint() -> void:
	_waypoint = INVALID_TILE
	_waypoint_label = ""
	waypoint_changed.emit(INVALID_TILE, "")
	_refresh_status()
	queue_redraws()

func get_visible_marker_count() -> int:
	return _visible_markers().size()

func get_cave_marker_count() -> int:
	var count := 0
	for marker in _markers:
		if _marker_kind(marker) == "caves":
			count += 1
	return count

func set_marker_filter(kind: String, enabled: bool) -> void:
	if not _filters.has(kind):
		return
	_filters[kind] = enabled
	_refresh_legend()
	queue_redraws()

func is_marker_filter_enabled(kind: String) -> bool:
	return bool(_filters.get(kind, false))

func get_revealed_chunk_count() -> int:
	return _revealed_chunk_keys.size()

func get_known_marker_count() -> int:
	return _markers.size()

func _process(_delta: float) -> void:
	# Both maps render the player at tile precision. Avoid recreating visible
	# marker lists and issuing canvas redraws every frame while the player is
	# stationary within a tile; waypoint and filter changes redraw explicitly.
	var player_tile := _get_player_tile()
	if player_tile != _last_player_tile:
		_last_player_tile = player_tile
		_sync_nearby_loaded_chunks()
		queue_redraws()

func _on_chunks_changed() -> void:
	_sync_nearby_loaded_chunks()

func _on_player_chunk_changed(_old_chunk: Vector2i, _new_chunk: Vector2i) -> void:
	_sync_nearby_loaded_chunks()

## POIs are already part of streamed chunk payloads. Reusing those payloads
## keeps map discovery free of world-wide generator work and ties fog-of-war
## knowledge to places the player has actually approached.
func _sync_nearby_loaded_chunks() -> void:
	if _chunk_system == null:
		return
	var center := _chunk_system.get_player_chunk()
	if center.x == -999999:
		return
	var chunks: Array = _chunk_system.get_loaded_chunks()
	chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.y == b.y else a.y < b.y
	)
	for chunk_variant in chunks:
		var chunk_coords: Vector2i = chunk_variant
		if maxi(abs(chunk_coords.x - center.x), abs(chunk_coords.y - center.y)) > POI_REVEAL_RADIUS_CHUNKS:
			continue
		reveal_chunk_pois(chunk_coords, _chunk_system.get_chunk(chunk_coords))

## Public because Main's chunk presentation path and the map's loaded-chunk
## synchronisation both use this single persistence-aware discovery route.
func reveal_chunk_pois(chunk_coords: Vector2i, chunk_data: Dictionary) -> void:
	var chunk_key := _chunk_key(chunk_coords)
	if _revealed_chunk_keys.has(chunk_key):
		return
	_revealed_chunk_keys[chunk_key] = true
	var changed := false
	for candidate_variant in chunk_data.get("poi_candidates", []):
		if typeof(candidate_variant) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = (candidate_variant as Dictionary).duplicate(true)
		var marker_key := _marker_key(candidate)
		if marker_key.is_empty() or _marker_keys.has(marker_key):
			continue
		_marker_keys[marker_key] = true
		_markers.append(candidate)
		var kind := _marker_kind(candidate)
		if not _filters.has(kind):
			_filters[kind] = true
		changed = true
	if changed and is_open():
		_refresh_legend()
	if changed:
		_refresh_status()
		queue_redraws()

func serialize_exploration() -> Dictionary:
	var chunks: Array[Dictionary] = []
	for key in _revealed_chunk_keys:
		var parts := str(key).split(",")
		if parts.size() == 2:
			chunks.append({"x": int(parts[0]), "y": int(parts[1])})
	chunks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["x"]) < int(b["x"]) if int(a["y"]) == int(b["y"]) else int(a["y"]) < int(b["y"])
	)
	var markers: Array[Dictionary] = _markers.duplicate(true)
	markers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ay := int(a.get("y", 0))
		var by := int(b.get("y", 0))
		if ay == by:
			var ax := int(a.get("x", 0))
			var bx := int(b.get("x", 0))
			return str(a.get("poi_id", "")) < str(b.get("poi_id", "")) if ax == bx else ax < bx
		return ay < by
	)
	return {"revealed_chunks": chunks, "markers": markers}

func deserialize_exploration(data: Variant) -> void:
	_markers.clear()
	_marker_keys.clear()
	_filters.clear()
	_revealed_chunk_keys.clear()
	if typeof(data) == TYPE_DICTIONARY:
		var exploration: Dictionary = data
		for chunk_variant in exploration.get("revealed_chunks", []):
			if typeof(chunk_variant) == TYPE_DICTIONARY:
				var chunk: Dictionary = chunk_variant
				_revealed_chunk_keys[_chunk_key(Vector2i(int(chunk.get("x", 0)), int(chunk.get("y", 0))))] = true
		for marker_variant in exploration.get("markers", []):
			if typeof(marker_variant) != TYPE_DICTIONARY:
				continue
			var marker: Dictionary = (marker_variant as Dictionary).duplicate(true)
			var key := _marker_key(marker)
			if key.is_empty() or _marker_keys.has(key):
				continue
			_marker_keys[key] = true
			_markers.append(marker)
			_filters[_marker_kind(marker)] = true
	if is_open():
		_refresh_legend()
	_refresh_status()
	queue_redraws()

func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		_window.visible = false
		get_viewport().set_input_as_handled()

func _build_minimap() -> void:
	_minimap = MapSurface.new()
	_minimap.owner_map = self
	_minimap.large = false
	_minimap.name = "Minimap"
	_minimap.set_anchors_preset(Control.LayoutPreset.PRESET_TOP_RIGHT)
	_minimap.position = Vector2(-250.0, 12.0)
	_minimap.size = Vector2(238.0, 174.0)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_minimap)

func _build_full_map() -> void:
	# A plain panel holds the fixed-size centred map. PanelContainer expands to
	# a tall legend's combined minimum size, which pushed the map below centre.
	_window = Panel.new()
	_window.name = "MapWindow"
	_window.set_anchors_preset(Control.LayoutPreset.PRESET_CENTER)
	_window.size = Vector2(960.0, 620.0)
	# PRESET_CENTER places the anchor at the viewport centre; offset the panel
	# by half its size so its own centre, rather than its top-left corner, sits
	# there.
	_window.position = -_window.size * 0.5
	_window.add_theme_stylebox_override("panel", _panel_style())
	_window.visible = false
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_window)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_and_offsets_preset(Control.LayoutPreset.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	_window.add_child(column)
	var title := Label.new()
	title.text = "World Map"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color(0.82, 0.86, 0.78))
	column.add_child(_status)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	column.add_child(body)
	_full_map = MapSurface.new()
	_full_map.owner_map = self
	_full_map.large = true
	_full_map.name = "FullMap"
	_full_map.custom_minimum_size = Vector2(710.0, 500.0)
	_full_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_full_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_full_map.mouse_filter = Control.MOUSE_FILTER_STOP
	body.add_child(_full_map)

	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(210.0, 0.0)
	body.add_child(sidebar)
	var legend_title := Label.new()
	legend_title.text = "Legend"
	legend_title.add_theme_font_size_override("font_size", 17)
	sidebar.add_child(legend_title)
	var legend_hint := Label.new()
	legend_hint.text = "Choose what is shown. Click a marker to set a waypoint."
	legend_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend_hint.add_theme_font_size_override("font_size", 12)
	sidebar.add_child(legend_hint)
	# Keep a dense world seed from growing the entire panel taller than the
	# viewport. The legend has its own scroll area instead, preserving the map's
	# fixed, centred footprint.
	var legend_scroll := ScrollContainer.new()
	legend_scroll.name = "LegendScroll"
	legend_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(legend_scroll)
	_legend = VBoxContainer.new()
	_legend.name = "Legend"
	_legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend_scroll.add_child(_legend)
	var clear := Button.new()
	clear.name = "ClearWaypoint"
	clear.text = "Clear waypoint"
	clear.pressed.connect(clear_waypoint)
	sidebar.add_child(clear)
	var close := Button.new()
	close.text = "Close map (M)"
	close.pressed.connect(func() -> void: _window.visible = false)
	sidebar.add_child(close)

func _refresh_legend() -> void:
	if _legend == null:
		return
	for child in _legend.get_children():
		_legend.remove_child(child)
		child.queue_free()
	var kinds: Array[String] = []
	for marker in _markers:
		var kind := _marker_kind(marker)
		if not kinds.has(kind):
			kinds.append(kind)
	kinds.sort()
	for kind in kinds:
		var toggle := CheckButton.new()
		toggle.name = "Filter_%s" % kind
		var marker_count := 0
		for marker in _markers:
			if _marker_kind(marker) == kind:
				marker_count += 1
		toggle.text = "%s  (%d)" % [_display_kind(kind), marker_count]
		toggle.button_pressed = bool(_filters.get(kind, true))
		toggle.toggled.connect(func(enabled: bool) -> void:
			_filters[kind] = enabled
			queue_redraws()
		)
		_legend.add_child(toggle)
	if kinds.is_empty():
		var empty := Label.new()
		empty.text = "No POIs discovered yet."
		_legend.add_child(empty)

func _refresh_status() -> void:
	if _status == null:
		return
	if has_waypoint():
		_status.text = "%s: tile %d, %d — shown in gold on the minimap" % [_waypoint_label, _waypoint.x, _waypoint.y]
	else:
		_status.text = "%d POIs discovered. Explore nearby terrain to reveal more." % _markers.size()

func _select_map_position(normalized: Vector2) -> void:
	var closest: Dictionary = {}
	var closest_distance := 0.018
	for marker in _visible_markers():
		var point := _tile_to_normalized(Vector2i(int(marker["x"]), int(marker["y"])))
		var distance := point.distance_to(normalized)
		if distance < closest_distance:
			closest = marker
			closest_distance = distance
	if closest.is_empty():
		set_waypoint(_normalized_to_tile(normalized), "Waypoint")
		return
	var tile := Vector2i(int(closest["x"]), int(closest["y"]))
	var label := "Cave: %s" % str(closest.get("poi_name", "Cave")) if _marker_kind(closest) == "caves" else str(closest.get("poi_name", "POI"))
	set_waypoint(tile, label)

func _visible_markers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for marker in _markers:
		if bool(_filters.get(_marker_kind(marker), true)):
			result.append(marker)
	return result

func _marker_kind(marker: Dictionary) -> String:
	return "caves" if not str(marker.get("cave_id", "")).is_empty() else "poi_%s" % str(marker.get("poi_category", "landmark"))

func _display_kind(kind: String) -> String:
	if kind == "caves":
		return "Caves"
	return kind.trim_prefix("poi_").replace("_", " ").capitalize()

func _marker_color(marker: Dictionary) -> Color:
	return Color(0.96, 0.72, 0.24) if _marker_kind(marker) == "caves" else Color(0.39, 0.72, 0.93)

func _chunk_key(chunk_coords: Vector2i) -> String:
	return "%d,%d" % [chunk_coords.x, chunk_coords.y]

func _marker_key(marker: Dictionary) -> String:
	var poi_id := str(marker.get("poi_id", ""))
	if poi_id.is_empty() or not marker.has("x") or not marker.has("y"):
		return ""
	return "%s@%d,%d" % [poi_id, int(marker["x"]), int(marker["y"])]

func _world_bounds() -> Rect2i:
	if _world_generator == null:
		return Rect2i(Vector2i.ZERO, Vector2i.ONE)
	var config := _world_generator.get_configuration()
	return Rect2i(config.world_origin_chunk * config.chunk_size_tiles,
			config.world_dimensions_chunks * config.chunk_size_tiles)

func _tile_to_normalized(tile: Vector2i) -> Vector2:
	var bounds := _world_bounds()
	return Vector2(
		clampf((float(tile.x - bounds.position.x) + 0.5) / float(bounds.size.x), 0.0, 1.0),
		clampf((float(tile.y - bounds.position.y) + 0.5) / float(bounds.size.y), 0.0, 1.0)
	)

func _normalized_to_tile(point: Vector2) -> Vector2i:
	var bounds := _world_bounds()
	return Vector2i(
		bounds.position.x + clampi(floori(point.x * bounds.size.x), 0, bounds.size.x - 1),
		bounds.position.y + clampi(floori(point.y * bounds.size.y), 0, bounds.size.y - 1)
	)

func _player_normalized() -> Vector2:
	var player_tile := _get_player_tile()
	if player_tile == INVALID_TILE:
		return Vector2(-1.0, -1.0)
	return _tile_to_normalized(player_tile)

func _get_player_tile() -> Vector2i:
	if _player == null:
		return INVALID_TILE
	var world_position := _player.get_world_position() / TILE_SIZE
	return Vector2i(floori(world_position.x), floori(world_position.y))

func _tile_in_world(tile: Vector2i) -> bool:
	return _world_bounds().has_point(tile)

func waypoint_clear_if_out_of_bounds() -> void:
	if has_waypoint() and not _tile_in_world(_waypoint):
		_waypoint = INVALID_TILE
		_waypoint_label = ""

func queue_redraws() -> void:
	if _minimap != null:
		_minimap.queue_redraw()
	if _full_map != null:
		_full_map.queue_redraw()

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.075, 0.065, 0.98)
	style.border_color = Color(0.38, 0.50, 0.38, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(7)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	style.shadow_size = 12
	return style

class MapSurface extends Control:
	var owner_map: WorldMap
	var large := false

	func _draw() -> void:
		if owner_map == null:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.10, 0.09, 0.96), true)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.58, 0.45, 0.9), false, 2.0)
		for fraction in [0.25, 0.5, 0.75]:
			draw_line(Vector2(size.x * fraction, 0), Vector2(size.x * fraction, size.y), Color(0.22, 0.32, 0.26, 0.65), 1.0)
			draw_line(Vector2(0, size.y * fraction), Vector2(size.x, size.y * fraction), Color(0.22, 0.32, 0.26, 0.65), 1.0)
		for marker in owner_map._visible_markers():
			var point := owner_map._tile_to_normalized(Vector2i(int(marker["x"]), int(marker["y"]))) * size
			var radius := 5.0 if large else 3.0
			draw_circle(point, radius, owner_map._marker_color(marker))
		if owner_map.has_waypoint():
			var waypoint := owner_map._tile_to_normalized(owner_map._waypoint) * size
			var extent := 8.0 if large else 5.0
			draw_line(waypoint + Vector2(-extent, -extent), waypoint + Vector2(extent, extent), Color(1.0, 0.92, 0.3), 2.0)
			draw_line(waypoint + Vector2(-extent, extent), waypoint + Vector2(extent, -extent), Color(1.0, 0.92, 0.3), 2.0)
		var player_point := owner_map._player_normalized()
		if player_point.x >= 0.0 and player_point.y >= 0.0:
			draw_circle(player_point * size, 4.0 if large else 3.0, Color(0.93, 0.96, 0.98))

	func _gui_input(event: InputEvent) -> void:
		if not large or owner_map == null:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var click: Vector2 = (event.position / size).clamp(Vector2.ZERO, Vector2.ONE)
			owner_map._select_map_position(click)
			accept_event()
