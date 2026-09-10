## Handles deterministic procedural world generation using FastNoiseLite.
class_name WorldGenerator
extends Node

const CHUNK_SIZE: int = 16
const GENERATOR_VERSION: int = 1

# Noise layers
var noise_layers: NoiseLayers = null

# Biome definitions
var _biomes: Dictionary = {}

# Signals
signal chunk_generated(chunk_coords: Vector2i, data: Dictionary)
signal world_regenerated

## Initialize the world generator.
func initialize(seed: int) -> void:
	noise_layers = NoiseLayers.new()
	noise_layers.initialize(seed)
	add_child(noise_layers)
	_load_default_biomes()

## Get a biome definition by ID.
func get_biome(biome_id: String) -> BiomeDefinition:
	return _biomes.get(biome_id)

## Get all biomes.
func get_biomes() -> Dictionary:
	return _biomes

## Register a biome.
func register_biome(biome: BiomeDefinition) -> void:
	biomes[biome.id] = biome

## Generate a single chunk deterministically.
func generate_chunk(chunk_coords: Vector2i, seed: int) -> Dictionary:
	if not noise_layers:
		noise_layers = NoiseLayers.new()
		noise_layers.initialize(seed)

	var size: int = CHUNK_SIZE
	var elevation: PackedFloat32Array = PackedFloat32Array()
	var moisture: PackedFloat32Array = PackedFloat32Array()
	var temperature: PackedFloat32Array = PackedFloat32Array()

	# Generate noise layers
	for y in range(CHUNK_SIZE):
		for x in range(CHUNK_SIZE):
			var world_x: float = float(chunk_coords.x * CHUNK_SIZE + x)
			var world_y: float = float(chunk_coords.y * CHUNK_SIZE + y)

			var elev: float = noise_layers.get_elevation(world_x, world_y)
			var moist: float = noise_layers.get_moisture(world_x, world_y)
			var temp: float = noise_layers.get_temperature(world_x, world_y)

			elevation.append(clamp((elev + 1.0) / 2.0, 0.0, 1.0))
			moisture.append(clamp((moist + 1.0) / 2.0, 0.0, 1.0))
			temperature.append(clamp((temp + 1.0) / 2.0, 0.0, 1.0))

	# Select biome based on noise values
	var biome_id: String = _select_biome(elevation, moisture, temperature)

	return {
		"coords": chunk_coords,
		"elevation": elevation,
		"moisture": moisture,
		"temperature": temperature,
		"biome": biome_id,
		"seed": seed,
		"version": GENERATOR_VERSION
	}

## Regenerate the world with a new seed.
func regenerate_world(seed: int) -> Dictionary:
	if noise_layers:
		noise_layers.reinitialize(seed)

	# Clear and regenerate all chunks
	var world_data: Dictionary = {
		"seed": seed,
		"chunks": {},
		"version": GENERATOR_VERSION
	}

	# Generate a 5x5 grid around origin (placeholder)
	for x in range(-2, 3):
		for y in range(-2, 3):
			var chunk_coords: Vector2i = Vector2i(x, y)
			var chunk_data: Dictionary = generate_chunk(chunk_coords, seed)
			world_data["chunks"][str(chunk_coords)] = chunk_data
			chunk_generated.emit(chunk_coords, chunk_data)

	world_regenerated.emit()
	return world_data

## Get the current seed.
func get_seed() -> int:
	if noise_layers:
		return noise_layers.get_seed()
	return 0

## Get noise values at a world position.
func get_noise_values(x: float, y: float) -> Dictionary:
	if noise_layers:
		return noise_layers.get_noise_values(x, y)
	return {"elevation": 0.0, "moisture": 0.0, "temperature": 0.0}

