## Building Sandbox tutorial card: a small top-right panel shown when the
## sandbox starts. Every row is authored in
## data/sandbox/sandbox_tutorial_card.tres — this script only lays the rows
## out, so teaching a new concept is a data-only change.
class_name SandboxTutorialCardPanel
extends Control

const DATA_PATH := "res://data/sandbox/sandbox_tutorial_card.tres"
const CARD_WIDTH := 420.0
const CARD_MARGIN := 12.0

var _window: Panel = null
var _close_button: Button = null
var _heading_labels: Array[Label] = []
var _card: SandboxTutorialCard = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = load(DATA_PATH) as SandboxTutorialCard
	if _card == null or _card.lines.is_empty():
		visible = false
		return
	_build_card()

## Re-shows the card (used by the Sandbox drawer's "?" button).
func open_card() -> void:
	visible = true

## The row headings in display order; tests compare this against the data
## resource so the card can never silently drop a topic.
func heading_labels() -> Array[String]:
	var labels: Array[String] = []
	for label in _heading_labels:
		if label != null:
			labels.append(label.text)
	return labels

func _build_card() -> void:
	_window = Panel.new()
	_window.size = Vector2(CARD_WIDTH, 480.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.07, 0.97)
	style.border_color = Color(0.35, 0.42, 0.35, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	_window.add_theme_stylebox_override("panel", style)
	add_child(_window)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(12, 10)
	vbox.size = Vector2(CARD_WIDTH - 24, 460.0)
	vbox.add_theme_constant_override("separation", 5)
	_window.add_child(vbox)

	var title := Label.new()
	title.text = _card.title
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", MenuStyle.TITLE)
	vbox.add_child(title)

	for heading in _card.lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		vbox.add_child(row)

		var heading_label := Label.new()
		heading_label.text = str(heading)
		heading_label.custom_minimum_size = Vector2(128, 0)
		heading_label.add_theme_font_size_override("font_size", 12)
		heading_label.add_theme_color_override("font_color", MenuStyle.TITLE)
		row.add_child(heading_label)
		_heading_labels.append(heading_label)

		var detail := Label.new()
		detail.text = str(_card.lines[heading])
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		detail.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.custom_minimum_size = Vector2(262, 0)
		detail.add_theme_font_size_override("font_size", 11)
		detail.add_theme_color_override("font_color", MenuStyle.MUTED)
		row.add_child(detail)

	var footer := Label.new()
	footer.text = "X dismisses this card — reopen it from the Sandbox drawer."
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", MenuStyle.MUTED)
	vbox.add_child(footer)

	_close_button = MenuStyle.make_button("X", 26.0)
	_close_button.custom_minimum_size = Vector2(26.0, 26.0)
	_close_button.position = Vector2(CARD_WIDTH - 12 - 26, 10)
	_close_button.tooltip_text = "Close the tutorial card"
	_close_button.pressed.connect(_on_close_pressed)
	_window.add_child(_close_button)

func _on_close_pressed() -> void:
	visible = false
