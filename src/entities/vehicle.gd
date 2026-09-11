## Base class for all vehicles (boats, carts, etc.).
class_name Vehicle
extends CharacterBody2D

# Vehicle types
enum VehicleType {
	BOAT,
	CART,
	RAIL,
	FLIGHT
}

# Vehicle data
var vehicle_type: VehicleType = VehicleType.BOAT
var vehicle_id: String = "boat"
var display_name: String = "Boat"
var speed: float = 100.0
var max_speed: float = 100.0
var acceleration: float = 50.0
# Braking: float = 100.0
var fuel_capacity: float = 100.0
var current_fuel: float = 100.0
var health: int = 50
var max_health: int = 50
var is_active: bool = false
var is_driver: bool = false

# Visual
var _sprite: Sprite2D = None
var _fuel_bar: ProgressBar = None

# Signals
signal vehicle_started(vehicle_id: String)
signal vehicle_stopped(vehicle_id: String)
signal vehicle_entered(vehicle_id: String)
signal vehicle_exited(vehicle_id: String)
signal fuel_changed(current: float, max: float)
signal health_changed(current: int, max: int)

## Initialize the vehicle.
func setup(vehicle_type: VehicleType, vehicle_id: String, display_name: String, 
           speed: float = 100.0, fuel_capacity: float = 100.0, health: int = 50) -> void:
	self.vehicle_type = vehicle_type
	self.vehicle_id = vehicle_id
	self.display_name = display_name
	self.max_speed = speed
	self.speed = speed
	self.fuel_capacity = fuel_capacity
	self.current_fuel = fuel_capacity
	self.health = health
	self.max_health = health
	_setup_visuals()
	_setup_collision()

## Set up visual representation.
func _setup_visuals() -> void:
	# Create sprite
	_sprite = Sprite2D.new()
	_sprite.position = Vector2(16, 16)
	
	var texture: ImageTexture = _get_vehicle_texture()
	if texture:
		_sprite.texture = texture
	else:
		var image := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
		var color := _get_vehicle_color()
		for y in range(32):
			for x in range(32):
				image.set_pixel(x, y, color)
		_sprite.texture = ImageTexture.create_from_image(image)
	
	add_child(_sprite)
	
	# Create fuel bar
	_fuel_bar = ProgressBar.new()
	_fuel_bar.min_value = 0
	_fuel_bar.max_value = fuel_capacity
	_fuel_bar.value = fuel_capacity
	_fuel_bar.custom_minimum_size = Vector2(32, 4)
	_fuel_bar.position = Vector2(0, -20)
	add_child(_fuel_bar)

## Get texture for vehicle type.
func _get_vehicle_texture() -> ImageTexture:
	var image := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	var color := _get_vehicle_color()
	
	for y in range(32):
		for x in range(32):
			var pixel_color := color
			# Add pattern based on vehicle type
			match vehicle_type:
				VehicleType.BOAT:
					# Hull shape
					if y > 20:
						pixel_color = color.lerp(Color(0.4, 0.3, 0.2), 0.5)
				VehicleType.CART:
					# Wheels
					if (x < 8 or x > 24) and (y > 20 or y < 12):
						pixel_color = Color(0.3, 0.3, 0.3)
				VehicleType.RAIL:
					# Rails
					if y % 8 == 0:
						pixel_color = Color(0.5, 0.5, 0.5)
				VehicleType.FLIGHT:
					# Wings
					if x < 8 or x > 24:
						pixel_color = color.lerp(Color(0.8, 0.8, 0.8), 0.3)
			image.set_pixel(x, y, pixel_color)
	
	return ImageTexture.create_from_image(image)

## Get color for vehicle type.
func _get_vehicle_color() -> Color:
	match vehicle_type:
		VehicleType.BOAT:
			return Color(0.6, 0.4, 0.3)  # Brown
		VehicleType.CART:
			return Color(0.5, 0.4, 0.3)  # Brown
		VehicleType.RAIL:
			return Color(0.4, 0.4, 0.4)  # Gray
		VehicleType.FLIGHT:
			return Color(0.7, 0.7, 0.8)  # Light gray
		_:
			return Color(0.5, 0.5, 0.5)

