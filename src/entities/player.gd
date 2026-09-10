## Main player entity with movement, health, hunger, and inventory.
class_name Player
extends CharacterBody2D

const MOVE_SPEED: float = 4.0
const MAX_HEALTH: int = 100
const MAX_HUNGER: float = 100.0
const HUNGER_RATE: float = 0.5  # hunger per second

# Components
var inventory: "InventoryComponent" = null
var health_component: "HealthComponent" = null
var hunger_component: "HungerComponent" = null

# State
@export var starting_inventory: Array[Dictionary] = []

# Signals
signal position_changed(position: Vector2)
signal health_changed(current: int, max: int)
signal hunger_changed(current: float, max: float)
signal died

func _ready() -> void:
	_init_components()
	_spawn_at(Vector2(0, 0))
	_populate_initial_inventory()

## Initialize components.
func _init_components() -> void:
	inventory = InventoryComponent.new()
	health_component = HealthComponent.new()
	health_component.max_health = MAX_HEALTH
	health_component.health = MAX_HEALTH
	hunger_component = HungerComponent.new()
	hunger_component.max_hunger = MAX_HUNGER
	hunger_component.hunger = MAX_HUNGER

	# Connect signals
	health_component.health_changed.connect(_on_health_changed)
	hunger_component.hunger_changed.connect(_on_hunger_changed)
	inventory.inventory_changed.connect(_on_inventory_changed)

	add_child(health_component)
	add_child(hunger_component)
	add_child(inventory)

## Spawn player at world position.
func _spawn_at(position: Vector2) -> void:
	global_position = position
	GameEventBus.player_spawned.emit(position)

## Handle input and movement.
func _process(delta: float) -> void:
	var direction: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		direction.y -= 1
	if Input.is_action_pressed("move_down"):
		direction.y += 1
	if Input.is_action_pressed("move_left"):
		direction.x -= 1
	if Input.is_action_pressed("move_right"):
		direction.x += 1

	if direction != Vector2.ZERO:
		direction = direction.normalized()

	velocity = direction * MOVE_SPEED
	move_and_slide()

	position_changed.emit(global_position)

	# Handle interactions
	if Input.is_action_just_pressed("interact"):
		_handle_interaction()

	# Handle UI toggles
	if Input.is_action_just_pressed("toggle_inventory"):
		_toggle_inventory()

	if Input.is_action_just_pressed("toggle_debug"):
		_toggle_debug()

## Update hunger over time.
func _process_physics(delta: float) -> void:
	if hunger_component:
		hunger_component.hunger -= HUNGER_RATE * delta
		if hunger_component.hunger <= 0:
			hunger_component.hunger = 0
			# Starvation damage
			if health_component:
				health_component.take_damage(1.0)

## Handle interaction with nearby objects.
func _handle_interaction() -> void:
	# Placeholder: check for nearby interactable objects
	pass

## Toggle inventory UI.
func _toggle_inventory() -> void:
	# Signal to show/hide inventory panel
	GameEventBus.emit_game_event("toggle_inventory_ui")

## Toggle debug overlay.
func _toggle_debug() -> void:
	var enabled: bool = not GameEventBus.debug_mode_toggled.is_connected(func() {}) if GameEventBus.debug_mode_toggled.get_connection_list().size() > 0 else false
	GameEventBus.debug_mode_toggled.emit(enabled)

## Populate starting inventory.
func _populate_initial_inventory() -> void:
	for item_data in starting_inventory:
		inventory.add_item(item_data["item_id"], item_data.get("quantity", 1))

## Get player's world position.
func get_world_position() -> Vector2:
	return global_position

## Get player's chunk coordinate.
func get_chunk_coordinate() -> Vector2i:
	return ChunkSystem.world_to_chunk_coords(Vector2i(global_position))

## Signals handlers.
func _on_health_changed(current: int, max: int) -> void:
	GameEventBus.health_changed.emit(current, max)
	if current <= 0:
		died.emit()

func _on_hunger_changed(current: float, max: float) -> void:
	GameEventBus.hunger_changed.emit(current, max)

func _on_inventory_changed() -> void:
	GameEventBus.inventory_changed.emit()