## Load default biomes.
func _load_default_biomes() -> void:
	# Temperate Forest
	var forest := BiomeDefinition.new()
	forest.id = "temperate_forest"
	forest.display_name = "Temperate Forest"
	forest.elevation_range = Vector2(0.3, 0.6)
	forest.moisture_range = Vector2(0.4, 0.7)
	forest.temperature_range = Vector2(0.3, 0.6)
	forest.ground_color = Color(0.15, 0.45, 0.15)
	register_biome(forest)

	# Grassland
	var grassland := BiomeDefinition.new()
	grassland.id = "grassland"
	grassland.display_name = "Grassland"
	grassland.elevation_range = Vector2(0.3, 0.5)
	grassland.moisture_range = Vector2(0.3, 0.5)
	grassland.temperature_range = Vector2(0.3, 0.6)
	grassland.ground_color = Color(0.3, 0.65, 0.2)
	register_biome(grassland)

	# Mountain
	var mountain := BiomeDefinition.new()
	mountain.id = "mountain"
	mountain.display_name = "Mountain"
	mountain.elevation_range = Vector2(0.6, 0.9)
	mountain.moisture_range = Vector2(0.2, 0.5)
	mountain.temperature_range = Vector2(0.2, 0.5)
	mountain.ground_color = Color(0.5, 0.5, 0.5)
	register_biome(mountain)

	# Desert
	var desert := BiomeDefinition.new()
	desert.id = "desert"
	desert.display_name = "Desert"
	desert.elevation_range = Vector2(0.2, 0.4)
	desert.moisture_range = Vector2(0.0, 0.2)
	desert.temperature_range = Vector2(0.6, 1.0)
	desert.ground_color = Color(0.8, 0.7, 0.4)
	register_biome(desert)

	# Arctic
	var arctic := BiomeDefinition.new()
	arctic.id = "arctic"
	arctic.display_name = "Arctic"
	arctic.elevation_range = Vector2(0.4, 0.8)
	arctic.moisture_range = Vector2(0.3, 0.6)
	arctic.temperature_range = Vector2(0.0, 0.2)
	arctic.ground_color = Color(0.85, 0.9, 0.95)
	register_biome(arctic)

	# Swamp
	var swamp := BiomeDefinition.new()
	swamp.id = "swamp"
	swamp.display_name = "Swamp"
	swamp.elevation_range = Vector2(0.2, 0.4)
	swamp.moisture_range = Vector2(0.7, 1.0)
	swamp.temperature_range = Vector2(0.4, 0.7)
	swamp.ground_color = Color(0.3, 0.4, 0.2)
	register_biome(swamp)

## Select biome based on elevation, moisture, and temperature.
func _select_biome(elevation: PackedFloat32Array, moisture: PackedFloat32Array, temperature: PackedFloat32Array) -> String:
	# Average values for chunk
	var avg_elevation: float = _array_average(elevation)
	var avg_moisture: float = _array_average(moisture)
	var avg_temperature: float = _array_average(temperature)

	# Find best matching biome
	var best_biome: String = "grassland"
	var best_score: float = -1.0

	for biome_id in _biomes:
		var biome: BiomeDefinition = _biomes[biome_id]
		var score: float = _biome_match_score(biome, avg_elevation, avg_moisture, avg_temperature)
		if score > best_score:
			best_score = score
			best_biome = biome_id

	return best_biome

## Calculate how well a biome matches given parameters.
func _biome_match_score(biome: BiomeDefinition, elevation: float, moisture: float, temperature: float) -> float:
	var score: float = 0.0

	# Check elevation match
	if elevation >= biome.elevation_range.x and elevation <= biome.elevation_range.y:
		score += 3.0
	else:
		var dist: float = min(abs(elevation - biome.elevation_range.x), abs(elevation - biome.elevation_range.y))
		score += max(0.0, 3.0 - dist * 3.0)

	# Check moisture match
	if moisture >= biome.moisture_range.x and moisture <= biome.moisture_range.y:
		score += 2.0
	else:
		var dist: float = min(abs(moisture - biome.moisture_range.x), abs(moisture - biome.moisture_range.y))
		score += max(0.0, 2.0 - dist * 3.0)

	# Check temperature match
	if temperature >= biome.temperature_range.x and temperature <= biome.temperature_range.y:
		score += 2.0
	else:
		var dist: float = min(abs(temperature - biome.temperature_range.x), abs(temperature - biome.temperature_range.y))
		score += max(0.0, 2.0 - dist * 3.0)

	return score

## Calculate average of an array.
func _array_average(arr: PackedFloat32Array) -> float:
	if arr.is_empty():
		return 0.5
	var sum: float = 0.0
	for v in arr:
		sum += v
	return sum / arr.size()
