## Smooth follow camera for the isometric/2D perspective.
class_name CameraController
extends Camera2D

@export var follow_speed: float = 5.0
@export var look_ahead_x: float = 0.0
@export var look_ahead_y: float = -50.0

var _target_position: Vector2 = Vector2.ZERO

func _process(_delta: float) -> void:
	# Smoothly follow the target (set by game manager or player)
	position = position.lerp(_target_position, follow_speed * 0.016)

## Set the camera target position.
func set_target(position: Vector2) -> void:
	_target_position = position + Vector2(look_ahead_x, look_ahead_y)

## Get the camera's current target.
func get_target() -> Vector2:
	return _target_position
