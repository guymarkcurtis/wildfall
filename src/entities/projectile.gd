## Simple hitscan-style arrow projectile for mouse-aimed ranged combat.
class_name Projectile
extends Area2D

const SPEED: float = 420.0
const MAX_DISTANCE: float = 420.0
const RADIUS: float = 4.0

var _direction: Vector2 = Vector2.RIGHT
var _damage: float = 6.0
var _traveled: float = 0.0
var _spent: bool = false

func setup(origin: Vector2, direction: Vector2, damage: float) -> void:
	global_position = origin
	_direction = direction.normalized()
	if _direction == Vector2.ZERO:
		_direction = Vector2.RIGHT
	_damage = damage
	rotation = _direction.angle()
	_setup_visuals()
	_setup_collision()
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

func _setup_visuals() -> void:
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(8.0, 0.0), Vector2(-6.0, -3.5), Vector2(-6.0, 3.5)
	])
	body.color = Color(0.82, 0.62, 0.28)
	add_child(body)

func _setup_collision() -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)
	collision_layer = 8
	collision_mask = 2
	monitoring = true
	monitorable = false

func _physics_process(delta: float) -> void:
	if _spent:
		return
	var step: Vector2 = _direction * SPEED * delta
	global_position += step
	_traveled += step.length()
	if _traveled >= MAX_DISTANCE:
		_spent = true
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	_try_hit(area)

func _on_body_entered(body: Node) -> void:
	_try_hit(body)

func _try_hit(node: Node) -> void:
	if _spent:
		return
	var creature := node as Creature
	if creature == null:
		creature = node.get_parent() as Creature
	if creature == null or creature.is_dead():
		return
	_spent = true
	creature.take_damage(_damage)
	queue_free()
