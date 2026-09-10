# Architecture Documentation

## System Overview

```
                    ┌─────────────────┐
                    │     Main        │
                    │   (Node)        │
                    └───────┬─────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌───────────────┐  ┌────────────────┐  ┌─────────────────┐
│ Player        │  │ WorldGenerator │  │ ChunkSystem     │
│ (Character    │  │ (Node)         │  │ (Node)          │
│  Body2D)      │  │                │  │                 │
│ - Movement    │  │ - Noise Layers │  │ - Chunk loading │
│ - Health      │  │ - Biomes       │  │ - Unloading     │
│ - Inventory   │  │ - Resources    │  │                 │
└───────┬───────┘  └───────┬────────┘  └────────┬────────┘
        │                  │                     │
        │          ┌───────┴────────┐            │
        │          │ NoiseLayers    │            │
        │          │ (FastNoiseLite)│            │
        │          └────────────────┘            │
        │                                       │
┌───────┴───────────────────────────────────────┴───────┐
│                    GameEventBus                      │
│              (Autoload Singleton)                     │
└──────────────────────────────────────────────────────┘
        │                   │                   │
        ▼                   ▼                   ▼
┌───────────────┐  ┌────────────────┐  ┌─────────────────┐
│ Camera        │  │ Terrain        │  │ Debug           │
│ Controller    │  │ Renderer       │  │ Overlay         │
│               │  │ (TileMapLayer) │  │                 │
│ - Smooth      │  │                │  │ - FPS           │
│   follow      │  │ - 8 tile types │  │ - Position      │
│ - Offset      │  │ - Biome colors │  │ - Chunk info    │
│               │  │                │  │ - Noise values  │
└───────────────┘  └────────────────┘  └─────────────────┘
```

## Core Systems

### GameEventBus
Central signal-based communication system. All systems emit and listen to signals here.

### Player
CharacterBody2D with:
- WASD movement + Sprint (Shift)
- Health and hunger components
- Inventory management
- Position tracking

### WorldGenerator
Handles procedural generation:
- FastNoiseLite for elevation, moisture, temperature
- Biome selection based on noise values
- Returns chunk data dictionary

### ChunkSystem
Manages chunk lifecycle:
- Generates chunks deterministically
- Loads chunks within viewport radius
- Unloads chunks outside viewport
- 16x16 tile chunks

### CameraController
Smooth follow camera:
- Interpolates toward player position
- Configurable speed and offset
- Part of the camera system

### TerrainRenderer
TileMapLayer-based rendering:
- 8 terrain types with distinct colors
- Updates chunks as they load
- Placeholder system for future sprite tiles

### DebugOverlay
Shows development information:
- FPS counter
- World/tile/chunk coordinates
- World seed
- Current biome
- Noise values (elevation, moisture, temperature)

### ResourceSpawner
Deterministic resource placement:
- Trees, rocks, fibre, berries, ores
- Placed per chunk based on seed
- Persistent world modifications

## Data-Driven Resources

All game content uses Resource subclasses:

| Resource | Purpose | Key Fields |
|----------|---------|------------|
| ItemDefinition | Item data | id, display_name, category, stack_size, weight |
| RecipeDefinition | Crafting recipe | id, ingredients[], outputs[], craft_time |
| BiomeDefinition | Biome config | id, elevation_range, moisture_range, temperature_range |
| CreatureDefinition | Creature data | id, type, health, speed, loot_table |
| TechnologyDefinition | Tech unlock | id, prerequisites[], unlock_cost[] |
| BuildingDefinition | Building data | id, width, height, build_cost[] |

## Signal Flow

```
Player input → GameEventBus → Systems respond
World gen completes → chunk_generated → ChunkSystem → UI updates
Debug toggle → DebugOverlay updates display
Seed change → World regenerates
```

## World Generation Pipeline

1. Player spawns at world center (0,0)
2. ChunkSystem generates chunks around player
3. WorldGenerator creates noise layers for each chunk
4. Biome selection based on noise averages
5. TerrainRenderer places tiles based on elevation/moisture
6. ResourceSpawner places resource nodes
7. DebugOverlay shows generation info

## Performance Considerations

- Only chunks within viewport radius are generated
- Chunk generation is deterministic (same seed = same result)
- No per-tile nodes (TileMapLayer is GPU-accelerated)
- Inventory/Crafting are RefCounted (no scene overhead)
- Debug overlay only renders when enabled
