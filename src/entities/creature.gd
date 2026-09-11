## Creature entity with wander / flee / chase / attack AI.
## Passive animals flee; hostile predators path toward the player and melee.
class_name Creature
extends CharacterBody2D

const TILE_SIZE: float = 32.0

enum State {
	IDLE,
	PATROL,
	FLEE,
	CHASE,
	ATTACK
}

# Creature data (filled in by setup from the CreatureDefinition)
var creature_type: String = "rabbit"
var display_name: String = "Rabbit"
var health: int = 10
var max_health: int = 10
var speed: float = 3.0  # tiles per second (CreatureDefinition schema)
var is_hostile: bool = false
var is_fish: bool = false

# State tracking
var current_state: State = State.IDLE
var target_position: Vector2 = Vector2.ZERO
var patrol_center: Vector2 = Vector2.ZERO
var patrol_radius: float = 100.0
var detection_range: float = 144.0  # pixels (tiles * TILE_SIZE)
var aggression_range: float = 96.0
var attack_damage: float = 4.0
var attack_cooldown: float = 1.2
var _attack_timer: float = 0.0
var hit_status: String = ""
var state_timer: float = 0.0

# World generator reference (sibling under Main) for water queries.
var world_generator: Node = null

# Runtime state
var _chunk_bounds: Rect2 = Rect2()
var _player_ref: Node = null
var _idle_duration: float = 2.0
# Pre-rolled per patrol leg so the state machine stays deterministic
# (re-rolling a random threshold every physics frame would not).
var _patrol_duration: float = 4.0
var _dead: bool = false
var _loot: Array[Dictionary] = []
var _loot_table: Array[Dictionary] = []

# Visual
var _body: Polygon2D = null
var _label: Label = null
var _health_bar: ProgressBar = null

# Signals
signal health_changed(current: int, max: int)
signal creature_died

## Initialize the creature from its definition. Must be called before the
## node is added to the tree (Main sets the position, calls setup, connects
## signals, then add_child — same pattern as HarvestableResource).
func setup(ctype: String, def: CreatureDefinition, chunk_coords: Vector2i, world_gen: Node) -> void:
	creature_type = def.id
	display_name = def.display_name
	health = def.health
	max_health = def.health
	speed = def.speed
	is_hostile = def.hostile
	is_fish = (ctype == "fish")
	detection_range = def.detection_range * TILE_SIZE
	aggression_range = def.aggression_range * TILE_SIZE
	attack_damage = def.attack_damage
	attack_cooldown = def.attack_cooldown
	hit_status = str(def.custom_data.get("hit_status", ""))
	patrol_radius = float(def.custom_data.get("patrol_radius", 100.0))
	_loot_table = def.loot_table
	world_generator = world_gen

	var start: Vector2i = Vector2i(chunk_coords) * 16
	_chunk_bounds = Rect2(
		float(start.x * TILE_SIZE),
		float(start.y * TILE_SIZE),
		float(CHUNK_PIXELS),
		float(CHUNK_PIXELS)
	)
	patrol_center = global_position
	_idle_duration = randf_range(1.0, 3.0)
	_setup_visuals(def)
	_setup_collision(def)

## The pixel size of one chunk (16 tiles * 32 px).
const CHUNK_PIXELS: int = 512

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	# The player is always a sibling under Main (works in the game and in
	# the headless test harness, which adds main.tscn to the tree root).
	var parent := get_parent()
	if parent:
		_player_ref = parent.get_node_or_null("Player")

## Set up the placeholder visual (a colored circle, a name label, and a
## small health bar) — same placeholder-art style as the resource nodes.
func _setup_visuals(def: CreatureDefinition) -> void:
	var size: float = float(def.custom_data.get("size", 10.0))
	# Godot 4's Circle2D is an abstract drawing primitive (it cannot be
	# instantiated), so the placeholder body is a filled Polygon2D that
	# approximates a circle.
	_body = Polygon2D.new()
	_body.polygon = _circle_points(size)
	_body.color = _get_creature_color()
	add_child(_body)

	_label = Label.new()
	_label.text = display_name
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-24.0, -size - 18.0)
	add_child(_label)

	_health_bar = ProgressBar.new()
	_health_bar.min_value = 0
	_health_bar.max_value = max_health
	_health_bar.value = health
	_health_bar.custom_minimum_size = Vector2(28, 4)
	_health_bar.position = Vector2(-14.0, -size - 10.0)
	add_child(_health_bar)

## Build the point list for a filled circle of the given radius.
func _circle_points(radius: float, segments: int = 16) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(segments):
		var angle: float = float(i) / float(segments) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

