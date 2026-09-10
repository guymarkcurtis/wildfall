## Manages all crafting stations in the world.
class_name StationManager
extends Node

# Dictionary of station_id -> CraftingStation
var stations: Dictionary = {}

# Signals
signal station_placed(station_id: String, coords: Vector2i)
signal station_removed(station_id: String)
signal station_interacted(station_id: String)

## Initialize the station manager.
func initialize() -> void:
	print("StationManager: Initialized")

## Place a new crafting station.
func place_station(station: CraftingStation, coords: Vector2i) -> bool:
	var station_id: String = station.get_station_id()
	if stations.has(station_id):
		return false
	
	stations[station_id] = station
	station.position = Vector2(coords)
	station_placed.emit(station_id, coords)
	return true

## Remove a crafting station.
func remove_station(station_id: String) -> bool:
	if not stations.has(station_id):
		return false
	
	stations[station_id].queue_free()
	stations.erase(station_id)
	station_removed.emit(station_id)
	return true

## Get a station by ID.
func get_station(station_id: String) -> CraftingStation:
	return stations.get(station_id)

## Get all stations.
func get_all_stations() -> Array[CraftingStation]:
	return stations.values()

## Get stations near a position.
func get_stations_near(position: Vector2, range: float = 64.0) -> Array[CraftingStation]:
	var nearby: Array[CraftingStation] = []
	for station_id in stations:
		var station: CraftingStation = stations[station_id]
		var dist: float = station.position.distance_to(position)
		if dist <= range:
			nearby.append(station)
	return nearby

## Interact with the nearest station.
func interact_nearest(player_position: Vector2) -> CraftingStation:
	var nearby: Array[CraftingStation] = get_stations_near(player_position)
	if nearby.is_empty():
		return null
	
	# Find closest active station
	var closest: CraftingStation = null
	var closest_dist: float = Float.MAX
	
	for station in nearby:
		if station.is_active_check():
			var dist: float = station.position.distance_to(player_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = station
	
	if closest:
		closest.interact()
		station_interacted.emit(closest.get_station_id())
	
	return closest

## Get stations of a specific type.
func get_stations_by_type(station_type: int) -> Array[CraftingStation]:
	var result: Array[CraftingStation] = []
	for station_id in stations:
		var station: CraftingStation = stations[station_id]
		if station.get_station_type() == station_type:
			result.append(station)
	return result

## Serialize station data for saving.
func serialize_all() -> Dictionary:
	var data := {}
	for station_id in stations:
		var station: CraftingStation = stations[station_id]
		data[station_id] = {
			"position": station.position,
			"station_type": station.get_station_type(),
			"station_id": station.get_station_id()
		}
	return data

## Restore station positions from save data.
func deserialize_all(data: Dictionary) -> void:
	for station_id in data:
		var station_data: Dictionary = data[station_id]
		var station: CraftingStation = get_station(station_id)
		if station:
			station.position = station_data.get("position", Vector2(0, 0))

## Get station count.
func get_station_count() -> int:
	return stations.size()

## Clear all stations.
func clear_all() -> void:
	for station_id in stations:
		stations[station_id].queue_free()
	stations.clear()
