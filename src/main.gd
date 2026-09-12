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
const CAVE_SPACE_SCENE := preload("res://scenes/cave_space.tscn")
# Cave spaces share the runtime scene tree but live outside the finite surface
# coordinate range. This keeps surface physics and streamed content separate.
const CAVE_SPACE_ORIGIN := Vector2(1000000.0, 1000000.0)

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
@onready var build_palette: Variant = $HUD/BuildPalette
@onready var technology_panel: Variant = $HUD/TechnologyPanel
@onready var mission_manager: MissionManager = $MissionManager
@onready var mission_panel: Variant = $HUD/MissionPanel
@onready var crafting_panel: CraftingPanel = $HUD/CraftingPanel
@onready var save_system: SaveSystem = $SaveSystem
@onready var day_night: DayNightCycle = $DayNightCycle
@onready var weather_system: WeatherSystem = $WeatherSystem
@onready var status_effects: StatusEffectSystem = $StatusEffectSystem
@onready var building_manager: BuildingManager = $BuildingManager
@onready var technology_system: TechnologySystem = $TechnologySystem
@onready var texture_pack_manager: TexturePackManager = $TexturePackManager
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
var _cave_entrance_nodes: Array[CaveEntrance] = []
var _cave_entrances_by_chunk: Dictionary = {}
# Generic runtime nodes for POIs no cave definition links to (sibling of the
# player, same bookkeeping pattern as cave entrances).
var _poi_marker_nodes: Array[PoiMarker] = []
var _poi_markers_by_chunk: Dictionary = {}
# Generic runtime nodes for terrain features (sibling of the player, same
# bookkeeping pattern as POI markers).
var _feature_marker_nodes: Array[TerrainFeatureMarker] = []
var _feature_markers_by_chunk: Dictionary = {}
var _active_cave_space: CaveSpace = null
var _active_cave_id: String = ""
var _surface_position_before_cave: Vector2 = Vector2.ZERO
# Spawn tiles removed by the player. The world itself is deterministic, so
# saves only need this small mutation ledger instead of serializing every
# generated resource and creature in every visited chunk.
var _destroyed_resource_tiles: Dictionary = {}
var _destroyed_creature_tiles: Dictionary = {}
# Stable cave identity/change ledgers. Generation is deterministic; persistence
# records only discoveries and future player-caused cave mutations.
var _discovered_cave_ids: Dictionary = {}
var _cave_changes: Dictionary = {}
# Terrain, resources and creatures are visual/gameplay-heavy to construct.
# Queue generated chunk content so crossing a boundary never builds a whole
# strip of chunks in one frame.
var _pending_chunk_visuals: Array[Vector2i] = []
var _world_info_elapsed := 0.0
var _last_crafting_station_signature := ""

