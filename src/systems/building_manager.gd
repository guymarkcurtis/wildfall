## Manages building placement and lifecycle.
class_name BuildingManager
extends Node

# Dictionary of building_id -> Building
var buildings: Dictionary = {}

# Signals
signal building_placed(building_id: String, coords: Vector2i)
signal building_removed(building_id: String)
signal building_damaged(building_id: String, current_health: int, max_health: int)

## Initialize the building manager.
func initialize() -> void:
	print("BuildingManager: Initialized")

## Place a new building.
func place_building(building: Building, coords: Vector2i) -> bool:
	var building_id := building.get_building_id()
	if buildings.has(building_id):
		return false
	
	buildings[building_id] = building
	building.position = Vector2(coords)
	add_child(building)
	building_placed.emit(building_id, coords)
	return true

## Remove a building.
func remove_building(building_id: String) -> bool:
	if not buildings.has(building_id):
		return false
	
	buildings[building_id].queue_free()
	buildings.erase(building_id)
	building_removed.emit(building_id)
	return true

## Get a building by ID.
func get_building(building_id: String) -> Building:
	return buildings.get(building_id)

## Get all buildings.
func get_all_buildings() -> Array[Building]:
	return buildings.values()

## Get buildings near a position.
func get_buildings_near(position: Vector2, range: float = 64.0) -> Array[Building]:
	var nearby: Array[Building] = []
	for building_id in buildings:
		var building := buildings[building_id]
		var dist := building.global_position.distance_to(position)
		if dist <= range:
			nearby.append(building)
	return nearby

## Damage a building.
func damage_building(building_id: String, amount: int) -> bool:
	var building := buildings.get(building_id)
	if building:
		var destroyed := building.take_damage(amount)
		if destroyed:
			buildings.erase(building_id)
		return destroyed
	return false

## Get building count.
func get_building_count() -> int:
	return buildings.size()

## Clear all buildings.
func clear_all() -> void:
	for building_id in buildings:
		buildings[building_id].queue_free()
	buildings.clear()

## Serialize building data.
func serialize_all() -> Dictionary:
	var data := {}
	for building_id in buildings:
		var building := buildings[building_id]
		data[building_id] = building.serialize()
	return data

## Restore building positions from save data.
func deserialize_all(data: Dictionary) -> void:
	for building_id in data:
		var building_data := data[building_id]
		var building := _create_building_from_data(building_data)
		if building:
			building.deserialize(building_data)
			buildings[building_id] = building
			add_child(building)

## Create a building from serialized data.
func _create_building_from_data(data: Dictionary) -> Building:
	var building_type := data.get("building_type", 0)
	var building_id := data.get("building_id", "")
	var health := data.get("health", 50)
	
	var building := Building.new()
	building.setup(building_type, building_id, building_id, health)
	return building

## Get buildings of a specific type.
func get_buildings_by_type(building_type: int) -> Array[Building]:
	var result: Array[Building] = []
	for building_id in buildings:
		var building := buildings[building_id]
		if building.get_building_type() == building_type:
			result.append(building)
	return result
