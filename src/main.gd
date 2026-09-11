## Main scene: wires up world generation, rendering, resources, player, and UI.
## This is the entry point of the game.
##
## Signal flow:
##   SeedInput.seed_changed            -> _on_seed_changed -> (re)generate world
##   GameEventBus.world_seed_set       -> _on_world_seed_set (e.g. SaveSystem restore)
##   ChunkSystem.chunk_generated       -> render terrain + spawn resources
##   ChunkSystem.chunk_unloaded        -> free that chunk's resources + terrain
##   Player / InventoryComponent       -> GameEventBus.inventory_changed -> UI refresh
##
## There are no autoloads in this project: every cross-node reference is
## resolved from the scene tree (children of Main) at startup.
extends Node

const TILE_SIZE: int = 32
const CHUNK_SIZE: int = 16
const INITIAL_CHUNK_RADIUS: int = 3

@onready var world_generator: WorldGenerator = $WorldGenerator
@onready var chunk_system: ChunkSystem = $ChunkSystem
@onready var terrain_renderer: TerrainRenderer = $TerrainRenderer
@onready var resource_spawner: ResourceSpawner = $ResourceSpawner
@onready var creature_spawner: CreatureSpawner = $CreatureSpawner
@onready var item_database: ItemDatabase = $ItemDatabase
@onready var player: Player = $Player
@onready var camera_controller: Camera2D = $CameraController
@onready var debug_overlay: DebugOverlay = $DebugOverlay
@onready var seed_input: SeedInput = $SeedInput
@onready var hud: HUD = $HUD
@onready var inventory_panel: InventoryPanel = $HUD/InventoryPanel
@onready var crafting_panel: CraftingPanel = $HUD/CraftingPanel
@onready var save_system: SaveSystem = $SaveSystem
@onready var day_night: DayNightCycle = $DayNightCycle
@onready var weather_system: WeatherSystem = $WeatherSystem
@onready var status_effects: StatusEffectSystem = $StatusEffectSystem
@onready var building_manager: BuildingManager = $BuildingManager
@onready var world_modulate: CanvasModulate = $WorldModulate
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var performance_overlay: PerformanceOverlay = $PerformanceOverlay

var _world_seed: int = 0
var _debug_enabled: bool = false
# Live HarvestableResource nodes (children of Main, siblings of the Player
# so the player's nearby-resource scan can find them).
var _resource_nodes: Array = []
# chunk_coords (Vector2i) -> Array of that chunk's resource nodes.
var _resources_by_chunk: Dictionary = {}
# RecipeDefinition objects, parallel to crafting_panel.recipes (dict form).
var _recipe_defs: Array = []
# Live Creature nodes (children of Main, siblings of the Player so the
# player's nearby-creature scan can find them).
var _creature_nodes: Array = []
# chunk_coords (Vector2i) -> Array of that chunk's creature nodes.
var _creatures_by_chunk: Dictionary = {}

func _ready() -> void:
	randomize()
	_world_seed = randi() % (SeedInput.MAX_SEED + 1)

	# Connect all signals first, then push the seed in: SeedInput.set_seed
	# emits seed_changed synchronously, which triggers initial world generation.
	var event_bus: Node = $GameEventBus
	seed_input.seed_changed.connect(_on_seed_changed)
	event_bus.world_seed_set.connect(_on_world_seed_set)
	event_bus.inventory_changed.connect(_on_inventory_changed)
	event_bus.toggle_inventory_ui.connect(_on_toggle_inventory_ui)
	event_bus.toggle_crafting_ui.connect(_on_toggle_crafting_ui)
	chunk_system.chunk_generated.connect(_on_chunk_generated)
	chunk_system.chunk_unloaded.connect(_on_chunk_unloaded)
	crafting_panel.recipe_craft_requested.connect(_on_craft_requested)
	player.died.connect(_on_player_died)

	# SaveSystem needs typed references (the project has no autoloads).
	save_system.set_player(player)
	save_system.set_world_generator(world_generator)
	_register_save_modules()
	if pause_menu:
		pause_menu.save_requested.connect(func() -> void: save_game())
		pause_menu.load_requested.connect(func(path: String) -> void: load_game(path))

	day_night.modulate_node = world_modulate
	day_night.initialize()
	weather_system.world_generator = world_generator
	weather_system.initialize()
	status_effects.initialize()
	status_effects.target_health = player.health_component
	player.status_effects = status_effects
	building_manager.player = player
	building_manager.item_database = item_database
	building_manager.building_placed.connect(func(id: String, coords: Vector2i):
		$GameEventBus.building_placed.emit(id, coords))

	# HUD (health/hunger bars, seed label, optional debug readout).
	hud.set_player(player)
	hud.set_seed(_world_seed)

	# Initialize the item database BEFORE the first refresh: the crafting
	# panel is filled from item_database.recipes, and nothing else in the
	# project calls initialize() (without this the panel shows 0 recipes).
	item_database.initialize()

	# Tell the player's inventory the real per-item stack sizes from the
	# database (the component defaults to 64 for everything without this).
	if player and player.inventory:
		var stack_sizes: Dictionary = {}
		for item_id in item_database.items:
			var item_def: ItemDefinition = item_database.get_item(item_id)
			if item_def != null:
				stack_sizes[str(item_id)] = int(item_def.stack_size)
		player.inventory.set_stack_sizes(stack_sizes)

	# SeedInput._ready already emitted its own random seed (before the
	# connections above existed). Push Main's chosen seed so the world is
	# generated exactly once, for the seed that is displayed — unless the
	# title screen asked us to load a save instead.
	if GameSession.consume_load():
		if not save_system.load_game(GameSession.load_path):
			seed_input.set_seed(_world_seed)
	else:
		seed_input.set_seed(_world_seed)

	_refresh_ui()
	print("Main scene ready. Seed: %d  Mode: %s" % [_world_seed, GameSession.mode_label()])

