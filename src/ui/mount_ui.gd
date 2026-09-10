## UI component for displaying mount information.
class_name MountUI
extends Control

@onready var mount_name_label: Label = $NameLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var stamina_bar: ProgressBar = $StaminaBar
@onready var status_label: Label = $StatusLabel

var mount_manager: MountManager = null

func _ready() -> void:
	visible = false

## Update mount display.
func update_mount(manager: MountManager) -> void:
	mount_manager = manager
	_refresh_display()

## Refresh the display.
func _refresh_display() -> void:
	var current_mount := mount_manager.get_current_mount() if mount_manager else None
	
	if current_mount:
		visible = true
		mount_name_label.text = current_mount.get_display_name()
		health_bar.value = current_mount.get_health_ratio() * 100
		stamina_bar.value = current_mount.get_stamina_ratio() * 100
		
		if current_mount.is_saddled_check():
			status_label.text = "Saddled"
		elif current_mount.is_ridden_check():
			status_label.text = "Riding"
		else:
			status_label.text = "Available"
	else:
		visible = false
		status_label.text = "No mount"

## Hide the UI.
func hide_ui() -> void:
	visible = false

## Show the UI.
func show_ui() -> void:
	visible = true

## Get health percentage.
func get_health_percentage() -> float:
	var current_mount := mount_manager.get_current_mount() if mount_manager else None
	if current_mount:
		return current_mount.get_health_ratio() * 100
	return 0.0

## Get stamina percentage.
func get_stamina_percentage() -> float:
	var current_mount := mount_manager.get_current_mount() if mount_manager else None
	if current_mount:
		return current_mount.get_stamina_ratio() * 100
	return 0.0