## Get color for creature type.
func _get_creature_color() -> Color:
	match creature_type:
		"rabbit":
			return Color(0.72, 0.56, 0.42)  # tan
		"deer":
			return Color(0.45, 0.3, 0.18)  # brown
		"boar":
			return Color(0.35, 0.25, 0.2)  # dark brown
		"wolf":
			return Color(0.55, 0.55, 0.58)  # gray
		"polar_bear":
			return Color(0.93, 0.95, 0.98)  # white
		"vulture":
			return Color(0.25, 0.22, 0.2)  # black
		"fish":
			return Color(0.4, 0.65, 1.0)  # blue
		_:
			return Color(0.5, 0.5, 0.5)

## Set up collision detection. Creatures ignore everything (mask 0): the
## player can walk through them and they do not clip into resource nodes.
func _setup_collision(def: CreatureDefinition) -> void:
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = max(6.0, float(def.custom_data.get("size", 10.0)))
	collision.shape = shape
	add_child(collision)

	collision_layer = 2
	collision_mask = 0

## Update creature behavior.
func _physics_process(delta: float) -> void:
	if _dead:
		return

	state_timer += delta
	_attack_timer = maxf(0.0, _attack_timer - delta)
	if _health_bar:
		_health_bar.value = health

	var player := _player_ref
	if player != null and not is_instance_valid(player):
		_player_ref = null
		player = null

	if player != null:
		var dist_to_player: float = global_position.distance_to(player.global_position)
		if dist_to_player <= detection_range:
			if is_hostile:
				current_state = State.ATTACK if dist_to_player <= 28.0 else State.CHASE
			elif current_state != State.FLEE:
				current_state = State.FLEE
				state_timer = 0.0
		elif current_state == State.FLEE or current_state == State.CHASE or current_state == State.ATTACK:
			current_state = State.PATROL
			state_timer = 0.0
			_patrol_duration = randf_range(3.0, 6.0)
			_set_patrol_target()

	match current_state:
		State.IDLE:
			_idle_behavior(delta)
		State.PATROL:
			_patrol_behavior(delta)
		State.FLEE:
			_flee_behavior(delta, player)
		State.CHASE:
			_chase_behavior(delta, player)
		State.ATTACK:
			_attack_behavior(delta, player)

## Stay still for a while, then start a patrol leg.
func _idle_behavior(_delta: float) -> void:
	velocity = Vector2.ZERO
	if state_timer > _idle_duration:
		state_timer = 0.0
		_idle_duration = randf_range(1.5, 4.0)
		_patrol_duration = randf_range(3.0, 6.0)
		current_state = State.PATROL
		_set_patrol_target()

## Walk toward the patrol target at half speed; stop when reached and drift
## back to IDLE. If the creature was pushed outside its spawn chunk (a long
## flee), steer it back first.
func _patrol_behavior(_delta: float) -> void:
	if not _chunk_bounds.grow(32.0).has_point(global_position):
		_return_to_chunk()
		return

	var dist_to_target: float = global_position.distance_to(target_position)
	if dist_to_target > 8.0:
		var direction: Vector2 = (target_position - global_position).normalized()
		velocity = direction * speed * 0.5 * TILE_SIZE
		move_and_slide()
	else:
		velocity = Vector2.ZERO

	if state_timer > _patrol_duration:
		state_timer = 0.0
		current_state = State.IDLE

## Run away from the player at 1.5x speed. Fish may not run onto land, so
## they try rotated flee directions until one stays in the water.
func _flee_behavior(_delta: float, player: Node) -> void:
	if player == null or not is_instance_valid(player):
		current_state = State.PATROL
		state_timer = 0.0
		_patrol_duration = randf_range(3.0, 6.0)
		_set_patrol_target()
		return

	var away: Vector2 = global_position - player.global_position
	if away.length() < 1.0:
		away = Vector2(1.0, 0.0)

	var direction: Vector2 = away.normalized()
	if is_fish:
		var options: Array[Vector2] = [
			away, away.rotated(0.9), away.rotated(-0.9), away.rotated(1.8)
		]
		var found_water: bool = false
		for option in options:
			var step_point: Vector2 = global_position + option.normalized() * 32.0
			if _is_water(step_point):
				direction = option.normalized()
				found_water = true
				break
		if not found_water:
			velocity = Vector2.ZERO  # boxed in: hold position
			move_and_slide()
			if not _chunk_bounds.grow(32.0).has_point(global_position):
				_return_to_chunk()
			return
	else:
		if not _chunk_bounds.grow(32.0).has_point(global_position):
			_return_to_chunk()
			return

	velocity = direction * speed * 1.5 * TILE_SIZE
	move_and_slide()

