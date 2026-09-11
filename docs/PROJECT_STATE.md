# PROJECT STATE

## CURRENT MILESTONE

**Phase 2 (Resource Harvesting) COMPLETE, Phase 3 (Creatures) wired in.**
The full loop works end-to-end and is covered by the automated test suite:
deterministic world generation with 6 biomes → chunk streaming (7×7
viewport) → biome-aware resource spawning → E-key harvesting with tool
multipliers → drops into a stack-based inventory → crafting (all 40
recipes visible — Phase 3 closed every obtainability gap) → save/load that
restores the player exactly. Creature spawning is now live: chunks spawn
their deterministic creature set (rabbits, deer, fish, ...), creatures
wander/flee on a state machine, the player can kill them (E) and they drop
loot (meat, fish, hide, feather, bone) into the inventory.

On 2026-09-10 a full code review found and fixed the defects that had been
blocking a clean run (157,518 runtime script errors at boot before the
fix; 0 after). A second pre-push verification on 2026-09-10 found the
Phase 3 work had lost its final fix in a context compaction: `creature.gd`
still used `Circle2D` (an abstract class in Godot 4 → `Creature.new()`
crashed on every chunk generation) and the test's ghost-recipe check still
encoded the pre-Phase-3 expectation. Both fixed: the placeholder body is a
`Polygon2D` circle approximation, and the test now asserts the whole
recipe database is visible (no ghosts left). See `docs/TEST_RESULTS.md`.

## TEST RESULTS (2026-09-10)

Automated headless run of the real main scene — **41/41 checks passed,
0 script errors, exit code 0**:

| Test | Status |
|------|--------|
| Scene loading + 9 required nodes | PASS (9/9) |
| World generation (chunk data, 3× coordinate math, biome variety) | PASS (4 biomes sampled) |
| Terrain rendering (12,544 tiles) + resource spawn | PASS |
| Item database (62 items, 40 recipes) | PASS |
| Crafting panel (all 40 visible — Phase 3 left no ghost recipes) | PASS |
| Camera follow (target set, lerp converges) | PASS |
| Seed input (T opens, pre-fill, Escape cancels) | PASS |
| Save/load round-trip (position restored exactly) | PASS |
| Chunk lifecycle (generate/unload/reload deterministic) + set_seed regen | PASS |

A 30-second headless run of the actual game also completed with 0 errors,
0 warnings and 0 leaked objects.

### Known Issues (remaining)
1. Terrain uses solid-color placeholder tiles — no sprite art yet (visual only).
2. Recipe list has no scroll view — with 40 recipes the list overflows the panel bounds (functional, cosmetic).
3. Crafting stations (campfire/furnace/anvil) are data-only: recipes show a station but proximity is not enforced because stations are not placeable yet.
4. 34 scripts for future phases (weather, vehicles, mounts, buildings, AI, ...) do not parse and are not wired into any scene — zero runtime impact. Inventory in `docs/ARCHITECTURE.md`.

## CURRENTLY WORKING (all verified by the test run above)

