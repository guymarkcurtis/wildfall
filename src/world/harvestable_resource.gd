## Interactive resource node that can be harvested.
class_name HarvestableResource
extends Area2D

const DEFAULT_HITBOX_RADIUS: float = 16.0

# Resource data
var resource_type: String = ""
var display_name: String = ""
var max_health: float = 10.0
var current_health: float = 10.0
var yield_items: Array[Dictionary] = []

# State
var is_destroyed: bool = false
var is_highlighted: bool = false

# Visual
var _sprite: Sprite2D = null
static var _texture_cache: Dictionary = {}

# Signals
signal health_changed(current: float, max: float)
signal resource_destroyed(item_id: String, quantity: int)
signal resource_hurt(amount: float)

## Initialize the resource.
func setup(resource_type: String, health: float, yields: Array[Dictionary]) -> void:
	self.resource_type = resource_type
	self.max_health = health
	self.current_health = health
	self.yield_items = yields.duplicate()
	display_name = _get_display_name(resource_type)
	_setup_visuals()
	_setup_collision()

## Set up visual representation.
func _setup_visuals() -> void:
	# Create sprite based on resource type
	_sprite = Sprite2D.new()
	
	var texture: ImageTexture = _get_resource_texture()
	if texture:
		_sprite.texture = texture
		_sprite.position = Vector2(16, 16)
	else:
		# Fallback: create a simple colored circle texture
		_sprite = _create_fallback_sprite()
	
	add_child(_sprite)
	
	# Add collision shape
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = DEFAULT_HITBOX_RADIUS
	collision.shape = shape
	add_child(collision)
	
	collision_layer = 1
	collision_mask = 0

## Get texture for resource type.
func _get_resource_texture() -> ImageTexture:
	if _texture_cache.has(resource_type):
		return _texture_cache[resource_type]
	var generator: Node = load("res://src/world/tile_set_generator.gd").new()
	var texture: ImageTexture = null
	
	match resource_type:
		"tree":
			texture = generator.call("_create_tree_texture")
		"rock":
			texture = generator.call("_create_rock_texture")
		"fibre":
			texture = generator.call("_create_fibre_texture")
		"berry_bush":
			texture = generator.call("_create_berry_texture")
		"iron_ore":
			texture = generator.call("_create_iron_ore_texture")
		"coal":
			texture = generator.call("_create_coal_texture")
		"gold_ore":
			texture = generator.call("_create_gold_ore_texture")
	
	if texture != null:
		_texture_cache[resource_type] = texture
	return texture

## Create a fallback colored sprite.
func _create_fallback_sprite() -> Sprite2D:
	var image := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	var color: Color = _get_resource_color()
	for y in range(32):
		for x in range(32):
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = Vector2(16, 16)
	return sprite

## Get color for resource type.
func _get_resource_color() -> Color:
	match resource_type:
		"tree": return Color(0.2, 0.6, 0.2)
		"rock": return Color(0.5, 0.5, 0.5)
		"fibre": return Color(0.6, 0.5, 0.3)
		"berry_bush": return Color(0.3, 0.7, 0.3)
		"iron_ore": return Color(0.4, 0.4, 0.4)
		"coal": return Color(0.2, 0.2, 0.2)
		"gold_ore": return Color(0.9, 0.7, 0.2)
		"plant": return Color(0.4, 0.75, 0.35)
		_: return Color(0.5, 0.5, 0.5)

## Set up collision detection.
func _setup_collision() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

## Check if a body is the player.
func _is_player(body: Node) -> bool:
	return body is CharacterBody2D and body.has_method("get_world_position")

## Handle body entering area.
func _on_body_entered(body: Node) -> void:
	if _is_player(body) and not is_destroyed:
		_highlight()

## Handle body leaving area.
func _on_body_exited(body: Node) -> void:
	if _is_player(body):
		_unhighlight()

## Highlight the resource.
func _highlight() -> void:
	is_highlighted = true
	if _sprite:
		_sprite.modulate = Color(1.0, 1.0, 0.8, 1.0)

## Unhighlight the resource.
func _unhighlight() -> void:
	is_highlighted = false
	if _sprite:
		_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

## Damage the resource. Returns true if destroyed.
func damage(amount: float, tool: String = "") -> bool:
	if is_destroyed or amount <= 0:
		return false

	current_health = max(0.0, current_health - amount)
	resource_hurt.emit(amount)
	health_changed.emit(current_health, max_health)

	if current_health <= 0:
		return destroy()
	return false

## Destroy the resource and yield items.
func destroy() -> bool:
	if is_destroyed:
		return false

	is_destroyed = true

	# Emit yields first, then queue the node for freeing. (Godot 4 defers
	# the actual free to the end of the frame, but this ordering keeps the
	# node fully alive while handlers process its yields.)
	for yield_entry in yield_items:
		var item_id: String = yield_entry["item_id"]
		var min_qty: int = yield_entry.get("min_qty", 1)
		var max_qty: int = yield_entry.get("max_qty", 1)
		var chance: float = yield_entry.get("chance", 1.0)

		if randf() < chance:
			var qty: int = randi() % (max_qty - min_qty + 1) + min_qty
			resource_destroyed.emit(item_id, qty)

	queue_free()
	return true

## Get remaining health ratio.
func get_health_ratio() -> float:
	return clamp(current_health / max_health, 0.0, 1.0)

## Get the resource type.
func get_resource_type() -> String:
	return resource_type

## Get the yield items.
func get_yields() -> Array[Dictionary]:
	return yield_items.duplicate()

## Check if resource is destroyed.
func is_destroyed_check() -> bool:
	return is_destroyed

## Get display name for resource type.
func _get_display_name(resource_type: String) -> String:
	match resource_type:
		"tree": return "Tree"
		"rock": return "Rock"
		"fibre": return "Fibre Bundle"
		"berry_bush": return "Berry Bush"
		"iron_ore": return "Iron Ore Deposit"
		"coal": return "Coal Deposit"
		"gold_ore": return "Gold Ore Deposit"
		"plant": return "Plant"
		_: return resource_type.capitalize()
