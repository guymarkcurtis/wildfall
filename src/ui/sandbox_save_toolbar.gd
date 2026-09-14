## Collapsible bottom-left control drawer for Building Sandbox. The quiet
## button keeps the test yard unobstructed; its expanded drawer holds time and
## sandbox-only save controls when the tester needs them.
class_name SandboxSaveToolbar
extends Control

var _main: Node = null
var _toggle: Button = null
var _drawer: PanelContainer = null
var _picker: OptionButton = null
var _time_picker: OptionButton = null
var _load_button: Button = null
var _delete_button: Button = null
var _status: Label = null
var _expanded := false

const TIME_OPTIONS := [
	{"label": "Dawn  •  6:00 AM", "hour": 6.0},
	{"label": "Morning  •  9:00 AM", "hour": 9.0},
	{"label": "Noon  •  12:00 PM", "hour": 12.0},
	{"label": "Afternoon  •  3:00 PM", "hour": 15.0},
	{"label": "Dusk  •  7:00 PM", "hour": 19.0},
	{"label": "Night  •  10:00 PM", "hour": 22.0}
]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_apply_layout()

func configure(main: Node) -> void:
	_main = main
	visible = GameSession.is_building_sandbox()
	refresh()

func refresh(select_path: String = "") -> void:
	if _picker == null:
		return
	_picker.clear()
	var entries := _sandbox_entries()
	for entry in entries:
		var path := str(entry.get("path", ""))
		_picker.add_item("%s  •  seed %d  •  day %d" % [str(entry.get("when", "")), int(entry.get("seed", 0)), int(entry.get("day", 1))])
		_picker.set_item_metadata(_picker.item_count - 1, path)
		if path == select_path:
			_picker.select(_picker.item_count - 1)
	var has_entries := not entries.is_empty()
	_picker.disabled = not has_entries
	_load_button.disabled = not has_entries
	_delete_button.disabled = not has_entries
	if has_entries and _status.text.is_empty():
		_status.text = "%d sandbox save%s" % [entries.size(), "" if entries.size() == 1 else "s"]
	elif not has_entries:
		_status.text = "No sandbox save yet"
	_sync_time_picker()

func _build() -> void:
	_toggle = MenuStyle.make_button("Sandbox  ▾", 144.0)
	_toggle.custom_minimum_size = Vector2(144.0, 34.0)
	_toggle.pressed.connect(_toggle_drawer)
	add_child(_toggle)

	_drawer = PanelContainer.new()
	_drawer.size = Vector2(430.0, 160.0)
	_drawer.visible = false
	_drawer.add_theme_stylebox_override("panel", _panel_style())
	add_child(_drawer)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	_drawer.add_child(box)
	var title := Label.new()
	title.text = "BUILDING SANDBOX"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", MenuStyle.TITLE)
	box.add_child(title)
	box.add_child(MenuStyle.make_label("Lighting is paused. Choose a time, then save or restore a layout.", 11, MenuStyle.MUTED))
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 8)
	box.add_child(time_row)
	var time_label := Label.new()
	time_label.text = "Time of day"
	time_label.custom_minimum_size = Vector2(95.0, 30.0)
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_label.add_theme_color_override("font_color", MenuStyle.TITLE)
	time_row.add_child(time_label)
	_time_picker = OptionButton.new()
	_time_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_picker.custom_minimum_size = Vector2(250.0, 30.0)
	for option in TIME_OPTIONS:
		_time_picker.add_item(str(option["label"]))
		_time_picker.set_item_metadata(_time_picker.item_count - 1, float(option["hour"]))
	_time_picker.item_selected.connect(_on_time_selected)
	time_row.add_child(_time_picker)
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 7)
	box.add_child(save_row)
	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.custom_minimum_size = Vector2(220.0, 30.0)
	save_row.add_child(_picker)
	var save := MenuStyle.make_button("Save", 62.0)
	save.custom_minimum_size = Vector2(62.0, 30.0)
	save.pressed.connect(_on_save)
	save_row.add_child(save)
	_load_button = MenuStyle.make_button("Load", 62.0)
	_load_button.custom_minimum_size = Vector2(62.0, 30.0)
	_load_button.pressed.connect(_on_load)
	save_row.add_child(_load_button)
	_delete_button = MenuStyle.make_button("Delete", 70.0)
	_delete_button.custom_minimum_size = Vector2(70.0, 30.0)
	_delete_button.pressed.connect(_on_delete)
	save_row.add_child(_delete_button)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", MenuStyle.MUTED)
	box.add_child(_status)

func _toggle_drawer() -> void:
	_expanded = not _expanded
	_apply_layout()
	_toggle.text = "Sandbox  ▴" if _expanded else "Sandbox  ▾"
	if _expanded:
		refresh(_selected_path())

func _apply_layout() -> void:
	if _expanded:
		offset_left = 12.0
		offset_top = -214.0
		offset_right = 442.0
		offset_bottom = -12.0
		_toggle.position = Vector2(0.0, 168.0)
		_drawer.position = Vector2.ZERO
		_drawer.visible = true
	else:
		offset_left = 12.0
		offset_top = -46.0
		offset_right = 156.0
		offset_bottom = -12.0
		_toggle.position = Vector2.ZERO
		_drawer.visible = false

func _on_time_selected(index: int) -> void:
	if _main == null or index < 0:
		return
	_main.set_sandbox_time(float(_time_picker.get_item_metadata(index)))
	_status.text = "Time set to %s and paused" % _time_picker.get_item_text(index)

func _sync_time_picker() -> void:
	if _time_picker == null or _main == null:
		return
	var day_night: DayNightCycle = _main.get_node_or_null("DayNightCycle") as DayNightCycle
	if day_night == null:
		return
	var hour := day_night.get_current_hour()
	var closest_index := 0
	var closest_distance := INF
	for index in range(_time_picker.item_count):
		var distance := absf(hour - float(_time_picker.get_item_metadata(index)))
		if distance < closest_distance:
			closest_distance = distance
			closest_index = index
	_time_picker.select(closest_index)

func _on_save() -> void:
	if _main == null:
		return
	if _main.save_game():
		var path := SaveSystem.most_recent_save_path_for_mode(GameSession.MODE_BUILDING_SANDBOX)
		_status.text = "Saved sandbox layout"
		refresh(path)

func _on_load() -> void:
	var path := _selected_path()
	if path.is_empty() or _main == null:
		return
	if _main.load_game(path):
		_status.text = "Loaded sandbox layout"
		refresh(path)

func _on_delete() -> void:
	var path := _selected_path()
	if path.is_empty() or _main == null:
		return
	var save_system := _main.get_node_or_null("SaveSystem") as SaveSystem
	if save_system != null and save_system.delete_save(path):
		_status.text = "Deleted sandbox save"
		refresh()
	else:
		_status.text = "Could not delete that save"

func _selected_path() -> String:
	if _picker == null or _picker.selected < 0:
		return ""
	return str(_picker.get_item_metadata(_picker.selected))

func _sandbox_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for entry in SaveSystem.list_save_entries():
		if str(entry.get("game_mode", GameSession.MODE_SURVIVAL)) == GameSession.MODE_BUILDING_SANDBOX:
			entries.append(entry)
	return entries

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.038, 0.94)
	style.border_color = Color(0.42, 0.52, 0.27, 0.92)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