func _ready() -> void:
	# The game is designed around a smooth 60 Hz simulation. Running uncapped
	# needlessly burns CPU/GPU and amplifies garbage-collection spikes.
	Engine.max_fps = 60
	randomize()
	_world_seed = randi() % (SeedInput.MAX_SEED + 1)

	# Connect all signals first, then push the seed in: SeedInput.set_seed
	# emits seed_changed synchronously, which triggers initial world generation.
	var event_bus: Node = $GameEventBus
	seed_input.seed_changed.connect(_on_seed_changed)
	event_bus.world_seed_set.connect(_on_world_seed_set)
	event_bus.inventory_changed.connect(_on_inventory_changed)
	event_bus.toggle_inventory_ui.connect(_on_toggle_inventory_ui)
	event_bus.tool_broken.connect(_on_tool_broken)
	event_bus.toggle_missions_ui.connect(_on_toggle_missions_ui)
	event_bus.missions_changed.connect(_on_missions_changed)
	event_bus.mission_completed.connect(_on_mission_completed)
	event_bus.toggle_crafting_ui.connect(_on_toggle_crafting_ui)
	chunk_system.chunk_generated.connect(_on_chunk_generated)
	chunk_system.chunk_unloaded.connect(_on_chunk_unloaded)
	crafting_panel.recipe_craft_requested.connect(_on_craft_requested)
	player.died.connect(_on_player_died)
	inventory_panel.hotbar_assignment_changed.connect(_on_hotbar_assignment_changed)
	inventory_panel.hotbar_slot_requested.connect(_on_hotbar_slot_requested)
	player.hotbar_changed.connect(_on_hotbar_changed)
	player.hotbar_slot_changed.connect(inventory_panel.set_active_hotbar_slot)

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
	building_manager.building_placed.connect(_on_building_placed)
	building_manager.building_removed.connect(_on_building_removed)
	# HUD (health/hunger bars, seed label, optional debug readout).
	hud.set_player(player)
	hud.set_seed(_world_seed)

	# Initialize the item database BEFORE the first refresh: the crafting
	# panel is filled from item_database.recipes, and nothing else in the
	# project calls initialize() (without this the panel shows 0 recipes).
	item_database.initialize()
	technology_system.initialize(player)
	building_manager.technology_system = technology_system
	technology_system.technology_unlocked.connect(_on_technology_unlocked)
	technology_system.technology_unlock_failed.connect(_on_technology_unlock_failed)
	if texture_pack_manager != null:
		texture_pack_manager.texture_pack_changed.connect(_on_texture_pack_changed)
	if build_palette != null:
		build_palette.configure(building_manager, item_database)
		build_palette.part_selected.connect(_on_build_part_selected)
	if technology_panel != null:
		technology_panel.configure(technology_system, item_database, player)
		technology_panel.unlock_requested.connect(_on_technology_unlock_requested)

	if mission_panel != null:
		mission_panel.configure(mission_manager)

	# Tell the player's inventory the real per-item stack sizes from the
	# database (the component defaults to 64 for everything without this).
	if player and player.inventory:
		var stack_sizes: Dictionary = {}
		for item_id in item_database.items:
			var item_def: ItemDefinition = item_database.get_item(item_id)
			if item_def != null:
				stack_sizes[str(item_id)] = int(item_def.stack_size)
		player.inventory.set_stack_sizes(stack_sizes)
	player.inventory.set_item_durations(item_database.get_all_durations())

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
	# A seed change starts a fresh world. Loading restores its mutation ledger
	# immediately after this reset through the world_state save module.
	if is_in_cave():
		_exit_cave(false)
	_destroyed_resource_tiles.clear()
	_destroyed_creature_tiles.clear()
	_discovered_cave_ids.clear()
	_cave_changes.clear()
	# Free the previous world's resource nodes and rendered terrain first.
	for node in _resource_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_resource_nodes.clear()
	_resources_by_chunk.clear()
	_pending_chunk_visuals.clear()
	terrain_renderer.clear_all()

	# Free the previous world's creature nodes and spawner records.
	for creature in _creature_nodes:
		if is_instance_valid(creature):
			creature.queue_free()
	_creature_nodes.clear()
	_creatures_by_chunk.clear()
	for entrance in _cave_entrance_nodes:
		if is_instance_valid(entrance):
			entrance.queue_free()
	_cave_entrance_nodes.clear()
	_cave_entrances_by_chunk.clear()
	for marker in _poi_marker_nodes:
		if is_instance_valid(marker):
			marker.queue_free()
	_poi_marker_nodes.clear()
	_poi_markers_by_chunk.clear()
	for feature in _feature_marker_nodes:
		if is_instance_valid(feature):
			feature.queue_free()
	_feature_marker_nodes.clear()
	_feature_markers_by_chunk.clear()
	if building_manager:
		building_manager.clear_all()

	world_generator.initialize(seed)
	resource_spawner.initialize(seed)
	creature_spawner.initialize(seed)
	chunk_system.initialize(seed, world_generator.get_configuration())
	chunk_system.set_viewport_radius(world_generator.get_configuration().streaming_radius)

	# Player returns to spawn; the chunk system loads the starting ring
	# (chunk_generated signals drive terrain rendering + resource spawns).
	player.global_position = Vector2.ZERO
	chunk_system.update_player_position(player.get_world_position())

	_refresh_ui()

## A chunk was generated by the chunk system: render terrain, spawn resources.
## This also fires when the player wanders into newly loaded chunks.
func _on_chunk_generated(chunk_coords: Vector2i) -> void:
	_queue_chunk_visual(chunk_coords)

