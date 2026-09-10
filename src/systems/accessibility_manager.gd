## Manages accessibility features for the game.
class_name AccessibilityManager
extends Node

# Accessibility settings
var settings := {
	"colorblind_mode": "none",  # none, protanopia, deuteranopia, tritanopia
	"high_contrast": False,
	"large_text": False,
	"subtitles": True,
	"sound_indicators": True,
	"input_remapping": True,
	"reduced_motion": False,
	"font_size": 16,
	"ui_scale": 1.0
}

# Colorblind palettes
var colorblind_palettes := {
	"none": [Color(1.0, 0.0, 0.0), Color(0.0, 1.0, 0.0), Color(0.0, 0.0, 1.0)],
	"protanopia": [Color(1.0, 0.6, 0.0), Color(0.0, 1.0, 0.6), Color(0.6, 0.0, 1.0)],
	"deuteranopia": [Color(1.0, 0.6, 0.0), Color(0.0, 1.0, 0.6), Color(0.6, 0.0, 1.0)],
	"tritanopia": [Color(1.0, 0.6, 0.0), Color(0.0, 1.0, 0.6), Color(0.6, 0.0, 1.0)]
}

# Signals
signal settings_changed
signal colorblind_changed(mode: String)
signal text_size_changed(size: int)
signal ui_scale_changed(scale: float)

## Initialize the accessibility manager.
func initialize() -> void:
	_load_settings()
	print("AccessibilityManager: Initialized")

## Load settings from config.
func _load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load("user://accessibility.cfg")
	if error == OK:
		settings["colorblind_mode"] = config.get_value("accessibility", "colorblind_mode", "none")
		settings["high_contrast"] = config.get_value("accessibility", "high_contrast", False)
		settings["large_text"] = config.get_value("accessibility", "large_text", False)
		settings["subtitles"] = config.get_value("accessibility", "subtitles", True)
		settings["sound_indicators"] = config.get_value("accessibility", "sound_indicators", True)
		settings["input_remapping"] = config.get_value("accessibility", "input_remapping", True)
		settings["reduced_motion"] = config.get_value("accessibility", "reduced_motion", False)
		settings["font_size"] = config.get_value("accessibility", "font_size", 16)
		settings["ui_scale"] = config.get_value("accessibility", "ui_scale", 1.0)

## Save settings to config.
func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("accessibility", "colorblind_mode", settings["colorblind_mode"])
	config.set_value("accessibility", "high_contrast", settings["high_contrast"])
	config.set_value("accessibility", "large_text", settings["large_text"])
	config.set_value("accessibility", "subtitles", settings["subtitles"])
	config.set_value("accessibility", "sound_indicators", settings["sound_indicators"])
	config.set_value("accessibility", "input_remapping", settings["input_remapping"])
	config.set_value("accessibility", "reduced_motion", settings["reduced_motion"])
	config.set_value("accessibility", "font_size", settings["font_size"])
	config.set_value("accessibility", "ui_scale", settings["ui_scale"])
	config.save("user://accessibility.cfg")

## Apply colorblind mode.
func apply_colorblind_mode(mode: String) -> void:
	if mode in colorblind_palettes:
		settings["colorblind_mode"] = mode
		_apply_colorblind_palette()
		colorblind_changed.emit(mode)
		_save_settings()

## Apply colorblind palette.
func _apply_colorblind_palette() -> void:
	var palette := colorblind_palettes[settings["colorblind_mode"]]
	# Would apply to game colors
	print("AccessibilityManager: Applied %s colorblind mode" % settings["colorblind_mode"])

## Toggle high contrast.
func toggle_high_contrast(enabled: bool) -> void:
	settings["high_contrast"] = enabled
	_apply_high_contrast()
	settings_changed.emit()
	_save_settings()

## Apply high contrast.
func _apply_high_contrast() -> void:
	if settings["high_contrast"]:
		# Increase contrast
		DisplayServer.window_set_transparent(true)
	else:
		DisplayServer.window_set_transparent(false)

## Toggle large text.
func toggle_large_text(enabled: bool) -> void:
	settings["large_text"] = enabled
	_apply_large_text()
	text_size_changed.emit(settings["font_size"])
	_save_settings()

## Apply large text.
func _apply_large_text() -> void:
	if settings["large_text"]:
		settings["font_size"] = 24
	else:
		settings["font_size"] = 16
	# Would update all labels

## Toggle sound indicators.
func toggle_sound_indicators(enabled: bool) -> void:
	settings["sound_indicators"] = enabled
	# Would set up visual indicators for sounds

## Toggle reduced motion.
func toggle_reduced_motion(enabled: bool) -> void:
	settings["reduced_motion"] = enabled
	# Would disable animations

## Set UI scale.
func set_ui_scale(scale: float) -> void:
	settings["ui_scale"] = clamp(scale, 0.5, 2.0)
	_apply_ui_scale()
	ui_scale_changed.emit(settings["ui_scale"])
	_save_settings()

## Apply UI scale.
func _apply_ui_scale() -> void:
	# Would scale all UI elements
	pass

## Get setting.
func get_setting(key: String) -> Variant:
	return settings.get(key, None)

## Set setting.
func set_setting(key: String, value) -> void:
	settings[key] = value
	_save_settings()
	settings_changed.emit()

## Get all settings.
func get_all_settings() -> Dictionary:
	return settings.duplicate()

## Reset to defaults.
func reset_to_defaults() -> void:
	settings = {
		"colorblind_mode": "none",
		"high_contrast": False,
		"large_text": False,
		"subtitles": True,
		"sound_indicators": True,
		"input_remapping": True,
		"reduced_motion": False,
		"font_size": 16,
		"ui_scale": 1.0
	}
	_apply_colorblind_mode("none")
	toggle_high_contrast(False)
	toggle_large_text(False)
	toggle_sound_indicators(True)
	toggle_reduced_motion(False)
	set_ui_scale(1.0)
	settings_changed.emit()

## Serialize settings.
func serialize() -> Dictionary:
	return settings.duplicate()

## Deserialize settings.
func deserialize(data: Dictionary) -> void:
	settings = data
	_apply_colorblind_mode(data.get("colorblind_mode", "none"))
	_apply_high_contrast()
	_apply_large_text()
	_apply_ui_scale()
	settings_changed.emit()
