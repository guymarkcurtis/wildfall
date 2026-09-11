## Main player entity with movement, health, hunger, and inventory.
class_name Player
extends CharacterBody2D

const MOVE_SPEED: float = 150.0
const SPRINT_SPEED: float = 250.0
const MAX_HEALTH: int = 100
const MAX_HUNGER: float = 100.0
const HUNGER_RATE: float = 0.5
const HARVEST_RANGE: float = 64.0

# Components (real component instances, not bare nodes)
var inventory: InventoryComponent = null
var health_component: HealthComponent = null
var hunger_component: HungerComponent = null

# State
@export var starting_inventory: Array[Dictionary] = []
var equipped_tool: String = "hand"
var nearby_resources: Array = []

# Event bus (GameEventBus is a sibling of the player under Main)
var event_bus: Node = null
# Item database (sibling under Main); supplies tool/weapon damage bonuses
# for creature attacks.
var item_database: ItemDatabase = null

# Signals
signal position_changed(position: Vector2)
signal health_changed(current: float, max: int)
signal hunger_changed(current: float, max: float)
signal died
signal tool_changed(tool_id: String)
signal resource_interacted(resource_type: String, item_id: String, quantity: int)

func _ready() -> void:
	event_bus = get_parent().get_node("GameEventBus")
	item_database = get_parent().get_node("ItemDatabase")
	_init_components()
	_spawn_at(Vector2(0, 0))
	_populate_initial_inventory()

## Initialize components with the real component implementations.
func _init_components() -> void:
	health_component = HealthComponent.new()
	health_component.max_health = MAX_HEALTH
	health_component.current_health = float(MAX_HEALTH)

	hunger_component = HungerComponent.new()
	hunger_component.max_hunger = MAX_HUNGER
	hunger_component.current_hunger = MAX_HUNGER

	# InventoryComponent is a RefCounted (not a Node), so it is held, not added.
	inventory = InventoryComponent.new()

	# Connect signals
	health_component.health_changed.connect(_on_health_changed)
	hunger_component.hunger_changed.connect(_on_hunger_changed)
	inventory.inventory_changed.connect(_on_inventory_changed)
	health_component.died.connect(_on_died)

## Spawn player at world position.
func _spawn_at(position: Vector2) -> void:
	global_position = position
	if event_bus:
		event_bus.player_spawned.emit(position)

## Handle input and movement.
func _physics_process(delta: float) -> void:
	var direction: Vector2 = Vector2.ZERO
	var speed: float = MOVE_SPEED

	# Sprint
	if Input.is_action_pressed("sprint") and velocity.length() > 0:
		speed = SPRINT_SPEED

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

	velocity = direction * speed
	move_and_slide()

	position_changed.emit(global_position)

	# Handle interactions
	if Input.is_action_just_pressed("interact"):
		_handle_interaction()

	# Handle tool switching (1-9 keys)
	for i in range(1, 10):
		if Input.is_action_just_pressed("tool_%d" % i):
			_equip_tool(i)

	# Handle UI toggles (the event bus is notified; Main performs the toggle)
	if Input.is_action_just_pressed("toggle_inventory"):
		if event_bus:
			event_bus.toggle_inventory_ui.emit()

## Update hunger over time.
func _process(delta: float) -> void:
	if hunger_component:
		hunger_component.lose_hunger(HUNGER_RATE * delta)
		hunger_component.apply_starvation(health_component, delta)

## Handle interaction: attack the nearest creature in range (hunting takes
## priority over harvesting), otherwise harvest the nearest resource.
func _handle_interaction() -> void:
	var nearby_creatures := _get_nearby_creatures()
	if not nearby_creatures.is_empty():
		_attack_creature(nearby_creatures[0])
		return

	var nearby := _get_nearby_resources()
	if nearby.is_empty():
		return

	var closest: HarvestableResource = nearby[0]
	if closest.is_destroyed:
		return

	# Tools grant a bonus against the matching resource type.
	var damage_amount: float = 1.0
	var resource_type: String = closest.resource_type
	if equipped_tool != "hand" and equipped_tool != "":
		if equipped_tool.ends_with("axe") and resource_type == "tree":
			damage_amount = 2.0
		elif equipped_tool.ends_with("pickaxe") and ["rock", "iron_ore", "coal", "gold_ore"].has(resource_type):
			damage_amount = 2.0

	# Yields are granted by Main through the resource's resource_destroyed
	# signal; here we only report the interaction for HUD/audio purposes.
	closest.damage(damage_amount, equipped_tool)
	resource_interacted.emit(resource_type, "", 0)

