## Manages all vehicles in the game.
class_name VehicleManager
extends Node

# Dictionary of vehicle_id -> Vehicle
var vehicles: Dictionary = {}

# Currently driven vehicle
var current_vehicle: Vehicle = None

# Signals
signal vehicle_acquired(vehicle_id: String)
signal vehicle_lost(vehicle_id: String)
signal vehicle_entered(vehicle_id: String)
signal vehicle_exited(vehicle_id: String)
signal vehicles_changed(vehicle_count: int)

## Initialize the vehicle manager.
func initialize() -> void:
	print("VehicleManager: Initialized")

## Acquire a vehicle.
func acquire_vehicle(vehicle: Vehicle) -> bool:
	var vehicle_id := vehicle.get_vehicle_id()
	if vehicles.has(vehicle_id):
		return False
	
	vehicles[vehicle_id] = vehicle
	vehicle_acquired.emit(vehicle_id)
	vehicles_changed.emit(vehicles.size())
	return True

## Lose a vehicle.
func lose_vehicle(vehicle_id: String) -> bool:
	if not vehicles.has(vehicle_id):
		return False
	
	if current_vehicle and current_vehicle.get_vehicle_id() == vehicle_id:
		current_vehicle.exit_vehicle()
		current_vehicle = None
	
	vehicles.erase(vehicle_id)
	vehicle_lost.emit(vehicle_id)
	vehicles_changed.emit(vehicles.size())
	return True

## Get a vehicle.
func get_vehicle(vehicle_id: String) -> Vehicle:
	return vehicles.get(vehicle_id)

## Get all vehicles.
func get_all_vehicles() -> Array[Vehicle]:
	return vehicles.values()

## Enter a vehicle.
func enter_vehicle(vehicle_id: String) -> bool:
	var vehicle := vehicles.get(vehicle_id)
	if not vehicle:
		return False
	
	if current_vehicle:
		current_vehicle.exit_vehicle()
	
	vehicle.enter_vehicle()
	current_vehicle = vehicle
	vehicle_entered.emit(vehicle_id)
	return True

## Exit current vehicle.
func exit_vehicle() -> bool:
	if not current_vehicle:
		return False
	
	current_vehicle.exit_vehicle()
	var vehicle_id := current_vehicle.get_vehicle_id()
	current_vehicle = None
	vehicle_exited.emit(vehicle_id)
	return True

## Get current vehicle.
func get_current_vehicle() -> Vehicle:
	return current_vehicle

## Check if player is driving.
func is_driving() -> bool:
	return current_vehicle != None

## Get vehicle count.
func get_vehicle_count() -> int:
	return vehicles.size()

## Clear all vehicles.
func clear_all() -> void:
	for vehicle_id in vehicles:
		vehicles[vehicle_id].queue_free()
	vehicles.clear()
	current_vehicle = None
	vehicles_changed.emit(0)

## Serialize vehicle data.
func serialize_all() -> Dictionary:
	var data := {}
	for vehicle_id in vehicles:
		data[vehicle_id] = vehicles[vehicle_id].serialize()
	return data

## Restore vehicle data from save.
func deserialize_all(data: Dictionary) -> void:
	clear_all()
	for vehicle_id in data:
		var vehicle_data := data[vehicle_id]
		var vehicle_type := vehicle_data.get("vehicle_type", 0)
		var vehicle := Vehicle.new()
		vehicle.deserialize(vehicle_data)
		vehicles[vehicle_id] = vehicle
		if vehicle_data.get("is_driver", False):
			vehicle.enter_vehicle()
			current_vehicle = vehicle
	vehicles_changed.emit(vehicles.size())

## Get vehicles of a specific type.
func get_vehicles_by_type(vehicle_type: int) -> Array[Vehicle]:
	var result: Array[Vehicle] = []
	for vehicle_id in vehicles:
		var vehicle := vehicles[vehicle_id]
		if vehicle.get_vehicle_type() == vehicle_type:
			result.append(vehicle)
	return result

## Damage current vehicle.
func damage_current_vehicle(amount: int) -> bool:
	if not current_vehicle:
		return False
	return current_vehicle.take_damage(amount)

## Refuel current vehicle.
func refuel_current_vehicle(amount: float) -> void:
	if current_vehicle:
		current_vehicle.refuel(amount)

## Get current vehicle fuel.
func get_current_fuel() -> float:
	if current_vehicle:
		return current_vehicle.get_fuel_ratio()
	return 0.0

## Get current vehicle health.
func get_current_health() -> int:
	if current_vehicle:
		return current_vehicle.health
	return 0
