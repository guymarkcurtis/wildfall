# Game Design Document

## Overview

2D Icarus is a 2D survival game inspired by games like Minecraft and Icarus. Players gather resources, craft tools, build structures, and survive in a procedurally generated world.

## Core Gameplay Loop

1. **Gather**: Collect resources from the environment (trees, rocks, ores)
2. **Craft**: Use resources to create tools, weapons, and building materials
3. **Build**: Construct shelters and structures for protection
4. **Survive**: Manage health and hunger, fend off predators
5. **Progress**: Unlock new technologies and explore biomes

## Key Systems

### World Generation
- Deterministic chunk-based world (16x16 tile chunks)
- Noise-based elevation, moisture, temperature layers
- Biome selection from parameter ranges
- 4 starting biomes: Grassland, Desert, Tundra, Forest

### Survival
- Health (100 max) — reduced by damage, starvation
- Hunger (100 max) — depletes over time, restored by food
- Starvation deals damage when hunger reaches 0

### Inventory
- Slot-based with stacking (max 64 per stack)
- Weight limit (100 units default)
- Categories: tool, food, material, resource, consumable, building, component, seed, weapon, armor

### Crafting
- Recipe-based system
- Hand crafting and station crafting
- Timed crafting for complex items
- Technology unlocks new recipes

### Building
- Place buildings on valid terrain
- Buildings have HP and can be destroyed
- Some buildings require crafting stations

### Technology
- Research tree with prerequisites
- Unlocks new crafting recipes
- Costs resources to research

### Creatures
- Passive, neutral, predator, boss types
- Spawn based on biome
- Have loot tables
- Some are hostile

## Controls

| Key | Action |
|-----|--------|
| W/Up | Move up |
| S/Down | Move down |
| A/Left | Move left |
| D/Right | Move right |
| E | Interact |
| I | Toggle inventory |
| F3 | Toggle debug |

## Visual Style

- 2D top-down perspective
- Tile-based terrain rendering
- Colored placeholders during development
- Simple, readable sprites

## Progression

1. Start with bare hands
2. Gather wood and stone
3. Craft basic tools (axe, pickaxe)
4. Build a shelter
5. Unlock crafting stations
6. Research technologies
7. Explore different biomes
8. Hunt creatures for loot
9. Build advanced structures
10. Survive as long as possible
