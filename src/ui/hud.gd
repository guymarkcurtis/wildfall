## Heads-up display showing player health, hunger, and game info.
class_name HUD
extends CanvasLayer

@onready var health_bar: ProgressBar = $Overlay/HBoxContainer/HealthBar
@onready var hunger_bar: ProgressBar = $Overlay/HBoxContainer/HungerBar
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
		info += "Chunk: %d, %d\n" % [_player.get_chunk_coordinate()]
		info += "Health: %d/%d\n" % [int(_player.health_component.current_health), _player.health_component.max_health]
		info += "Hunger: %.1f/%.1f\n" % [_player.hunger_component.current_hunger, _player.hunger_component.max_hunger]

	info += "\nFPS: %d" % Engine.get_frames_per_second()
	debug_label.text = info

## Set the game seed for display.
func set_seed(seed: int) -> void:
	seed_label.text = "Seed: %d" % seed

## Show/hide the entire HUD.
func set_hud_visible(visible: bool) -> void:
	$Overlay.visible = visible
