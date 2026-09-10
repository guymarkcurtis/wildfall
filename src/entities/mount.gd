## Base class for all mountable animals.
class_name Mount
extends CharacterBody2D

# Mount types
enum MountType {
	HORSE,
	CAMEL,
	WOLF,
	BIRD,
	BISON,
	BOAR
}

# Mount data
var mount_type: MountType = MountType.HORSE
var mount_id: String = "horse"
var display_name: String = "Horse"
var speed: float = 150.0
var health: int = 100
var max_health: int = 100
var stamina: float = 100.0
var max_stamina: float = 100.0
var is_saddled: bool = false
var is_ridden: bool = false

# Visual
var _sprite: Sprite2D = null
var _saddle_sprite: Sprite2D = None

# Signals
signal mount_ridden(mount_id: String)
signal mount_dismounted(mount_id: String)
signal mount_health_changed(current: int, max: int)
signal mount_stamina_changed(current: float, max: float)

## Initialize the mount.
func setup(mount_type: MountType, mount_id: String, display_name: String, 
           speed: float = 150.0, health: int = 100, stamina: float = 100.0) -> void:
	self.mount_type = mount_type
	self.mount_id = mount_id
	self.display_name = display_name
	self.speed = speed
	self.health = health
	self.max_health = health
	self.stamina = stamina
	self.max_stamina = stamina
	_setup_visuals()
	_setup_collision()

## Set up visual representation.
func _setup_visuals() -> void:
	# Create sprite
	_sprite = Sprite2D.new()
	_sprite.position = Vector2(16, 16)
	
	var texture: ImageTexture = _get_mount_texture()
	if texture:
		_sprite.texture = texture
	else:
		var image := Image.new()
		image.create(32, 32, false, Image.FORMAT_RGBA8)
		var color := _get_mount_color()
		for y in range(32):
			for x in range(32):
				image.set_pixel(x, y, color)
		_sprite.texture = ImageTexture.create_from_image(image)
	
	add_child(_sprite)
	
	# Create saddle sprite (hidden by default)
	_saddle_sprite = Sprite2D.new()
	_saddle_sprite.position = Vector2(16, 12)
	_saddle_sprite.visible = is_saddled
	add_child(_saddle_sprite)

## Get texture for mount type.
func _get_mount_texture() -> ImageTexture:
	var image := Image.new()
	image.create(32, 32, false, Image.FORMAT_RGBA8)
	var color := _get_mount_color()
	
	for y in range(32):
		for x in range(32):
			var pixel_color := color
			# Add simple pattern
			if (x + y) % 4 < 2:
				pixel_color = color.lerp(Color(1.0, 1.0, 1.0), 0.2)
			image.set_pixel(x, y, pixel_color)
	
	return ImageTexture.create_from_image(image)

## Get color for mount type.
func _get_mount_color() -> Color:
	match mount_type:
		MountType.HORSE:
			return Color(0.6, 0.4, 0.3)  # Brown
		MountType.CAMEL:
			return Color(0.7, 0.6, 0.4)  # Tan
		MountType.WOLF:
			return Color(0.5, 0.5, 0.5)  # Gray
		MountType.BIRD:
			return Color(0.8, 0.7, 0.5)  # Tan
		MountType.BISON:
			return Color(0.4, 0.3, 0.2)  # Dark brown
		MountType.BOAR:
			return Color(0.5, 0.4, 0.3)  # Brown
		_:
			return Color(0.5, 0.5, 0.5)

## Set up collision detection.
func _setup_collision() -> void:
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 20.0
	collision.shape = shape
	add_child(collision)
	
	collision_layer = 3
	collision_mask = 0

## Ride the mount.
func ride() -> void:
	if is_ridden:
		return
	is_ridden = true
	mount_ridden.emit(mount_id)

## Dismount the mount.
func dismount() -> void:
	if not is_ridden:
		return
	is_ridden = false
	mount_dismounted.emit(mount_id)

## Add saddle to mount.
func add_saddle() -> void:
	is_saddled = true
	if _saddle_sprite:
		_saddle_sprite.visible = true

## Remove saddle from mount.
func remove_saddle() -> void:
	is_saddled = false
	if _saddle_sprite:
		_saddle_sprite.visible = false

## Damage the mount.
func take_damage(amount: int) -> bool:
	health = max(0, health - amount)
	mount_health_changed.emit(health, max_health)
	return health <= 0

## Use stamina.
func use_stamina(amount: float) -> void:
	stamina = max(0.0, stamina - amount)
	mount_stamina_changed.emit(stamina, max_stamina)

## Restore stamina.
func restore_stamina(amount: float) -> void:
	stamina = min(max_stamina, stamina + amount)
	mount_stamina_changed.emit(stamina, max_stamina)

## Update mount behavior.
func _physics_process(delta: float) -> void:
	# Regenerate stamina when not in use
	if not is_ridden:
		stamina = min(max_stamina, stamina + delta * 5.0)
		mount_stamina_changed.emit(stamina, max_stamina)

## Get mount type.
func get_mount_type() -> MountType:
	return mount_type

## Get mount ID.
func get_mount_id() -> String:
	return mount_id

## Get display name.
func get_display_name() -> String:
	return display_name

## Check if mount is saddled.
func is_saddled_check() -> bool:
	return is_saddled

## Check if mount is being ridden.
func is_ridden_check() -> bool:
	return is_ridden

## Get health ratio.
func get_health_ratio() -> float:
	return float(health) / float(max_health)

## Get stamina ratio.
func get_stamina_ratio() -> float:
	return stamina / max_stamina

## Serialize mount data.
func serialize() -> Dictionary:
	return {
		"mount_id": mount_id,
		"mount_type": mount_type,
		"position": global_position,
		"health": health,
		"max_health": max_health,
		"stamina": stamina,
		"max_stamina": max_stamina,
		"is_saddled": is_saddled,
		"is_ridden": is_ridden
	}

## Deserialize mount data.
func deserialize(data: Dictionary) -> void:
	global_position = data.get("position", Vector2.ZERO)
	health = data.get("health", max_health)
	stamina = data.get("stamina", max_stamina)
	is_saddled = data.get("is_saddled", false)
	is_ridden = data.get("is_ridden", false)
	if _saddle_sprite:
		_saddle_sprite.visible = is_saddled
	mount_health_changed.emit(health, max_health)
	mount_stamina_changed.emit(stamina, max_stamina)
