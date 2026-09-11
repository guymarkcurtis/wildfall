## Base class for all buildable structures.
class_name Building
extends StaticBody2D

# Building types
enum BuildingType {
	WALL,
	FLOOR,
	DOOR,
	ROOF,
	TORCH,
	CONTAINER,
	WORKBENCH,
	FURNACE,
	FARM_TILE
}

# Building data
var building_type: BuildingType = BuildingType.WALL
var building_id: String = "wall"
var display_name: String = "Wall"
var health: int = 50
var max_health: int = 50
var is_locked: bool = false
var is_interactable: bool = false

# Visual
var _sprite: Sprite2D = null
var _health_bar: ProgressBar = None

# Collision
var _collision: CollisionShape2D = null

# Signals
signal building_placed(coords: Vector2i)
signal building_destroyed
signal building_damaged(current_health: int, max_health: int)

## Initialize the building.
func setup(building_type: BuildingType, building_id: String, display_name: String, health: int = 50) -> void:
	self.building_type = building_type
	self.building_id = building_id
	self.display_name = display_name
	self.health = health
	self.max_health = health
	_setup_visuals()
	_setup_collision()
	building_placed.emit(Vector2i(position))

## Set up visual representation.
func _setup_visuals() -> void:
	# Create sprite
	_sprite = Sprite2D.new()
	_sprite.position = Vector2(16, 16)
	
	var texture: ImageTexture = _get_building_texture()
	if texture:
		_sprite.texture = texture
	else:
		# Fallback colored sprite
		var image := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
		var color := _get_building_color()
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

## Get texture for building type.
func _get_building_texture() -> ImageTexture:
	var image := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	var color := _get_building_color()
	
	for y in range(32):
		for x in range(32):
			var pixel_color := color
			# Add pattern based on building type
			match building_type:
				BuildingType.WALL:
					# Brick pattern
					if y % 8 == 0 or x % 16 == 0:
						pixel_color = color.lerp(Color(0.8, 0.6, 0.4), 0.5)
				BuildingType.FLOOR:
					# Tile pattern
					if (x + y) % 16 < 8:
						pixel_color = color.lerp(Color(0.8, 0.7, 0.5), 0.3)
				BuildingType.TORCH:
					# Flame pattern
					var dist := Vector2(float(x) - 16.0, float(y) - 12.0).length()
					if dist < 8.0:
						pixel_color = Color(0.9, 0.6, 0.2)
				BuildingType.FARM_TILE:
					# Soil pattern
					if y > 16:
						pixel_color = Color(0.4, 0.3, 0.2)
			image.set_pixel(x, y, pixel_color)
	
	return ImageTexture.create_from_image(image)

## Get color for building type.
func _get_building_color() -> Color:
	match building_type:
		BuildingType.WALL:
			return Color(0.5, 0.4, 0.3)  # Brown
		BuildingType.FLOOR:
			return Color(0.6, 0.5, 0.4)  # Tan
		BuildingType.DOOR:
			return Color(0.4, 0.3, 0.2)  # Dark brown
		BuildingType.ROOF:
			return Color(0.6, 0.3, 0.2)  # Red
		BuildingType.TORCH:
			return Color(0.8, 0.5, 0.2)  # Orange
		BuildingType.CONTAINER:
			return Color(0.5, 0.4, 0.3)  # Brown
		BuildingType.WORKBENCH:
			return Color(0.6, 0.5, 0.3)  # Light brown
		BuildingType.FURNACE:
			return Color(0.4, 0.4, 0.4)  # Gray
		BuildingType.FARM_TILE:
			return Color(0.4, 0.3, 0.2)  # Brown
		_:
			return Color(0.5, 0.5, 0.5)

## Set up collision detection.
func _setup_collision() -> void:
	_collision = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(32, 32)
	_collision.shape = shape
	add_child(_collision)
	
	collision_layer = 4
	collision_mask = 0

## Damage the building.
func take_damage(amount: int) -> bool:
	if health <= 0:
		return false
	
	health = max(0, health - amount)
	building_damaged.emit(health, max_health)
	
	if _health_bar:
		_health_bar.value = health
	
	if health <= 0:
		building_destroyed.emit()
		return true
	
	return false

## Get building type.
func get_building_type() -> BuildingType:
	return building_type

## Get building ID.
func get_building_id() -> String:
	return building_id

## Get health ratio.
func get_health_ratio() -> float:
	return float(health) / float(max_health)

## Check if building is destroyed.
func is_destroyed() -> bool:
	return health <= 0

## Serialize building data.
func serialize() -> Dictionary:
	return {
		"building_id": building_id,
		"position": global_position,
		"health": health,
		"max_health": max_health,
		"building_type": building_type
	}

## Deserialize building data.
func deserialize(data: Dictionary) -> void:
	global_position = data.get("position", Vector2.ZERO)
	health = data.get("health", max_health)
	if _health_bar:
		_health_bar.value = health
