## Base creature entity with movement, health, and AI.
class_name Creature
extends CharacterBody2D

const BASE_SPEED: float = 50.0
const DETECTION_RANGE: float = 200.0
const ATTACK_RANGE: float = 32.0
const PATROL_RANGE: float = 100.0

# Creature states
enum State {
	IDLE,
	PATROL,
	CHASE,
	ATTACK,
	FLEE
}

# Creature data
var creature_type: String = "slime"
var display_name: String = "Slime"
var health: int = 20
var max_health: int = 20
var damage: int = 2
var speed: float = BASE_SPEED
var is_hostile: bool = false
var xp_reward: int = 10

# State tracking
var current_state: State = State.IDLE
var target_position: Vector2 = Vector2.ZERO
var patrol_center: Vector2 = Vector2.ZERO
var patrol_radius: float = 50.0
var state_timer: float = 0.0
var attack_timer: float = 0.0

# Visual
var _sprite: Sprite2D = null
var _health_bar: ProgressBar = null

# Signals
signal health_changed(current: int, max: int)
signal creature_died
signal creature_spotted(player_position: Vector2)

## Initialize the creature.
func setup(creature_type: String, health: int, damage: int, is_hostile: bool, xp_reward: int) -> void:
	self.creature_type = creature_type
	self.health = health
	self.max_health = health
	self.damage = damage
	self.is_hostile = is_hostile
	self.xp_reward = xp_reward
	self.patrol_center = global_position
	_setup_visuals()
	_setup_collision()

## Set up visual representation.
func _setup_visuals() -> void:
	# Create sprite
	_sprite = Sprite2D.new()
	_sprite.position = Vector2(16, 16)
	
	var texture: ImageTexture = _get_creature_texture()
	if texture:
		_sprite.texture = texture
	else:
		# Fallback colored sprite
		var image := Image.new()
		image.create(32, 32, false, Image.FORMAT_RGBA8)
		var color := _get_creature_color()
		for y in range(32):
			for x in range(32):
				image.set_pixel(x, y, color)
		_sprite.texture = ImageTexture.create_from_image(image)
	
	add_child(_sprite)
	
	# Create health bar
	_health_bar = ProgressBar.new()
	_health_bar.min_value = 0
	_health_bar.max_value = max_health
	_health_bar.value = health
	_health_bar.custom_minimum_size = Vector2(32, 4)
	_health_bar.position = Vector2(0, -20)
	add_child(_health_bar)

## Get texture for creature type.
func _get_creature_texture() -> ImageTexture:
	var image := Image.new()
	image.create(32, 32, false, Image.FORMAT_RGBA8)
	var color := _get_creature_color()
	
	for y in range(32):
		for x in range(32):
			var pixel_color := color
			# Add simple pattern
			if (x + y) % 4 < 2:
				pixel_color = color.lerp(Color(1.0, 1.0, 1.0), 0.2)
			image.set_pixel(x, y, pixel_color)
	
	return ImageTexture.create_from_image(image)

## Get color for creature type.
func _get_creature_color() -> Color:
	match creature_type:
		"slime":
			return Color(0.3, 0.8, 0.3)  # Green
		"rat":
			return Color(0.6, 0.5, 0.4)  # Brown
		"wolf":
			return Color(0.5, 0.5, 0.5)  # Gray
		"bear":
			return Color(0.4, 0.3, 0.2)  # Brown
		"slime_poison":
			return Color(0.4, 0.8, 0.2)  # Lime
		"zombie":
			return Color(0.4, 0.6, 0.4)  # Sickly green
		"skeleton":
			return Color(0.9, 0.9, 0.8)  # White
		"slime_fire":
			return Color(0.9, 0.4, 0.2)  # Orange
		_:
			return Color(0.5, 0.5, 0.5)

## Set up collision detection.
func _setup_collision() -> void:
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 16.0
	collision.shape = shape
	add_child(collision)
	
	collision_layer = 2
	collision_mask = 0

