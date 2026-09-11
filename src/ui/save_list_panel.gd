## Load-game list: manual saves and autosaves, newest first.
class_name SaveListPanel
extends ColorRect

signal save_chosen(path: String)
signal closed

var _list: VBoxContainer = null
var _empty: Label = null

func _ready() -> void:
	color = Color(0.0, 0.0, 0.0, 0.55)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

func open() -> void:
	visible = true
	refresh()

func refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	var entries: Array[Dictionary] = SaveSystem.list_save_entries()
	_empty.visible = entries.is_empty()
	for entry in entries:
		_list.add_child(_make_row(entry))

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680.0, 460.0)
	var style := StyleBoxFlat.new()
	style.bg_color = MenuStyle.PANEL
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(MenuStyle.make_label("Load Game", 26, MenuStyle.TITLE))
	box.add_child(MenuStyle.make_label("Manual saves and autosaves", 14, MenuStyle.MUTED))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620.0, 280.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	_empty = MenuStyle.make_label("No saves yet", 16, MenuStyle.MUTED)
	box.add_child(_empty)

	var back := MenuStyle.make_button("Back", 160.0)
	back.pressed.connect(_on_back)
	box.add_child(back)

func _make_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var kind: String = str(entry.get("kind", "manual"))
	var tag := MenuStyle.make_label("AUTOSAVE" if kind == "autosave" else "SAVE", 12, MenuStyle.TITLE)
	tag.custom_minimum_size = Vector2(90.0, 0)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(tag)

	var mode: String = GameSession.mode_label(str(entry.get("game_mode", GameSession.MODE_SURVIVAL)))
	var text := "%s    %s    seed %d    day %d" % [
		str(entry.get("when", "")),
		mode,
		int(entry.get("seed", 0)),
		int(entry.get("day", 1))
	]
	var info := MenuStyle.make_label(text, 14, MenuStyle.MUTED)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var load_btn := MenuStyle.make_button("Load", 90.0)
	load_btn.custom_minimum_size = Vector2(90.0, 36.0)
	var path: String = str(entry.get("path", ""))
	load_btn.pressed.connect(func() -> void:
		if path != "":
			save_chosen.emit(path)
	)
	row.add_child(load_btn)
	return row

func _on_back() -> void:
	visible = false
	closed.emit()
