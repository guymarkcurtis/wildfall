## A lightweight world-space loot drop. The sprite follows a short two-hop
## arc, then attracts to the player when they move nearby. Inventory transfer
## remains owned by Main through collection_requested.
class_name WorldPickup
extends Node2D

signal collection_requested(item_id: String, quantity: int, pickup: WorldPickup)

const BOUNCE_DURATION := 0.68
const COLLECT_DELAY := 0.42
const MAGNET_RADIUS := 112.0
const COLLECT_RADIUS := 14.0
const MAGNET_SPEED := 300.0
const MAX_LIFETIME := 120.0

var item_id := ""
var quantity := 0
var target: Node2D = null

var _age := 0.0
var _ground_position := Vector2.ZERO
var _launch_velocity := Vector2.ZERO
var _sprite: Sprite2D = null
var _shadow: Polygon2D = null
var _quantity_label: Label = null
var _collect_cooldown := 0.0

func setup(drop_item_id: String, drop_quantity: int, pickup_target: Node2D,
		texture: Texture2D, launch_velocity: Vector2) -> void:
	item_id = drop_item_id
	quantity = maxi(1, drop_quantity)
	target = pickup_target
	_launch_velocity = launch_velocity
	_ground_position = global_position

	_shadow = Polygon2D.new()
	_shadow.polygon = PackedVector2Array([
		Vector2(-8, -3), Vector2(8, -3), Vector2(10, 0),
		Vector2(8, 3), Vector2(-8, 3), Vector2(-10, 0)
	])
	_shadow.color = Color(0.04, 0.06, 0.08, 0.28)
	_shadow.z_index = 0
	add_child(_shadow)

	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.z_index = 1
	# Tiny pickups remain legible in motion while retaining their 32px source.
	_sprite.scale = Vector2(1.15, 1.15)
	add_child(_sprite)

	if quantity > 1:
		_quantity_label = Label.new()
		_quantity_label.text = str(quantity)
		_quantity_label.position = Vector2(6, 4)
		_quantity_label.add_theme_font_size_override("font_size", 10)
		_quantity_label.add_theme_color_override("font_color", Color.WHITE)
		_quantity_label.add_theme_color_override("font_outline_color", Color(0.04, 0.06, 0.08))
		_quantity_label.add_theme_constant_override("outline_size", 3)
		_quantity_label.z_index = 2
		add_child(_quantity_label)

func _process(delta: float) -> void:
	_age += delta
	_collect_cooldown = maxf(0.0, _collect_cooldown - delta)
	if _age >= MAX_LIFETIME:
		queue_free()
		return

	if _age < BOUNCE_DURATION:
		_process_bounce(delta)
		return

	_sprite.position.y = 0.0
	_shadow.scale = Vector2.ONE
	if not is_instance_valid(target) or _age < COLLECT_DELAY:
		return
	var distance := global_position.distance_to(target.global_position)
	if distance <= COLLECT_RADIUS and _collect_cooldown <= 0.0:
		_collect_cooldown = 0.2
		collection_requested.emit(item_id, quantity, self)
	elif distance <= MAGNET_RADIUS:
		var speed := MAGNET_SPEED + (MAGNET_RADIUS - distance) * 2.0
		_ground_position = _ground_position.move_toward(target.global_position, speed * delta)
		global_position = _ground_position

func _process_bounce(delta: float) -> void:
	var progress := clampf(_age / BOUNCE_DURATION, 0.0, 1.0)
	var damping := 1.0 - progress
	_ground_position += _launch_velocity * damping * delta
	global_position = _ground_position
	var height := 0.0
	if progress < 0.68:
		height = sin((progress / 0.68) * PI) * 25.0
	else:
		height = sin(((progress - 0.68) / 0.32) * PI) * 8.0
	_sprite.position.y = -height
	var shadow_factor := clampf(1.0 - height / 60.0, 0.55, 1.0)
	_shadow.scale = Vector2(shadow_factor, shadow_factor)

## Main reports the accepted amount after applying inventory limits. A full
## inventory leaves the remainder on the ground for a later attempt.
func apply_collection(accepted_quantity: int) -> void:
	quantity = maxi(0, quantity - accepted_quantity)
	if quantity <= 0:
		queue_free()
		return
	if _quantity_label != null:
		_quantity_label.text = str(quantity)
	_collect_cooldown = 0.35

func get_bounce_height() -> float:
	return -_sprite.position.y if _sprite != null else 0.0