- **Presentation**: Orthogonal 2D top-down (square 32px tiles, Camera2D). Not isometric. View rotation and mouse-aim are designed, not implemented yet.
- **Player Movement**: WASD + Sprint (Shift), CharacterBody2D. Intended to stay screen-relative once view rotation lands.
- **Camera**: Smooth follow (delta-based lerp) with configurable offset
- **World Generation**: Deterministic seed-based generation using 3 FastNoiseLite layers
- **Chunk System**: 16×16 tile chunks, radius-3 (7×7) viewport streaming; reloads are deterministic (B3)
- **Terrain Rendering**: TileMapLayer, 8 terrain types (water, sand, grass, forest, dirt, stone, snow, mud) with per-biome ground colors and per-tile biome lookup
- **Biome System**: 6 biomes (temperate forest, grassland, mountain, desert, arctic, swamp), per-chunk selection + per-tile refinement
- **Resource Nodes**: Interactive HarvestableResource (health, biome-aware yields, proximity highlight)
- **Harvest System**: Tool-based damage multipliers (axe→trees ×2, pickaxe→rock/ore ×2), yields on destruction
- **Resource Spawner**: Deterministic placement, biome-aware (desert rock yields sand; mountain yields copper; arctic yields tin)
- **Debug Overlay**: FPS, position, chunk, seed, biome, noise values
- **Seed Input**: T opens the editor (buffer pre-filled), Enter confirms + full world regeneration, Escape cancels; seed 0–999999
- **HUD**: Health bar, hunger bar, seed label (all wired to real nodes)
- **Event Bus**: Centralized signal-based communication (plain node, no autoload)
- **Inventory System**: Stack-based with weight limits, `inventory_full` signal
- **Crafting System**: 40 recipes; Phase 3 closed every obtainability gap, so the panel shows all 40 (the obtainability filter remains as a safety net for future recipes)
- **Creature System (Phase 3)**: per-chunk deterministic spawning (7 creature types, biome-gated; fish only in water), IDLE/PATROL/FLEE AI, E-to-kill with per-creature loot tables (meat, fish, hide, feather, bone)
- **Save System**: JSON (user://savegame.json) with version tracking; position/health/hunger/inventory/seed round-trip verified

## ARCHITECTURE

- `src/core/` — GameEventBus, CameraController, SeedInput
- `src/entities/` — Player (CharacterBody2D with harvesting, RefCounted components), Creature (Phase 3: wander/flee AI, loot on death)
- `src/components/` — HealthComponent, HungerComponent, InventoryComponent, CraftingComponent
- `src/world/` — WorldGenerator, ChunkSystem, NoiseLayers, TerrainRenderer, ResourceSpawner, HarvestableResource, HarvestSystem
- `src/ui/` — HUD, DebugOverlay, InventoryPanel, CraftingPanel
- `src/systems/` — SaveSystem, ItemDatabase, CreatureSpawner (Phase 3)
- `resources/` — ItemDefinition, RecipeDefinition, BiomeDefinition, CreatureDefinition (wired); TechnologyDefinition, BuildingDefinition (future phases)
- `scenes/` — `main.tscn` is the only wired scene (see dead-code inventory in ARCHITECTURE.md)
- `tests/` — `test_game.gd` headless harness (41 checks)
- `docs/` — Project documentation

## RECENTLY COMPLETED (2026-09-10 review)

- Fixed 6 parse errors (A1–A6: Godot 3.x syntax left in v4 scripts)
- Fixed boot sequence, seed handling, chunk reload path (B1–B13)
- Fixed HUD bar node paths (B14) and crafting-panel refresh ordering (B15)
- Fixed noise config to the Godot 4.x `FastNoiseLite` API — `fractal_gain` (B16)
- Fixed biome registration (bare Resource → BiomeDefinition; null-key bug) (B17)
- Fixed ObjectDB leak: NoiseLayers now a child of WorldGenerator (B18)
- Raised the recipe panel cap so all obtainable recipes are reachable (B19)
- Rewrote the test harness to exercise the real main scene end-to-end (41 checks)
- Corrected all stale documentation
- Phase 3: wired creature spawning into chunk generation (7 creature types,
  per-chunk deterministic placement), live Creature nodes with wander/flee
  AI, E-to-kill with per-creature loot tables
- Phase 3: closed the last recipe obtainability gaps (stone_brick, flour) —
  every one of the 40 recipes is now reachable, so the panel shows all 40
- Pre-push fix: `creature.gd` lost its Godot 4 port in a context compaction
  (`Circle2D` is abstract in Godot 4 and cannot be instantiated — the body
  is now a `Polygon2D` circle) and the harness's ghost-recipe check was
  still asserting the pre-Phase-3 expectation (now asserts all 40 recipes
  are visible). Verified: 41/41 checks, 0 script errors; 35 s live headless
  run with 0 errors

## NEXT TASKS

1. Replace placeholder tile colors with sprite tiles (tileset + art)
2. Make crafting stations placeable and enforce station proximity in crafting
3. Add a scroll view to the recipe list (panel currently overflows)
4. Phase 3 creature system: hostile AI (chase/attack), creature persistence in saves, sprite visuals
5. Tool durability system
6. Day/night cycle and weather
7. Building placement
8. Mission system

## KNOWN ISSUES

- Terrain uses color placeholders (no actual sprite tiles)
- Resource nodes use colored circles / simple shapes (no sprites)
- No tool durability system
- Crafting stations are data-only (not placeable, not proximity-enforced)
- No day/night cycle, no building placement (planned phases)
- Creatures are not persisted in saves (they respawn from seed on load)
- Save system persists player state but not destroyed-resource state (resources regenerate from seed on load)

## TESTING

Automated (recommended first):
```bash
HOME=/tmp/godot_home /tmp/godot/Godot_v4.6-stable_linux.x86_64 \
  --headless --path /home/guy/2d-icarus --script tests/test_game.gd
```
Exit code = number of failed checks (0 = green). Also run
`--headless --import` after any script change to refresh the class cache.

Manual:
1. Open project in Godot 4.6+ (this machine: 4.7.2), run the main scene (F5)
2. WASD to move (orthogonal 2D top-down, not isometric), Shift+WASD to sprint
3. Walk to a tree/rock/ore node and press E to harvest (matching tool doubles damage)
4. Walk to a creature and press E to hunt (loot drops into inventory)
5. Check inventory (I key) for collected resources
6. Open crafting (C key) and craft planks → a tool
7. F3 toggles the debug overlay
8. T changes the world seed (Enter confirms, Escape cancels) — the whole world regenerates
9. Verify different biomes look and drop differently (desert → sand, mountain → copper, arctic → tin)

Local headless:
```bash
godot --headless --path . --script tests/test_game.gd
```

## IMPORTANT DECISIONS

- **Graphics: orthogonal 2D top-down**, square tiles / Camera2D. Not isometric. A later 2.5D look is sprites + Y-sort on this same grid, not an iso or 3D rewrite.
- **Controls: WASD to move** (screen-relative), **mouse pointer to aim** ranged weapons, **`,` / `.` and middle-mouse drag to rotate the view**, Home to reset north-up. Mouse-aim and view rotation are specified, not implemented yet.
- Project name is "Wildfall" (renamed from "2D Icarus")
- HarvestableResource is an Area2D for proximity detection
- Resource yields are configurable per type and biome
- Tool multipliers affect damage dealt to resources
- Resources are created as children of Main's WorldRoot node
- Each chunk generates 5–15 resources
- No autoloads: all singletons are plain nodes in `main.tscn` (GameEventBus included)
- Seeds are 0–999999; chunk seeds derive arithmetically from world seed + chunk coords (see WORLD_GENERATION.md)

## TEMPORARY IMPLEMENTATIONS

- Resource nodes use simple CircleShape2D collision and placeholder visuals
- Tool system is basic (no durability or degradation)
- Crafting is instant by default; stations are not enforced
- Recipe list has no scroll view
