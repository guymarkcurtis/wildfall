## UI component for audio controls.
class_name AudioUI
extends Control

@onready var music_slider: HSlider = $MarginContainer/MusicSlider
@onready var sfx_slider: HSlider = $MarginContainer/SFXSlider
@onready var master_slider: HSlider = $MarginContainer/MasterSlider
@onready var music_label: Label = $MarginContainer/MusicLabel
@onready var sfx_label: Label = $MarginContainer/SFXLabel
@onready var master_label: Label = $MarginContainer/MasterLabel
@onready var mute_button: Button = $MuteButton

var audio_manager: AudioManager = null

# Signals
signal music_changed(volume: float)
signal sfx_changed(volume: float)
signal master_changed(volume: float)
signal muted(muted: bool)

func _ready() -> void:
	visible = true
	_setup_sliders()

## Set up sliders.
func _setup_sliders() -> void:
	music_slider.value_changed.connect(_on_music_slider_changed)
	sfx_slider.value_changed.connect(_on_sfx_slider_changed)
	master_slider.value_changed.connect(_on_master_slider_changed)
	mute_button.pressed.connect(_on_mute_pressed)

## Show audio panel.
func show_panel(manager: AudioManager) -> void:
	audio_manager = manager
	_refresh_sliders()

## Refresh sliders.
func _refresh_sliders() -> void:
	if audio_manager:
		music_slider.value = audio_manager.get_music_volume()
		sfx_slider.value = audio_manager.get_sfx_volume()
		master_slider.value = audio_manager.get_master_volume()

## Handle music slider change.
func _on_music_slider_changed(value: float) -> void:
	if audio_manager:
		audio_manager.set_music_volume(value)
	music_label.text = "Music: %.0f%%" % (value * 100)
	music_changed.emit(value)

## Handle SFX slider change.
func _on_sfx_slider_changed(value: float) -> void:
	if audio_manager:
		audio_manager.set_sfx_volume(value)
	sfx_label.text = "SFX: %.0f%%" % (value * 100)
	sfx_changed.emit(value)

## Handle master slider change.
func _on_master_slider_changed(value: float) -> void:
	if audio_manager:
		audio_manager.set_master_volume(value)
	master_label.text = "Master: %.0f%%" % (value * 100)
	master_changed.emit(value)

## Handle mute button.
func _on_mute_pressed() -> void:
	var is_muted := master_slider.value == 0.0
	if is_muted:
		master_slider.value = 0.5
	else:
		master_slider.value = 0.0
	mute_button.text = "Unmute" if is_muted else "Mute"
	muted.emit(not is_muted)

## Hide the panel.
func hide_panel() -> void:
	visible = false

## Show the panel.
func show_panel_ui() -> void:
	visible = true
