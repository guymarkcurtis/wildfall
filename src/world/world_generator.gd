## Handles deterministic procedural world generation using FastNoiseLite.
class_name WorldGenerator
extends Node

const CHUNK_SIZE: int = 16
const GENERATOR_VERSION: int = 1

# Noise layers (seeded Perlin noise; created on initialize)
var noise_layers: NoiseLayers = null

# Current world seed (0 until initialized)
var current_seed: int = 0

# Biome definitions
var _biomes: Dictionary = {}

# Signals
signal chunk_generated(chunk_coords: Vector2i, data: Dictionary)
signal world_regenerated

## Initialize the world generator with a seed.
func initialize(seed: int) -> void:
	current_seed = seed
	if noise_layers != null and is_instance_valid(noise_layers):
		noise_layers.reinitialize(seed)
	else:
		noise_layers = NoiseLayers.new()
		# Add it to the tree so it is freed with the generator (a bare
		# .new() Node would leak at exit: "ObjectDB instances leaked").
		add_child(noise_layers)
		noise_layers.initialize(seed)
	_load_default_biomes()

## Get a biome definition by ID.
func get_biome(biome_id: String) -> Variant:
	return _biomes.get(biome_id)

## Get all biomes.
func get_biomes() -> Dictionary:
	return _biomes

## Register a biome.
func register_biome(biome: Variant) -> void:
	_biomes[biome.get("id")] = biome

## Generate a single chunk deterministically from the seeded noise layers.
func generate_chunk(chunk_coords: Vector2i, seed: int) -> Dictionary:
	# Lazy init so generate_chunk() works even without an explicit initialize().
	if noise_layers == null or not is_instance_valid(noise_layers):
		initialize(seed)

	var elevation: PackedFloat32Array = PackedFloat32Array()
	var moisture: PackedFloat32Array = PackedFloat32Array()
	var temperature: PackedFloat32Array = PackedFloat32Array()

	# Sample the seeded noise layers (normalized from [-1, 1] to [0, 1])
	for y in range(CHUNK_SIZE):
		for x in range(CHUNK_SIZE):
			var world_x: float = float(chunk_coords.x * CHUNK_SIZE + x)
			var world_y: float = float(chunk_coords.y * CHUNK_SIZE + y)

			elevation.append(clamp((noise_layers.get_elevation(world_x, world_y) + 1.0) / 2.0, 0.0, 1.0))
			moisture.append(clamp((noise_layers.get_moisture(world_x, world_y) + 1.0) / 2.0, 0.0, 1.0))
			temperature.append(clamp((noise_layers.get_temperature(world_x, world_y) + 1.0) / 2.0, 0.0, 1.0))

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
## Chunk data is derivable from the seed on demand, so only the seed and
## version are stored; Main re-renders the visible chunks after this.
func regenerate_world(seed: int) -> Dictionary:
	initialize(seed)
	world_regenerated.emit()
	return {
		"seed": seed,
		"chunks": {},
		"version": GENERATOR_VERSION
	}

## Get the current seed.
func get_seed() -> int:
	if noise_layers != null and is_instance_valid(noise_layers):
		return noise_layers.get_seed()
	return current_seed

## Get normalized noise values at a world position (for the debug overlay).
func get_noise_values(x: float, y: float) -> Dictionary:
	if noise_layers != null and is_instance_valid(noise_layers):
		return {
			"elevation": clamp((noise_layers.get_elevation(x, y) + 1.0) / 2.0, 0.0, 1.0),
			"moisture": clamp((noise_layers.get_moisture(x, y) + 1.0) / 2.0, 0.0, 1.0),
			"temperature": clamp((noise_layers.get_temperature(x, y) + 1.0) / 2.0, 0.0, 1.0)
		}
	# Fallback before initialization: deterministic but unseeded.
	var elev: float = sin(x * 0.1) * cos(y * 0.1)
	var moist: float = sin(x * 0.05 + 1.0) * cos(y * 0.05)
	var temp: float = sin(x * 0.03 + y * 0.03)
	return {
		"elevation": clamp((elev + 1.0) / 2.0, 0.0, 1.0),
		"moisture": clamp((moist + 1.0) / 2.0, 0.0, 1.0),
		"temperature": clamp((temp + 1.0) / 2.0, 0.0, 1.0)
	}

## Classify the biome at a world tile position using the seeded noise layers.
## Used by the resource spawner so spawns match the visible terrain biome.
func get_biome_at_world(world_x: int, world_y: int) -> String:
	if noise_layers == null or not is_instance_valid(noise_layers):
		initialize(current_seed if current_seed != 0 else 0)
	var elev: float = clamp((noise_layers.get_elevation(float(world_x), float(world_y)) + 1.0) / 2.0, 0.0, 1.0)
	var moist: float = clamp((noise_layers.get_moisture(float(world_x), float(world_y)) + 1.0) / 2.0, 0.0, 1.0)
	var temp: float = clamp((noise_layers.get_temperature(float(world_x), float(world_y)) + 1.0) / 2.0, 0.0, 1.0)
	return _select_biome_at(elev, moist, temp)

