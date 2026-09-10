## Handles deterministic procedural world generation using noise layers.
## Generates: elevation, moisture, temperature → biome selection → terrain.
class_name WorldGenerator
extends Node

const CHUNK_SIZE: int = 16
const ELEVATION_OCTAVES: int = 4
const MOISTURE_OCTAVES: int = 3
const TEMPERATURE_OCTAVES: int = 2
const ELEVATION_LACUNARITY: float = 2.0
const MOISTURE_LACUNARITY: float = 2.0
const TEMPERATURE_LACUNARITY: float = 1.5
const ELEVATION_PERSISTENCE: float = 0.5
const MOISTURE_PERSISTENCE: float = 0.5
const TEMPERATURE_PERSISTENCE: float = 0.5

# Biome definitions (populated from resources)
var _biomes: Dictionary = {}

# Registered chunk generators
var _chunk_generators: Array[Callable] = []

# Signals
signal chunk_generated(chunk_coords: Vector2i, data: Dictionary)
signal world_regenerated

## Register a biome definition.
func register_biome(biome: "BiomeDefinition") -> void:
	_biomes[biome.id] = biome

## Get all registered biomes.
func get_biomes() -> Dictionary:
	return _biomes

## Get a biome by ID.
func get_biome(biome_id: String) -> "BiomeDefinition":
	return _biomes.get(biome_id)

## Generate a complete world with the given seed.
func generate_world(seed: int) -> Dictionary:
	var world_data: Dictionary = {
		"seed": seed,
		"chunks": {},
		"version": CHUNK_SYSTEM_GENERATOR_VERSION
	}

	# Generate chunks around origin (placeholder: generate a 5x5 grid)
	for x in range(-2, 3):
		for y in range(-2, 3):
			var chunk_coords: Vector2i = Vector2i(x, y)
			var chunk_data: Dictionary = _generate_chunk(chunk_coords, seed)
			world_data["chunks"][str(chunk_coords)] = chunk_data
			chunk_generated.emit(chunk_coords, chunk_data)

	world_regenerated.emit()
	return world_data

## Regenerate world with same seed (for updates).
func regenerate_world(seed: int) -> Dictionary:
	return generate_world(seed)

## Generate a single chunk deterministically.
func _generate_chunk(chunk_coords: Vector2i, world_seed: int) -> Dictionary:
	var chunk_random: RandomNumberGenerator = RandomNumberGenerator.new()
	chunk_random.seed = _get_chunk_seed(chunk_coords, world_seed)

	var size: int = CHUNK_SIZE
	var elevation: PackedFloat32Array = PackedFloat32Array()
	var moisture: PackedFloat32Array = PackedFloat32Array()
	var temperature: PackedFloat32Array = PackedFloat32Array()

	# Generate noise layers
	for y in range(CHUNK_SIZE):
		for x in range(CHUNK_SIZE):
			var world_x: int = chunk_coords.x * CHUNK_SIZE + x
			var world_y: int = chunk_coords.y * CHUNK_SIZE + y

			var elev: float = _generate_noise(world_x, world_y, 0, ELEVATION_OCTAVES, ELEVATION_PERSISTENCE, ELEVATION_LACUNARITY, world_seed)
			var moist: float = _generate_noise(world_x, world_y, 1, MOISTURE_OCTAVES, MOISTURE_PERSISTENCE, MOISTURE_LACUNARITY, world_seed)
			var temp: float = _generate_noise(world_x, world_y, 2, TEMPERATURE_OCTAVES, TEMPERATURE_PERSISTENCE, TEMPERATURE_LACUNARITY, world_seed)

			elevation.append(clamp(elev, 0.0, 1.0))
			moisture.append(clamp(moist, 0.0, 1.0))
			temperature.append(clamp(temp, 0.0, 1.0))

	# Select biome based on noise values
	var biome_id: String = _select_biome(elevation, moisture, temperature)

	return {
		"coords": chunk_coords,
		"elevation": elevation,
		"moisture": moisture,
		"temperature": temperature,
		"biome": biome_id,
		"terrain": [],
		"vegetation": [],
		"resources": [],
		"entities": [],
		"seed": world_seed
	}

## Select biome based on elevation, moisture, and temperature.
func _select_biome(elevation: PackedFloat32Array, moisture: PackedFloat32Array, temperature: PackedFloat32Array) -> String:
	# Average values for chunk
	var avg_elevation: float = _array_average(elevation)
	var avg_moisture: float = _array_average(moisture)
	var avg_temperature: float = _array_average(temperature)

	# Default to grassland
	var default_biome: String = "grassland"

	# Find matching biome
	for biome_id in _biomes:
		var biome: BiomeDefinition = _biomes[biome_id]
		if _biome_matches(biome, avg_elevation, avg_moisture, avg_temperature):
			return biome_id

	return default_biome

## Check if a biome matches given parameters.
func _biome_matches(biome: BiomeDefinition, elevation: float, moisture: float, temperature: float) -> bool:
	return (
		elevation >= biome.elevation_range.x and elevation <= biome.elevation_range.y and
		moisture >= biome.moisture_range.x and moisture <= biome.moisture_range.y and
		temperature >= biome.temperature_range.x and temperature <= biome.temperature_range.y
	)

## Generate deterministic Perlin-like noise.
func _generate_noise(x: int, y: int, layer: int, octaves: int, persistence: float, lacunarity: float, seed: int) -> float:
	var total: float = 0.0
	var frequency: float = 1.0
	var amplitude: float = 1.0
	var max_value: float = 0.0

	for i in range(octaves):
		var noise_val: float = _simple_noise(float(x) * frequency, float(y) * frequency, seed + layer * 1000 + i)
		total += noise_val * amplitude
		max_value += amplitude
		amplitude *= persistence
		frequency *= lacunarity

	return total / max_value if max_value != 0 else 0.0

## Simple deterministic noise function.
func _simple_noise(x: float, y: float, seed: int) -> float:
	var n: int = sin(x * 12.9898 + y * 78.233 + float(seed)) * 43758.5453
	n = n - floor(n)
	return n

## Calculate average of an array.
func _array_average(arr: PackedFloat32Array) -> float:
	if arr.is_empty():
		return 0.0
	var sum: float = 0.0
	for v in arr:
		sum += v
	return sum / arr.size()

## Get deterministic seed for a chunk.
func _get_chunk_seed(chunk_coords: Vector2i, world_seed: int) -> int:
	var hasher := HashingContext.new()
	hasher.start()
	hasher.hash_int(world_seed)
	hasher.hash_int(chunk_coords.x)
	hasher.hash_int(chunk_coords.y)
	hasher.hash_int(CHUNK_SYSTEM_GENERATOR_VERSION)
	var bytes := hasher.finish()
	return bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24)
