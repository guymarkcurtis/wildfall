## The in-game mission journal: lists active, available, and completed
## missions with their live progress, rewards, and unmet prerequisites.
## Opened and closed with M (bus toggle_missions_ui); Escape closes it.
class_name MissionPanel
extends Control

var _mission_manager: MissionManager = null
var _window: PanelContainer = null
var _column: VBoxContainer = null
var _scroll: ScrollContainer = null
var _entries: VBoxContainer = null
var _status: Label = null

func _ready() -> void:
	anchors_preset = Control.LayoutPreset.PRESET_FULL_RECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	visible = false

## Store the manager reference and paint the initial journal.
func configure(manager: MissionManager) -> void:
	_mission_manager = manager
	if _window != null and visible:
		refresh()

## M key path: open the journal if hidden, close it if visible.
func toggle() -> void:
	if _window == null:
		return
	visible = not visible
	if visible:
		refresh()

## Optional one-line status message under the header.
func show_status(message: String) -> void:
	if _status != null:
		_status.text = message

## Escape closes the journal while it is open.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		visible = false
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	_window = PanelContainer.new()
	_window.name = "MissionWindow"
	_window.anchors_preset = Control.LayoutPreset.PRESET_CENTER
	_window.size = Vector2(640.0, 460.0)
	_window.add_theme_stylebox_override("panel", _make_style())
	add_child(_window)

	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.size_flags_horizontal = Control.SIZE_FILL
	_column.size_flags_vertical = Control.SIZE_FILL
	_column.add_theme_constant_override("separation", 10)
	_window.add_child(_column)

	var header := Label.new()
	header.text = "Missions"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 20)
	_column.add_child(header)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color(0.85, 0.87, 0.80))
	_column.add_child(_status)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_horizontal = Control.SIZE_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_child(_scroll)

	_entries = VBoxContainer.new()
	_entries.name = "Entries"
	_entries.size_flags_horizontal = Control.SIZE_FILL
	_entries.size_flags_vertical = Control.SIZE_FILL
	_entries.add_theme_constant_override("separation", 10)
	_scroll.add_child(_entries)

## Rebuild the entry list. The journal is invisible until M is pressed,
## so refreshing eagerly would waste frames on an empty window.
func refresh() -> void:
	if _entries == null or _window == null or not visible or _mission_manager == null:
		return
	for child in _entries.get_children():
		_entries.remove_child(child)
		child.queue_free()
	var active: Array = _mission_manager.get_active_missions()
	var available: Array = _mission_manager.get_available_missions()
	var completed: Array = _mission_manager.get_completed_missions()
	if active.is_empty() and available.is_empty() and completed.is_empty():
		_status.text = "No missions available right now."
		return
	_status.text = ""
	if not active.is_empty():
		_entries.add_child(_section_header("Active"))
		for mission in active:
			_entries.add_child(_make_entry(mission, true, false))
	if not available.is_empty():
		_entries.add_child(_section_header("Available"))
		for mission in available:
			_entries.add_child(_make_entry(mission, false, false))
	if not completed.is_empty():
		_entries.add_child(_section_header("Completed"))
		for mission in completed:
			_entries.add_child(_make_entry(mission, false, true))

func _section_header(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.90, 0.82, 0.55))
	return label

func _make_entry(mission: Mission, is_active: bool, is_completed: bool) -> PanelContainer:
	var entry := PanelContainer.new()
	entry.add_theme_stylebox_override("panel", _entry_style(is_active, is_completed))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	entry.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	margin.add_child(box)

	var title_mark := "✓ " if is_completed else ("◉ " if is_active else "○ ")
	var title := Label.new()
	title.text = title_mark + mission.title
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)

	var description := Label.new()
	description.text = mission.description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 12)
	description.add_theme_color_override("font_color", Color(0.78, 0.80, 0.74))
	box.add_child(description)

	if is_active and not is_completed:
		var progress_label := Label.new()
		progress_label.text = "Progress: " + _mission_manager.get_objective_display(mission.mission_id)
		progress_label.add_theme_font_size_override("font_size", 12)
		var fraction := 0.0
		if mission.objective_count > 0:
			fraction = float(mission.progress) / float(mission.objective_count)
		if fraction >= 0.5:
			progress_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55))
		else:
			progress_label.add_theme_color_override("font_color", Color(0.90, 0.55, 0.45))
		box.add_child(progress_label)

	var reward_label := Label.new()
	reward_label.text = "Reward: " + _mission_manager.get_reward_display(mission.mission_id)
	reward_label.add_theme_font_size_override("font_size", 11)
	reward_label.add_theme_color_override("font_color", Color(0.90, 0.82, 0.55))
	box.add_child(reward_label)

	if not is_active and not is_completed:
		var unmet: Array[String] = _mission_manager.get_unmet_prerequisites(mission.mission_id)
		if not unmet.is_empty():
			var requires := Label.new()
			requires.text = "Requires: " + ", ".join(unmet)
			requires.add_theme_font_size_override("font_size", 11)
			requires.add_theme_color_override("font_color", Color(0.67, 0.72, 0.62))
			box.add_child(requires)
		var accept_button := Button.new()
		accept_button.text = "Accept mission"
		accept_button.disabled = not unmet.is_empty()
		accept_button.pressed.connect(func() -> void: _mission_manager.accept_mission(mission.mission_id))
		box.add_child(accept_button)

	return entry

func _make_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.12, 0.09, 0.97)
	style.border_color = Color(0.34, 0.37, 0.28, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 6)
	return style

func _entry_style(is_active: bool, is_completed: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if is_completed:
		style.bg_color = Color(0.10, 0.14, 0.10, 0.85)
		style.border_color = Color(0.45, 0.65, 0.45, 0.6)
	elif is_active:
		style.bg_color = Color(0.13, 0.18, 0.12, 0.95)
		style.border_color = Color(0.45, 0.70, 0.40, 0.8)
	else:
		style.bg_color = Color(0.12, 0.12, 0.10, 0.9)
		style.border_color = Color(0.34, 0.37, 0.28, 0.72)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	return style