## SeedInput wants the world (re)generated with a new seed.
func _on_seed_changed(seed: int) -> void:
	_world_seed = seed
	hud.set_seed(seed)
	_generate_world(seed)
	print("Seed changed: %d" % seed)

## The event bus wants the world set to a specific seed (e.g. SaveSystem).
## Routes through SeedInput so the input UI and the world always agree.
func _on_world_seed_set(seed: int) -> void:
	seed_input.set_seed(seed)
	print("World seed set: %d" % seed)

## (Re)generate the world: noise, chunk loading, terrain, and resources.
func _generate_world(seed: int) -> void:
	# Free the previous world's resource nodes and rendered terrain first.
	for node in _resource_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_resource_nodes.clear()
	_resources_by_chunk.clear()
	terrain_renderer.clear_all()

	# Free the previous world's creature nodes and spawner records.
	for creature in _creature_nodes:
		if is_instance_valid(creature):
			creature.queue_free()
	_creature_nodes.clear()
	_creatures_by_chunk.clear()
	if building_manager:
		building_manager.clear_all()

	world_generator.initialize(seed)
	resource_spawner.initialize(seed)
	creature_spawner.initialize(seed)
	chunk_system.initialize(seed)

	# Player returns to spawn; the chunk system loads the starting ring
	# (chunk_generated signals drive terrain rendering + resource spawns).
	player.global_position = Vector2.ZERO
	chunk_system.update_player_position(player.get_world_position())

	_refresh_ui()

## A chunk was generated by the chunk system: render terrain, spawn resources.
## This also fires when the player wanders into newly loaded chunks.
func _on_chunk_generated(chunk_coords: Vector2i) -> void:
	var data: Dictionary = chunk_system.get_chunk(chunk_coords)
	if data.is_empty():
		return
	var start_usec := Time.get_ticks_usec()
	terrain_renderer.update_chunk(chunk_coords, data)
	_spawn_resources_for_chunk(chunk_coords)
	_spawn_creatures_for_chunk(chunk_coords)
	if performance_overlay != null:
		performance_overlay.record_chunk_load(chunk_coords,
				float(Time.get_ticks_usec() - start_usec) / 1000.0)

## A chunk left the viewport: free its resources and clear its terrain.
func _on_chunk_unloaded(chunk_coords: Vector2i) -> void:
	var nodes: Array = _resources_by_chunk.get(chunk_coords, [])
	for node in nodes:
		if is_instance_valid(node):
			_resource_nodes.erase(node)
			node.queue_free()
	_resources_by_chunk.erase(chunk_coords)
	# Drop the spawners' records for this chunk too: otherwise their
	# tile-keyed entries survive the unload and re-entering the chunk
	# spawns nothing (the guards think the chunk is already done).
	resource_spawner.remove_chunk(chunk_coords)
	# Free that chunk's creature nodes.
	var creature_nodes: Array = _creatures_by_chunk.get(chunk_coords, [])
	for creature in creature_nodes:
		if is_instance_valid(creature):
			_creature_nodes.erase(creature)
			creature.queue_free()
	_creatures_by_chunk.erase(chunk_coords)
	creature_spawner.remove_chunk(chunk_coords)
	terrain_renderer.clear_chunk(chunk_coords)