func _queue_chunk_visual(chunk_coords: Vector2i) -> void:
	if _pending_chunk_visuals.has(chunk_coords):
		return
	# Nearest chunks are completed first, so the player's immediate area is
	# always ready before the outer streaming ring.
	var center: Vector2i = chunk_system.get_player_chunk()
	var distance: int = maxi(abs(chunk_coords.x - center.x), abs(chunk_coords.y - center.y))
	var insert_at: int = _pending_chunk_visuals.size()
	for index in range(_pending_chunk_visuals.size()):
		var queued: Vector2i = _pending_chunk_visuals[index]
		var queued_distance: int = maxi(abs(queued.x - center.x), abs(queued.y - center.y))
		if distance < queued_distance:
			insert_at = index
			break
	_pending_chunk_visuals.insert(insert_at, chunk_coords)

func _process_one_chunk_visual() -> void:
	if _pending_chunk_visuals.is_empty():
		return
	var chunk_coords: Vector2i = _pending_chunk_visuals.pop_front()
	var data: Dictionary = chunk_system.get_chunk(chunk_coords)
	if data.is_empty():
		return
	var start_usec := Time.get_ticks_usec()
	terrain_renderer.update_chunk(chunk_coords, data)
	_spawn_resources_for_chunk(chunk_coords, data)
	_spawn_creatures_for_chunk(chunk_coords)
	_spawn_pois_for_chunk(chunk_coords, data)
	_spawn_features_for_chunk(chunk_coords, data)
	if performance_overlay != null:
		performance_overlay.record_chunk_load(chunk_coords,
				float(Time.get_ticks_usec() - start_usec) / 1000.0)

## Test/tool hook: drains deferred chunk presentation deliberately, while
## normal play uses one chunk per frame to keep movement responsive.
func flush_pending_chunk_visuals() -> void:
	while not _pending_chunk_visuals.is_empty():
		_process_one_chunk_visual()

## A chunk left the viewport: free its resources and clear its terrain.
func _on_chunk_unloaded(chunk_coords: Vector2i) -> void:
	_pending_chunk_visuals.erase(chunk_coords)
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
	var entrances: Array = _cave_entrances_by_chunk.get(chunk_coords, [])
	for entrance in entrances:
		if is_instance_valid(entrance):
			_cave_entrance_nodes.erase(entrance)
			entrance.queue_free()
	_cave_entrances_by_chunk.erase(chunk_coords)
	# Free that chunk's generic POI markers (same bookkeeping as entrances).
	var markers: Array = _poi_markers_by_chunk.get(chunk_coords, [])
	for marker in markers:
		if is_instance_valid(marker):
			_poi_marker_nodes.erase(marker)
			marker.queue_free()
	_poi_markers_by_chunk.erase(chunk_coords)
	# Free that chunk's terrain-feature markers (same bookkeeping as POIs).
	var feature_nodes: Array = _feature_markers_by_chunk.get(chunk_coords, [])
	for feature in feature_nodes:
		if is_instance_valid(feature):
			_feature_marker_nodes.erase(feature)
			feature.queue_free()
	_feature_markers_by_chunk.erase(chunk_coords)
	terrain_renderer.clear_chunk(chunk_coords)

