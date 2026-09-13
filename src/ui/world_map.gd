## Lightweight finite-world map: an always-visible minimap plus a filterable
## full-screen POI map. Markers are deterministic generator candidates, not a
## record of which chunks happen to be loaded.
class_name WorldMap
extends Control

const TILE_SIZE := 32.0
const INVALID_TILE := Vector2i(999999999, 999999999)
const MARKER_SCAN_BUDGET_MSEC := 2.0

var _world_generator: WorldGenerator = null
var _player: Player = null
var _markers: Array[Dictionary] = []
var _filters: Dictionary = {}
var _marker_seed := -1
var _waypoint := INVALID_TILE
var _waypoint_label := ""
## The maps use tile-level positions, so redrawing only when this changes
## preserves their visual behaviour without issuing canvas work every frame.
var _last_player_tile := INVALID_TILE
var _marker_scan_queue: Array[Dictionary] = []
var _marker_scan_index := 0
var _marker_scan_active := false

var _minimap: MapSurface
var _window: PanelContainer
var _full_map: MapSurface
var _legend: VBoxContainer
var _status: Label

signal waypoint_changed(tile: Vector2i, label: String)

func _ready() -> void:
	anchors_preset = Control.LayoutPreset.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_minimap()
	_build_full_map()

func configure(generator: WorldGenerator, player_ref: Player) -> void:
	_world_generator = generator
	_player = player_ref
	_last_player_tile = INVALID_TILE
	queue_redraws()

## Invalidate candidates on a seed swap. The next map interaction regenerates
## the small, anchor-only snapshot lazily, so re-seeding does not build an
## entire-world map during the gameplay-critical frame.
func set_world_seed(seed: int) -> void:
	if _marker_seed == seed:
		return
	_marker_seed = -1
	_markers.clear()
	_filters.clear()
	_marker_scan_queue.clear()
	_marker_scan_index = 0
	_marker_scan_active = false
	if has_waypoint():
		clear_waypoint()
	queue_redraws()

func toggle() -> void:
	if _window == null:
		return
	_window.visible = not _window.visible
	if _window.visible:
		_begin_marker_scan()
		if not _marker_scan_active:
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
	_ensure_markers()
	return _visible_markers().size()

func get_cave_marker_count() -> int:
	_ensure_markers()
	var count := 0
	for marker in _markers:
		if _marker_kind(marker) == "caves":
			count += 1
	return count

func set_marker_filter(kind: String, enabled: bool) -> void:
	_ensure_markers()
	if not _filters.has(kind):
		return
	_filters[kind] = enabled
	_refresh_legend()
	queue_redraws()

func is_marker_filter_enabled(kind: String) -> bool:
	_ensure_markers()
	return bool(_filters.get(kind, false))

func _process(_delta: float) -> void:
	_process_marker_scan()
	# Both maps render the player at tile precision. Avoid recreating visible
	# marker lists and issuing canvas redraws every frame while the player is
	# stationary within a tile; waypoint and filter changes redraw explicitly.
	var player_tile := _get_player_tile()
	if player_tile != _last_player_tile:
		_last_player_tile = player_tile
		queue_redraws()

func _begin_marker_scan() -> void:
	if _world_generator == null or _marker_seed == _world_generator.get_seed() or _marker_scan_active:
		return
	_markers.clear()
	_filters.clear()
	_marker_scan_queue = _world_generator.get_map_poi_anchor_requests()
	_marker_scan_index = 0
	_marker_scan_active = true

func _process_marker_scan() -> void:
	if not _marker_scan_active or _world_generator == null:
		return
	var started_usec := Time.get_ticks_usec()
	while _marker_scan_index < _marker_scan_queue.size():
		var request: Dictionary = _marker_scan_queue[_marker_scan_index]
		_marker_scan_index += 1
		var candidate := _world_generator.get_map_poi_candidate(str(request["poi_id"]), request["tile"])
		if not candidate.is_empty():
			_markers.append(candidate)
			var kind := _marker_kind(candidate)
			if not _filters.has(kind):
				_filters[kind] = true
		if float(Time.get_ticks_usec() - started_usec) / 1000.0 >= MARKER_SCAN_BUDGET_MSEC:
			break
	if _marker_scan_index >= _marker_scan_queue.size():
		_marker_scan_active = false
		_marker_seed = _world_generator.get_seed()
		_marker_scan_queue.clear()
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
	_window = PanelContainer.new()
	_window.name = "MapWindow"
	_window.set_anchors_preset(Control.LayoutPreset.PRESET_CENTER)
	_window.size = Vector2(960.0, 620.0)
	_window.add_theme_stylebox_override("panel", _panel_style())
	_window.visible = false
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_window)

	var column := VBoxContainer.new()
	column.name = "Column"
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
	_legend = VBoxContainer.new()
	_legend.name = "Legend"
	_legend.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(_legend)
	var clear := Button.new()
	clear.name = "ClearWaypoint"
	clear.text = "Clear waypoint"
	clear.pressed.connect(clear_waypoint)
	sidebar.add_child(clear)
	var close := Button.new()
	close.text = "Close map (M)"
	close.pressed.connect(func() -> void: _window.visible = false)
	sidebar.add_child(close)

func _ensure_markers() -> void:
	if _world_generator == null:
		return
	var seed := _world_generator.get_seed()
	if _marker_seed == seed:
		return
	# Synchronous callers (tests/tools) deliberately request a complete
	# snapshot; cancel any partially evaluated UI scan so results cannot be
	# appended twice afterward.
	_marker_scan_active = false
	_marker_scan_queue.clear()
	_marker_scan_index = 0
	_markers = _world_generator.get_map_poi_candidates()
	_marker_seed = seed
	for marker in _markers:
		var kind := _marker_kind(marker)
		if not _filters.has(kind):
			_filters[kind] = true

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
		empty.text = "No POIs for this seed."
		_legend.add_child(empty)

func _refresh_status() -> void:
	if _status == null:
		return
	if _marker_scan_active:
		_status.text = "Scanning points of interest… %d%%" % int(100.0 * float(_marker_scan_index)
				/ float(maxi(1, _marker_scan_queue.size())))
		return
	if has_waypoint():
		_status.text = "%s: tile %d, %d — shown in gold on the minimap" % [_waypoint_label, _waypoint.x, _waypoint.y]
	else:
		_status.text = "Select a visible point of interest, or click the map to place a waypoint."

func _select_map_position(normalized: Vector2) -> void:
	if _marker_scan_active:
		return
	_ensure_markers()
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
