## Shared look for title / pause / options menus.
class_name MenuStyle
extends RefCounted

const BG := Color(0.07, 0.09, 0.07, 0.94)
const PANEL := Color(0.10, 0.13, 0.10, 0.96)
const TITLE := Color(0.88, 0.90, 0.72)
const MUTED := Color(0.62, 0.66, 0.55)
const BUTTON_BG := Color(0.16, 0.22, 0.16)
const BUTTON_HOVER := Color(0.24, 0.34, 0.22)
const BUTTON_DISABLED := Color(0.14, 0.16, 0.14)

static func make_button(text: String, width: float = 280.0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 44.0)
	var style := StyleBoxFlat.new()
	style.bg_color = BUTTON_BG
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 12
	style.content_margin_right = 12
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = BUTTON_HOVER
	var disabled := style.duplicate() as StyleBoxFlat
	disabled.bg_color = BUTTON_DISABLED
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", TITLE)
	button.add_theme_color_override("font_disabled_color", MUTED)
	return button

static func make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