## Spawn harvestable resources in a chunk (as siblings of the player).
## The chunk payload's terrain-feature mask (WG-04) is handed to the spawner:
## features whose influence tags include its spawn-block tag veto tiles.
func _spawn_resources_for_chunk(chunk_coords: Vector2i, chunk_data: Dictionary) -> void:
	var feature_candidates: Array = chunk_data.get("feature_candidates", [])
	var resources: Array = resource_spawner.generate_chunk_resources(chunk_coords, _world_seed, feature_candidates)
	var spawn_count: int = 0
	for res_data in resources:
		var x_val: int = int(res_data.get("x", 0))
		var y_val: int = int(res_data.get("y", 0))
		var spawn_tile := Vector2i(x_val, y_val)
		if _destroyed_resource_tiles.has(spawn_tile):
			# The deterministic generator created a transient record before Main
			# could apply the save ledger. Remove it as well as skipping the node.
			resource_spawner.remove_resource(spawn_tile)
			continue
		var res_type: String = str(res_data.get("type", "rock"))

		# Create a real HarvestableResource node (sibling of the player
		# under Main, so the player's nearby-resource scan can find it).
		var resource := HarvestableResource.new()
		resource.position = Vector2(x_val, y_val) * float(TILE_SIZE)
		resource.setup(res_type, float(res_data.get("health", 100.0)), res_data.get("yields", []))
		resource.set_meta("resource_type", res_type)
		resource.set_meta("chunk_coords", chunk_coords)
		resource.set_meta("spawn_tile", spawn_tile)
		resource.resource_depleted.connect(_on_resource_depleted.bind(resource))
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
		var spawn_tile := Vector2i(int(creature_data.get("x", 0)), int(creature_data.get("y", 0)))
		if _destroyed_creature_tiles.has(spawn_tile):
			creature_spawner.remove_creature(spawn_tile)
			continue
		var def: CreatureDefinition = creature_spawner.get_definition(ctype)
		if def == null:
			continue

		# Create a real Creature node (sibling of the player under Main).
		var creature := Creature.new()
		creature.position = Vector2(spawn_tile) * float(TILE_SIZE)
		creature.setup(ctype, def, chunk_coords, world_generator)
		creature.set_meta("chunk_coords", chunk_coords)
		creature.set_meta("spawn_tile", spawn_tile)
		creature.creature_died.connect(_on_creature_died.bind(creature))
		add_child(creature)
		_creature_nodes.append(creature)
		if not _creatures_by_chunk.has(chunk_coords):
			_creatures_by_chunk[chunk_coords] = []
		_creatures_by_chunk[chunk_coords].append(creature)

## Populate intentional POIs emitted by the world-generation pipeline.
## The routing is by data fields, not content names: a candidate that a
## cave definition links to becomes a CaveEntrance (the cave consumer of
## the generic POI layer); any other candidate becomes a plain PoiMarker.
## New POI runtime types can attach here without a content-name branch.
func _spawn_pois_for_chunk(chunk_coords: Vector2i, chunk_data: Dictionary) -> void:
	var candidates: Array = chunk_data.get("poi_candidates", [])
	for candidate in candidates:
		var cave_type_id := str(candidate.get("cave_type_id", ""))
		if cave_type_id.is_empty():
			var marker := PoiMarker.new()
			marker.setup(candidate)
			marker.position = Vector2(marker.marker_tile) * float(TILE_SIZE) + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
			marker.set_meta("chunk_coords", chunk_coords)
			add_child(marker)
			_poi_marker_nodes.append(marker)
			if not _poi_markers_by_chunk.has(chunk_coords):
				_poi_markers_by_chunk[chunk_coords] = []
			_poi_markers_by_chunk[chunk_coords].append(marker)
			continue
		var cave_id := str(candidate.get("cave_id", ""))
		if cave_id.is_empty():
			continue
		var entrance := CaveEntrance.new()
		entrance.setup(candidate)
		entrance.position = Vector2(entrance.entrance_tile) * float(TILE_SIZE) + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
		entrance.set_meta("chunk_coords", chunk_coords)
		entrance.entered.connect(_on_cave_entrance_entered)
		add_child(entrance)
		_cave_entrance_nodes.append(entrance)
		if not _cave_entrances_by_chunk.has(chunk_coords):
			_cave_entrances_by_chunk[chunk_coords] = []
		_cave_entrances_by_chunk[chunk_coords].append(entrance)

## Populate terrain features emitted by the world-generation pipeline. Only
## candidates whose anchor is inside this chunk get a marker here — halo
## entries (footprints crossing in from neighbouring chunks) supply the mask
## for placement but are marked by their owning chunk exactly once.
func _spawn_features_for_chunk(chunk_coords: Vector2i, chunk_data: Dictionary) -> void:
	var candidates: Array = chunk_data.get("feature_candidates", [])
	for candidate in candidates:
		if not bool(candidate.get("in_chunk", false)):
			continue
		var marker := TerrainFeatureMarker.new()
		marker.setup(candidate)
		marker.position = Vector2(marker.marker_tile) * float(TILE_SIZE) + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
		marker.set_meta("chunk_coords", chunk_coords)
		add_child(marker)
		_feature_marker_nodes.append(marker)
		if not _feature_markers_by_chunk.has(chunk_coords):
			_feature_markers_by_chunk[chunk_coords] = []
		_feature_markers_by_chunk[chunk_coords].append(marker)

