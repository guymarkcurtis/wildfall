## Smooth follow camera for the orthogonal 2D top-down view.
class_name CameraController
extends Camera2D

@export var follow_speed: float = 5.0
@export var look_ahead_x: float = 0.0
@export var look_ahead_y: float = -50.0

var _target_position: Vector2 = Vector2.ZERO
var _has_target: bool = false

func _process(delta: float) -> void:
	if not _has_target:
		return
	# Frame-rate-independent damping: the same follow_speed behaves the
	# same at 30 FPS and 144 FPS (lerp(x, follow_speed * delta) would not).
	var t: float = 1.0 - exp(-follow_speed * delta)
	position = position.lerp(_target_position, t)

## Set the camera target position (the player's position, plus look-ahead).
func set_target(position: Vector2) -> void:
	var desired: Vector2 = position + Vector2(look_ahead_x, look_ahead_y)
	# Snap across large jumps (a world regeneration teleports the player
	# back to the origin) instead of gliding half the map.
	if not _has_target or position.distance_to(_target_position) > 2000.0:
		position = desired
	_target_position = desired
	_has_target = true

## Get the camera's current target.
func get_target() -> Vector2:
	return _target_position