## Steer toward the player, sidestepping water for land creatures.
func _chase_behavior(_delta: float, player: Node) -> void:
	if player == null or not is_instance_valid(player):
		current_state = State.PATROL
		return
	var toward: Vector2 = player.global_position - global_position
	if toward.length() < 1.0:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var direction: Vector2 = toward.normalized()
	if not is_fish:
		var step_point: Vector2 = global_position + direction * 24.0
		if _is_water(step_point):
			var sidestep: Array[Vector2] = [direction.rotated(0.8), direction.rotated(-0.8), direction.rotated(1.6)]
			for option in sidestep:
				if not _is_water(global_position + option.normalized() * 24.0):
					direction = option.normalized()
					break
	else:
		if not _is_water(global_position + direction * 24.0):
			velocity = Vector2.ZERO
			move_and_slide()
			return
	velocity = direction * speed * 1.15 * TILE_SIZE
	move_and_slide()

## Melee the player when close enough and the cooldown is ready.
func _attack_behavior(_delta: float, player: Node) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	if player == null or not is_instance_valid(player):
		current_state = State.PATROL
		return
	var dist: float = global_position.distance_to(player.global_position)
	if dist > 32.0:
		current_state = State.CHASE
		return
	if _attack_timer > 0.0:
		return
	_attack_timer = attack_cooldown
	var target := player as Player
	if target != null and target.health_component != null:
		target.health_component.take_damage(attack_damage)
		if hit_status != "" and target.status_effects != null:
			target.status_effects.apply_effect(hit_status)

	if player != null and is_instance_valid(player):
		if global_position.distance_to(player.global_position) > detection_range * 2.0:
			current_state = State.PATROL
			state_timer = 0.0
			_patrol_duration = randf_range(3.0, 6.0)
			_set_patrol_target()

## Steer the creature back toward the center of its spawn chunk (fish return
## to their spawn point, which is always in water).
func _return_to_chunk() -> void:
	state_timer = 0.0
	_patrol_duration = randf_range(3.0, 6.0)
	if is_fish:
		target_position = patrol_center
	else:
		target_position = _chunk_bounds.position + _chunk_bounds.size * 0.5
	current_state = State.PATROL

## Pick a new patrol target: a random point within patrol_radius of the
## patrol anchor, clamped into the spawn chunk and on the right terrain
## (fish must stay in water, land creatures on land).
func _set_patrol_target() -> void:
	for _i in range(24):
		var candidate: Vector2 = _random_point_in_chunk()
		if is_fish:
			if _is_water(candidate):
				target_position = candidate
				return
		else:
			if not _is_water(candidate):
				target_position = candidate
				return
	# Fallback: hold the current anchor (never leaves its terrain).
	target_position = patrol_center

## Random point within patrol_radius of the patrol anchor, clamped into the
## spawn chunk bounds.
func _random_point_in_chunk() -> Vector2:
	var angle: float = randf() * TAU
	var distance: float = randf_range(0.0, patrol_radius)
	var point: Vector2 = patrol_center + Vector2(cos(angle), sin(angle)) * distance
	point.x = clampf(point.x, _chunk_bounds.position.x, _chunk_bounds.end.x)
	point.y = clampf(point.y, _chunk_bounds.position.y, _chunk_bounds.end.y)
	return point

## Is the given world position water? Uses the same noise the terrain
## renderer renders from (elevation < 0.3 is water).
func _is_water(world_pos: Vector2) -> bool:
	if world_generator == null or not is_instance_valid(world_generator):
		return is_fish  # assume open water if the generator is gone
	var values: Dictionary = world_generator.get_noise_values(world_pos.x, world_pos.y)
	return float(values.get("elevation", 0.5)) < 0.3

## Apply damage (from the player's interact/attack). Returns true when this
## hit killed the creature. On death the loot is rolled and creature_died is
## emitted; Main hands the loot to the inventory and frees the node.
func take_damage(amount: float) -> bool:
	if _dead or amount <= 0:
		return false

	health = maxi(0, health - int(amount))
	health_changed.emit(health, max_health)
	if _health_bar:
		_health_bar.value = health

	if health <= 0:
		_dead = true
		_roll_loot()
		creature_died.emit()
		return true

	return false

## Roll the loot table into the concrete drop list (random, at death time).
func _roll_loot() -> void:
	for entry in _loot_table:
		var chance: float = float(entry.get("chance", 1.0))
		if randf() < chance:
			var min_qty: int = int(entry.get("min_qty", 1))
			var max_qty: int = int(entry.get("max_qty", 1))
			var qty: int = randi_range(mini(min_qty, max_qty), maxi(min_qty, max_qty))
			if qty > 0:
				_loot.append({"item_id": str(entry["item_id"]), "quantity": qty})

## The rolled drop list (filled in when the creature dies).
func get_loot() -> Array[Dictionary]:
	return _loot

## Check if creature is dead.
func is_dead() -> bool:
	return _dead

## Get health ratio.
func get_health_ratio() -> float:
	if max_health <= 0:
		return 0.0
	return float(health) / float(max_health)

## Get creature type.
func get_creature_type() -> String:
	return creature_type
