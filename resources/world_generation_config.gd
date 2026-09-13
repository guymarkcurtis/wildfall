## Data-driven knobs for the world-generation engine.
## Content assets should reference this configuration rather than changing the
## generator when the initial world scale or field balance changes.
class_name WorldGenerationConfig
extends Resource

@export var config_id: String = "default_world"
@export var generation_version: int = 2
@export var tile_size_pixels: int = 32
@export var chunk_size_tiles: int = 16
@export var world_dimensions_chunks: Vector2i = Vector2i(128, 128)
@export var world_origin_chunk: Vector2i = Vector2i(-64, -64)
@export var streaming_radius: int = 3

@export var water_level: float = 0.30
@export var shoreline_level: float = 0.35
@export var lake_level: float = 0.24
@export var lake_moisture_threshold: float = 0.72
@export var lake_noise_threshold: float = 0.56

## Cap of the shore distance field, measured in Chebyshev (8-neighbor) tiles.
## 0 disables the field: chunk payloads carry empty distance arrays and
## distance-constrained content cannot be satisfied. For 1..cap - 1 a value
## is the exact tile distance to the nearest water tile (0 = the water tile
## itself); the cap value means "no water within cap - 1 tiles". Content
## rules consume the precomputed per-chunk array, so no rule ever branches
## on a water body name.
@export_range(0, 64) var distance_to_water_cap_tiles: int = 16

## WG-06: halo, in Chebyshev tiles from the chunk edge, of the bounded
## flow stage that derives the river/stream mask. Every land tile within
## the halo of the chunk is a unit water source; each source traces at
## most halo steps downstream over the elevation field, stopping when it
## enters water. A land tile is a river tile when at least
## river_accumulation_threshold distinct sources drain through it. The
## stage samples the one rect the chunk already samples, grown by the
## halo, so a tile's river status depends only on that rect and is
## identical however the chunk is generated. 0 disables the stage:
## payloads carry an empty river_mask and on-demand queries return -1.
@export_range(0, 64) var river_halo_tiles: int = 24

## WG-06: distinct-source accumulation a land tile needs to count as a
## river tile in the flow stage above. Higher values thin the network
## toward trunk channels; lower values flood the mask with sheet flow.
## Must stay >= 1 whenever the stage is enabled.
@export_range(1, 256) var river_accumulation_threshold: int = 32

## Low-frequency regional sampling keeps biome regions broad while preserving
## local environmental variation at their boundaries.
@export_range(0.01, 1.0) var regional_field_coordinate_scale: float = 0.18
@export_range(0.0, 8.0) var regional_biome_weight: float = 2.0
@export_range(0.0, 8.0) var transition_biome_weight: float = 0.85
@export_range(0.0, 8.0) var preferred_neighbor_weight: float = 0.4

## Side length in tiles of the world-aligned square cells used by the
## coherent-region stage to measure biome fragments. Cells are anchored to
## world coordinates, so every chunk and every on-demand biome query compute
## the same region decisions from their own coordinates alone.
@export_range(1, 64) var region_cell_size_tiles: int = 8

@export var resource_min_per_chunk: int = 5
@export var resource_max_per_chunk: int = 15
@export var resource_attempt_multiplier: int = 8

## Noise settings are dictionaries so designers can tune fields without
## editing procedural-generation code. Missing keys use NoiseLayers defaults.
@export var noise_settings: Dictionary = {
	"elevation_frequency": 0.005,
	"elevation_octaves": 4,
	"elevation_lacunarity": 2.0,
	"elevation_gain": 0.5,
	"moisture_frequency": 0.003,
	"moisture_octaves": 3,
	"moisture_lacunarity": 2.0,
	"moisture_gain": 0.5,
	"temperature_frequency": 0.002,
	"temperature_octaves": 2,
	"temperature_lacunarity": 1.5,
	"temperature_gain": 0.5,
	"water_frequency": 0.0015,
	"water_octaves": 2,
	"water_lacunarity": 2.0,
	"water_gain": 0.5
}

func is_chunk_in_bounds(coords: Vector2i) -> bool:
	return coords.x >= world_origin_chunk.x \
		and coords.y >= world_origin_chunk.y \
		and coords.x < world_origin_chunk.x + world_dimensions_chunks.x \
		and coords.y < world_origin_chunk.y + world_dimensions_chunks.y

func get_world_max_chunk() -> Vector2i:
	return world_origin_chunk + world_dimensions_chunks - Vector2i.ONE
