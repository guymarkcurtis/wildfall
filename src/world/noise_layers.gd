## Manages deterministic Perlin noise layers for world generation.
## Uses Godot's FastNoiseLite for proper Perlin noise.
class_name NoiseLayers
extends Node

const ELEVATION_OCTAVES: int = 4
const MOISTURE_OCTAVES: int = 3
const TEMPERATURE_OCTAVES: int = 2
const ELEVATION_LACUNARITY: float = 2.0
const MOISTURE_LACUNARITY: float = 2.0
const TEMPERATURE_LACUNARITY: float = 1.5
const ELEVATION_GAIN: float = 0.5
const MOISTURE_GAIN: float = 0.5
const TEMPERATURE_GAIN: float = 0.5

# Noise generators
var elevation_noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var temperature_noise: FastNoiseLite

# Current seed
var _seed: int = 0

## Initialize noise generators with a seed.
func initialize(seed: int) -> void:
	_seed = seed

	elevation_noise = FastNoiseLite.new()
	elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	elevation_noise.seed = seed
	elevation_noise.frequency = 0.005
	elevation_noise.fractal_octaves = ELEVATION_OCTAVES
	elevation_noise.fractal_lacunarity = ELEVATION_LACUNARITY
	elevation_noise.fractal_gain = ELEVATION_GAIN

	moisture_noise = FastNoiseLite.new()
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	moisture_noise.seed = seed + 1000
	moisture_noise.frequency = 0.003
	moisture_noise.fractal_octaves = MOISTURE_OCTAVES
	moisture_noise.fractal_lacunarity = MOISTURE_LACUNARITY
	moisture_noise.fractal_gain = MOISTURE_GAIN

	temperature_noise = FastNoiseLite.new()
	temperature_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	temperature_noise.seed = seed + 2000
	temperature_noise.frequency = 0.002
	temperature_noise.fractal_octaves = TEMPERATURE_OCTAVES
	temperature_noise.fractal_lacunarity = TEMPERATURE_LACUNARITY
	temperature_noise.fractal_gain = TEMPERATURE_GAIN

## Get elevation value at world position.
func get_elevation(x: float, y: float) -> float:
	return elevation_noise.get_noise_2d(x, y)

## Get moisture value at world position.
func get_moisture(x: float, y: float) -> float:
	return moisture_noise.get_noise_2d(x, y)

## Get temperature value at world position.
func get_temperature(x: float, y: float) -> float:
	return temperature_noise.get_noise_2d(x, y)

## Get raw noise values for debug overlay.
func get_noise_values(x: float, y: float) -> Dictionary:
	return {
		"elevation": elevation_noise.get_noise_2d(x, y),
		"moisture": moisture_noise.get_noise_2d(x, y),
		"temperature": temperature_noise.get_noise_2d(x, y)
	}

## Get the current seed.
func get_seed() -> int:
	return _seed

## Reinitialize with a new seed.
func reinitialize(seed: int) -> void:
	_seed = seed
	initialize(seed)
