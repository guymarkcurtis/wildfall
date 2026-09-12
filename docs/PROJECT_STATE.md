# PROJECT STATE

## CURRENT MILESTONE

**Phase 2 (Resource Harvesting) COMPLETE, Phase 3 Gameplay COMPLETE,
Phase 4 core (tool durability + mission system) COMPLETE.**
The full loop works end-to-end and is covered by the automated test suite:
deterministic world generation with 6 biomes → chunk streaming (7×7
viewport) → biome-aware resource spawning → E-key harvesting with tool
multipliers → drops into a stack-based inventory → crafting (research-gated
recipes with complete obtainable ingredient chains) → save/load that
restores the player and every player-caused world mutation. Creature spawning is now live: chunks spawn
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
recipe database is visible (no ghosts left).

The first real play-through (same day, post-push) then found two runtime
bugs the harness could not catch because it teleports the player instead of
walking: **chunk coordinates were computed as pixels ÷ 16 instead of
pixels ÷ 512** (the 7×7 ring re-centred every 16 px and the ground under
the player was unloaded ~64 px into every walk — "the terrain disappears
when I move"), and **the crafting panel was visible at startup with no
input action to close it** ("a big crafting list over everything"). Both
fixed: chunk coords now floor pixel positions by `PIXELS_PER_CHUNK` (512);
the panel starts hidden and a new C-key `toggle_crafting` action opens/closes
it (event bus → Main, same wiring as the I-key inventory). The harness grew
4 pixel/floor unit checks plus a live-input phase (panel toggle + a held
1050 px walk with chunk/terrain-under-feet guards). See
`docs/TEST_RESULTS.md`.

The 2026-09-11 pass added the two Phase 4 core systems: **tool
durability** (consume on use, break at zero with a bare-hand fallback,
re-craft at full, persisted in save v5) and the **mission system**
(7 data-driven missions tracking real pickups/kills/builds, M-key
journal, prerequisite-gated chain, item + tech rewards, save/load).
The pass also fixed a real save-system bug the harness exposed: two
saves written in the same second tie on timestamp, so "most recent
save" picked a random one — slot summaries now carry a sequence number
from the filename and the sort breaks ties by it. See
`docs/MISSION_SYSTEM.md`, `docs/TOOL_SYSTEM.md`, and `docs/TEST_RESULTS.md`.

The same day the **generated-art pass closed out the sprite-polish
task**: all four sheets from `docs/ART_REQUESTS.md` were produced by
driving the Antigravity CLI (`agy`, Gemini image model) on this
machine and composed with PIL into exact contract sizes — creature
roster v2 (2688×1024; columns 0–3 keep the original art, columns 4–6
are new wolf / polar bear / fish), a 2×9 building parts atlas
(64×288), a 5-cell utilities sheet (160×32), and a hand-made station
atlas (128×32) that replaces the procedural generator (now a
missing-file fallback). The wiring pass re-pointed `CreatureVisual`
to the 7-column grid, made `Building` render all 18 structural parts
and the 5 utilities from regioned atlas cells (flat-color rectangles
remain only as a fallback when an art file is missing), and added the
two new atlases to the texture-pack export. All requests in
`docs/ART_REQUESTS.md` are DONE.

## CURRENT TEST RESULTS (2026-09-11)

Automated headless run of the real main scene — **239/239 checks passed,
0 failures, 0 script errors**:

| Test | Status |
|------|--------|
| Scene loading + 9 required nodes | PASS (9/9) |
| World generation (chunk data, 4× pixel/chunk coordinate math, biome variety) | PASS (4 biomes sampled) |
| Terrain rendering (12,544 tiles) + resource spawn | PASS |
| Item database (78 items, 56 recipes) | PASS |
| Crafting + stations + research (scrollable recipe list, nearby station gates, starting recipes, paid research unlocks) | PASS |
| Camera follow (target set, lerp converges) | PASS |
| Seed input (T opens, pre-fill, Escape cancels) | PASS |
| Save/load round-trip (player, destroyed resource/creature spawns, placed buildings) | PASS |
| Chunk lifecycle (generate/unload/reload deterministic) + set_seed regen | PASS |
| Live input: crafting panel hidden at start, C opens it, second C closes it | PASS |
| Live input: 1050 px walk keeps the chunk loaded + terrain rendered under the player | PASS |
| Inventory (persistent quick bar, expandable storage, uniform slot spacing, click/drag transfers) | PASS |
| Building (palette selection, station placement, HUD click pass-through, 4-story support/cutaway) | PASS |
| Resource accessibility (water rejected; rocky ground walkable) | PASS |
| Technology (U panel, costs, prerequisite gating, recipe/build access, save/load) | PASS |
| Texture packs (full-resolution world art, stock-card export, station atlas + structured metadata, explicit Apply + preview, editable pack creation, live switch, fallback) | PASS |
| Tool durability (defined max values, consumed per landed swing/shot, break at zero with bare-hand fallback, re-craft at full, non-durable items, save/load round trip) | PASS |
| Missions (M-key journal, auto-accept on new world, prerequisite lock, progress from real pickups/kills/builds, item + tech rewards, 7/7 completions, save/load) | PASS |
| Generated art (roster 2688×1024, 7 unique species columns, 2×9 parts atlas with all 18 cells drawn, 5-cell utilities atlas, 4-cell station atlas) | PASS (9 checks) |

A 30-second headless run of the actual game also completed with 0 errors,
0 warnings and 0 leaked objects.

### Known Issues (remaining)
1. Some future-phase scripts remain intentionally unwired; see the inventory in `docs/ARCHITECTURE.md`.

## CURRENTLY WORKING (all verified by the test run above)

- **Presentation**: Orthogonal 2D top-down (square 32px tiles, Camera2D). Not isometric.
- **Player Movement**: World-relative WASD (W north, A west, S south, D east) + Sprint and a short aimed Space-bar jump. Faces the pointer, which controls tool and ranged aim. Rocky ground is walkable; water retains terrain collision.
- **Camera**: Smooth follow; `,`/`.` snap-rotate, middle-mouse free rotate, Home resets north-up.
- **Ranged combat**: Face the cursor; LMB fires the wooden bow (consumes arrows).
- **Buildings**: B opens the build palette. Select an owned part, LMB places it, wheel cycles parts, F demolishes, and [ / ] selects one of four stackable cutaway stories. Wood is available immediately; stone parts require Stone Construction research.
- **World clock / weather / statuses**: DayNightCycle + WeatherSystem + StatusEffectSystem, shown on the HUD.
- **World Generation**: Deterministic seed-based generation using 3 FastNoiseLite layers
- **Chunk System**: 16×16 tile chunks, radius-3 (7×7) viewport streaming; reloads are deterministic (B3)
- **Terrain Rendering**: TileMapLayer, 8 terrain types (water, sand, grass, forest, dirt, stone, snow, mud) with per-biome ground colors and per-tile biome lookup
- **Biome System**: 6 biomes (temperate forest, grassland, mountain, desert, arctic, swamp), per-chunk selection + per-tile refinement
- **Resource Nodes**: Interactive HarvestableResource (health, biome-aware yields, proximity highlight)
- **Harvest System**: Tool-based damage multipliers (axe→trees ×2, pickaxe→rock/ore ×2), yields on destruction
- **Resource Spawner**: Deterministic, biome-aware placement on reachable terrain only (desert rock yields sand; mountain yields copper; arctic yields tin)
- **Debug Overlay**: FPS, position, chunk, seed, biome, noise values
- **Seed Input**: T opens the editor (buffer pre-filled), Enter confirms + full world regeneration, Escape cancels; seed 0–999999
- **HUD**: Health bar, hunger bar, seed label (all wired to real nodes)
- **Texture Packs**: Options and Pause → Options can export stock art/contact cards plus a plain JSON image manifest (name, purpose, game use, atlas layout, edit note), create editable override packs, and switch terrain/resource/player/creature/station presentation live. Active pack terrain uses its native 32px-per-tile source resolution. Select a pack then press Apply; a water/sand/grass preview visibly confirms the active art even at the title screen. Eight seamless biome-ground images, the building parts + utilities atlases, and a four-cell crafting-station atlas are included in every export.
- **Event Bus**: Centralized signal-based communication (plain node, no autoload)
- **Inventory System**: Stack-based with weight limits, `inventory_full`, persistent 1–9 quick bar, and expandable click/drag inventory UI
- **Technology System**: U opens research. Free Wood Construction leads to paid Stone Construction (20 wood, 30 stone), then Metalworking; unlocks gate recipes and building placement and persist in saves.
- **Crafting System**: 56 recipes; every unlocked recipe has an obtainable ingredient chain. Campfires, furnaces, workbenches, and anvils are placeable and gate their nearby recipes within 72 pixels. The panel labels nearby stations, disables unavailable recipes, and the game revalidates the requirement on crafting.
- **Creature System (Phase 3)**: per-chunk deterministic spawning (7 creature types, biome-gated; fish only in water), IDLE/PATROL/FLEE AI, E-to-kill with per-creature loot tables (meat, fish, hide, feather, bone)
- **Title screen**: New Game (Survival / Creative, locked per world), Load Game, Options, Quit. Esc pause in-game.
- **Save System**: Versioned module JSON under `user://saves/` — unlimited timestamped manual saves plus rotating autosaves (last 2). A compact spawn-tile ledger preserves destroyed resources and creatures while retaining deterministic chunk generation; placed buildings retain their item, story, and health. Load Game lists both. Options toggles autosave.

## ARCHITECTURE

- `src/core/` — GameEventBus, CameraController, SeedInput
- `src/entities/` — Player (CharacterBody2D with harvesting, RefCounted components), Creature (Phase 3: wander/flee AI, loot on death)
- `src/components/` — HealthComponent, HungerComponent, InventoryComponent (tool durability lives here)
- `src/world/` — WorldGenerator, ChunkSystem, NoiseLayers, TerrainRenderer, ResourceSpawner, HarvestableResource, Mission (Phase 4 data)
- `src/ui/` — HUD, DebugOverlay, InventoryPanel, InventorySlot, BuildPalette, TechnologyPanel, CraftingPanel, MissionPanel (Phase 4)
- `src/systems/` — SaveSystem, ItemDatabase, BuildingManager, TechnologySystem, TexturePackManager, CreatureSpawner, MissionManager (Phase 4)
- `resources/` — ItemDefinition, RecipeDefinition, BiomeDefinition, CreatureDefinition, BuildingDefinition, TechnologyDefinition (wired)
- `scenes/` — `main.tscn` is the only wired scene (see dead-code inventory in ARCHITECTURE.md)
- `tests/` — `test_game.gd` headless harness (230 checks)
- `docs/` — Project documentation

## RECENTLY COMPLETED (2026-09-10 review)

- Fixed 6 parse errors (A1–A6: Godot 3.x syntax left in v4 scripts)
- Fixed boot sequence, seed handling, chunk reload path (B1–B13)
- Fixed HUD bar node paths (B14) and crafting-panel refresh ordering (B15)
- Fixed noise config to the Godot 4.x `FastNoiseLite` API — `fractal_gain` (B16)
- Fixed biome registration (bare Resource → BiomeDefinition; null-key bug) (B17)
- Fixed ObjectDB leak: NoiseLayers now a child of WorldGenerator (B18)
- Raised the recipe panel cap so all obtainable recipes are reachable (B19)
- Rewrote the test harness to exercise the real main scene end-to-end (50 checks)
- Corrected all stale documentation
- Phase 3: wired creature spawning into chunk generation (7 creature types,
  per-chunk deterministic placement), live Creature nodes with wander/flee
  AI, E-to-kill with per-creature loot tables
- Phase 3: closed the then-current recipe obtainability gaps (stone_brick, flour) —
  every one of the then-current 40 recipes was reachable
- Pre-push fix: `creature.gd` lost its Godot 4 port in a context compaction
  (`Circle2D` is abstract in Godot 4 and cannot be instantiated — the body
  is now a `Polygon2D` circle) and the harness's ghost-recipe check was
  still asserting the pre-Phase-3 expectation (then updated to assert all 40 recipes
  are visible). Verified: 41/41 checks, 0 script errors; 35 s live headless
  run with 0 errors
- Post-push gameplay fixes (player-reported): chunk coords now floor
  **pixel** positions by 512 px (the old pixels ÷ 16 math unloaded the
  ground under the player ~64 px into every walk); crafting panel starts
  hidden with a new C-key `toggle_crafting` action (event bus → Main).
  Harness gained 4 pixel-math checks + a live-input phase (panel
  open/close + 1050 px walk with terrain-under-feet guards): **50/50
  checks, 0 script errors; 35 s live headless run with 0 errors**

## RECENTLY COMPLETED (2026-09-11 gameplay pass)

- Rebuilt the inventory into an expandable storage window with a persistent
  nine-slot quick bar, keyboard selection, click transfers, and drag/drop.
- Added the build palette and fixed HUD input pass-through so selecting a
  structural part can be followed by actual world placement.
- Expanded building into wood and stone structural kits with foundations,
  floors, walls, windows, doors, roofs, stairs, ramps, and pillars; supports
  four stackable stories with a lower-story cutaway.
- Made rocky terrain walkable and constrained resource spawning to reachable
  non-water terrain.
- Expanded the automated harness to **126 passing checks** covering those
  gameplay paths.

## RECENTLY COMPLETED (2026-09-11 technology pass)

- Added a saved, data-driven research tree and an in-game `U` technology
  panel with costs, prerequisite feedback, and a creative-mode bypass.
- Made Stone Construction cost 20 wood + 30 stone after free Wood
  Construction; Metalworking follows Stone Construction.
- Applied research gates consistently to the crafting list, actual crafting,
  build-palette ownership, and direct building placement.
- Expanded the harness to **142 passing checks**, including research UI,
  costs, gates, and save/load restoration.

## RECENTLY COMPLETED (2026-09-11 texture-pack pass)

- Added an Options and Pause-menu texture-pack selector with live visual
  refresh and persistent selected-pack setting.
- Added stock contact-card/reference export and a non-destructive editable
  `refinement` pack workflow for external or AI-assisted art editing.
- Preserved atlas dimensions, TileSet IDs, terrain corner blending, and water
  collision while changing artwork.
- Added eight editable, seamless biome-ground textures and a schema-versioned
  `manifest.json` that identifies every exported image's name, purpose, game
  use, sheet layout, and edit constraints.
- Expanded the harness to **152 passing checks** including export metadata,
  ground overrides, and live selection coverage.

## RECENTLY COMPLETED (2026-09-11 world-state persistence)

- Added a JSON-safe, seed-relative mutation ledger for depleted resource and
  killed creature spawn tiles; unloaded chunks remain deterministic while
  those exact spawns remain absent after loading.
- Retained the existing building serialization (item, tile, story, and
  health), so only surviving placed buildings are restored after loading.
- Bumped saves to v4; v1–v3 saves migrate with an empty world-state ledger.
- Expanded the real-scene harness to **178 passing checks**, including a
  destroy/kill/place → save → load round-trip.

## RECENTLY COMPLETED (2026-09-11 generated art + wiring pass)

- Generated all four art sheets with the Antigravity CLI (`agy`
  v1.2.1, Gemini image model, headless `--print` mode) and composed
  them with PIL to the exact grid contracts:
  - `assets/creatures/alien-creature-roster.png` — 2688×1024
    (7×2, columns 0–3 preserved from the old sheet, new wolf /
    polar bear / fish columns)
  - `assets/tiles/wildfall-building-parts.png` — 64×288 (2×9 wood/stone)
  - `assets/tiles/wildfall-building-utilities.png` — 160×32 (torch, bed, chest, farm soil, fence)
  - `assets/tiles/wildfall-crafting-stations.png` — 128×32 (replaces the
    procedural pixels; the generator now runs only when the file is missing)
- Wiring: `CreatureVisual` 7-column grid + new species column map;
  `Building._atlas_cell()` renders 18 structural parts + 5 utilities
  from regioned atlas sprites with the color rectangles demoted to
  a missing-art fallback; `TexturePackManager` exports the two new
  atlases in every pack.
- One regeneration: the first fence tile was a 7%-frame thin strip
  (invisible at 32px); the re-generated fence is a chunky
  posts-and-rails block at 47% frame fill, consistent with its
  utility-sheet neighbours.
- Harness expanded to **239 passing checks** (9 new art checks:
  sheet dimensions, 7 unique species columns, per-cell artwork
  presence for all 18 parts + 5 utilities + 4 stations), 0
  failures, 0 script errors.

## RECENTLY COMPLETED (2026-09-11 durability + missions pass)

- **Tool durability (task 2)**: every tool carries a durability value from
  its ItemDefinition (wooden axe 50, pickaxe 100, sword 50, bow 80). One
  point is consumed per swing that lands on a resource or creature and per
  bow shot; selecting a tool on the quick-bar costs nothing. At zero the
  tool breaks — slot cleared, toast, automatic fallback to bare hands —
  and re-crafting gives a fresh full-durability tool (no repair in v1).
  Durability state lives in the inventory component and persists through
  save format v5 (pre-v5 saves backfill tools at full on load).
- **Mission system (task 3)**: 7 data-driven missions (4-chapter main
  chain + 3 side missions) in `MissionManager` (code-defined catalog),
  tracked from real gameplay (pickups, kills, builds) — progress only
  counts while a mission is IN_PROGRESS, and a mission arms on accept.
  First Steps auto-accepts on a new world; the chain gates on completed
  prerequisites; completion grants item rewards + free tech unlocks
  (stone_building, metalworking). The M-key journal (MissionPanel)
  lists active/completed/available missions with accept buttons and
  refreshes on every state change; missions persist in save v5.
- **Save-slot tiebreak fix**: same-second manual saves tied on timestamp
  and `most_recent_save_path()` picked one arbitrarily (the harness hit
  this and loaded a stale save). Slot summaries now parse the
  `_N` filename suffix into a `seq` field and the newest-save sort
  breaks timestamp ties by seq.
- Expanded the harness to **230 passing checks** (22 durability + 32
  mission checks, plus the reworked durability/mission blocks), 0
  failures, 0 script errors — green on two consecutive runs.

## NEXT TASKS

(Sprite polish is done — all four generated-art requests in
`docs/ART_REQUESTS.md` are landed and wired, 239/239 harness checks
green. Durability and the mission system are done too — see
RECENTLY COMPLETED below.)

1. **Sound effects** (next open Phase 4 item in `docs/ROADMAP.md`) —
   the game currently has no audio: UI clicks, harvesting, combat
   hits, creature deaths, building placement/demolition, mission
   accept/complete toasts, and the day/night ambience hooks are the
   natural first set.

## KNOWN ISSUES

- Terrain uses color placeholders (no actual sprite tiles)
- Resource nodes use colored circles / simple shapes (no sprites)
- Technology currently has three tiers; later content needs additional tier definitions and unlock rewards

## TESTING

Automated (recommended first — Godot 4.7.2 headless, see TEST_RESULTS.md
for the exact XDG-prefixed command this sandbox requires):
```bash
XDG_DATA_HOME=/tmp/godot-check/xdg XDG_CONFIG_HOME=/tmp/godot-check/xdg \
XDG_CACHE_HOME=/tmp/godot-check/xdg \
  /tmp/godot-check/Godot_v4.7.2-stable_linux.x86_64 \
  --headless --path /home/guy/2d-icarus --script res://tests/test_game.gd
```
Exit code = number of failed checks (0 = green). Also run
`--headless --import` after any script change to refresh the class cache.

Manual:
1. Open project in Godot 4.6+ (this machine: 4.7.2), run the main scene (F5)
2. WASD is world-relative (W north, A west, S south, D east), Shift sprints, and Space performs a short aimed jump
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
- **Controls: WASD is world-relative** (W north, A west, S south, D east), **mouse aims** character-facing and ranged weapons, Space jumps, and **`,` / `.` and middle-mouse drag rotate the view**, Home resets north-up.
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
- Crafting is instant by default; station proximity is enforced but craft times are not yet simulated
