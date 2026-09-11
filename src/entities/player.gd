## Main player entity with movement, health, hunger, and inventory.
class_name Player
extends CharacterBody2D

const MOVE_SPEED: float = 150.0
const SPRINT_SPEED: float = 250.0
const MAX_HEALTH: int = 100
const MAX_HUNGER: float = 100.0
const HUNGER_RATE: float = 0.5
const HARVEST_RANGE: float = 64.0
const FIRE_COOLDOWN: float = 0.45
const WATER_SPEED: float = 0.55

# Components (real component instances, not bare nodes)
var inventory: InventoryComponent = null
var health_component: HealthComponent = null
var hunger_component: HungerComponent = null

# State
@export var starting_inventory: Array[Dictionary] = []
@export_enum("male", "female") var character_gender: String = "female"
@export_enum("base", "storm") var character_outfit: String = "base"
var equipped_tool: String = "hand"
var nearby_resources: Array = []
var character_visual: CharacterVisual = null

# Event bus (GameEventBus is a sibling of the player under Main)
var event_bus: Node = null
# Item database (sibling under Main); supplies tool/weapon damage bonuses
# for creature attacks.
var item_database: ItemDatabase = null
var status_effects: StatusEffectSystem = null

var _aim_dir: Vector2 = Vector2.RIGHT
var _aim_locked: bool = false
var _fire_cooldown: float = 0.0
var _facing: Polygon2D = null

# Signals
signal position_changed(position: Vector2)
signal health_changed(current: float, max: int)
signal hunger_changed(current: float, max: float)
signal died
signal tool_changed(tool_id: String)
signal resource_interacted(resource_type: String, item_id: String, quantity: int)

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	event_bus = get_parent().get_node("GameEventBus")
	item_database = get_parent().get_node("ItemDatabase")
	status_effects = get_parent().get_node_or_null("StatusEffectSystem")
	_init_components()
	_setup_collision()
	_setup_facing()
	_setup_character_visual()
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
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_update_aim()

	var direction: Vector2 = get_move_vector()
	var speed: float = MOVE_SPEED
	if Input.is_action_pressed("sprint") and direction != Vector2.ZERO:
		speed = SPRINT_SPEED
	speed *= _speed_multiplier()
	if direction != Vector2.ZERO:
		direction = direction.normalized()
	velocity = direction * speed
	move_and_slide()
	if character_visual != null:
		character_visual.update_animation(velocity, delta, _aim_dir)
	position_changed.emit(global_position)

	if not _ui_blocks_world_input():
		if Input.is_action_pressed("fire") and _fire_cooldown <= 0.0:
			_fire_ranged()
		if Input.is_action_just_pressed("interact"):
			_handle_interaction()

	for i in range(1, 10):
		if Input.is_action_just_pressed("tool_%d" % i):
			_equip_tool(i)

	if Input.is_action_just_pressed("toggle_inventory"):
		if event_bus:
			event_bus.toggle_inventory_ui.emit()
	if Input.is_action_just_pressed("toggle_crafting"):
		if event_bus:
			event_bus.toggle_crafting_ui.emit()

## Mouse-relative move: W toward the pointer, S away, A/D orbit around it.
## Facing stays on the cursor; movement never turns the character.
func get_move_vector() -> Vector2:
	var forward: Vector2 = _aim_dir
	if forward == Vector2.ZERO:
		forward = Vector2.RIGHT
	var right: Vector2 = forward.rotated(PI * 0.5)
	var direction: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		direction += forward
	if Input.is_action_pressed("move_down"):
		direction -= forward
	if Input.is_action_pressed("move_right"):
		direction += right
	if Input.is_action_pressed("move_left"):
		direction -= right
	return direction

func get_aim_direction() -> Vector2:
	return _aim_dir

## Used by the headless harness so a walk test can keep a stable aim.
func set_aim_locked(dir: Vector2) -> void:
	_aim_locked = true
	if dir != Vector2.ZERO:
		_aim_dir = dir.normalized()