## Update creature behavior.
func _physics_process(delta: float) -> void:
	state_timer += delta
	attack_timer += delta
	
	# Update health bar
	if _health_bar:
		_health_bar.value = health
	
	# Check for player
	var player := _get_player()
	if player:
		var dist_to_player: float = global_position.distance_to(player.global_position)
		
		if dist_to_player <= DETECTION_RANGE:
			creature_spotted.emit(player.global_position)
			
			if is_hostile and dist_to_player <= ATTACK_RANGE:
				_current_state = State.CHASE
			elif not is_hostile and dist_to_player <= DETECTION_RANGE * 0.5:
				_current_state = State.FLEE
		elif dist_to_player > DETECTION_RANGE * 2:
			_current_state = State.PATROL
	
	# Execute current state
	match _current_state:
		State.IDLE:
			_idle_behavior(delta)
		State.PATROL:
			_patrol_behavior(delta)
		State.CHASE:
			_chase_behavior(delta, player)
		State.ATTACK:
			_attack_behavior(delta, player)
		State.FLEE:
			_flee_behavior(delta, player)

## Get the player node.
func _get_player() -> Node:
	var root := get_tree().root
	var player := root.get_node_or_null("/root/Main/Player")
	return player

## Idle behavior.
func _idle_behavior(delta: float) -> void:
	if state_timer > randf_range(2.0, 5.0):
		state_timer = 0.0
		if randf() < 0.3:
			_current_state = State.PATROL
			_set_random_patrol_target()

## Patrol behavior.
func _patrol_behavior(delta: float) -> void:
	if global_position.distance_to(patrol_center) > patrol_radius:
		_current_state = State.IDLE
		state_timer = 0.0
		return
	
	var direction := (patrol_center - global_position).normalized()
	velocity = direction * speed * 0.5
	move_and_slide()
	
	if state_timer > randf_range(3.0, 6.0):
		state_timer = 0.0
		_current_state = State.IDLE

## Chase behavior.
func _chase_behavior(delta: float, player: Node) -> void:
	if not player:
		_current_state = State.IDLE
		return
	
	var direction := (player.global_position - global_position).normalized()
	velocity = direction * speed
	move_and_slide()
	
	# Check if in attack range
	if global_position.distance_to(player.global_position) <= ATTACK_RANGE:
		_current_state = State.ATTACK
		attack_timer = 0.0

## Attack behavior.
func _attack_behavior(delta: float, player: Node) -> void:
	if not player:
		_current_state = State.CHASE
		return
	
	# Face player
	if velocity.length() > 0:
		velocity = velocity.normalized()
	
	# Attack timer
	if attack_timer >= 1.0:
		attack_timer = 0.0
		_attack_player(player)
	else:
		velocity = Vector2.ZERO
		move_and_slide()

## Flee behavior.
func _flee_behavior(delta: float, player: Node) -> void:
	if not player:
		_current_state = State.PATROL
		return
	
	var direction := (global_position - player.global_position).normalized()
	velocity = direction * speed * 1.5
	move_and_slide()
	
	if global_position.distance_to(player.global_position) > DETECTION_RANGE:
		_current_state = State.PATROL

## Attack the player.
func _attack_player(player: Node) -> void:
	if player.has_method("take_damage"):
		player.take_damage(damage)

## Set a random patrol target.
func _set_random_patrol_target() -> void:
	var angle := randf() * TAU
	var distance := randf_range(20.0, patrol_radius)
	patrol_center = global_position + Vector2(cos(angle), sin(angle)) * distance

## Damage the creature.
func take_damage(amount: int) -> bool:
	if health <= 0:
		return false
	
	health = max(0, health - amount)
	health_changed.emit(health, max_health)
	
	if health <= 0:
		creature_died.emit()
		return true
	
	return false

## Get creature type.
func get_creature_type() -> String:
	return creature_type

## Get health ratio.
func get_health_ratio() -> float:
	return float(health) / float(max_health)

## Check if creature is dead.
func is_dead() -> bool:
	return health <= 0

## Get XP reward.
func get_xp_reward() -> int:
	return xp_reward

## Serialize creature data.
func serialize() -> Dictionary:
	return {
		"creature_type": creature_type,
		"position": global_position,
		"health": health,
		"max_health": max_health,
		"is_hostile": is_hostile
	}

## Deserialize creature data.
func deserialize(data: Dictionary) -> void:
	global_position = data.get("position", Vector2.ZERO)
	health = data.get("health", max_health)
	health_changed.emit(health, max_health)
