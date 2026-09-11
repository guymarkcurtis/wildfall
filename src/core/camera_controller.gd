## Smooth follow camera for the orthogonal 2D top-down view.
## Supports 45° snap rotation, free middle-mouse rotate, and north-up reset.
class_name CameraController
extends Camera2D

const SNAP_RADIANS: float = PI * 0.25
const DRAG_SENSITIVITY: float = 0.008

@export var follow_speed: float = 5.0
@export var look_ahead_x: float = 0.0
@export var look_ahead_y: float = -50.0

var _target_position: Vector2 = Vector2.ZERO
var _has_target: bool = false
var _dragging: bool = false
var _rotation_locked: bool = false

func _input(event: InputEvent) -> void:
	if _rotation_locked:
		return
	if event.is_action_pressed("rotate_ccw"):
		rotate_view(-SNAP_RADIANS)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate_cw"):
		rotate_view(SNAP_RADIANS)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reset_view"):
		reset_view()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mouse.pressed
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		rotate_view(motion.relative.x * DRAG_SENSITIVITY)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not _has_target:
		return
	var t: float = 1.0 - exp(-follow_speed * delta)
	self.position = self.position.lerp(_target_position, t)

## Set the camera target (player position plus rotated look-ahead).
func set_target(target_pos: Vector2) -> void:
	var ahead: Vector2 = Vector2(look_ahead_x, look_ahead_y).rotated(rotation)
	var desired: Vector2 = target_pos + ahead
	if not _has_target or target_pos.distance_to(_target_position) > 2000.0:
		self.position = desired
	_target_position = desired
	_has_target = true

## Rotate the view by radians (positive = clockwise on screen).
func rotate_view(delta_radians: float) -> void:
	rotation = wrapf(rotation + delta_radians, -TAU, TAU)

## Snap rotation to the nearest 45° and set it to world-north up.
func reset_view() -> void:
	rotation = 0.0

## Ignore rotate input while the seed editor (or similar) owns the keyboard.
func set_rotation_locked(locked: bool) -> void:
	_rotation_locked = locked
	if locked:
		_dragging = false

## Get the camera's current target.
func get_target() -> Vector2:
	return _target_position
