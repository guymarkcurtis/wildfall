## Main game scene controller for Wildfall.
extends Node

const SAVE_VERSION: int = 1

@onready var player: CharacterBody2D = $Player
@onready var world_generator: Node = $WorldGenerator
@onready var chunk_system: Node = $ChunkSystem
@onready var terrain_renderer: TileMapLayer = $TerrainRenderer
@onready var resource_spawner: Node = $ResourceSpawner
@onready var camera_controller: Node = $CameraController
@onready var debug_overlay: CanvasLayer = $DebugOverlay
@onready var seed_input: Node = $SeedInput
@onready var item_database: Node = $ItemDatabase
@onready var inventory_panel: Control = $HUD/InventoryPanel
@onready var crafting_panel: Control = $HUD/CraftingPanel

var _world_seed: int = 0
var _is_editing_seed: bool = false
var _resource_nodes: Array = []
var _inventory: Dictionary = {}
var _show_ui: bool = false

func _ready() -> void:
	# Initialize game systems
	_world_seed = _generate_seed()
	item_database.initialize()
	_initialize_game()

	# Connect event bus signals
	$GameEventBus.world_seed_set.connect(_on_world_seed_set)
	$GameEventBus.toggle_debug.connect(_on_toggle_debug)
	seed_input.seed_changed.connect(_on_seed_changed)

	# Set up camera target
	camera_controller.set_target(player.global_position)

	# Set up debug overlay
	debug_overlay.set_enabled(false)

	# Generate initial world
	_generate_world(_world_seed)
	
	# Set up inventory UI
	_refresh_ui()

func _generate_seed() -> int:
	return randi() % 999999

func _initialize_game() -> void:
	pass

func _generate_world(seed: int) -> void:
	chunk_system.initialize(seed)
	world_generator.initialize(seed)

	# Generate and render chunks around origin
	_generate_initial_chunks(seed)

	# Spawn resources
	resource_spawner.initialize(seed)
	_generate_initial_resources(seed)

## Generate initial chunks around the player.
func _generate_initial_chunks(seed: int) -> void:
	for x in range(-3, 4):
		for y in range(-3, 4):
			var chunk_coords: String = "%d,%d" % [x, y]
			var chunk_data: Dictionary = world_generator.call("generate_chunk", chunk_coords, seed)
			terrain_renderer.update_chunk(chunk_coords, chunk_data)

## Generate initial resources around the player.
func _generate_initial_resources(seed: int) -> void:
	_resource_nodes.clear()
	for x in range(-3, 4):
		for y in range(-3, 4):
			var chunk_coords: String = "%d,%d" % [x, y]
			var resources: Array[Dictionary] = resource_spawner.generate_chunk_resources(chunk_coords, seed)
			for res_data in resources:
				var coords: String = res_data["coords"]
				var parts: PackedStringArray = coords.split(",")
				var x_val: int = int(parts[0])
				var y_val: int = int(parts[1])
				var type: String = res_data["type"]
				var health: float = res_data["health"]
				var yields: Array[Dictionary] = res_data["yields"]

				# Create a simple placeholder node for the resource
				var resource := Node2D.new()
				resource.position = Vector2(x_val, y_val)
				resource.set_meta("resource_type", type)
				resource.set_meta("health", health)
				resource.set_meta("yields", yields)
				add_child(resource)
				_resource_nodes.append(resource)

## Update player position and manage chunk loading/unloading.
func _update_chunks() -> void:
	chunk_system.update_player_position(player.global_position)

	# Update terrain for newly generated chunks
	var loaded_chunks: Array = chunk_system.get_loaded_chunks()
	for chunk_coords in loaded_chunks:
		var chunk_data: Dictionary = chunk_system.get_chunk(chunk_coords)
		if not chunk_data.is_empty():
			terrain_renderer.update_chunk(chunk_coords, chunk_data)

func _process(delta: float) -> void:
	# Update camera to follow player
	camera_controller.set_target(player.global_position)

	# Update chunks
	_update_chunks()

	# Update debug overlay
	_update_debug_overlay()

	# Handle seed input
	_handle_seed_input()
	
	# Handle UI toggle
	if Input.is_action_just_pressed("toggle_inventory"):
		_show_ui = not _show_ui
		inventory_panel.visible = _show_ui
		crafting_panel.visible = _show_ui

## Handle seed input.
func _handle_seed_input() -> void:
	if Input.is_key_pressed(KEY_T):
		if not _is_editing_seed:
			_is_editing_seed = true
			seed_input.start_editing()
	elif _is_editing_seed:
		if Input.is_key_pressed(KEY_ENTER):
			seed_input.finish_editing()
			_is_editing_seed = false
		elif Input.is_key_pressed(KEY_ESCAPE):
			seed_input.cancel_editing()
			_is_editing_seed = false

## Update debug overlay.
func _update_debug_overlay() -> void:
	var tile_pos: Vector2i = Vector2i(player.global_position)
	var chunk_pos: Vector2i = chunk_system.world_to_chunk_coords(tile_pos)
	var noise_vals: Dictionary = world_generator.get_noise_values(player.global_position.x, player.global_position.y)
	var biome: String = "unknown"
	var chunk_data: Dictionary = chunk_system.get_chunk(chunk_pos)
	if not chunk_data.is_empty():
		biome = chunk_data.get("biome", "unknown")

	debug_overlay.update_debug(
		player.global_position,
		tile_pos,
		chunk_pos,
		_world_seed,
		biome,
		noise_vals,
		Engine.get_frames_per_second()
	)

## Refresh UI displays.
func _refresh_ui() -> void:
	# Refresh inventory panel
	if inventory_panel:
		inventory_panel.refresh(_inventory)
	
	# Refresh crafting panel with recipes
	if crafting_panel:
		var recipes: Array[Dictionary] = []
		var item_db: Node = $ItemDatabase
		if item_db:
			var all_recipes: Dictionary = item_db.call("recipes")
			for recipe_id in all_recipes:
				var recipe: Dictionary = all_recipes[recipe_id]
				recipes.append({
					"recipe_id": recipe_id,
					"result_item_id": recipe.result_item_id,
					"result_quantity": recipe.result_quantity,
					"crafting_station": recipe.crafting_station,
					"required_items": recipe.required_items
				})
		crafting_panel.refresh(recipes, _inventory)

## Toggle debug overlay.
func _on_toggle_debug() -> void:
	debug_overlay.toggle()

func _on_world_seed_set(seed: int) -> void:
	_world_seed = seed
	_generate_world(seed)
	terrain_renderer.clear_all()
	resource_spawner.initialize(seed)
	_generate_initial_chunks(seed)
	_generate_initial_resources(seed)

func _on_seed_changed(seed: int) -> void:
	_world_seed = seed
	_generate_world(seed)
	terrain_renderer.clear_all()
	resource_spawner.initialize(seed)
	_generate_initial_chunks(seed)
	_generate_initial_resources(seed)

## Save game.
func save_game(path: String = "user://savegame.json") -> void:
	var save_system := get_node_or_null("SaveSystem") as Node
	if save_system:
		save_system.save_game(path)

## Load game.
func load_game(path: String = "user://savegame.json") -> void:
	var save_system := get_node_or_null("SaveSystem") as Node
	if save_system:
		save_system.load_game(path)
