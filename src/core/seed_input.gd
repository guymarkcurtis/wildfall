## Handles seed input and world regeneration.
class_name SeedInput
extends Node

signal seed_changed(new_seed: int)
signal world_regenerated

const MAX_INPUT_LENGTH: int = 12
const MIN_SEED: int = 0
const MAX_SEED: int = 999999

var _input_buffer: String = ""
var _current_seed: int = 0
var _is_editing: bool = false

func _ready() -> void:
	# Generate initial random seed
	_current_seed = _generate_random_seed()
	seed_changed.emit(_current_seed)

## Generate a random seed.
func _generate_random_seed() -> int:
	return randi() % (MAX_SEED - MIN_SEED + 1)

## Start editing the seed.
func start_editing() -> void:
	_input_buffer = str(_current_seed)
	_is_editing = true

## Finish editing and apply the seed.
func finish_editing() -> void:
	_is_editing = false
	if _input_buffer.is_valid_int():
		var new_seed: int = int(_input_buffer)
		if new_seed >= MIN_SEED and new_seed <= MAX_SEED:
			_current_seed = new_seed
			seed_changed.emit(_current_seed)
			world_regenerated.emit()

## Cancel editing and restore current seed.
func cancel_editing() -> void:
	_is_editing = false
	_input_buffer = str(_current_seed)

## Handle text input for seed editing.
func _input(event: InputEvent) -> void:
	if not _is_editing:
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_ESCAPE:
			finish_editing()
		elif event.keycode == KEY_BACKSPACE:
			if len(_input_buffer) > 0:
				_input_buffer = _input_buffer.substr(0, len(_input_buffer) - 1)
		elif event.keycode >= KEY_0 and event.keycode <= KEY_9:
			if len(_input_buffer) < MAX_INPUT_LENGTH:
				_input_buffer += str(event.keycode - KEY_0)

## Get the current seed.
func get_seed() -> int:
	return _current_seed

## Set seed directly.
func set_seed(seed: int) -> void:
	_current_seed = seed
	seed_changed.emit(seed)