## Spawn harvestable resources in a chunk (as siblings of the player).
func _spawn_resources_for_chunk(chunk_coords: Vector2i) -> void:
	var resources: Array = resource_spawner.generate_chunk_resources(chunk_coords, _world_seed)
	var spawn_count: int = 0
	for res_data in resources:
		var x_val: int = int(res_data.get("x", 0))
		var y_val: int = int(res_data.get("y", 0))
		var res_type: String = str(res_data.get("type", "rock"))

		# Create a real HarvestableResource node (sibling of the player
		# under Main, so the player's nearby-resource scan can find it).
		var resource := HarvestableResource.new()
		resource.position = Vector2(x_val, y_val) * float(TILE_SIZE)
		resource.setup(res_type, float(res_data.get("health", 100.0)), res_data.get("yields", []))
		resource.set_meta("resource_type", res_type)
		resource.set_meta("chunk_coords", chunk_coords)
		resource.resource_destroyed.connect(func(item_id: String, quantity: int):
			_on_resource_destroyed(resource, item_id, quantity))
		add_child(resource)
		_resource_nodes.append(resource)
		if not _resources_by_chunk.has(chunk_coords):
			_resources_by_chunk[chunk_coords] = []
		_resources_by_chunk[chunk_coords].append(resource)
		spawn_count += 1

## Spawn creatures in a chunk (as siblings of the player, so the player's
## nearby-creature scan can find them).
func _spawn_creatures_for_chunk(chunk_coords: Vector2i) -> void:
	var creatures: Array = creature_spawner.generate_chunk_creatures(chunk_coords, _world_seed)
	for creature_data in creatures:
		var ctype: String = str(creature_data.get("type", "rabbit"))
		var def: CreatureDefinition = creature_spawner.get_definition(ctype)
		if def == null:
			continue

		# Create a real Creature node (sibling of the player under Main).
		var creature := Creature.new()
		creature.position = Vector2(int(creature_data.get("x", 0)), int(creature_data.get("y", 0))) * float(TILE_SIZE)
		creature.setup(ctype, def, chunk_coords, world_generator)
		creature.set_meta("chunk_coords", chunk_coords)
		creature.set_meta("spawn_tile", Vector2i(int(creature_data.get("x", 0)), int(creature_data.get("y", 0))))
		creature.creature_died.connect(_on_creature_died.bind(creature))
		add_child(creature)
		_creature_nodes.append(creature)
		if not _creatures_by_chunk.has(chunk_coords):
			_creatures_by_chunk[chunk_coords] = []
		_creatures_by_chunk[chunk_coords].append(creature)

## A creature was killed: remove it, hand the rolled loot to the player's
## inventory, announce the death on the event bus, and free the node.
func _on_creature_died(creature_node: Node) -> void:
	if _creature_nodes.has(creature_node):
		_creature_nodes.erase(creature_node)
	var chunk_key: Vector2i = creature_node.get_meta("chunk_coords", Vector2i(0, 0))
	var chunk_list: Array = _creatures_by_chunk.get(chunk_key, [])
	if chunk_list.has(creature_node):
		chunk_list.erase(creature_node)
	var creature := creature_node as Creature
	if creature != null:
		if is_instance_valid(creature):
			$GameEventBus.entity_died.emit(creature.creature_type)
		for entry in creature.get_loot():
			var item_id: String = str(entry.get("item_id", ""))
			var quantity: int = int(entry.get("quantity", 0))
			if item_id == "" or quantity <= 0:
				continue
			if player and player.inventory:
				player.inventory.add_item(item_id, quantity)
			$GameEventBus.item_added.emit(item_id, quantity)
	if is_instance_valid(creature_node):
		creature_node.queue_free()

## A harvestable resource was destroyed: hand its yield to the player.
func _on_resource_destroyed(resource_node: Node, item_id: String, quantity: int) -> void:
	if _resource_nodes.has(resource_node):
		_resource_nodes.erase(resource_node)
	var chunk_key: Vector2i = resource_node.get_meta("chunk_coords", Vector2i(0, 0))
	var chunk_list: Array = _resources_by_chunk.get(chunk_key, [])
	if chunk_list.has(resource_node):
		chunk_list.erase(resource_node)
	if player and player.inventory:
		player.inventory.add_item(item_id, quantity)
	$GameEventBus.item_added.emit(item_id, quantity)

