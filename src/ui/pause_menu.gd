## In-game pause overlay: continue, save/load, options, title, quit.
class_name PauseMenu
extends CanvasLayer

signal save_requested
signal load_requested(path: String)

var _root: Control = null
var _status: Label = null
var _load_button: Button = null
var _options: OptionsPanel = null
var _save_list: SaveListPanel = null

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"):
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	visible = true
	get_tree().paused = true
	_refresh()

func close() -> void:
	visible = false
	if _options:
		_options.visible = false
	if _save_list:
		_save_list.visible = false
	get_tree().paused = false

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.02, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)

	column.add_child(MenuStyle.make_label("Paused", 36, MenuStyle.TITLE))

	var continue_btn := MenuStyle.make_button("Continue")
	continue_btn.pressed.connect(close)
	column.add_child(continue_btn)

	var save_btn := MenuStyle.make_button("Save Game")
	save_btn.pressed.connect(_on_save)
	column.add_child(save_btn)

	_load_button = MenuStyle.make_button("Load Game")
	_load_button.pressed.connect(_on_load)
	column.add_child(_load_button)

	var options_btn := MenuStyle.make_button("Options")
	options_btn.pressed.connect(func() -> void: _options.open())
	column.add_child(options_btn)

	var title_btn := MenuStyle.make_button("Return to Title")
	title_btn.pressed.connect(_on_title)
	column.add_child(title_btn)

	var quit_btn := MenuStyle.make_button("Quit Game")
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	column.add_child(quit_btn)

	_status = MenuStyle.make_label("", 14, MenuStyle.MUTED)
	column.add_child(_status)

	_options = OptionsPanel.new()
	_root.add_child(_options)
	_save_list = SaveListPanel.new()
	_save_list.save_chosen.connect(_on_save_chosen)
	_root.add_child(_save_list)

func _refresh() -> void:
	_load_button.disabled = SaveSystem.list_save_entries().is_empty()
	_status.text = ""

func _on_save() -> void:
	save_requested.emit()
	_status.text = "Game saved"
	_refresh()

func _on_load() -> void:
	if SaveSystem.list_save_entries().is_empty():
		_status.text = "No save to load"
		return
	_save_list.open()

func _on_save_chosen(path: String) -> void:
	load_requested.emit(path)
	_status.text = "Game loaded"
	close()

func _on_title() -> void:
	close()
	GameSession.go_to_title(get_tree())