## Set up collision detection.
func _setup_collision() -> void:
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(32, 32)
	collision.shape = shape
	add_child(collision)
	
	collision_layer = 5
	collision_mask = 0

## Start the vehicle.
func start_vehicle() -> void:
	is_active = true
	vehicle_started.emit(vehicle_id)

## Stop the vehicle.
func stop_vehicle() -> void:
	is_active = False
	velocity = Vector2.ZERO
	vehicle_stopped.emit(vehicle_id)

## Enter the vehicle.
func enter_vehicle() -> void:
	is_driver = True
	vehicle_entered.emit(vehicle_id)

## Exit the vehicle.
func exit_vehicle() -> void:
	is_driver = False
	vehicle_exited.emit(vehicle_id)

## Damage the vehicle.
func take_damage(amount: int) -> bool:
	health = max(0, health - amount)
	health_changed.emit(health, max_health)
	return health <= 0

## Use fuel.
func use_fuel(amount: float) -> void:
	current_fuel = max(0.0, current_fuel - amount)
	fuel_changed.emit(current_fuel, fuel_capacity)

## Refuel the vehicle.
func refuel(amount: float) -> void:
	current_fuel = min(fuel_capacity, current_fuel + amount)
	fuel_changed.emit(current_fuel, fuel_capacity)

## Update vehicle physics.
func _physics_process(delta: float) -> void:
	# Update fuel bar
	if _fuel_bar:
		_fuel_bar.value = current_fuel
	
	# Handle movement if active and driver
	if is_active and is_driver:
		var input := Vector2.ZERO
		if Input.is_action_pressed("ui_up"):
			input.y -= 1
		if Input.is_action_pressed("ui_down"):
			input.y += 1
		if Input.is_action_pressed("ui_left"):
			input.x -= 1
		if Input.is_action_pressed("ui_right"):
			input.x += 1
		
		if input != Vector2.ZERO:
			input = input.normalized()
			velocity = input * speed
			
			# Use fuel while moving
			use_fuel(delta * 2.0)
		else:
			velocity = Vector2.ZERO
			# Regenerate fuel slowly
			current_fuel = min(fuel_capacity, current_fuel + delta * 0.5)
			fuel_changed.emit(current_fuel, fuel_capacity)
	
	move_and_slide()

## Get vehicle type.
func get_vehicle_type() -> VehicleType:
	return vehicle_type

## Get vehicle ID.
func get_vehicle_id() -> String:
	return vehicle_id

## Get display name.
func get_display_name() -> String:
	return display_name

## Check if vehicle is active.
func is_active_check() -> bool:
	return is_active

## Check if player is driving.
func is_driver_check() -> bool:
	return is_driver

## Get fuel ratio.
func get_fuel_ratio() -> float:
	return current_fuel / fuel_capacity

## Get health ratio.
func get_health_ratio() -> float:
	return float(health) / float(max_health)

## Serialize vehicle data.
func serialize() -> Dictionary:
	return {
		"vehicle_id": vehicle_id,
		"vehicle_type": vehicle_type,
		"position": global_position,
		"health": health,
		"max_health": max_health,
		"current_fuel": current_fuel,
		"fuel_capacity": fuel_capacity,
		"is_active": is_active,
		"is_driver": is_driver
	}

## Deserialize vehicle data.
func deserialize(data: Dictionary) -> void:
	global_position = data.get("position", Vector2.ZERO)
	health = data.get("health", max_health)
	current_fuel = data.get("current_fuel", fuel_capacity)
	is_active = data.get("is_active", False)
	is_driver = data.get("is_driver", False)
	if _fuel_bar:
		_fuel_bar.value = current_fuel
	health_changed.emit(health, max_health)
	fuel_changed.emit(current_fuel, fuel_capacity)