func get_cave_entrances() -> Array[CaveEntrance]:
	return _cave_entrance_nodes.duplicate()

func is_in_cave() -> bool:
	return _active_cave_space != null and is_instance_valid(_active_cave_space)

func _on_cave_entrance_entered(entrance: CaveEntrance) -> void:
	enter_cave_from_entrance(entrance)

## Enter a separate generated cave space from a stable surface entrance.
func enter_cave_from_entrance(entrance: CaveEntrance) -> bool:
	if is_in_cave() or entrance == null or not is_instance_valid(entrance):
		return false
	var definition: CaveDefinition = world_generator.get_cave(entrance.cave_type_id)
	if definition == null:
		return false
	var generator := CaveSpaceGenerator.new()
	var generated := generator.generate_cave(_world_seed, entrance.cave_id, entrance.entrance_tile,
			definition, world_generator.get_content_registry().resources)
	if generated.is_empty():
		return false
	_active_cave_id = entrance.cave_id
	_surface_position_before_cave = player.global_position
	_active_cave_space = CAVE_SPACE_SCENE.instantiate() as CaveSpace
	if _active_cave_space == null:
		return false
	_active_cave_space.name = "ActiveCaveSpace"
	_active_cave_space.z_index = -5
	_active_cave_space.position = CAVE_SPACE_ORIGIN
	_active_cave_space.setup(generated)
	_active_cave_space.exit_requested.connect(_on_cave_exit_requested)
	add_child(_active_cave_space)
	_discovered_cave_ids[_active_cave_id] = true
	terrain_renderer.set_world_visible(false)
	if building_manager != null:
		building_manager.visible = false
	for node in _resource_nodes:
		if is_instance_valid(node):
			node.visible = false
	for creature in _creature_nodes:
		if is_instance_valid(creature):
			creature.visible = false
			creature.process_mode = Node.PROCESS_MODE_DISABLED
	for cave_entrance in _cave_entrance_nodes:
		if is_instance_valid(cave_entrance):
			cave_entrance.visible = false
	for marker in _poi_marker_nodes:
		if is_instance_valid(marker):
			marker.visible = false
	player.global_position = _active_cave_space.to_global(_active_cave_space.exit_position)
	if hud != null:
		hud.show_toast("Entered %s  (E near the entrance to leave)" % definition.display_name)
	return true

func interact_with_active_cave() -> bool:
	if not is_in_cave():
		return false
	if _active_cave_space.contains_exit(player.global_position):
		_active_cave_space.request_exit()
		return true
	return false

func _on_cave_exit_requested() -> void:
	_exit_cave(true)

func _exit_cave(show_toast: bool = true) -> void:
	if not is_in_cave():
		return
	if is_instance_valid(_active_cave_space):
		_active_cave_space.queue_free()
	_active_cave_space = null
	_active_cave_id = ""
	player.global_position = _surface_position_before_cave
	terrain_renderer.set_world_visible(true)
	if building_manager != null:
		building_manager.visible = true
	for node in _resource_nodes:
		if is_instance_valid(node):
			node.visible = true
	for creature in _creature_nodes:
		if is_instance_valid(creature):
			creature.visible = true
			creature.process_mode = Node.PROCESS_MODE_INHERIT
	for cave_entrance in _cave_entrance_nodes:
		if is_instance_valid(cave_entrance):
			cave_entrance.visible = true
	for marker in _poi_marker_nodes:
		if is_instance_valid(marker):
			marker.visible = true
	if show_toast and hud != null:
		hud.show_toast("Returned to the surface")

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
	var spawn_tile: Vector2i = creature_node.get_meta("spawn_tile", Vector2i.ZERO)
	_destroyed_creature_tiles[spawn_tile] = true
	creature_spawner.remove_creature(spawn_tile)
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

func _on_tool_broken(item_id: String) -> void:
	var item_name := item_database.get_item_display_name(item_id) if item_database.has_item(item_id) else item_id
	hud.show_toast("%s broke!" % item_name)
	_refresh_ui()

