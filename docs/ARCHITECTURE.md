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
└───────┬───────┘  └───────┬────────┘  └────────┬────────┘
        │                  │                     │
        │          ┌───────┴────────┐            │
        │          │ BiomeDefinition│            │
        │          │ (Resource)     │            │
        │          └────────────────┘            │
        │                                       │
┌───────┴───────────────────────────────────────┴───────┐
│                     GameEventBus                     │
│              (Autoload Singleton)                     │
└──────────────────────────────────────────────────────┘
        │                   │                   │
        ▼                   ▼                   ▼
┌───────────────┐  ┌────────────────┐  ┌─────────────────┐
│ HealthComp    │  │ InventoryComp  │  │ CraftingComp    │
│ (Node)        │  │ (RefCounted)   │  │ (RefCounted)    │
└───────────────┘  └────────────────┘  └─────────────────┘
```

## Core Systems

### GameEventBus
Central signal-based communication system. All systems emit and listen to signals here rather than maintaining direct references.

### ChunkSystem
Manages chunk lifecycle:
- Generates chunks deterministically based on seed + coordinates
- Loads chunks within viewport radius
- Unloads chunks outside viewport radius
- Emits `chunk_generated` and `chunk_unloaded` signals

### WorldGenerator
Handles procedural generation:
- Elevation noise layer
- Moisture noise layer
- Temperature noise layer
- Biome selection from noise values
- Returns chunk data dictionary

### Player
Main playable entity:
- WASD movement via CharacterBody2D
- Health and hunger components
- Inventory management
- Interaction handling

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

## Component Architecture

Components are attached to entities and manage specific aspects:

- **HealthComponent**: Damage, healing, death
- **HungerComponent**: Hunger depletion, starvation
- **InventoryComponent**: Item storage, stacking, weight
- **CraftingComponent**: Recipe validation, crafting

Components use RefCounted for inventory/crafting (shareable) and Node for health/hunger (entity-owned).

## Signal Flow

```
Player input → GameEventBus → Systems respond
World gen completes → chunk_generated → ChunkSystem → UI updates
Crafting complete → recipe_crafted → UI updates, inventory changes
Player dies → player_died → Game over state
```

## Save System

Save format: JSON with version number
- Version 1: Basic player state + world seed
- Future: Full world state, inventory, buildings

## Performance Considerations

- Only chunks within viewport radius are generated
- Chunk generation is deterministic (same seed = same result)
- No per-tile nodes (tilemap-based rendering planned)
- Inventory/Crafting are RefCounted (no scene overhead)
