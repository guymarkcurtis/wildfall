# PROJECT STATE

## CURRENT MILESTONE

**Phase 2: Resource Harvesting** — The harvesting system is implemented. Players can approach resource nodes (trees, rocks, minerals) and press E to harvest them. Tools improve yield. Resources drop items into inventory.

## CURRENTLY WORKING

- **Player Movement**: WASD + Sprint (Shift), responsive CharacterBody2D
- **Camera**: Smooth follow camera with configurable offset
- **World Generation**: Deterministic seed-based generation using FastNoiseLite
- **Chunk System**: 16x16 tile chunks with viewport-based loading/unloading
- **Terrain Rendering**: TileMapLayer with 8 terrain types (water, sand, grass, forest, dirt, stone, snow, mud)
- **Biome System**: 6 biomes (temperate forest, grassland, mountain, desert, arctic, swamp)
- **Resource Nodes**: Interactive HarvestableResource with health, yields, and proximity highlighting
- **Harvest System**: Tool-based damage with multipliers, yield generation on destruction
- **Resource Spawner**: Deterministic placement of trees, rocks, fibre, berries, ores
- **Debug Overlay**: Shows FPS, position, chunk, seed, biome, noise values
- **Seed Input**: T key to change seed, Enter to confirm, Escape to cancel
- **HUD**: Health bar, hunger bar, seed display
- **Event Bus**: Centralized signal-based communication
- **Inventory System**: Stack-based with weight limits
- **Crafting System**: Recipe-based with validation
- **Save System**: JSON serialization with version tracking

## ARCHITECTURE

- `src/core/` — GameEventBus, CameraController, SeedInput, ChunkSystem
- `src/entities/` — Player (CharacterBody2D with harvesting)
- `src/components/` — HealthComponent, HungerComponent, InventoryComponent, CraftingComponent
- `src/world/` — WorldGenerator, ChunkSystem, NoiseLayers, TerrainRenderer, ResourceSpawner, HarvestableResource, HarvestSystem
- `src/ui/` — HUD, DebugOverlay, InventoryPanel, CraftingPanel
- `src/systems/` — SaveSystem
- `resources/` — ItemDefinition, RecipeDefinition, BiomeDefinition, CreatureDefinition, TechnologyDefinition, BuildingDefinition
- `scenes/` — Main scene, UI panels
- `docs/` — Project documentation

## RECENTLY COMPLETED

- Created HarvestableResource (Area2D with health, yields, proximity detection)
- Created HarvestSystem (tool multipliers, yield generation, range checking)
- Updated Player to include harvesting and tool system
- Updated ResourceSpawner to generate interactive nodes
- Updated Main to create and manage resource nodes
- Added resource_yield signal for feedback

## NEXT TASKS

1. Add proper tile sprites for terrain and resources
2. Implement hotbar UI for tools
3. Add tool durability system
4. Create item definitions for all resources
5. Add crafting stations (workbench, furnace)
6. Implement day/night cycle
7. Add weather system
8. Create creature definitions and spawning
9. Implement building placement
10. Create mission system

## KNOWN ISSUES

- Terrain uses color placeholders (no actual sprite tiles)
- Resource nodes have no visual representation yet
- No tool durability system
- No crafting station UI
- No day/night cycle
- No creature spawning
- No building system
- Save system doesn't persist world state yet

## TESTING

To test the current implementation:

1. Open project in Godot 4.6
2. Run the main scene (F5)
3. WASD to move player
4. Shift+WASD to sprint
5. Walk near tree/rock icons (colored circles)
6. Press E to harvest nearby resources
7. Check inventory (I key) for collected resources
8. F3 toggles debug overlay
9. T key changes world seed
10. Verify different biomes have different resources

## IMPORTANT DECISIONS

- Project renamed from "2D Icarus" to "Wildfall"
- HarvestableResource is an Area2D for proximity detection
- Resource yields are configurable per type
- Tool multipliers affect damage dealt to resources
- Resources are created as children of Main node
- Each chunk generates 5-15 random resources

## TEMPORARY IMPLEMENTATIONS

- Resource nodes use simple CircleShape2D collision
- No visual sprites for resources yet
- Tool system is basic (hand, wooden_axe, stone_pickaxe, etc.)
- No tool degradation or durability
- No crafting UI yet
