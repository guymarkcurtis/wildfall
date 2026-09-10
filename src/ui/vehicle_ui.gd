## UI component for displaying vehicle information.
class_name VehicleUI
extends Control

@onready var vehicle_name_label: Label = $NameLabel
@onready var fuel_bar: ProgressBar = $FuelBar
@onready var health_bar: ProgressBar = $HealthBar
@onready def status_label: Label = $StatusLabel

var vehicle_manager: VehicleManager = None

func _ready() -> void:
	visible = False

## Update vehicle display.
func update_vehicle(manager: VehicleManager) -> void:
	vehicle_manager = manager
	_refresh_display()

## Refresh the display.
func _refresh_display() -> void:
	var current_vehicle := vehicle_manager.get_current_vehicle() if vehicle_manager else None
	
	if current_vehicle:
		visible = True
		vehicle_name_label.text = current_vehicle.get_display_name()
		fuel_bar.value = current_vehicle.get_fuel_ratio() * 100
		health_bar.value = current_vehicle.get_health_ratio() * 100
		
		if current_vehicle.is_active_check():
			status_label.text = "Active"
		else:
			status_label.text = "Idle"
	else:
		visible = False
		status_label.text = "No vehicle"

## Hide the UI.
func hide_ui() -> void:
	visible = False

## Show the UI.
func show_ui() -> void:
	visible = True

## Get fuel percentage.
func get_fuel_percentage() -> float:
	var current_vehicle := vehicle_manager.get_current_vehicle() if vehicle_manager else None
	if current_vehicle:
		return current_vehicle.get_fuel_ratio() * 100
	return 0.0

## Get health percentage.
func get_health_percentage() -> float:
	var current_vehicle := vehicle_manager.get_current_vehicle() if vehicle_manager else None
	if current_vehicle:
		return current_vehicle.get_health_ratio() * 100
	return 0.0