func _on_toggle_missions_ui() -> void:
	if mission_panel != null:
		mission_panel.toggle()

func _on_missions_changed() -> void:
	if mission_panel != null and mission_panel.visible:
		mission_panel.refresh()

func _on_mission_completed(mission_id: String) -> void:
	if mission_panel != null:
		var mission := mission_manager.get_mission(mission_id)
		hud.show_toast("Mission complete: %s" % (mission.title if mission != null else mission_id))
		if mission_panel.visible:
			mission_panel.refresh()

## Record the depleted spawn before the node leaves the tree. This is kept
## separate from loot because an unlucky resource can yield no optional drops.
func _on_resource_depleted(resource_node: Node) -> void:
	if _resource_nodes.has(resource_node):
		_resource_nodes.erase(resource_node)
	var chunk_key: Vector2i = resource_node.get_meta("chunk_coords", Vector2i(0, 0))
	var chunk_list: Array = _resources_by_chunk.get(chunk_key, [])
	if chunk_list.has(resource_node):
		chunk_list.erase(resource_node)
	var spawn_tile: Vector2i = resource_node.get_meta("spawn_tile", Vector2i.ZERO)
	_destroyed_resource_tiles[spawn_tile] = true
	resource_spawner.remove_resource(spawn_tile)

## A harvestable resource yielded an item: hand it to the player.
func _on_resource_destroyed(_resource_node: Node, item_id: String, quantity: int) -> void:
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
	inventory_panel.toggle()

func _on_hotbar_assignment_changed(assignments: Array[String]) -> void:
	if player != null:
		player.set_hotbar_items(assignments)
	_refresh_ui()

func _on_hotbar_slot_requested(slot_index: int) -> void:
	if player != null:
		player.select_hotbar_slot(slot_index)

func _on_hotbar_changed(_assignments: Array[String]) -> void:
	_refresh_ui()

func _on_build_part_selected(item_id: String) -> void:
	if building_manager != null and building_manager.select_item(item_id):
		if build_palette != null:
			build_palette.show_status("Selected %s — click a clear tile to place it" % item_database.get_item_display_name(item_id))

func _on_building_placed(item_id: String, coords: Vector2i) -> void:
	$GameEventBus.building_placed.emit(item_id, coords)
	_refresh_crafting_ui()

func _on_building_removed(_item_id: String, _coords: Vector2i) -> void:
	_refresh_crafting_ui()

func _on_technology_unlock_requested(technology_id: String) -> void:
	if technology_system != null:
		technology_system.try_unlock(technology_id, player.inventory if player != null else null)

func _on_technology_unlocked(technology_id: String) -> void:
	var definition := technology_system.get_definition(technology_id) if technology_system != null else null
	if technology_panel != null:
		technology_panel.show_status("%s researched" % (definition.display_name if definition != null else technology_id))
	_refresh_ui()

func _on_technology_unlock_failed(_technology_id: String, reason: String) -> void:
	if technology_panel != null:
		technology_panel.show_status(reason)

## Texture packs are presentation-only. Rebuild live visual layers while
## leaving generated chunks, terrain collision, inventory, and save state
## completely intact so a visual refinement can be tested mid-session.
func _on_texture_pack_changed(_pack_id: String) -> void:
	if terrain_renderer != null:
		terrain_renderer.refresh_texture_pack()
	if player != null:
		player.reload_visual_texture()
	for resource in _resource_nodes:
		if is_instance_valid(resource) and resource.has_method("reload_visual_texture"):
			resource.reload_visual_texture()
	for creature in _creature_nodes:
		if is_instance_valid(creature) and creature.has_method("reload_visual_texture"):
			creature.reload_visual_texture()
	if building_manager != null:
		building_manager.refresh_texture_pack()

## Player toggled the crafting UI (C key, via the event bus).
func _on_toggle_crafting_ui() -> void:
	crafting_panel.visible = not crafting_panel.visible
	if crafting_panel.visible:
		_refresh_crafting_ui()

