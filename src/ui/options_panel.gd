## Shared options overlay (title and pause). Autosave is the first real setting.
class_name OptionsPanel
extends ColorRect

signal closed

var _checkbox: CheckButton = null

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
	if _checkbox:
		_checkbox.set_pressed_no_signal(SaveSystem.is_autosave_enabled())

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440.0, 260.0)
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
	box.add_child(MenuStyle.make_label("Options", 26, MenuStyle.TITLE))

	_checkbox = CheckButton.new()
	_checkbox.text = "Autosave every 5 minutes"
	_checkbox.add_theme_color_override("font_color", MenuStyle.TITLE)
	_checkbox.button_pressed = SaveSystem.is_autosave_enabled()
	_checkbox.toggled.connect(_on_autosave_toggled)
	box.add_child(_checkbox)

	box.add_child(MenuStyle.make_label("Keeps the last 2 autosaves. Manual saves are unlimited.", 13, MenuStyle.MUTED))

	var back := MenuStyle.make_button("Back", 160.0)
	back.pressed.connect(_on_back)
	box.add_child(back)

func _on_autosave_toggled(enabled: bool) -> void:
	SaveSystem.set_autosave_enabled(enabled)

func _on_back() -> void:
	visible = false
	closed.emit()
