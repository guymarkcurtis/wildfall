## UI component for accessibility settings.
class_name AccessibilityUI
extends Control

@onready var colorblind_combo: OptionButton = $MarginContainer/VBoxContainer/ColorblindCombo
@onready var contrast_check: CheckButton = $MarginContainer/VBoxContainer/ContrastCheck
@onready var text_check: CheckButton = $MarginContainer/VBoxContainer/TextCheck
@onready var subtitles_check: CheckButton = $MarginContainer/VBoxContainer/SubtitlesCheck
@onready var sound_check: CheckButton = $MarginContainer/VBoxContainer/SoundCheck
@onready var motion_check: CheckButton = $MarginContainer/VBoxContainer/MotionCheck
@onready var font_slider: HSlider = $MarginContainer/VBoxContainer/FontSlider
@onready var scale_slider: HSlider = $MarginContainer/VBoxContainer/ScaleSlider

var accessibility_manager: AccessibilityManager = None

# Signals
signal colorblind_changed(mode: String)
signal contrast_toggled(enabled: bool)
signal text_toggled(enabled: bool)
signal subtitles_toggled(enabled: bool)
signal sound_toggled(enabled: bool)
signal motion_toggled(enabled: bool)
signal font_changed(size: int)
signal scale_changed(scale: float)

func _ready() -> void:
	visible = True
	_setup_controls()

## Set up controls.
func _setup_controls() -> void:
	# Colorblind modes
	colorblind_combo.add_item("None")
	colorblind_combo.add_item("Protanopia")
	colorblind_combo.add_item("Deuteranopia")
	colorblind_combo.add_item("Tritanopia")
	colorblind_combo.item_selected.connect(_on_colorblind_selected)
	
	# Checks
	contrast_check.toggled.connect(_on_contrast_toggled)
	text_check.toggled.connect(_on_text_toggled)
	subtitles_check.toggled.connect(_on_subtitles_toggled)
	sound_check.toggled.connect(_on_sound_toggled)
	motion_check.toggled.connect(_on_motion_toggled)
	
	# Sliders
	font_slider.value_changed.connect(_on_font_changed)
	scale_slider.value_changed.connect(_on_scale_changed)

## Show the accessibility panel.
func show_panel(manager: AccessibilityManager) -> void:
	accessibility_manager = manager
	_refresh_controls()

## Refresh controls.
func _refresh_controls() -> void:
	if not accessibility_manager:
		return
	
	var settings := accessibility_manager.get_all_settings()
	
	colorblind_combo.selected = ["none", "protanopia", "deuteranopia", "tritanopia"].find(settings["colorblind_mode"])
	contrast_check.button_pressed = settings["high_contrast"]
	text_check.button_pressed = settings["large_text"]
	subtitles_check.button_pressed = settings["subtitles"]
	sound_check.button_pressed = settings["sound_indicators"]
	motion_check.button_pressed = settings["reduced_motion"]
	font_slider.value = settings["font_size"]
	scale_slider.value = settings["ui_scale"]

## Handle colorblind selection.
func _on_colorblind_selected(index: int) -> void:
	var modes := ["none", "protanopia", "deuteranopia", "tritanopia"]
	if index >= 0 and index < modes.size():
		if accessibility_manager:
			accessibility_manager.apply_colorblind_mode(modes[index])
		colorblind_changed.emit(modes[index])

## Handle contrast toggle.
func _on_contrast_toggled(enabled: bool) -> void:
	if accessibility_manager:
		accessibility_manager.toggle_high_contrast(enabled)
	contrast_toggled.emit(enabled)

## Handle text toggle.
func _on_text_toggled(enabled: bool) -> void:
	if accessibility_manager:
		accessibility_manager.toggle_large_text(enabled)
	text_toggled.emit(enabled)

## Handle subtitles toggle.
func _on_subtitles_toggled(enabled: bool) -> void:
	if accessibility_manager:
		accessibility_manager.set_setting("subtitles", enabled)
	subtitles_toggled.emit(enabled)

## Handle sound toggle.
func _on_sound_toggled(enabled: bool) -> void:
	if accessibility_manager:
		accessibility_manager.toggle_sound_indicators(enabled)
	sound_toggled.emit(enabled)

## Handle motion toggle.
func _on_motion_toggled(enabled: bool) -> void:
	if accessibility_manager:
		accessibility_manager.toggle_reduced_motion(enabled)
	motion_toggled.emit(enabled)

## Handle font size change.
func _on_font_changed(value: float) -> void:
	if accessibility_manager:
		accessibility_manager.set_setting("font_size", int(value))
	font_changed.emit(int(value))

## Handle scale change.
func _on_scale_changed(value: float) -> void:
	if accessibility_manager:
		accessibility_manager.set_ui_scale(value)
	scale_changed.emit(value)

## Hide the panel.
func hide_panel() -> void:
	visible = False

## Show the panel.
func show_panel_ui() -> void:
	visible = True
