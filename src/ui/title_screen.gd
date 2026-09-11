## Boot menu: New Game, Load Game, Options, Quit.
class_name TitleScreen
extends Control

var _load_button: Button = null
var _status: Label = null
var _options: OptionsPanel = null
var _save_list: SaveListPanel = null
var _mode_panel: ColorRect = null

func _ready() -> void:
	_build_ui()
	_refresh_load_button()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = MenuStyle.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)

	column.add_child(MenuStyle.make_label("WILDFALL", 56, MenuStyle.TITLE))
	column.add_child(MenuStyle.make_label("A persistent wilderness", 18, MenuStyle.MUTED))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	column.add_child(spacer)

	var new_btn := MenuStyle.make_button("New Game")
	new_btn.pressed.connect(_on_new_game)
	column.add_child(new_btn)
	new_btn.grab_focus()

	_load_button = MenuStyle.make_button("Load Game")
	_load_button.pressed.connect(_on_load_game)
	column.add_child(_load_button)

	var options_btn := MenuStyle.make_button("Options")
	options_btn.pressed.connect(func() -> void: _options.open())
	column.add_child(options_btn)

	var quit_btn := MenuStyle.make_button("Quit Game")
	quit_btn.pressed.connect(_on_quit)
	column.add_child(quit_btn)

	_status = MenuStyle.make_label("", 14, MenuStyle.MUTED)
	column.add_child(_status)
	column.add_child(MenuStyle.make_label("v0.1.0", 12, MenuStyle.MUTED))

	_options = OptionsPanel.new()
	add_child(_options)
	_save_list = SaveListPanel.new()
	_save_list.save_chosen.connect(_on_save_chosen)
	add_child(_save_list)
	_mode_panel = _make_mode_panel()
	add_child(_mode_panel)

func _refresh_load_button() -> void:
	var entries: Array[Dictionary] = SaveSystem.list_save_entries()
	_load_button.disabled = entries.is_empty()
	if entries.is_empty():
		_status.text = "No saves yet"
	else:
		_status.text = "%d save%s" % [entries.size(), "" if entries.size() == 1 else "s"]

func _on_new_game() -> void:
	_mode_panel.visible = true

func _start_new_game(mode: String) -> void:
	GameSession.request_new_game(mode)
	GameSession.go_to_game(get_tree())

func _make_mode_panel() -> ColorRect:
	var overlay := ColorRect.new()
	overlay.name = "ModeSelect"
	overlay.color = Color(0.0, 0.0, 0.0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
	overlay.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420.0, 320.0)
	var style := StyleBoxFlat.new()
	style.bg_color = MenuStyle.PANEL
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(MenuStyle.make_label("Choose Mode", 26, MenuStyle.TITLE))
	box.add_child(MenuStyle.make_label("Locked for that world once you start.", 14, MenuStyle.MUTED))

	var survival := MenuStyle.make_button("Survival")
	survival.pressed.connect(func() -> void: _start_new_game(GameSession.MODE_SURVIVAL))
	box.add_child(survival)
	box.add_child(MenuStyle.make_label("Gather, hunt, and watch for predators.", 13, MenuStyle.MUTED))

	var creative := MenuStyle.make_button("Creative")
	creative.pressed.connect(func() -> void: _start_new_game(GameSession.MODE_CREATIVE))
	box.add_child(creative)
	box.add_child(MenuStyle.make_label("Free crafting. Wildlife stays peaceful. You can still die.", 13, MenuStyle.MUTED))

	var back := MenuStyle.make_button("Back", 160.0)
	back.pressed.connect(func() -> void: overlay.visible = false)
	box.add_child(back)
	return overlay

func _on_load_game() -> void:
	if SaveSystem.list_save_entries().is_empty():
		_status.text = "No save to load"
		return
	_save_list.open()

func _on_save_chosen(path: String) -> void:
	GameSession.request_load_game(path)
	GameSession.go_to_game(get_tree())

func _on_quit() -> void:
	get_tree().quit()
