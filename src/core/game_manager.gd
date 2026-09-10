## Central game coordinator. Does not own game state — delegates to subsystems.
extends Node

const SAVE_VERSION: int = 1

# Subsystem references
var world_generator: Node = null
var player: Node = null
var inventory_system: Node = null
var crafting_system: Node = null
var save_system: Node = null

# Game state
var _world_seed: int = 0
var _game_time: float = 0.0
var _day_length_seconds: float = 120.0  # seconds per full day

# Signals
signal game_started
signal game_paused
signal game_resumed
signal game_over

func _ready() -> void:
	_world_seed = _generate_seed()
	GameEventBus.world_seed_set.emit(_world_seed)
	game_started.emit()

## Generate a random world seed.
func _generate_seed() -> int:
	return randi() % 999999

## Get the current world seed.
func get_world_seed() -> int:
	return _world_seed

## Get current game time in seconds.
func get_game_time() -> float:
	return _game_time

## Get the current day number (1-based).
func get_day_number() -> int:
	return int(_game_time / _day_length_seconds) + 1

## Get the day/night ratio (0.0 = midnight, 0.5 = noon, 1.0 = next midnight).
func get_day_ratio() -> float:
	return (_game_time % _day_length_seconds) / _day_length_seconds

## Advance game time by delta.
func _process(delta: float) -> void:
	_game_time += delta

## Save game state to disk.
func save_game(path: String) -> bool:
	if save_system:
		return save_system.save_game(path)
	return false

## Load game state from disk.
func load_game(path: String) -> bool:
	if save_system:
		return save_system.load_game(path)
	return false

## Restart the game with a new seed.
func restart_game() -> void:
	_world_seed = _generate_seed()
	GameEventBus.world_seed_set.emit(_world_seed)
	_game_time = 0.0
	# Reload world and reset player
	if world_generator:
		world_generator.regenerate_world(_world_seed)

## Pause the game.
func pause_game() -> void:
	get_tree().paused = true
	game_paused.emit()

## Resume the game.
func resume_game() -> void:
	get_tree().paused = false
	game_resumed.emit()

## End the game.
func end_game() -> void:
	game_over.emit()
