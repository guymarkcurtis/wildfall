# PROJECT STATE

## CURRENT MILESTONE

**Phase 0-1: Foundation & World Generation** — The core engine is built: player movement, camera, deterministic chunk-based world generation with FastNoiseLite, terrain rendering, resource placement, debug overlay, and seed input. The world generates biomes (forest, grassland, mountain, desert, arctic, swamp) and places resource nodes.

## CURRENTLY WORKING

- **Player Movement**: WASD + Sprint (Shift), responsive CharacterBody2D
- **Camera**: Smooth follow camera with configurable offset
- **World Generation**: Deterministic seed-based generation using FastNoiseLite
- **Chunk System**: 16x16 tile chunks with viewport-based loading/unloading
- **Terrain Rendering**: TileMapLayer with 8 terrain types (water, sand, grass, forest, dirt, stone, snow, mud)
- **Biome System**: 6 biomes (temperate forest, grassland, mountain, desert, arctic, swamp) with parameter-based selection
- **Resource Placement**: Deterministic placement of trees, rocks, fibre, berries, iron ore, coal, gold ore
- **Debug Overlay**: Shows FPS, world position, tile position, chunk position, seed, biome, noise values
- **Seed Input**: Press T to enter/change seed, Enter to confirm, Escape to cancel
- **HUD**: Health bar, hunger bar, seed display
- **Event Bus**: Centralized signal-based communication
- **Inventory System**: Stack-based with weight limits
- **Crafting System**: Recipe-based with validation
- **Save System**: JSON serialization with version tracking

## ARCHITECTURE

- `src/core/` — GameEventBus, CameraController, SeedInput, ChunkSystem
- `src/entities/` — Player (CharacterBody2D)
- `src/components/` — HealthComponent, HungerComponent, InventoryComponent, CraftingComponent
- `src/world/` — WorldGenerator, ChunkSystem, NoiseLayers, TerrainRenderer, ResourceSpawner
- `src/ui/` — HUD, DebugOverlay, InventoryPanel, CraftingPanel
- `src/systems/` — SaveSystem
- `resources/` — ItemDefinition, RecipeDefinition, BiomeDefinition, CreatureDefinition, TechnologyDefinition, BuildingDefinition
- `scenes/` — Main scene, UI panels
- `docs/` — Project documentation

Key architectural decisions:
- **No God Object**: Systems communicate via GameEventBus signals
- **Data-Driven Content**: All game objects use Resource subclasses with stable IDs
- **Deterministic Gen**: Same seed + generator version = same world
- **Chunk-Based**: 16x16 tile chunks, viewport-based loading
- **FastNoiseLite**: Proper Perlin noise for terrain generation
- **TileMapLayer**: GPU-accelerated terrain rendering

## RECENTLY COMPLETED

- Implemented FastNoiseLite-based world generation
- Created 8 terrain tile types with color-based placeholders
- Added 6 biome definitions with parameter ranges
- Implemented deterministic resource node placement
- Added CameraController with smooth following
- Created DebugOverlay showing all world generation data
- Added seed input mechanism (T key to change seed)
- Updated project name to "Wildfall"
- Added sprint input (Shift key)
- Fixed chunk system to properly use seed

## NEXT TASKS

1. Add proper tile set with sprites (replace color placeholders)
2. Implement resource harvesting (chop tree, mine rock)
3. Add player interaction system
4. Implement crafting stations
5. Add more item and recipe definitions
6. Create creature definitions and spawning
7. Implement day/night cycle
8. Add weather system
9. Implement building placement
10. Create mission system

## KNOWN ISSUES

- Terrain uses color placeholders (no actual sprite tiles)
- No resource harvesting mechanic yet
- No player collision with terrain
- No creature spawning
- No building system
- Weather system not started
- Save system doesn't persist world state yet
- No day/night cycle
- No combat system

## TESTING

To test the current implementation:

1. Open project in Godot 4.6
2. Run the main scene (F5)
3. WASD to move player
4. Shift+WASD to sprint
5. I key toggles inventory panel
6. F3 toggles debug overlay
7. T key changes world seed (Enter to confirm, Escape to cancel)
8. Check debug shows: FPS, position, chunk, seed, biome, noise values
9. Walk around to see different biomes and resources
10. Verify same seed generates same world

## IMPORTANT DECISIONS

- Project renamed from "2D Icarus" to "Wildfall"
- Chunk size is 16x16 tiles
- Generator version is 1
- All resources use stable string IDs
- World generation uses FastNoiseLite (not simple sine noise)
- Biome selection uses weighted scoring
- Camera follows player with smooth interpolation
- Debug overlay shows all world generation metrics

## TEMPORARY IMPLEMENTATIONS

- Terrain uses colored placeholder rects (replace with sprite tiles)
- No collision with terrain
- No resource harvesting
- No creature AI
- No building system
- Save system is minimal (needs expansion)
