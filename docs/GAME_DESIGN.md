# Game Design Document - Wildfall

## Overview

Wildfall is an original persistent open-world 2D/2.5D survival crafting action RPG. The player begins with almost nothing and gradually transforms a dangerous wilderness into a network of camps, settlements, workshops, roads, and advanced facilities.

## Core Vision

The entire game takes place in one persistent procedural world. There are no disposable mission maps. Everything the player builds, gathers, and discovers remains in the world forever. The player's world IS the campaign.

## Core Gameplay Loop

```
EXPLORE → DISCOVER → GATHER → CRAFT → FIGHT → SURVIVE → BUILD → ADVANCE
```

Constant tension between:
- **Safety at home** vs **Rewards in the unknown**

## Primary Game Mode

**Persistent Open World** — The player creates or selects a procedural world that remains persistent across the entire playthrough. All exploration, crafting, building, combat, missions, and progression occur within this same world.

## World Philosophy

The player's world should gradually develop a history:
- Early: A camp beside a river
- Later: That camp becomes a cabin
- Later: The cabin becomes a stone settlement
- Later: A road connects that settlement to a mining outpost
- Later: A bridge crosses the river
- Later: The mining outpost becomes an industrial facility

## Key Systems

### World Generation
- Deterministic chunk-based world (16x16 tile chunks)
- FastNoiseLite for elevation, moisture, temperature
- 6 biomes: Temperate Forest, Grassland, Mountain, Desert, Arctic, Swamp
- Resource placement (trees, rocks, ores, berries)
- Rivers, lakes, and varied terrain

### Survival
- Health, Stamina, Hunger, Thirst, Oxygen, Temperature
- Slower depletion rates for better gameplay flow
- Progression reduces early-game pressure

### Inventory & Crafting
- Slot-based inventory with stacking
- Hand crafting and station crafting
- Data-driven recipes
- Technology unlocks new recipes

### Building
- Persistent structures (foundations, walls, roofs, doors)
- Multiple building tiers (primitive → wood → stone → metal)
- Buildings remain after missions

### Combat
- Action RPG feel with responsive attacks
- Melee and ranged weapons
- Enemy variety with state-based AI
- Boss encounters in persistent world

### Missions
- Objectives occur in the persistent world
- Built structures remain after completion
- Procedural mission generation possible

## Progression Eras

1. **Survival** — Primitive tools, campfire, basic shelter
2. **Settlement** — Workbench, farming, metalworking
3. **Industrial** — Machining, electricity, advanced tools
4. **Electrical** — Generators, powered machinery
5. **Frontier Tech** — Advanced composites, vehicles

## Controls

| Key | Action |
|-----|--------|
| W/Up | Move up |
| S/Down | Move down |
| A/Left | Move left |
| D/Right | Move right |
| Shift | Sprint |
| E | Interact |
| I | Toggle inventory |
| F3 | Toggle debug |
| T | Change world seed |

## Development Phases

### Phase 0: Foundation
- Godot 4.6 project
- Player movement and camera
- Basic test scene
- Documentation

### Phase 1: World Generation
- Deterministic seed
- Chunk system
- FastNoiseLite terrain
- Biomes and resources
- Debug overlay

### Phase 2: Interaction
- Resource pickup/harvesting
- Tree chopping, rock mining

### Phase 3: Inventory
- Item definitions
- Stack-based inventory
- Hotbar UI

### Phase 4: Basic Crafting
- Hand crafting
- Basic tools and weapons

### Phase 5: Survival
- Full survival stats
- Death and respawn
- HUD polish

### Phase 6-21: ... (see ROADMAP.md)

## Visual Target

- 2D/2.5D isometric perspective
- High-quality sprites (eventually)
- Dynamic lighting and weather
- Particle effects
- Polished UI
