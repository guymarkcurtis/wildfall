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

## Handle input for the seed editor.
##   * Not editing: T (change_seed) opens the editor.
##   * Editing: digits (number row or numpad) append, BACKSPACE deletes,
##     ENTER applies the new seed, ESCAPE cancels and keeps the old one.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if not _is_editing:
			if event.is_action_pressed("change_seed"):
				start_editing()
			return
		# While editing, only the editor's own keys do anything.
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				get_viewport().set_input_as_handled()
				finish_editing()
			KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				cancel_editing()
			KEY_BACKSPACE:
				get_viewport().set_input_as_handled()
				if len(_input_buffer) > 0:
					_input_buffer = _input_buffer.substr(0, len(_input_buffer) - 1)
			_:
				# unicode 48..57 covers both the number row and the numpad.
				if event.unicode >= 48 and event.unicode <= 57 \
						and len(_input_buffer) < MAX_INPUT_LENGTH:
					get_viewport().set_input_as_handled()
					_input_buffer += str(event.unicode - 48)

## Whether the seed editor is currently active.
func is_editing() -> bool:
	return _is_editing

## The digit buffer the player is currently typing.
func get_input_buffer() -> String:
	return _input_buffer

## Get the current seed.
func get_seed() -> int:
	return _current_seed

## Set seed directly.
func set_seed(seed: int) -> void:
	_current_seed = seed
	seed_changed.emit(seed)