## Per-frame: keep chunk loading in sync with the player, move the camera, keep the HUD
## in step with the seed editor, and update the debug overlay.
func _process(delta: float) -> void:
	if not is_in_cave():
		chunk_system.update_player_position(player.get_world_position())
		_process_one_chunk_visual()
	# The camera is a plain Camera2D node that nothing else drives; without
	# this it never follows the player.
	if camera_controller != null and is_instance_valid(player):
		camera_controller.set_target(player.get_world_position())
		if camera_controller.has_method("set_rotation_locked") and seed_input != null:
			camera_controller.set_rotation_locked(seed_input.is_editing())
	# Reflect the seed editor (T) state in the HUD seed label.
	if hud != null and seed_input != null:
		hud.set_seed_editing(seed_input.is_editing(), seed_input.get_input_buffer())
	_world_info_elapsed += delta
	if _world_info_elapsed >= 0.20:
		_update_world_presentation(delta)
		_world_info_elapsed = 0.0
	_update_debug_overlay()
	if performance_overlay != null:
		performance_overlay.update_frame(delta, chunk_system.get_loaded_chunk_count(),
				_resource_nodes.size(), _creature_nodes.size())
	if crafting_panel != null and crafting_panel.visible:
		var station_signature := ",".join(_get_nearby_station_ids())
		if station_signature != _last_crafting_station_signature:
			_refresh_crafting_ui()

	if pause_menu != null and pause_menu.visible:
		return
	if Input.is_action_just_pressed("toggle_debug"):
		_toggle_debug()
	if Input.is_action_just_pressed("save"):
		save_game()
	if Input.is_action_just_pressed("load"):
		load_game()
	if Input.is_action_just_pressed("toggle_technology"):
		if technology_panel != null:
			technology_panel.toggle()

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
			extra = "   Build L%d: %s  (LMB place, wheel cycle, [ / ] story, F demolish, B exit)" % [building_manager.selected_story + 1, building_manager.selected_item_id]
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
	var items: Dictionary = player.inventory.get_all_items()
	inventory_panel.refresh(items, player.get_hotbar_items(), player.inventory.get_all_durations())
	_refresh_crafting_ui()
	if technology_panel != null:
		technology_panel.refresh()

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
		if not _is_recipe_unlocked(def):
			continue
		_recipe_defs.append(def)
		recipe_dicts.append(_recipe_to_dict(def))

	var nearby_stations := _get_nearby_station_ids()
	_last_crafting_station_signature = ",".join(nearby_stations)
	crafting_panel.refresh(recipe_dicts, inv_data, nearby_stations)

func _get_nearby_station_ids() -> PackedStringArray:
	if GameSession.is_creative() or building_manager == null or player == null:
		return PackedStringArray()
	return building_manager.get_nearby_station_ids(player.get_world_position())

func _has_required_crafting_station(def: RecipeDefinition) -> bool:
	return GameSession.is_creative() or def.crafting_station.is_empty() or _get_nearby_station_ids().has(def.crafting_station)

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

func _is_recipe_unlocked(def: RecipeDefinition) -> bool:
	return GameSession.is_creative() or technology_system == null or technology_system.is_unlocked(def.technology_id)

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
	if not _is_recipe_unlocked(def):
		$GameEventBus.recipe_failed.emit(def.recipe_id, "technology_locked")
		return
	if not _has_required_crafting_station(def):
		$GameEventBus.recipe_failed.emit(def.recipe_id, "requires_nearby_%s" % def.crafting_station)
		_refresh_crafting_ui()
		return
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
	save_system.register_module("world_state", _collect_world_state, _apply_world_state)
	save_system.register_module("time", _collect_time, _apply_time)
	save_system.register_module("weather", _collect_weather, _apply_weather)
	save_system.register_module("status", _collect_status, _apply_status)
	save_system.register_module("technology", _collect_technology, _apply_technology)
	save_system.register_module("buildings", _collect_buildings, _apply_buildings)
	save_system.register_module("player", _collect_player, _apply_player)
	save_system.register_module("missions", _collect_missions, _apply_missions)
	save_system.register_module("camera", _collect_camera, _apply_camera)

func _collect_world() -> Dictionary:
	return {"seed": _world_seed, "game_mode": GameSession.game_mode}

