## Clickable, no-currency supply counter used only by Building Sandbox.
## It deliberately exposes the existing ItemDatabase rather than carrying a
## second, hand-maintained item list, so new collectible content is available
## here automatically.
class_name SandboxSupplyStore
extends Node2D

const INTERACTION_RANGE := 112.0
const CLICK_RADIUS := 34.0

var player: Player = null

signal opened

func _ready() -> void:
	name = "SandboxSupplyStore"
	queue_redraw()
	var label := Label.new()
	label.text = "SUPPLY STORE\nClick to browse"
	label.position = Vector2(-78.0, -62.0)
	label.size = Vector2(156.0, 42.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("f1e7a6"))
	label.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.03, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

func _draw() -> void:
	# A tiny, readable counter rather than a content-specific prop asset: this
	# is tooling furniture, not a new world-content type.
	draw_rect(Rect2(-26.0, -22.0, 52.0, 44.0), Color("263523"), true)
	draw_rect(Rect2(-26.0, -22.0, 52.0, 44.0), Color("b7c870"), false, 2.0)
	draw_rect(Rect2(-30.0, 16.0, 60.0, 12.0), Color("5f482d"), true)
	draw_circle(Vector2(0.0, -5.0), 8.0, Color("e0bb79"))
	draw_rect(Rect2(-10.0, -18.0, 20.0, 5.0), Color("d7a957"), true)

func _unhandled_input(event: InputEvent) -> void:
	if not visible or player == null or not is_instance_valid(player):
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if player.global_position.distance_to(global_position) > INTERACTION_RANGE:
		return
	if get_global_mouse_position().distance_to(global_position) > CLICK_RADIUS:
		return
	opened.emit()
	get_viewport().set_input_as_handled()