## Select the best-matching biome for single normalized noise values.
func _select_biome_at(elevation: float, moisture: float, temperature: float) -> String:
	var best_biome: String = "grassland"
	var best_score: float = -1.0
	for biome_id in _biomes:
		var biome: Resource = _biomes[biome_id]
		var score: float = _biome_match_score(biome, elevation, moisture, temperature)
		if score > best_score:
			best_score = score
			best_biome = biome_id
	return best_biome

## Load default biomes.
func _load_default_biomes() -> void:
	# Temperate Forest
	var forest := BiomeDefinition.new()
	forest.set("id", "temperate_forest")
	forest.set("display_name", "Temperate Forest")
	forest.set("elevation_range", Vector2(0.3, 0.6))
	forest.set("moisture_range", Vector2(0.4, 0.7))
	forest.set("temperature_range", Vector2(0.3, 0.6))
	forest.set("ground_color", Color(0.15, 0.45, 0.15))
	register_biome(forest)

	# Grassland
	var grassland := BiomeDefinition.new()
	grassland.set("id", "grassland")
	grassland.set("display_name", "Grassland")
	grassland.set("elevation_range", Vector2(0.3, 0.5))
	grassland.set("moisture_range", Vector2(0.3, 0.5))
	grassland.set("temperature_range", Vector2(0.3, 0.6))
	grassland.set("ground_color", Color(0.3, 0.65, 0.2))
	register_biome(grassland)

	# Mountain
	var mountain := BiomeDefinition.new()
	mountain.set("id", "mountain")
	mountain.set("display_name", "Mountain")
	mountain.set("elevation_range", Vector2(0.6, 0.9))
	mountain.set("moisture_range", Vector2(0.2, 0.5))
	mountain.set("temperature_range", Vector2(0.2, 0.5))
	mountain.set("ground_color", Color(0.5, 0.5, 0.5))
	register_biome(mountain)

	# Desert
	var desert := BiomeDefinition.new()
	desert.set("id", "desert")
	desert.set("display_name", "Desert")
	desert.set("elevation_range", Vector2(0.2, 0.4))
	desert.set("moisture_range", Vector2(0.0, 0.2))
	desert.set("temperature_range", Vector2(0.6, 1.0))
	desert.set("ground_color", Color(0.8, 0.7, 0.4))
	register_biome(desert)

	# Arctic
	var arctic := BiomeDefinition.new()
	arctic.set("id", "arctic")
	arctic.set("display_name", "Arctic")
	arctic.set("elevation_range", Vector2(0.4, 0.8))
	arctic.set("moisture_range", Vector2(0.3, 0.6))
	arctic.set("temperature_range", Vector2(0.0, 0.2))
	arctic.set("ground_color", Color(0.85, 0.9, 0.95))
	register_biome(arctic)

	# Swamp
	var swamp := BiomeDefinition.new()
	swamp.set("id", "swamp")
	swamp.set("display_name", "Swamp")
	swamp.set("elevation_range", Vector2(0.2, 0.4))
	swamp.set("moisture_range", Vector2(0.7, 1.0))
	swamp.set("temperature_range", Vector2(0.4, 0.7))
	swamp.set("ground_color", Color(0.3, 0.4, 0.2))
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
		var biome: Resource = _biomes[biome_id]
		var score: float = _biome_match_score(biome, avg_elevation, avg_moisture, avg_temperature)
		if score > best_score:
			best_score = score
			best_biome = biome_id

	return best_biome

## Calculate how well a biome matches given parameters.
func _biome_match_score(biome: Resource, elevation: float, moisture: float, temperature: float) -> float:
	var score: float = 0.0

	# Check elevation match
	var elev_range: Vector2 = biome.get("elevation_range")
	if elev_range.x == 0 and elev_range.y == 0:
		elev_range = Vector2(0, 1)
	if elevation >= elev_range.x and elevation <= elev_range.y:
		score += 3.0
	else:
		var dist: float = min(abs(elevation - elev_range.x), abs(elevation - elev_range.y))
		score += max(0.0, 3.0 - dist * 3.0)

	# Check moisture match
	var moist_range: Vector2 = biome.get("moisture_range")
	if moist_range.x == 0 and moist_range.y == 0:
		moist_range = Vector2(0, 1)
	if moisture >= moist_range.x and moisture <= moist_range.y:
		score += 2.0
	else:
		var dist: float = min(abs(moisture - moist_range.x), abs(moisture - moist_range.y))
		score += max(0.0, 2.0 - dist * 3.0)

	# Check temperature match
	var temp_range: Vector2 = biome.get("temperature_range")
	if temp_range.x == 0 and temp_range.y == 0:
		temp_range = Vector2(0, 1)
	if temperature >= temp_range.x and temperature <= temp_range.y:
		score += 2.0
	else:
		var dist: float = min(abs(temperature - temp_range.x), abs(temperature - temp_range.y))
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
