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
const HOTBAR_SIZE := 9

# Components (real component instances, not bare nodes)
var inventory: InventoryComponent = null
var health_component: HealthComponent = null
var hunger_component: HungerComponent = null

# State
@export var starting_inventory: Array[Dictionary] = []
@export_enum("male", "female") var character_gender: String = "female"
@export_enum("base", "storm") var character_outfit: String = "base"
var equipped_tool: String = "hand"
var hotbar_items: Array[String] = ["", "", "", "", "", "", "", "", ""]
var active_hotbar_slot := -1
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
signal hotbar_changed(items: Array[String])
signal hotbar_slot_changed(slot_index: int)
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
	populate_hotbar_from_inventory()

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
	inventory.durability_changed.connect(_on_tool_durability_changed)
	inventory.tool_broken.connect(_on_tool_broken)
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
			if _is_holding_bow():
				_fire_ranged()
			else:
				_handle_interaction()
		if Input.is_action_pressed("interact") and _fire_cooldown <= 0.0:
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
	if Input.is_action_just_pressed("toggle_missions"):
		if event_bus:
			event_bus.toggle_missions_ui.emit()

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
	var manager := get_parent().get_node_or_null("BuildingManager") as BuildingManager
	if _ui_blocks_world_input() or (manager != null and manager.build_mode) or _fire_cooldown > 0.0:
		return
	_fire_cooldown = FIRE_COOLDOWN
	if character_visual != null:
		character_visual.play_tool_swing()
	var nearby := _get_nearby_resources()
	if nearby.is_empty():
		var creatures := _get_nearby_creatures()
		if not creatures.is_empty():
			_attack_creature(creatures[0])
		return

	var closest: HarvestableResource = nearby[0]
	if closest.is_destroyed:
		return

	# Tools grant a bonus against the matching resource type.
	var damage_amount: float = 5.0
	var resource_type: String = closest.resource_type
	var tool: ItemDefinition = item_database.get_item(equipped_tool) if item_database != null else null
	if tool != null and inventory.has_item(equipped_tool):
		var matches: bool = (tool.tool_type == "axe" and resource_type == "tree") or (tool.tool_type == "pickaxe" and resource_type in ["rock", "iron_ore", "coal", "gold_ore"])
		if matches:
			damage_amount = maxf(10.0, float(tool.damage_bonus) * 5.0)
	if resource_type in ["plant", "fibre", "berry_bush"]:
		damage_amount = maxf(damage_amount, 25.0)

	# Yields are granted by Main through the resource's resource_destroyed
	# signal; here we only report the interaction for HUD/audio purposes.
	closest.damage(damage_amount, equipped_tool)
	_consume_tool_durability()
	resource_interacted.emit(resource_type, "", 0)

## Get nearby harvestable resources (live HarvestableResource nodes),
## sorted by distance to the player (closest first).
func _get_nearby_resources() -> Array[HarvestableResource]:
	var nearby: Array[HarvestableResource] = []
	var parent := get_parent()
	if parent:
		for child in parent.get_children():
			if child is HarvestableResource and not child.is_destroyed:
				var offset: Vector2 = child.global_position + Vector2(16, 16) - global_position
				var dist: float = offset.length()
				if dist <= HARVEST_RANGE and (dist < 20.0 or offset.normalized().dot(_aim_dir) > 0.25):
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
	_consume_tool_durability()

## Select the item assigned to the numbered quick-bar slot. Tools and weapons
## become the equipped item; other selected items remain ready for their game
## action once that action is available.
func _equip_tool(slot: int) -> void:
	select_hotbar_slot(slot - 1)

func select_hotbar_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= HOTBAR_SIZE:
		return
	active_hotbar_slot = slot_index
	var item_id := hotbar_items[slot_index]
	equipped_tool = item_id if item_id != "" and inventory != null and inventory.has_item(item_id) else "hand"
	hotbar_slot_changed.emit(active_hotbar_slot)
	tool_changed.emit(equipped_tool)

func get_hotbar_items() -> Array[String]:
	return hotbar_items.duplicate()