func clear_aim_lock() -> void:
	_aim_locked = false

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
	# Floor (not truncate) — must match ChunkSystem.world_to_chunk_coords.
	return Vector2i(int(floor(global_position.x / 512.0)), int(floor(global_position.y / 512.0)))

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
	inventory.add_item("wooden_sword", 1)
	inventory.add_item("wooden_bow", 1)
	inventory.add_item("arrow", 24)
	inventory.add_item("wooden_wall", 8)
	inventory.add_item("campfire", 1)

func _setup_collision() -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	add_child(shape)
	collision_layer = 1
	collision_mask = 1

func _setup_facing() -> void:
	_facing = Polygon2D.new()
	_facing.polygon = PackedVector2Array([
		Vector2(14.0, 0.0), Vector2(-8.0, -7.0), Vector2(-8.0, 7.0)
	])
	_facing.color = Color(0.95, 0.85, 0.35)
	_facing.visible = false
	add_child(_facing)

func _setup_character_visual() -> void:
	character_visual = CharacterVisual.new()
	character_visual.name = "CharacterVisual"
	add_child(character_visual)
	character_visual.set_appearance(character_gender, character_outfit)

func set_character_outfit(outfit: String) -> void:
	character_outfit = outfit
	if character_visual != null:
		character_visual.set_outfit(outfit)

func _update_aim() -> void:
	if not _aim_locked:
		var to_mouse: Vector2 = get_global_mouse_position() - global_position
		if to_mouse.length() > 1.0:
			_aim_dir = to_mouse.normalized()
	if _facing:
		_facing.rotation = _aim_dir.angle()

func _fire_ranged() -> void:
	if _ui_blocks_world_input():
		return
	var building_manager := get_parent().get_node_or_null("BuildingManager") as BuildingManager
	if building_manager != null and building_manager.build_mode:
		return
	if inventory == null or not inventory.has_item("arrow", 1):
		return
	if not _is_holding_bow():
		# Equip the bow automatically when firing if the player owns it.
		if inventory.has_item("wooden_bow", 1):
			equipped_tool = "wooden_bow"
			tool_changed.emit(equipped_tool)
		else:
			return
	inventory.remove_item("arrow", 1)
	_fire_cooldown = FIRE_COOLDOWN
	var damage: float = 7.0
	if item_database != null:
		var bow: ItemDefinition = item_database.get_item("wooden_bow")
		if bow != null:
			damage = float(bow.damage_bonus)
	var bolt := Projectile.new()
	get_parent().add_child(bolt)
	bolt.setup(global_position + _aim_dir * 16.0, _aim_dir, damage)
	if event_bus:
		event_bus.projectile_fired.emit(global_position, _aim_dir)

func _is_holding_bow() -> bool:
	return equipped_tool.ends_with("bow")

func _speed_multiplier() -> float:
	var mult: float = 1.0
	var terrain := get_parent().get_node_or_null("TerrainRenderer") as TerrainRenderer
	if terrain != null:
		var tile := Vector2i(int(floor(global_position.x / 32.0)), int(floor(global_position.y / 32.0)))
		if terrain.is_water_cell(tile):
			mult *= WATER_SPEED
	if status_effects != null:
		mult *= clampf(1.0 + status_effects.get_speed_bonus() * 0.08, 0.35, 1.6)
	var weather := get_parent().get_node_or_null("WeatherSystem") as WeatherSystem
	if weather != null:
		mult *= weather.get_speed_multiplier()
	return mult

func _ui_blocks_world_input() -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	var seed_input: Node = parent.get_node_or_null("SeedInput")
	if seed_input != null and seed_input.has_method("is_editing") and seed_input.is_editing():
		return true
	var inv_panel: Node = parent.get_node_or_null("HUD/InventoryPanel")
	if inv_panel != null and inv_panel.visible:
		return true
	var craft_panel: Node = parent.get_node_or_null("HUD/CraftingPanel")
	if craft_panel != null and craft_panel.visible:
		return true
	return false
