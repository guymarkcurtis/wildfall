## Heads-up display showing player health, hunger, and game info.
class_name HUD
extends CanvasLayer

@onready var health_bar: ProgressBar = $Overlay/HealthBar
@onready var hunger_bar: ProgressBar = $Overlay/HungerBar
@onready var debug_label: Label = $Overlay/DebugLabel
@onready var seed_label: Label = $Overlay/SeedLabel

var _debug_enabled: bool = false
var _player: Node = null

func _ready() -> void:
	$Overlay.self_modulate.a = 0.8
	debug_label.visible = false

## Set the player reference for HUD updates.
func set_player(player: Node) -> void:
	_player = player
	if player.health_component:
		player.health_component.health_changed.connect(_on_health_changed)
	if player.hunger_component:
		player.hunger_component.hunger_changed.connect(_on_hunger_changed)

## Toggle debug overlay.
func toggle_debug(enabled: bool) -> void:
	_debug_enabled = enabled
	debug_label.visible = enabled

## Update health bar.
func _on_health_changed(current: float, max_health: int) -> void:
	health_bar.value = current
	health_bar.max_value = max_health

## Update hunger bar.
func _on_hunger_changed(current: float, max_hunger: float) -> void:
	hunger_bar.value = current
	hunger_bar.max_value = max_hunger

## Update debug overlay.
func _process(_delta: float) -> void:
	if not _debug_enabled:
		return

	var info: String = ""
	if _player:
		info += "Position: %.1f, %.1f\n" % [_player.global_position.x, _player.global_position.y]
		var player_chunk: Vector2i = _player.get_chunk_coordinate()
		info += "Chunk: %d, %d\n" % [player_chunk.x, player_chunk.y]
		info += "Health: %d/%d\n" % [int(_player.health_component.current_health), _player.health_component.max_health]
		info += "Hunger: %.1f/%.1f\n" % [_player.hunger_component.current_hunger, _player.hunger_component.max_hunger]

	info += "\nFPS: %d" % Engine.get_frames_per_second()
	debug_label.text = info

var _seed: int = -1

## Set the game seed for display.
func set_seed(seed: int) -> void:
	_seed = seed
	seed_label.text = "Seed: %d" % seed

## Reflect the seed editor state in the seed label while the player types
## a new seed (T to edit, Enter to apply, Esc to cancel).
func set_seed_editing(editing: bool, buffer: String = "") -> void:
	var new_text: String
	if editing:
		new_text = "Seed: %s  (Enter apply / Esc cancel)" % buffer
	else:
		new_text = "Seed: %d" % (_seed if _seed >= 0 else 0)
	if seed_label.text != new_text:
		seed_label.text = new_text

## Show/hide the entire HUD.
func set_hud_visible(visible: bool) -> void:
	$Overlay.visible = visible