func _apply_world(data: Variant) -> void:
	var world: Dictionary = data if typeof(data) == TYPE_DICTIONARY else {}
	var seed: int = int(world.get("seed", _world_seed))
	seed_input.set_seed(seed)

## JSON-safe mutation ledger. Spawn coordinates are stable across chunk
## unload/reload and across future save format changes, unlike Node paths.
func _collect_world_state() -> Dictionary:
	return {
		"destroyed_resources": _serialize_tiles(_destroyed_resource_tiles),
		"destroyed_creatures": _serialize_tiles(_destroyed_creature_tiles),
		"discovered_caves": _serialize_string_keys(_discovered_cave_ids),
		"cave_changes": _cave_changes.duplicate(true)
	}

func _apply_world_state(data: Variant) -> void:
	_destroyed_resource_tiles.clear()
	_destroyed_creature_tiles.clear()
	_discovered_cave_ids.clear()
	_cave_changes.clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var state: Dictionary = data
	_destroyed_resource_tiles = _deserialize_tiles(state.get("destroyed_resources", []))
	_destroyed_creature_tiles = _deserialize_tiles(state.get("destroyed_creatures", []))
	_discovered_cave_ids = _deserialize_string_keys(state.get("discovered_caves", []))
	if typeof(state.get("cave_changes", {})) == TYPE_DICTIONARY:
		_cave_changes = (state.get("cave_changes", {}) as Dictionary).duplicate(true)

func _serialize_tiles(tiles: Dictionary) -> Array:
	var out: Array = []
	for key in tiles:
		var tile: Vector2i = key
		out.append({"x": tile.x, "y": tile.y})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ay: int = int(a.get("y", 0))
		var by: int = int(b.get("y", 0))
		return int(a.get("x", 0)) < int(b.get("x", 0)) if ay == by else ay < by
	)
	return out

func _deserialize_tiles(data: Variant) -> Dictionary:
	var tiles: Dictionary = {}
	if typeof(data) != TYPE_ARRAY:
		return tiles
	for entry in data:
		if typeof(entry) == TYPE_DICTIONARY:
			tiles[Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))] = true
	return tiles

func _serialize_string_keys(values: Dictionary) -> Array[String]:
	var output: Array[String] = []
	for key in values:
		output.append(str(key))
	output.sort()
	return output

func _deserialize_string_keys(data: Variant) -> Dictionary:
	var values: Dictionary = {}
	if typeof(data) != TYPE_ARRAY:
		return values
	for value in data:
		if not str(value).is_empty():
			values[str(value)] = true
	return values

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

func _collect_technology() -> Dictionary:
	return technology_system.serialize() if technology_system else {}

func _apply_technology(data: Variant) -> void:
	if technology_system:
		technology_system.deserialize(data)

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
		"equipped_tool": "hand",
		"hotbar": [],
		"active_hotbar_slot": -1
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
	payload["hotbar"] = player.get_hotbar_items()
	payload["active_hotbar_slot"] = player.active_hotbar_slot
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
	if player_data.has("hotbar"):
		var stored_hotbar: Array[String] = []
		for item_id in player_data.get("hotbar", []):
			stored_hotbar.append(str(item_id))
		player.set_hotbar_items(stored_hotbar)
	else:
		# Older saves did not have quick-bar assignments; create a useful
		# initial layout once rather than discarding their inventory ordering.
		player.populate_hotbar_from_inventory()
	if player_data.has("active_hotbar_slot"):
		player.select_hotbar_slot(int(player_data.get("active_hotbar_slot", -1)))
	if player_data.has("equipped_tool"):
		player.equipped_tool = str(player_data.get("equipped_tool", "hand"))
		player.tool_changed.emit(player.equipped_tool)

func _collect_camera() -> Dictionary:
	if camera_controller == null:
		return {"rotation": 0.0}
	return {"rotation": camera_controller.rotation}

func _apply_camera(data: Variant) -> void:
	if camera_controller == null or typeof(data) != TYPE_DICTIONARY:
		return
	camera_controller.rotation = float(data.get("rotation", 0.0))

func _collect_missions() -> Dictionary:
	if mission_manager == null:
		return {}
	return mission_manager.serialize()

func _apply_missions(data: Variant) -> void:
	if mission_manager != null:
		mission_manager.apply_missions(data)
