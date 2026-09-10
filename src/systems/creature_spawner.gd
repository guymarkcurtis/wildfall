## Manages creature spawning and lifecycle.
class_name CreatureSpawner
extends Node

const MAX_CREATURES_PER_CHUNK: int = 5
const CHUNK_SIZE: int = 16

# Creature definitions
var creature_definitions: Dictionary = {}

# Active creatures
var creatures: Array = []

# Signals
signal creature_spawned(creature: Node)
signal creature_removed(creature: Node)
signal creatures_updated(count: int)

## Initialize the creature spawner.
func initialize() -> void:
	_load_creature_definitions()
	print("CreatureSpawner: Initialized with %d definitions" % creature_definitions.size())

## Load creature definitions.
func _load_creature_definitions() -> void:
	# Passive creatures
	creature_definitions["slime"] = {
		"type": "slime",
		"health": 20,
		"damage": 0,
		"hostile": false,
		"speed": 30.0,
		"xp": 10,
		"biome": ["grassland", "temperate_forest"]
	}
	
	creature_definitions["rat"] = {
		"type": "rat",
		"health": 15,
		"damage": 0,
		"hostile": false,
		"speed": 60.0,
		"xp": 5,
		"biome": ["grassland", "swamp"]
	}
	
	creature_definitions["slime_poison"] = {
		"type": "slime_poison",
		"health": 30,
		"damage": 0,
		"hostile": false,
		"speed": 25.0,
		"xp": 15,
		"biome": ["swamp"]
	}
	
	# Hostile creatures
	creature_definitions["wolf"] = {
		"type": "wolf",
		"health": 40,
		"damage": 8,
		"hostile": true,
		"speed": 70.0,
		"xp": 25,
		"biome": ["temperate_forest", "mountain"]
	}
	
	creature_definitions["bear"] = {
		"type": "bear",
		"health": 80,
		"damage": 15,
		"hostile": true,
		"speed": 40.0,
		"xp": 50,
		"biome": ["temperate_forest", "mountain"]
	}
	
	creature_definitions["zombie"] = {
		"type": "zombie",
		"health": 50,
		"damage": 10,
		"hostile": true,
		"speed": 35.0,
		"xp": 30,
		"biome": ["swamp", "temperate_forest"]
	}
	
	creature_definitions["skeleton"] = {
		"type": "skeleton",
		"health": 45,
		"damage": 12,
		"hostile": true,
		"speed": 45.0,
		"xp": 35,
		"biome": ["mountain", "arctic"]
	}
	
	creature_definitions["slime_fire"] = {
		"type": "slime_fire",
		"health": 60,
		"damage": 5,
		"hostile": true,
		"speed": 35.0,
		"xp": 20,
		"biome": ["desert"]
	}

## Spawn a creature at a position.
func spawn_creature(creature_type: String, position: Vector2, biome: String = "") -> Node:
	var definition := creature_definitions.get(creature_type)
	if not definition:
		return null
	
	var creature := Creature.new()
	creature.setup(
		definition["type"],
		definition["health"],
		definition["damage"],
		definition["hostile"],
		definition["xp"]
	)
	creature.position = position
	add_child(creature)
	creatures.append(creature)
	creature_spawned.emit(creature)
	creatures_updated.emit(creatures.size())
	return creature

## Spawn creatures for a chunk.
func spawn_chunk_creators(chunk_coords: Vector2i, biome: String, seed: int) -> Array:
	var spawned: Array = []
	var random := RandomNumberGenerator.new()
	random.seed = seed + chunk_coords.x * 1000 + chunk_coords.y
	
	# Determine how many creatures to spawn
	var count := int(random.randf_range(0, MAX_CREATURES_PER_CHUNK))
	
	# Get eligible creatures for this biome
	var eligible: Array = []
	for type in creature_definitions:
		var definition := creature_definitions[type]
		if biome in definition["biome"]:
			eligible.append(type)
	
	if eligible.is_empty():
		return spawned
	
	# Spawn creatures
	for i in range(count):
		var type_index := int(random.randf_range(0, eligible.size()))
		var type := eligible[type_index]
		
		var x := chunk_coords.x * CHUNK_SIZE + int(random.randf_range(0, CHUNK_SIZE))
		var y := chunk_coords.y * CHUNK_SIZE + int(random.randf_range(0, CHUNK_SIZE))
		var position := Vector2(x, y)
		
		var creature := spawn_creature(type, position, biome)
		if creature:
			spawned.append(creature)
	
	return spawned

## Remove a creature.
func remove_creature(creature: Node) -> bool:
	if creature in creatures:
		creatures.erase(creature)
		creature.queue_free()
		creature_removed.emit(creature)
		creatures_updated.emit(creatures.size())
		return true
	return false

## Get all creatures.
func get_all_creatures() -> Array:
	return creatures.duplicate()

## Get creatures near a position.
func get_creatures_near(position: Vector2, range: float = 100.0) -> Array:
	var nearby: Array = []
	for creature in creatures:
		var dist := creature.global_position.distance_to(position)
		if dist <= range:
			nearby.append(creature)
	return nearby

## Get creature count.
func get_creature_count() -> int:
	return creatures.size()

## Clear all creatures.
func clear_all() -> void:
	for creature in creatures:
		creature.queue_free()
	creatures.clear()
	creatures_updated.emit(0)

## Serialize creature data.
func serialize_all() -> Dictionary:
	var data := {}
	for i in range(creatures.size()):
		var creature := creatures[i]
		data[str(i)] = creature.serialize()
	return data

## Restore creature positions from save data.
func deserialize_all(data: Dictionary) -> void:
	clear_all()
	for key in data:
		var creature_data := data[key]
		var type := creature_data.get("creature_type", "slime")
		var position := creature_data.get("position", Vector2.ZERO)
		var biome := creature_data.get("biome", "")
		var creature := spawn_creature(type, position, biome)
		if creature:
			creature.deserialize(creature_data)