## Player death (HUD / respawn handling can hook in here later).
func _on_player_died() -> void:
	print("Player died.")

## Inventory changed (via the event bus): refresh all UI.
func _on_inventory_changed() -> void:
	_refresh_ui()

## Player toggled the inventory UI (I key, via the event bus).
func _on_toggle_inventory_ui() -> void:
	inventory_panel.visible = not inventory_panel.visible

## Player toggled the crafting UI (C key, via the event bus).
func _on_toggle_crafting_ui() -> void:
	crafting_panel.visible = not crafting_panel.visible

## Per-frame: keep chunk loading in sync with the player, move the camera, keep the HUD
## in step with the seed editor, and update the debug overlay.
func _process(delta: float) -> void:
	chunk_system.update_player_position(player.get_world_position())
	# The camera is a plain Camera2D node that nothing else drives; without
	# this it never follows the player.
	if camera_controller != null and is_instance_valid(player):
		camera_controller.set_target(player.get_world_position())
		if camera_controller.has_method("set_rotation_locked") and seed_input != null:
			camera_controller.set_rotation_locked(seed_input.is_editing())
	# Reflect the seed editor (T) state in the HUD seed label.
	if hud != null and seed_input != null:
		hud.set_seed_editing(seed_input.is_editing(), seed_input.get_input_buffer())
	_update_world_presentation(delta)
	_update_debug_overlay()
	if performance_overlay != null:
		performance_overlay.update_frame(delta, chunk_system.get_loaded_chunk_count(),
				_resource_nodes.size(), _creature_nodes.size())

	if pause_menu != null and pause_menu.visible:
		return
	if Input.is_action_just_pressed("toggle_debug"):
		_toggle_debug()
	if Input.is_action_just_pressed("save"):
		save_game()
	if Input.is_action_just_pressed("load"):
		load_game()

func _update_world_presentation(_delta: float) -> void:
	if weather_system != null and status_effects != null:
		if weather_system.is_wet() and not status_effects.has_effect("slow"):
			status_effects.apply_effect("slow")
		if weather_system.is_cold_weather() and not status_effects.has_effect("frozen"):
			status_effects.apply_effect("frozen")
		if day_night != null and day_night.is_nighttime():
			var tile := Vector2i(int(floor(player.global_position.x / 32.0)), int(floor(player.global_position.y / 32.0)))
			var biome: String = world_generator.get_biome_at_world(tile.x, tile.y)
			if biome == "arctic" and not status_effects.has_effect("frozen"):
				status_effects.apply_effect("frozen")
	if hud != null and day_night != null and weather_system != null:
		var extra: String = ""
		if building_manager != null and building_manager.build_mode:
			extra = "   Build: %s  (LMB place, wheel cycle, F demolish, B exit)" % building_manager.selected_item_id
		hud.set_world_info(day_night.get_time_of_day(), weather_system.get_weather_name(),
				status_effects.get_effect_names() if status_effects else PackedStringArray(),
				extra, GameSession.mode_label())

## Toggle the debug overlays (Main's DebugOverlay + the HUD debug label).
func _toggle_debug() -> void:
	_debug_enabled = not _debug_enabled
	debug_overlay.set_enabled(_debug_enabled)
	hud.toggle_debug(_debug_enabled)

## Update the debug overlay with current world/player info.
func _update_debug_overlay() -> void:
	if not _debug_enabled:
		return
	var player_pos: Vector2 = player.get_world_position()
	var tile_pos: Vector2i = Vector2i(int(player_pos.x / float(TILE_SIZE)), int(player_pos.y / float(TILE_SIZE)))
	# Show the same chunk ChunkSystem uses (pixel-based, floor) so the debug
	# label never disagrees with the chunk that is actually loaded.
	var chunk_pos: Vector2i = ChunkSystem.world_to_chunk_coords(player_pos)
	var biome: String = world_generator.get_biome_at_world(tile_pos.x, tile_pos.y)
	debug_overlay.update_debug(player_pos, tile_pos, chunk_pos, _world_seed, biome,
			world_generator.get_noise_values(float(tile_pos.x), float(tile_pos.y)),
			Engine.get_frames_per_second())