func set_hotbar_items(items: Array[String]) -> void:
	var normalised := _normalise_hotbar(items)
	if normalised == hotbar_items:
		return
	hotbar_items = normalised
	if active_hotbar_slot >= 0 and hotbar_items[active_hotbar_slot] == "":
		equipped_tool = "hand"
		tool_changed.emit(equipped_tool)
	hotbar_changed.emit(get_hotbar_items())

## New games start with useful equipment in the bar. Existing assignments are
## retained, which lets a loaded save preserve intentional empty slots.
func populate_hotbar_from_inventory() -> void:
	if inventory == null:
		return
	var preferred: Array[String] = ["wooden_axe", "stone_pickaxe", "wooden_sword", "wooden_bow", "arrow"]
	var available: Dictionary = inventory.get_all_items()
	for item_id in available.keys():
		var id := str(item_id)
		if not preferred.has(id):
			preferred.append(id)
	var next_slot := 0
	for item_id in preferred:
		if not available.has(item_id) or hotbar_items.has(item_id):
			continue
		while next_slot < HOTBAR_SIZE and hotbar_items[next_slot] != "":
			next_slot += 1
		if next_slot >= HOTBAR_SIZE:
			break
		hotbar_items[next_slot] = item_id
	hotbar_changed.emit(get_hotbar_items())

func _normalise_hotbar(items: Array[String]) -> Array[String]:
	var result: Array[String] = ["", "", "", "", "", "", "", "", ""]
	var seen: Dictionary = {}
	for index in range(min(items.size(), HOTBAR_SIZE)):
		var item_id := str(items[index])
		if item_id != "" and inventory != null and inventory.has_item(item_id) and not seen.has(item_id):
			result[index] = item_id
			seen[item_id] = true
	return result

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
	var normalised := _normalise_hotbar(hotbar_items)
	if normalised != hotbar_items:
		hotbar_items = normalised
		hotbar_changed.emit(get_hotbar_items())
	if event_bus:
		event_bus.inventory_changed.emit()

## A carried tool's durability changed — relay to the bus (HUD toasts,
## mission panel refresh, ...).
func _on_tool_durability_changed(item_id: String, current: int, max: int) -> void:
	if event_bus:
		event_bus.durability_changed.emit(item_id, current, max)

## A tool just broke. If it was the equipped tool, fall back to bare hands
## immediately so the player does not keep 'wielding' a tool they no
## longer carry. (The empty hotbar slot itself is normalised by
## _on_inventory_changed, since a broken tool's slot is removed.)
func _on_tool_broken(item_id: String) -> void:
	if equipped_tool == item_id:
		equipped_tool = "hand"
		tool_changed.emit(equipped_tool)
	if event_bus:
		event_bus.tool_broken.emit(item_id)

## One durability point per tool use: a swing that actually hits a
## resource or creature, or a bow shot fired. The inventory handles the
## decrement, breakage (slot removed, tool_broken signal) and UI events.
func _consume_tool_durability() -> void:
	if inventory != null and equipped_tool != "" and equipped_tool != "hand":
		inventory.damage_tool(equipped_tool, 1)

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
	tool_changed.connect(character_visual.set_equipped_tool)
	character_visual.set_equipped_tool(equipped_tool)

func set_character_outfit(outfit: String) -> void:
	character_outfit = outfit
	if character_visual != null:
		character_visual.set_outfit(outfit)

func reload_visual_texture() -> void:
	if character_visual != null:
		character_visual.reload_texture_pack()

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
	_consume_tool_durability()
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
	if inv_panel != null and inv_panel.has_method("is_open") and inv_panel.is_open():
		return true
	var craft_panel: Node = parent.get_node_or_null("HUD/CraftingPanel")
	if craft_panel != null and craft_panel.visible:
		return true
	var tech_panel: Node = parent.get_node_or_null("HUD/TechnologyPanel")
	if tech_panel != null and tech_panel.visible:
		return true
	var mission_panel: Node = parent.get_node_or_null("HUD/MissionPanel")
	if mission_panel != null and mission_panel.visible:
		return true
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return true
	return false
