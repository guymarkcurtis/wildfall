# World Generation Documentation

## Overview

The world is generated deterministically using noise layers. Same seed + generator version = identical world.

## Generation Layers

### 1. Elevation
- Range: 0.0 to 1.0
- Determines terrain height
- Used for biome selection

### 2. Moisture
- Range: 0.0 to 1.0
- Determines precipitation
- Affects biome and vegetation

### 3. Temperature
- Range: 0.0 to 1.0
- Determines climate
- Affects biome selection

## Biome Selection

Biomes are selected based on where noise values fall within defined ranges:

| Biome | Elevation | Moisture | Temperature |
|-------|-----------|----------|-------------|
| Grassland | 0.3 - 0.7 | 0.3 - 0.7 | 0.3 - 0.7 |
| Desert | 0.2 - 0.5 | 0.0 - 0.2 | 0.6 - 1.0 |
| Tundra | 0.5 - 0.9 | 0.2 - 0.5 | 0.0 - 0.3 |
| Forest | 0.3 - 0.6 | 0.5 - 0.8 | 0.3 - 0.6 |

## Chunk Structure

Each chunk is a 16x16 tile area containing:
- elevation: PackedFloat32Array (256 values)
- moisture: PackedFloat32Array (256 values)
- temperature: PackedFloat32Array (256 values)
- biome: String (biome ID)
- terrain: Array (to be populated with tile IDs)
- vegetation: Array (tree/plant positions)
- resources: Array (resource node positions)
- entities: Array (creature positions)

## Deterministic Seeding

```
chunk_seed = hash(world_seed, chunk_x, chunk_y, generator_version)
```

This ensures:
- Same world always generates the same terrain
- Generation order doesn't matter
- Chunks can be generated independently

## Chunk Coordinates

```
world_pos = chunk_pos * CHUNK_SIZE
chunk_pos = world_pos / CHUNK_SIZE
```

## Viewport System

Only chunks within `viewport_radius` of the player are loaded:
- Default radius: 3 chunks (7x7 area)
- Can be adjusted for performance
- Unloaded chunks are freed from memory