## Save the game (F5 / pause Save). Empty path creates a new manual slot.
func save_game(path: String = "") -> bool:
	if path == "":
		return save_system.save_manual()
	return save_system.save_game(path, "manual")

## Load a save (F9 loads the newest). Empty path picks the most recent file.
func load_game(path: String = "") -> bool:
	if path == "":
		path = save_system.most_recent_save_path()
	if path == "":
		return false
	var ok: bool = save_system.load_game(path)
	if ok:
		_refresh_ui()
	return ok

## Refresh the inventory and crafting UI from the player's real components.
func _refresh_ui() -> void:
	if not player or not player.inventory:
		return
	# The inventory panel keeps a slot-indexed display model
	# ({slot_index: {item_id, quantity}}); adapt the component's
	# item-id-keyed counts into that shape.
	var items: Dictionary = player.inventory.get_all_items()
	var slot_data: Dictionary = {}
	var index: int = 0
	for item_id in items:
		if index >= InventoryPanel.MAX_SLOTS:
			break
		slot_data[index] = {"item_id": str(item_id), "quantity": int(items[item_id])}
		index += 1
	inventory_panel.refresh(slot_data)
	_refresh_crafting_ui()

## Refresh the crafting UI.
## The panel consumes plain-dict recipes (with item-id-keyed required_items);
## we adapt the ItemDatabase's RecipeDefinition objects into that shape and
## keep the originals in _recipe_defs so crafting can use their can_craft().
func _refresh_crafting_ui() -> void:
	if not item_database:
		return
	var inv_data: Dictionary = {}
	if player and player.inventory:
		inv_data = player.inventory.get_all_items()

	var obtainable: Dictionary = _get_obtainable_items()

	var recipe_dicts: Array[Dictionary] = []
	_recipe_defs = []
	for recipe_id in item_database.recipes:
		var def: RecipeDefinition = item_database.get_recipe(recipe_id)
		if def == null:
			continue
		# Hide "ghost" recipes whose ingredients no live system can provide.
		# After Phase 3 every recipe in the database is obtainable, so this
		# filter is a safety net for future recipe additions.
		if not _recipe_is_obtainable(def, obtainable):
			continue
		_recipe_defs.append(def)
		recipe_dicts.append(_recipe_to_dict(def))

	crafting_panel.refresh(recipe_dicts, inv_data)

## Item ids the player can actually obtain in the current phase:
## everything the resource spawner and the creature spawner can drop,
## everything the player carries, plus the iterative closure over recipes
## (wood -> plank -> ...).
func _get_obtainable_items() -> Dictionary:
	var obtainable: Dictionary = {}
	if resource_spawner != null:
		for item_id in resource_spawner.get_all_droppable_items():
			obtainable[str(item_id)] = true
	# Also everything creatures can drop: Phase 3 makes this what unhides
	# the hunting recipes (cooked meat/fish, soup, bed, potions, ...).
	if creature_spawner != null:
		for item_id in creature_spawner.get_all_droppable_items():
			obtainable[str(item_id)] = true
	if player and player.inventory:
		for item_id in player.inventory.get_all_items():
			obtainable[str(item_id)] = true
	# Recipes can unlock other recipe ingredients, so iterate to a fixpoint.
	var progress: bool = true
	while progress:
		progress = false
		for recipe_id in item_database.recipes:
			var def: RecipeDefinition = item_database.get_recipe(recipe_id)
			if def == null or obtainable.has(def.result_item_id):
				continue
			if _recipe_is_obtainable(def, obtainable):
				obtainable[str(def.result_item_id)] = true
				progress = true
	return obtainable

## True if every ingredient of the recipe is in the obtainable set.
func _recipe_is_obtainable(def: RecipeDefinition, obtainable: Dictionary) -> bool:
	for req_id in def.required_items:
		if not obtainable.has(req_id):
			return false
	return true

## Adapt a RecipeDefinition into the panel's plain-dict schema.
func _recipe_to_dict(def: RecipeDefinition) -> Dictionary:
	var display_name: String = def.result_item_id
	if item_database.has_item(def.result_item_id):
		display_name = item_database.get_item_display_name(def.result_item_id)
	return {
		"id": def.recipe_id,
		"display_name": display_name,
		"result_item_id": def.result_item_id,
		"result_quantity": def.result_quantity,
		"crafting_station": def.crafting_station,
		"craft_time": def.craft_time,
		"required_items": def.required_items.duplicate()
	}