## Get nearby harvestable resources (live HarvestableResource nodes),
## sorted by distance to the player (closest first).
func _get_nearby_resources() -> Array[HarvestableResource]:
	var nearby: Array[HarvestableResource] = []
	var parent := get_parent()
	if parent:
		for child in parent.get_children():
			if child is HarvestableResource and not child.is_destroyed:
				var dist: float = child.position.distance_to(global_position)
				if dist <= HARVEST_RANGE:
					nearby.append(child)
	nearby.sort_custom(func(a, b): return a.position.distance_to(global_position) < b.position.distance_to(global_position))
	return nearby

## Get nearby creatures (live Creature nodes), sorted by distance to the
## player (closest first) — the same scan as the resource list.
func _get_nearby_creatures() -> Array[Creature]:
	var nearby: Array[Creature] = []
	var parent := get_parent()
	if parent:
		for child in parent.get_children():
			if child is Creature and not child.is_dead():
				var dist: float = child.position.distance_to(global_position)
				if dist <= HARVEST_RANGE:
					nearby.append(child)
	nearby.sort_custom(func(a, b): return a.position.distance_to(global_position) < b.position.distance_to(global_position))
	return nearby

## Attack a creature: a bare-hand hit does 1; any held tool/weapon uses its
## damage bonus instead (swords are the best hunting tools). The event bus
## announces the hit; death, loot, and freeing the node are handled by Main
## through the creature's creature_died signal.
func _attack_creature(creature: Creature) -> void:
	var damage_amount: float = 1.0
	if equipped_tool != "" and equipped_tool != "hand" and item_database != null:
		var tool_def: ItemDefinition = item_database.get_item(equipped_tool)
		if tool_def != null:
			damage_amount = float(tool_def.damage_bonus)
	if event_bus:
		event_bus.entity_hit.emit(creature.creature_type, damage_amount)
	creature.take_damage(damage_amount)

## Equip the tool for a hotbar slot. Only tools the player actually owns
## can be equipped — iron tools must be crafted first (progression).
func _equip_tool(slot: int) -> void:
	var tools: PackedStringArray = ["hand", "wooden_axe", "stone_pickaxe", "wooden_sword", "iron_axe", "iron_pickaxe"]
	if slot < 1 or slot > tools.size():
		return
	var tool_id: String = tools[slot - 1]
	if tool_id == "hand" or (inventory != null and inventory.has_item(tool_id)):
		if equipped_tool != tool_id:
			equipped_tool = tool_id
			tool_changed.emit(equipped_tool)

## Get player's world position.
func get_world_position() -> Vector2:
	return global_position

## Get player's chunk coordinate (pixels / (TILE_SIZE * CHUNK_SIZE)).
func get_chunk_coordinate() -> Vector2i:
	return Vector2i(int(global_position.x / 512.0), int(global_position.y / 512.0))

## Signal handlers.
func _on_health_changed(current: float, max: int) -> void:
	if event_bus:
		event_bus.health_changed.emit(current, max)
	health_changed.emit(current, max)
	if current <= 0:
		died.emit()

func _on_hunger_changed(current: float, max: float) -> void:
	if event_bus:
		event_bus.hunger_changed.emit(current, max)
	hunger_changed.emit(current, max)

func _on_inventory_changed() -> void:
	if event_bus:
		event_bus.inventory_changed.emit()

func _on_died() -> void:
	if event_bus:
		event_bus.player_died.emit()
	died.emit()

## Populate starting inventory.
func _populate_initial_inventory() -> void:
	for item_data in starting_inventory:
		inventory.add_item(item_data["item_id"], item_data.get("quantity", 1))
	inventory.add_item("wooden_axe", 1)
	inventory.add_item("stone_pickaxe", 1)
	# Phase 3: the player also starts with a basic sword for hunting.
	inventory.add_item("wooden_sword", 1)
