## Interactive crafting station (workbench, furnace, anvil, etc.).
class_name CraftingStation
extends Area2D

const INTERACTION_RANGE: float = 64.0

# Station types
enum StationType {
	WORKBENCH,
	FURNACE,
	ANVIL,
	CAMPFIRE,
	CRAFTING_TABLE
}

# Station data
var station_type: StationType = StationType.WORKBENCH
var station_id: String = "workbench"
var display_name: String = "Workbench"
var description: String = "A workbench for crafting items."
var recipes: Array[Dictionary] = []
var is_active: bool = false

# Visual
var _sprite: Sprite2D = null
var _highlight_sprite: Sprite2D = null

# Signals
signal station_interacted(station_id: String)
signal station_activated(station_id: String)
signal station_deactivated(station_id: String)

## Initialize the crafting station.
func setup(station_type: StationType, station_id: String, display_name: String, description: String, recipes: Array[Dictionary]) -> void:
	self.station_type = station_type
	self.station_id = station_id
	self.display_name = display_name
	self.description = description
	self.recipes = recipes
	_setup_visuals()
	_setup_collision()

## Set up visual representation.
func _setup_visuals() -> void:
	# Create sprite based on station type
	_sprite = Sprite2D.new()
	_sprite.position = Vector2(16, 16)
	
	var texture: ImageTexture = _get_station_texture()
	if texture:
		_sprite.texture = texture
	else:
		# Fallback colored sprite
		var image := Image.new()
		image.create(32, 32, false, Image.FORMAT_RGBA8)
		var color := _get_station_color()
		for y in range(32):
			for x in range(32):
				image.set_pixel(x, y, color)
		_sprite.texture = ImageTexture.create_from_image(image)
	
	add_child(_sprite)
	
	# Create highlight sprite (hidden by default)
	_highlight_sprite = Sprite2D.new()
	_highlight_sprite.position = Vector2(16, 16)
	_highlight_sprite.visible = false
	add_child(_highlight_sprite)
	
	# Set up collision
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = INTERACTION_RANGE
	collision.shape = shape
	add_child(collision)
	
	collision_layer = 1
	collision_mask = 0

## Get texture for station type.
func _get_station_texture() -> ImageTexture:
	var image := Image.new()
	image.create(32, 32, false, Image.FORMAT_RGBA8)
	var color := _get_station_color()
	
	for y in range(32):
		for x in range(32):
			# Create a simple pattern based on station type
			var pixel_color := color
			match station_type:
				StationType.WORKBENCH:
					# Checkered pattern
					if (x + y) % 8 < 4:
						pixel_color = color.lerp(Color(0.8, 0.6, 0.3), 0.5)
				StationType.FURNACE:
					# Dark with orange center
					var dist := Vector2(float(x) - 16.0, float(y) - 16.0).length()
					if dist < 8.0:
						pixel_color = Color(0.9, 0.5, 0.2)
				StationType.ANVIL:
					# Dark gray with highlight
					if x > 8 and x < 24 and y > 8 and y < 24:
						pixel_color = Color(0.4, 0.4, 0.4)
				StationType.CAMPFIRE:
					# Orange/red center
					var dist := Vector2(float(x) - 16.0, float(y) - 16.0).length()
					if dist < 10.0:
						pixel_color = Color(0.9, 0.4, 0.1)
				StationType.CRAFTING_TABLE:
					# Green pattern
					if (x * y) % 16 < 8:
						pixel_color = color.lerp(Color(0.3, 0.7, 0.3), 0.5)
			image.set_pixel(x, y, pixel_color)
	
	return ImageTexture.create_from_image(image)

## Get color for station type.
func _get_station_color() -> Color:
	match station_type:
		StationType.WORKBENCH:
			return Color(0.6, 0.4, 0.2)  # Brown
		StationType.FURNACE:
			return Color(0.4, 0.3, 0.3)  # Dark gray
		StationType.ANVIL:
			return Color(0.3, 0.3, 0.3)  # Dark gray
		StationType.CAMPFIRE:
			return Color(0.8, 0.4, 0.1)  # Orange
		StationType.CRAFTING_TABLE:
			return Color(0.4, 0.6, 0.3)  # Green
		_:
			return Color(0.5, 0.5, 0.5)

## Set up collision detection.
func _setup_collision() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

## Check if a body is the player.
func _is_player(body: Node) -> bool:
	return body is CharacterBody2D and body.has_method("get_world_position")

## Handle body entering area.
func _on_body_entered(body: Node) -> void:
	if _is_player(body):
		_highlight()

## Handle body leaving area.
func _on_body_exited(body: Node) -> void:
	if _is_player(body):
		_unhighlight()

## Highlight the station.
func _highlight() -> void:
	is_active = true
	_highlight_sprite.visible = true
	_highlight_sprite.modulate = Color(1.0, 1.0, 0.8, 0.5)

## Unhighlight the station.
func _unhighlight() -> void:
	is_active = false
	_highlight_sprite.visible = false

## Interact with the station.
func interact() -> void:
	station_interacted.emit(station_id)
	station_activated.emit(station_id)

## Get recipes for this station.
func get_recipes() -> Array[Dictionary]:
	return recipes.duplicate()

## Check if station can craft a recipe.
func can_craft(recipe: Dictionary, inventory: Dictionary) -> bool:
	if recipe.get("crafting_station", "") != station_id and station_type != StationType.WORKBENCH:
		return false
	
	var required: Dictionary = recipe.get("required_items", {})
	for item_id in required:
		var needed: int = required[item_id]
		var available: int = inventory.get(item_id, 0)
		if available < needed:
			return false
	return true

## Get station ID.
func get_station_id() -> String:
	return station_id

## Get station type.
func get_station_type() -> StationType:
	return station_type

## Get display name.
func get_display_name() -> String:
	return display_name

## Check if station is active (player nearby).
func is_active_check() -> bool:
	return is_active
