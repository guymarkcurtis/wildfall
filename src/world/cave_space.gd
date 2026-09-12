## Separate generated cave-space runtime node.
## This is intentionally a lightweight placeholder space: geometry is supplied
## by CaveSpaceGenerator, while transition UX and reset/depletion policy remain
## owned by Main/save systems.
class_name CaveSpace
extends Node2D

signal exit_requested

var cave_data: Dictionary = {}
var cave_id: String = ""
var exit_position: Vector2 = Vector2.ZERO

func setup(generated_data: Dictionary) -> void:
	cave_data = generated_data.duplicate(true)
	cave_id = str(cave_data.get("cave_id", ""))
	queue_redraw()

func contains_exit(world_position: Vector2, radius: float = 64.0) -> bool:
	return world_position.distance_to(to_global(exit_position)) <= radius

func request_exit() -> void:
	exit_requested.emit()

func _draw() -> void:
	# The cave lives in its own local coordinate space around the player spawn.
	draw_rect(Rect2(-720.0, -480.0, 1440.0, 960.0), Color(0.025, 0.022, 0.02, 1.0), true)
	for tunnel in cave_data.get("tunnels", []):
		var from_point: Vector2 = Vector2(tunnel.get("from", Vector2i.ZERO)) * 32.0
		var to_point: Vector2 = Vector2(tunnel.get("to", Vector2i.ZERO)) * 32.0
		draw_line(from_point, to_point, Color(0.16, 0.14, 0.12, 1.0), float(tunnel.get("width", 2)) * 8.0)
	for room in cave_data.get("rooms", []):
		var center: Vector2 = Vector2(room.get("center", Vector2i.ZERO)) * 32.0
		var size: Vector2 = Vector2(room.get("size", Vector2i(8, 8))) * 32.0
		draw_rect(Rect2(center - size * 0.5, size), Color(0.24, 0.21, 0.18, 1.0), true)
		draw_rect(Rect2(center - size * 0.5, size), Color(0.48, 0.40, 0.30, 1.0), false, 3.0)
	for deposit in cave_data.get("resource_candidates", []):
		var deposit_position: Vector2 = Vector2(deposit.get("position", Vector2i.ZERO)) * 32.0
		var resource_seed := WorldGenerationContext.stable_string_seed(str(deposit.get("resource_id", "")))
		var color := Color.from_hsv(fposmod(float(resource_seed), 360.0) / 360.0, 0.55, 0.92)
		draw_circle(deposit_position, 8.0, color)
		draw_circle(deposit_position, 11.0, Color(color, 0.25), false, 1.5)
	draw_circle(exit_position, 14.0, Color(0.25, 0.58, 0.42, 1.0))
	draw_arc(exit_position, 18.0, 0.0, TAU, 16, Color(0.65, 0.90, 0.70, 1.0), 2.0)
