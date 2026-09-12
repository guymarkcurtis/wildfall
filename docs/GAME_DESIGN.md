# Game Design Document - Wildfall

## Overview

Wildfall is an original persistent open-world 2D top-down survival crafting action RPG. The player begins with almost nothing and gradually transforms a dangerous wilderness into a network of camps, settlements, workshops, roads, and advanced facilities.

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

Game mode is chosen on **New Game** and is locked for that world:

| Mode | Rules |
|---|---|
| Survival | Crafting needs ingredients. Hostile wildlife hunts the player. |
| Creative | Crafting is free (no ingredients). Wildlife is peaceful. The player can still die. |

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
- Story-aware 2D cutaway construction: build on up to four stackable levels,
  select levels with `[` / `]` in build mode, and hide higher stories while
  working on a lower one.
- Buildings remain after missions

### Combat
- Action RPG feel with responsive attacks
- Melee (E) plus mouse-aimed ranged weapons (face the cursor, fire with LMB)
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

## Presentation

**Current and intended camera:** orthogonal **2D top-down**. Square 32px tiles on a `TileMapLayer`, `Camera2D` looking straight down, `CharacterBody2D` movement on a cartesian grid. This is not isometric and not a 3D world.

Depth and “2.5D” later means taller sprites, Y-sort, shadows, and height offsets on this same top-down grid — not a switch to isometric tiles or a 3D camera. See [ARCHITECTURE.md](ARCHITECTURE.md#presentation--camera).

## Controls

Movement is **world-relative**: **W** is north, **A** west, **S** south, and **D** east regardless of facing or view rotation. The character sprite **always faces the cursor**, which also controls tool use and ranged aim.

| Input | Action | Status |
|-----|--------|--------|
| W / A / S / D | Move north / west / south / east | Implemented |
| Shift | Sprint | Implemented |
| Space | Short aimed jump (respects terrain collision) | Implemented |
| Mouse pointer | Aim ranged weapons | Implemented |
| Left mouse (hold) | Use selected tool; fire when bow is selected | Implemented |
| `,` / `.` | Rotate view 45° CCW / CW | Implemented |
| Middle-mouse drag | Free-rotate view | Implemented |
| Home | Reset view to world-north up | Implemented |
| E (hold) | Harvest resources in front of player / melee | Implemented |
| B | Toggle build mode | Implemented |
| `[` / `]` (build mode) | Select lower / upper construction story | Implemented |
| Mouse wheel (build mode) | Cycle placeable buildings | Implemented |
| F | Demolish nearby building | Implemented |
| I | Toggle inventory | Implemented |
| C | Toggle crafting | Implemented |
| U | Toggle technology / research | Implemented |
| F3 | Toggle debug | Implemented |
| T | Change world seed | Implemented |
| Esc | Pause menu (save / load / title / quit) | Implemented |

## Development Phases

### Phase 0: Foundation
- Godot project (created on 4.6, upgraded to 4.7 on 2026-09-11)
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

- Orthogonal 2D top-down (square tiles, not isometric)
- Optional player-controlled view rotation around the character
- High-quality top-down sprites (eventually); tall props may Y-sort for a 2.5D read
- Dynamic lighting and weather
- Particle effects
- Polished UI
