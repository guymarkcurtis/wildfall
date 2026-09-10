## Main game scene controller.
extends Node

const SAVE_VERSION: int = 1

@onready var player: CharacterBody2D = $Player
@onready var world_generator: Node = $WorldGenerator
@onready var chunk_system: Node = $ChunkSystem
@onready var hud: CanvasLayer = $HUD
@onready var inventory_panel: Control = $InventoryPanel
@onready var crafting_panel: Control = $CraftingPanel
@onready var save_system: Node = $SaveSystem

var _world_seed: int = 0

func _ready() -> void:
	# Initialize game systems
	_world_seed = _generate_seed()
	_initialize_game()

	# Connect event bus signals
	GameEventBus.toggle_inventory_ui.connect(_on_toggle_inventory)
	GameEventBus.toggle_crafting_ui.connect(_on_toggle_crafting)
	GameEventBus.debug_mode_toggled.connect(_on_debug_toggled)
	GameEventBus.world_seed_set.connect(_on_world_seed_set)

	# Set up HUD
	hud.set_player(player)
	hud.set_seed(_world_seed)

	# Set up inventory panel
	inventory_panel.set_inventory(player.inventory)

	# Set up crafting panel
	crafting_panel.set_crafting($CraftingComponent, player.inventory)

	# Generate initial world
	_generate_world(_world_seed)

func _generate_seed() -> int:
	return randi() % 999999

func _initialize_game() -> void:
	# Initialize world generator with default biomes
	_add_default_biomes()

	# Register default recipes
	_add_default_recipes()

func _add_default_biomes() -> void:
	var grassland := BiomeDefinition.new()
	grassland.id = "grassland"
	grassland.display_name = "Grassland"
	grassland.elevation_range = Vector2(0.3, 0.7)
	grassland.moisture_range = Vector2(0.3, 0.7)
	grassland.temperature_range = Vector2(0.3, 0.7)
	grassland.ground_color = Color(0.2, 0.6, 0.2)
	world_generator.register_biome(grassland)

	var desert := BiomeDefinition.new()
	desert.id = "desert"
	desert.display_name = "Desert"
	desert.elevation_range = Vector2(0.2, 0.5)
	desert.moisture_range = Vector2(0.0, 0.2)
	desert.temperature_range = Vector2(0.6, 1.0)
	desert.ground_color = Color(0.8, 0.7, 0.4)
	world_generator.register_biome(desert)

	var tundra := BiomeDefinition.new()
	tundra.id = "tundra"
	tundra.display_name = "Tundra"
	tundra.elevation_range = Vector2(0.5, 0.9)
	tundra.moisture_range = Vector2(0.2, 0.5)
	tundra.temperature_range = Vector2(0.0, 0.3)
	tundra.ground_color = Color(0.8, 0.8, 0.9)
	world_generator.register_biome(tundra)

	var forest := BiomeDefinition.new()
	forest.id = "forest"
	forest.display_name = "Forest"
	forest.elevation_range = Vector2(0.3, 0.6)
	forest.moisture_range = Vector2(0.5, 0.8)
	forest.temperature_range = Vector2(0.3, 0.6)
	forest.ground_color = Color(0.15, 0.45, 0.15)
	world_generator.register_biome(forest)

func _add_default_recipes() -> void:
	var recipes := $RecipeRegistry as Node
	if recipes:
		# Add default recipes through the registry
		pass

func _generate_world(seed: int) -> void:
	chunk_system.initialize(seed)
	world_generator.generate_world(seed)

func _process(delta: float) -> void:
	# Update chunk system based on player position
	chunk_system.update_player_position(player.global_position)

func _on_toggle_inventory() -> void:
	inventory_panel.visible = not inventory_panel.visible
	if inventory_panel.visible:
		inventory_panel.show_panel()
	else:
		inventory_panel.hide_panel()

func _on_toggle_crafting() -> void:
	crafting_panel.visible = not crafting_panel.visible
	if crafting_panel.visible:
		crafting_panel.show_panel()
	else:
		crafting_panel.hide_panel()

func _on_debug_toggled(enabled: bool) -> void:
	hud.toggle_debug(enabled)

func _on_world_seed_set(seed: int) -> void:
	_world_seed = seed
	hud.set_seed(seed)

## Save game.
func save_game(path: String = "user://savegame.json") -> void:
	save_system.save_game(path)

## Load game.
func load_game(path: String = "user://savegame.json") -> void:
	save_system.load_game(path)

## Restart game with new seed.
func restart_game() -> void:
	_world_seed = _generate_seed()
	_generate_world(_world_seed)
	player._spawn_at(Vector2(0, 0))
