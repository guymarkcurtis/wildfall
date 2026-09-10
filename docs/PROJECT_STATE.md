# PROJECT STATE

## CURRENT MILESTONE

**Foundation Phase** — Core game architecture and data-driven systems are established. World generation, inventory, crafting, and basic player movement are implemented. UI panels and save system are in place.

## CURRENTLY WORKING

- **World Generation**: Deterministic chunk-based generation using Perlin noise layers (elevation, moisture, temperature)
- **Biome System**: 4 biomes (grassland, desert, tundra, forest) with parameter-based selection
- **Chunk System**: Loads/unloads chunks around player with configurable viewport radius
- **Inventory System**: Stack-based inventory with weight limits, add/remove/split/transfer
- **Crafting System**: Recipe-based crafting with ingredient validation and timed crafts
- **Player Entity**: CharacterBody2D with WASD movement, health/hunger components
- **HUD**: Health bar, hunger bar, debug overlay, seed display
- **Save System**: JSON-based save/load with version tracking
- **Event Bus**: Centralized signal-based communication between systems
- **Data-Driven Resources**: ItemDefinition, RecipeDefinition, BiomeDefinition, CreatureDefinition, TechnologyDefinition, BuildingDefinition

## ARCHITECTURE

- `src/core/` — EventBus, ChunkSystem, GameManager
- `src/entities/` — Player entity
- `src/components/` — HealthComponent, HungerComponent, InventoryComponent, CraftingComponent
- `src/world/` — WorldGenerator, ChunkSystem
- `src/ui/` — InventoryPanel, CraftingPanel, HUD
- `src/systems/` — SaveSystem
- `resources/` — All data-driven definitions (ItemDefinition, RecipeDefinition, etc.)
- `scenes/` — Main scene, UI panels
- `docs/` — Project documentation

Key architectural decisions:
- **No God Object**: GameManager coordinates but doesn't own game state
- **Data-Driven Content**: All game objects use Resource subclasses
- **Deterministic Gen**: Same seed + generator version = same world
- **Chunk-Based**: World is divided into 16x16 tile chunks
- **Signal-Based**: Systems communicate via signals, not direct coupling

## RECENTLY COMPLETED

- Initialized empty project with full directory structure
- Created all core system scripts (EventBus, ChunkSystem, GameManager)
- Created data-driven resource types (ItemDefinition, RecipeDefinition, BiomeDefinition, etc.)
- Implemented world generation with noise layers and biome selection
- Implemented chunk loading/unloading system
- Implemented inventory component with stack support
- Implemented crafting component with recipe validation
- Implemented player entity with health/hunger components
- Created UI panels (inventory, crafting, HUD)
- Created save system with JSON serialization
- Created main scene and scene files
- Added placeholder biome definitions

## NEXT TASKS

1. Create tile set and terrain rendering system
2. Add more recipe definitions and item definitions
3. Implement creature/AI system
4. Add building placement system
5. Create weather system
6. Add technology progression system
7. Implement status effects
8. Add more biomes and terrain types
9. Create placeholder art assets
10. Add audio system

## KNOWN ISSUES

- World generator uses simple noise, not Perlin (needs FastNoiseLite integration)
- No tile set rendered yet (placeholder colored rects in UI only)
- RecipeRegistry node referenced in main scene but not created
- No creature spawning implemented
- No building placement implemented
- Weather system not started
- Player movement has no collision with terrain
- No pickup/drop mechanics for items
- Save system is placeholder (doesn't save actual world state)

## TESTING

To test the current implementation:

1. Open project in Godot 4.6
2. Run the main scene (F5)
3. WASD to move player
4. I key toggles inventory panel
5. E key triggers interaction (placeholder)
6. F3 toggles debug overlay
7. Check HUD shows health/hunger bars
8. Check debug shows position, chunk, FPS

## IMPORTANT DECISIONS

- Used `GameEventBus` as autoload singleton (not `EventBus`) for consistency
- Chunk size is 16x16 tiles (configurable in ChunkSystem)
- Generator version is 1 (for save compatibility)
- All resources use stable string IDs, not display names
- Inventory is a RefCounted component, not a Node (can be shared)
- World seed is generated randomly at startup

## TEMPORARY IMPLEMENTATIONS

- World generator uses simple sine-based noise (replace with FastNoiseLite)
- Tile rendering is not implemented yet (use colored placeholders)
- RecipeRegistry node is referenced but empty (populate with actual recipes)
- Player collision is disabled (no terrain collision yet)
- Save system collects minimal data (expand for full save/load)