## Apply a crafting request (from the CraftingPanel) to the real inventory.
func _on_craft_requested(index: int) -> void:
	if not player or not player.inventory:
		return
	if index < 0 or index >= _recipe_defs.size():
		$GameEventBus.recipe_failed.emit("unknown", "invalid_recipe_index")
		return
	var def: RecipeDefinition = _recipe_defs[index]
	if not GameSession.is_creative():
		var inv_data: Dictionary = player.inventory.get_all_items()
		if not def.can_craft(inv_data):
			$GameEventBus.recipe_failed.emit(def.recipe_id, "missing_items")
			return
		for item_id in def.required_items:
			player.inventory.remove_item(item_id, int(def.required_items[item_id]))
	player.inventory.add_item(def.result_item_id, def.result_quantity)
	$GameEventBus.recipe_crafted.emit(def.recipe_id)
	_refresh_ui()

func _register_save_modules() -> void:
	save_system.clear_modules()
	save_system.register_module("world", _collect_world, _apply_world)
	save_system.register_module("time", _collect_time, _apply_time)
	save_system.register_module("weather", _collect_weather, _apply_weather)
	save_system.register_module("status", _collect_status, _apply_status)
	save_system.register_module("buildings", _collect_buildings, _apply_buildings)
	save_system.register_module("player", _collect_player, _apply_player)
	save_system.register_module("camera", _collect_camera, _apply_camera)

func _collect_world() -> Dictionary:
	return {"seed": _world_seed, "game_mode": GameSession.game_mode}

func _apply_world(data: Variant) -> void:
	var world: Dictionary = data if typeof(data) == TYPE_DICTIONARY else {}
	var seed: int = int(world.get("seed", _world_seed))
	seed_input.set_seed(seed)

func _collect_time() -> Dictionary:
	return day_night.serialize() if day_night else {}

func _apply_time(data: Variant) -> void:
	if day_night and typeof(data) == TYPE_DICTIONARY:
		day_night.deserialize(data)

func _collect_weather() -> Dictionary:
	return weather_system.serialize() if weather_system else {}

func _apply_weather(data: Variant) -> void:
	if weather_system and typeof(data) == TYPE_DICTIONARY:
		weather_system.deserialize(data)

func _collect_status() -> Dictionary:
	return status_effects.serialize_all() if status_effects else {}

func _apply_status(data: Variant) -> void:
	if status_effects and typeof(data) == TYPE_DICTIONARY:
		status_effects.deserialize_all(data)

func _collect_buildings() -> Array:
	return building_manager.serialize() if building_manager else []

func _apply_buildings(data: Variant) -> void:
	if building_manager:
		building_manager.deserialize(data)

func _collect_player() -> Dictionary:
	var payload: Dictionary = {
		"position": {"x": 0.0, "y": 0.0},
		"health": {},
		"hunger": {},
		"inventory": {},
		"equipped_tool": "hand"
	}
	if player == null:
		return payload
	var pos: Vector2 = player.get_world_position()
	payload["position"] = {"x": pos.x, "y": pos.y}
	if player.health_component:
		payload["health"] = player.health_component.serialize()
	if player.hunger_component:
		payload["hunger"] = player.hunger_component.serialize()
	if player.inventory:
		payload["inventory"] = player.inventory.serialize()
	payload["equipped_tool"] = player.equipped_tool
	return payload

func _apply_player(data: Variant) -> void:
	if player == null or typeof(data) != TYPE_DICTIONARY:
		return
	var player_data: Dictionary = data
	var pos: Dictionary = player_data.get("position", {"x": 0.0, "y": 0.0})
	player.global_position = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	if player.health_component != null and player_data.has("health"):
		player.health_component.deserialize(player_data["health"])
	if player.hunger_component != null and player_data.has("hunger"):
		player.hunger_component.deserialize(player_data["hunger"])
	if player.inventory != null and player_data.has("inventory"):
		player.inventory.deserialize(player_data["inventory"])
	if player_data.has("equipped_tool"):
		player.equipped_tool = str(player_data.get("equipped_tool", "hand"))

func _collect_camera() -> Dictionary:
	if camera_controller == null:
		return {"rotation": 0.0}
	return {"rotation": camera_controller.rotation}

func _apply_camera(data: Variant) -> void:
	if camera_controller == null or typeof(data) != TYPE_DICTIONARY:
		return
	camera_controller.rotation = float(data.get("rotation", 0.0))
