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
│                      GameEventBus                    │
│        (plain node in main.tscn — no autoloads)      │
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
Central signal-based communication system. All systems emit and listen to
signals here. It is a **plain Node child of Main** in `main.tscn` — the
project deliberately has **no autoloads**, so `Main` keeps a cached
reference and passes it into the systems it creates.

### Player
CharacterBody2D with:
- WASD movement + Sprint (Shift)
- Health and hunger components
- Inventory management
- Position tracking

### WorldGenerator
Handles procedural generation:
- Three FastNoiseLite layers (elevation, moisture, temperature),
  configured with `fractal_gain` (the Godot 4.x name)
- NoiseLayers is a **child node** of WorldGenerator (added in
  initialize; freed together with it — a bare `.new()` would leak)
- Biome selection: per-chunk from noise averages, per-tile via
  `get_biome_at_world()`
- Biome definitions are `BiomeDefinition` resources (not bare
  Resources — bare `Resource.set()` on undeclared properties is a
  silent no-op and used to register all 6 biomes under a null key)
- Returns chunk data dictionary (noise arrays + biome + chunk seed)

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

### CreatureSpawner (Phase 3 — wired)
Deterministic per-chunk creature placement, driven by `CreatureDefinition`
resources:
- `initialize(seed)` builds per-chunk creature lists (a separate
  arithmetic seed mix from the resource spawner, so the two streams do
  not mirror each other)
- Only creature types whose `allowed_biomes` include the chunk's biome
  are eligible (fish target the "water" sentinel, never a land biome)
- Main spawns a live `Creature` node per entry (as a sibling of the
  Player, so the player's nearby-creature scan can find them) and tracks
  them per chunk so unload/reload frees and recreates them
- `get_all_droppable_items()` feeds Main's recipe obtainability filter —
  creature drops are what unhide the Phase 3 hunting recipes

### Creature (Phase 3 — wired)
CharacterBody2D with a small IDLE → PATROL → FLEE state machine:
creatures wander inside their spawn chunk's bounds and flee while the
player is within `detection_range`; fish only flee into water tiles.
Placeholder visual is a filled `Polygon2D` circle (Godot 4's `Circle2D`
is an abstract drawing primitive that cannot be instantiated) plus a name
label and a mini health bar. Phase 3 creatures are passive/neutral — the
player kills them with E and they roll their loot table
(meat/fish/hide/feather/bone) on death.

## Data-Driven Resources

All game content uses Resource subclasses:

| Resource | Purpose | Key Fields (actual) |
|----------|---------|------------|
| ItemDefinition | Item data (62 items) | item_id, display_name, category, stack_size, weight, rarity, health_bonus, hunger_bonus, damage_bonus, durability, tool_type |
| RecipeDefinition | Crafting recipe (40 recipes) | recipe_id, result_item_id, result_quantity, crafting_station, required_items {id: qty}, craft_time, unlocked |
| BiomeDefinition | Biome config (6 biomes) | id, display_name, elevation_range, moisture_range, temperature_range, ground_color, rain_chance, snow_chance, resource_types, creature_types, vegetation_types |
| CreatureDefinition | Creature data — **wired (Phase 3)** | id, type, health, speed, detection_range, hostile, allowed_biomes, loot_table, custom_data |
| TechnologyDefinition | Tech unlock — **future phase, not wired** | id, prerequisites[], unlock_cost[] |
| BuildingDefinition | Building data — **future phase, not wired** | id, width, height, build_cost[] |

## Unwired future-phase code (known, intentional)

34 scripts for phases 4+ do **not** parse (they were drafted with Godot
3.x / Python-style syntax) and are **not referenced by any scene or
script**, so they have zero runtime impact — the game's entire runtime
surface is the ~27 wired scripts listed above (including the Phase 3
`Creature` entity and `CreatureSpawner`). The scripts below are kept as
placeholders for their future phases and are NOT part of the shipped
game:

- `src/entities/`: combat_system, mount, vehicle
- `src/systems/`: accessibility_manager, advanced_ai, ai_manager,
  audio_effects, building_manager, combat_manager,
  durability_system, mission_manager, mount_manager,
  optimization_manager, performance_manager, station_manager,
  status_effect_system, vehicle_manager, weather_effects
- `src/core/`: audio_manager, game_manager
- `src/components/`: inventory_upgrades
- `src/ui/`: accessibility_ui, ai_display, audio_ui, building_panel,
  inventory_upgrades_ui, mission_panel, mount_ui, performance_ui,
  status_effect_ui, vehicle_ui, weather_display
- `src/world/`: building, weather_system

Also unwired: orphan scene duplicates `scenes/crafting_panel.tscn` and
`scenes/inventory_panel.tscn` (the real panels live inside
`main.tscn`), and the empty directories `feature_profiles/`,
`export_templates/`, `script_templates/`, `text_editor_themes/`.

These files will either be ported to Godot 4.x when their phase is
built or deleted; they should not be read as working code.

## Signal Flow

Actual signals on GameEventBus:

```
world_seed_set(int)  inventory_changed   item_added(item_id, qty)
recipe_crafted       recipe_failed       entity_hit
entity_died          player_spawned      health_changed
hunger_changed       player_died         toggle_debug
toggle_inventory_ui
```

Flows:
- Seed change → SeedInput emits seed_changed → Main._generate_world →
  WorldGenerator + ResourceSpawner re-initialize → ChunkSystem
  regenerates the 7×7 viewport → terrain/resources/HUD refresh
- Player moves → ChunkSystem viewport check → load/unload chunks
  (deterministic from seed) → Main creates/frees resource + creature nodes
- Creatures: chunk generated → CreatureSpawner list → Main adds Creature
  nodes → wander/flee in _physics_process → player E → take_damage →
  death rolls loot → creature_died → Main adds loot to inventory +
  entity_died on the bus
- Harvest: Player E → HarvestSystem → node destroyed → yields →
  Main adds to inventory → item_added → HUD/panel refresh
- Craft: panel button → CraftingComponent.craft_recipe →
  result_crafted / recipe_failed → inventory + panel refresh
- Debug toggle (F3) → toggle_debug → DebugOverlay
- Seed change (T/Enter) → seed_changed + world_regenerated

## World Generation Pipeline (boot)

1. SeedInput._ready picks a random seed (0–999999) and emits
   seed_changed — this happens **before** Main's _ready
2. Main._on_seed_changed → _generate_world: WorldGenerator.initialize
   (noise + biomes), ResourceSpawner.initialize, ChunkSystem.initialize
   (radius-3 box, 49 chunks)
3. Per chunk: chunk seed = world_seed*73856093 + x*19349663 +
   y*83492791 → 256×3 noise values → chunk biome from averages
4. Player moved to world origin
5. Main._ready: spawns the player, renders all visible chunks
   (TerrainRenderer + ResourceSpawner nodes), sets the camera
6. Movement drives viewport streaming; DebugOverlay shows live state

## Performance Considerations

- Only chunks within viewport radius are generated
- Chunk generation is deterministic (same seed = same result)
- No per-tile nodes (TileMapLayer is GPU-accelerated)
- Inventory/Crafting are RefCounted (no scene overhead)
- Debug overlay only renders when enabled
