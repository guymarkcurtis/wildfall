# Wildfall Test Results

## Test Run Summary
- **Current verification**: 327 checks passed, 0 failures, 0 script errors (Godot 4.7.2 headless run after the data-driven world-generation, regional-biome, POI-spacing, cave-runtime, directional-animation, fixed-world-direction control, startup content-validation (WG-01), the generic POI layer (WG-02), the coherent-region stage (WG-03), and the terrain-feature candidate layer (WG-04) work; includes registry, large-world configuration, underground-mineral filtering, deterministic regional/POI/cave identity, underground cave deposits, cave entry/exit, discovery-ledger checks, authored player-direction/action frames, jumping, all four fixed WASD axes, the 20-check invalid-content validation suite, the 11-check coherent-region suite (fixture data-driven region floors, world-aligned cell grid, no sub-floor fragments, metadata-respecting merges, tile-for-tile payload/query agreement, seam-chunk and reversed-order stability, and a live-seed dormant no-op), and the 15-check terrain-feature suite (asset discovery/validation, dormant live world, regeneration + seam + reversed-order stability, halo/owner invariants, min-spacing, and the spawner's no_spawn veto end-to-end))
- **Godot Version**: 4.7.2.stable (linux.x86_64, official) — the project was upgraded to Godot 4.7 on 2026-09-11 (editor config sync from the Mac) and the Linux verification binary was upgraded to match
- **Test Script**: `tests/test_game.gd` (SceneTree harness that boots the real `main.tscn`, validates world, UI, inventory, building, technology progression, texture-pack export/live switching, save persistence of player-caused world mutations, and resource accessibility, then exits with the failure count as its exit code)

### Test command
```bash
# XDG overrides are required in this sandbox (the default ~/.local/share/godot
# path is unwritable and makes Godot crash with signal 11).
XDG_DATA_HOME=/tmp/godot-check/xdg XDG_CONFIG_HOME=/tmp/godot-check/xdg \
XDG_CACHE_HOME=/tmp/godot-check/xdg \
  /tmp/godot-check/Godot_v4.7.2-stable_linux.x86_64 \
  --headless --path /home/guy/2d-icarus --script res://tests/test_game.gd
```

## Engine upgrade: 4.6 → 4.7.2 (2026-09-11)

## Data-driven world-generation refactor (2026-09-12)

The world-generation foundation now discovers biome/resource/cave/POI Resource
assets, derives stable world/chunk/tile/cave seeds, uses configurable finite
bounds and streaming, emits a physical water mask and POI candidates, and
filters underground-only mineral definitions out of surface spawning. The
existing mutation-ledger save flow remains compatible. The harness grew from
239 to **253 checks** and passes with 0 failures and 0 script errors. Regional
biome fields and adjacency metadata are deterministic and data-defined; POI
coverage includes deterministic cross-chunk spacing and stable candidate
generation; cave coverage includes deterministic identity, data-defined
underground deposit candidates, an entry chamber, entering/exiting a separate
runtime space, and discovery-ledger persistence.

## Startup content validation — WG-01 (2026-09-12)

`WorldContentRegistry` now fails clearly on invalid content. Discovery reports
load failures, wrong script types, missing `id`s, and duplicate `id`s (naming
both assets, later file still wins at runtime); `validate()` then checks
per-asset rules (inverted or out-of-bounds normalized environment ranges,
missing/unsupported terrain ids, `water` as biome terrain, out-of-range cave
entrance suitability, unknown distribution modes, unspawnable resources, empty
yield items, inconsistent cave room/deposit ranges, negative POI spacing) and
cross-references (biome neighbours/transitions/resource links, cave POI/biome/
resource links, POI biome links, and impossible surface/underground
combinations). Every problem is reported as `"<asset path>: <problem>"`. While
any problem remains, `WorldGenerator` logs the full report once per session and
`generate_chunk()` returns empty chunks — the world boots safely and the query
APIs stay crash-free; re-seeding re-runs discovery, so fixing the assets
recovers the world without a restart. Shipped content validates clean.

The harness grew from **271 to 291 checks** and passes with **0 failures and
0 script errors** (exit 0). The 20 new checks use eight invalid fixture
scenarios under `tests/fixtures/world_validation/` — `missing_id`,
`duplicate_id`, `invalid_range`, `unknown_terrain`, `dangling_references`,
`unknown_distribution`, `broken_cave_links`, `unspawnable_combinations` — each
asserting that the registry reports the problem with the offending asset's
path, plus a shipped-content check and duplicate-id controls.

| # | Issue found by the new fixtures | Root cause | Fix |
|---|--------------------------------|-----------|-----|
| V1 | Discovery-phase errors (missing id, duplicate ids) were silently lost — invalid fixtures produced an empty registry with an **empty** error list, masquerading as "the files don't exist" | `discover()` ended with `validation_errors = validate()`, *replacing* the array that `_discover_directory` had filled during loading with `validate()`'s fresh cross-reference array | The append-only design is kept: `discover()` now does `validation_errors.append_array(validate())` |

## Generic POI layer — WG-02 (2026-09-12)

POI candidate generation is now a generic stage: every discovered
`POIDefinition` contributes candidates (shared water/biome eligibility plus
the asset's own `min_spacing_tiles` grid and spawn weight), and cave
entrances are one consumer of that output rather than a special path —
cave-linked POIs additionally scale by the host biome's
`cave_entrance_suitability` and each candidate carries the stable
`"<cave>@<x>,<y>"` identity the cave runtime consumes. POIs no cave
definition links to load as plain `PoiMarker` debug nodes. `survey_marker`
is the minimal shipped non-cave POI (a debug marker; no new gameplay
content).

Harness grew 291 → **301 checks**, all passing with **0 failures and
0 script errors** (exit 0):

- Live world (9×9-chunk region around the origin, generated twice): a POI
  no cave links to is discovered from data alone; its candidates appear
  across the region; the full candidate set — cave and non-cave POIs
  together — is byte-stable across regeneration; no position is claimed by
  two different chunks at a boundary; spacing respects the asset's
  `min_spacing_tiles` across chunk edges; and the runtime loads the payload
  as live nodes whose tiles match their chunk's deterministic candidates.
- The cave-consumer guarantee uses a fixture world rather than the live
  seed: the live world's seed decides which biomes sit near the origin (a
  probe run found zero `rocky`-tagged tiles within a 65×65-chunk radius of
  the origin on one seed, so a presence assertion there would flake). A
  disposable `WorldGenerator` with its registry pointed at
  `tests/fixtures/world_validation/poi_consumers/` (one tag-eligible biome
  at full cave suitability, one cave linking one POI, plus one unlinked POI)
  verifies both consumers of the same stage: 22 cave candidates each
  carrying the context-derived stable identity, 25 plain candidates
  carrying no cave identity, and the whole region deterministic across
  regeneration.

Design note: presence assertions for biome- or tag-gated content belong in
fixture worlds with controlled content, never in the live-seed world, whose
regional biome fields can place an entire biome class far from the origin.

## Coherent regions — WG-03 (2026-09-12)

`BiomeDefinition.minimum_region_size` is now operative: a coherent-region
stage runs after per-tile biome selection over world-aligned 8-tile region
cells (config `region_cell_size_tiles`, 8 divides the 16-tile chunk, so a
chunk holds a disjoint 2×2 of cells and no cell straddles a boundary). A
cell whose dominant biome declares `M > 0` and whose raw 8-connected
fragment is below `ceil(M/cell²)` cells is merged into a neighbouring
cell's dominant biome, scored by the raw biome's authored adjacency
(preferred +2.0, transition +1.0, then adjacency count, then id). Merged
cells rewrite their land tiles only; water tiles keep their raw biome in
both the payload and on-demand queries. The stage is dormant — byte-
identical map, empty `region_cells` — while no biome declares `M > 0`.
Cell decisions are world-coordinate pure and memoised in a generator-level
cache shared by chunk payloads and `get_biome_at_world`.

Harness grew 301 → **312 checks**, all passing with **0 failures and
0 script errors** (exit 0). The section 2c checks:

- Fixture world `tests/fixtures/world_validation/region_coherence/`
  discovers 3 biomes with 0 validation errors, and the 256/256/0
  `minimum_region_size` values are read from the biome assets, not code.
- In a 9×9-chunk box, every chunk's payload carries exactly the 2×2
  world-aligned cells it owns (no tiny forbidden islands can hide in a
  straddling cell).
- No kept region cell leaves a raw fragment below its biome's declared
  minimum, measured with the same windowed rule the stage uses (0
  violations over 294 kept cells). Fragments are counted through the
  generator's own shared raw map, so the check verifies decisions against
  the exact fragments they were made on.
- Raw fragments below the floor are actually merged (the stage fires, not
  silently skipped).
- Every merged cell joins a neighbouring cell's biome, and the receiver
  honors the raw biome's authored adjacency (a preferred neighbour always
  beats a transition one, which beats plain adjacency — a property the
  +2.0/+1.0/+0.1 scoring guarantees).
- Payload and on-demand `get_biome_at_world` agree at every tile of the
  box, water tiles included (the stage rewrites land only, so the query
  path needs no special-casing beyond the water guard).
- Seam stability: chunk (0,0) generated alone (its own halo only) versus
  inside the box produces identical `biomes` and `region_cells` — adjacent
  chunks provably match at shared boundaries.
- Full-payload equality in reversed generation order (the documented
  "same world regardless of generation order" property, now including the
  region stage).
- On the live seed, the shipped world stays dormant: empty `region_cells`
  and byte-identical biome maps at every tile of a sampled chunk.

Design note: the reversed-order check compares chunk payloads individually
after verifying the key sets match — a Godot `Dictionary`'s string form
follows insertion order, so stringifying the whole box dict would report a
false mismatch for an order-different-but-equal box.

## Terrain-feature candidate layer — WG-04 (2026-09-12)

`TerrainFeatureDefinition` is now a first-class content kind: discovered from
`data/world/terrain_features/`, validated at startup, and interpreted by a
new generic stage in `WorldGenerator`. It runs after the coherent-region
stage and before the POI stage, so every discovered feature emits
deterministic candidates from its own anchor grid (per-feature grid offset),
biome/environment eligibility, and `spawn_weight` roll. Each candidate claims
a square footprint of `footprint_radius_tiles`; a chunk's payload carries
halo candidates anchored in neighbouring chunks (out-of-world anchors
skipped) so every chunk holds a complete local mask, and `in_chunk` marks
the owner — the runtime spawns exactly one `TerrainFeatureMarker` per
candidate, in the owning chunk. `ResourceSpawner` owns the `no_spawn`
influence tag and vetoes covered tiles without consuming random rolls, so
dormant-world placement is byte-identical.

Harness grew 312 → **327 checks**, all passing with **0 failures and
0 script errors** (exit 0). The section 2d checks:

- The fixture world `tests/fixtures/world_validation/terrain_features/`
  discovers 2 feature assets with 0 validation errors, and spacing,
  footprint, and influence-tag values are read from the assets, not code.
- The live registry carries 0 features — the dormancy premise.
- In a 5×5-chunk box (fixed seed 42) both feature assets emit candidates
  (13 scree, 3 clearing) — the done-when seam: the second asset joins the
  same generic stage with no `WorldGenerator` modification.
- Regeneration stability: generating the box twice produces identical
  payloads, halo entries included.
- Seam stability: chunk (0,0) generated alone (its own halo only) versus
  inside the box produces an identical full payload — the feature mask,
  like regions, is independent of generation history.
- Full-payload equality in reversed generation order (the documented
  "same world regardless of generation order" property, now including the
  feature stage).
- Halo/owner invariant: every halo candidate reports its anchor's own chunk
  and `in_chunk` marks exactly the owners, so no feature is ever double-
  spawned or lost.
- Same-feature candidates in the box respect the asset's
  `min_spacing_tiles` (Chebyshev) across chunk boundaries.
- The spawner's pure mask helper vetoes exactly the tiles a `no_spawn`
  feature's footprint covers (inside, on the edge, and one tile past it).
- End-to-end: a spawner pointed at the fixture world places 228 resources
  and none on tiles the mask vetoes — real spawn-eligibility influence, not
  a vacuous pass.
- Live dormancy: the live scene spawns 0 `TerrainFeatureMarker` nodes and
  live chunk payloads carry an empty `feature_candidates` layer.
- The runtime marker built from a fixture payload candidate carries stable
  identity (`id@x,y`) and footprint.
- A feature asset referencing a missing biome fails startup validation like
  other content (`tests/fixtures/world_validation/invalid_feature/`).

Design note: influence-tag vocabularies are owned by the consumers —
`no_spawn` belongs to the spawner. The renderer's presentation-consumption
of feature masks is a documented seam, not yet wired this card; the live
world is byte-identical apart from the new (empty) payload key.

## Player directional animation (2026-09-12)

The player presentation now chooses authored PixelLab directional frames rather
than rotating the body Sprite2D. Both Trailblazer appearances ship with eight
cardinal/intercardinal walk, axe, pickaxe, sword, bow, and jump sets; the
selector preserves a 16-slot facing model, mapping it to the nearest authored
frame until 16-way art is supplied. Space triggers a short aimed hop that still
respects terrain collision. Harness coverage verifies both appearances'
complete action sets, east/south/north frame changes, jump lifecycle, and
guards against reintroducing visual-node rotation.

### Fixed world-direction controls (2026-09-12)

Movement is world-relative: W always moves north, A west, S south, and D east,
independent of mouse aim and animation facing. The mouse still controls
directional animation, tool actions, and projectile firing; Space retains the
short aimed hop. The harness verifies all four fixed movement axes.

The project was bumped to `config/features = "4.7"` by the editor config
sync from the Mac (commit `dfe7324`, alongside the illustrated-terrain
commit). The Linux verification binary was upgraded from
`Godot_v4.6-stable` to `Godot_v4.7.2-stable` to match. Re-verified under
4.7.2: `--import` clean (3 new atlases), harness **50/50, exit 0** (the
TileMapLayer cell checks still hold — the renderer keeps TileMapLayer as
its logical grid), and a 35 s live headless run with **0 errors**. The
new rendering code uses only 4.0-era API, so nothing 4.7-specific was
required.

## Durability + missions pass (2026-09-11)

The Phase 4 core work (tool durability + the mission system) extended
the harness from 178 to **230 checks**, adding a 22-check durability
section and a 32-check mission section (plus reworked hotbar checks —
the axe is located by `get_hotbar_items().find(...)` instead of a
hardcoded slot, since the quick bar keeps stale entries by design).
All 230 pass with 0 script errors and exit code 0; a second
consecutive run (with the first run's save files still on disk) is
also green, which is what caught and then confirmed the fix for S1
below.

- **Durability (22 checks)** — per-tool max values from the item
  definitions (wooden axe 50 / pickaxe 100 / sword 50 / bow 80); one
  point consumed per landed swing and per bow shot, none on quick-bar
  selection; live decrement; break at zero (slot cleared, toast,
  bare-hand fallback); re-craft restores full durability;
  non-durable items untouched; worn durability survives a save/load
  round trip (save format v5).
- **Missions (32 checks)** — 7-mission catalog; M-key journal
  toggle; First Steps auto-accepts on a new world; prerequisite locks
  (accept rejected with the unmet-prerequisite titles reported);
  progress counts only while a mission is IN_PROGRESS and only from
  real pickups / kills / builds; completion grants item rewards +
  free tech unlocks; the full 7/7 main + side chain completes; panel
  refreshes on every state change; mission state + progress survive
  save/load.

### Bugs found by the harness

| # | Issue | Root cause | Fix |
|---|-------|-----------|-----|
| S1 | "Worn durability survives a save/load round trip" flaked — the post-load step could restore the *older* of two saves made in the same wall-clock second | Save files are named `manual_<unix-sec>[_N].json` and the payload stores a second-granularity timestamp; `list_save_entries()` sorted by timestamp only, so same-second saves tied and "most recent save" was a coin flip (the harness's section-7 and section-12 saves land in the same second) | `peek_save_summary()` now parses the `_N` filename suffix into a `seq` field, and the newest-save sort breaks timestamp ties by `seq` (descending) — the last-written slot deterministically wins |

## Generated art + wiring pass (2026-09-11)

All four sheets from `docs/ART_REQUESTS.md` were generated on this
machine (Antigravity CLI `agy` driving the Gemini image model in
headless `--print` mode, one generation per cell/sheet) and composed
with PIL to the exact grid contracts the code slices:

| Sheet | Size | Layout | Source |
|-------|------|--------|--------|
| `assets/creatures/alien-creature-roster.png` | 2688×1024 | 7 cols × 2 rows (idle/move) of 384×512, true alpha | cols 0–3 kept from the previous sheet; wolf/polar_bear/fish generated at 768×1024 (3:4) and resampled exactly 0.5× |
| `assets/tiles/wildfall-building-parts.png` | 64×288 | 2 cols (0 wood, 1 stone) × 9 rows (foundation, floor, wall, window, door, roof, stair, ramp, pillar) | 9 generated 1024×1024 dual-cell sheets (left=wood, right=stone), each half resampled 512→32 |
| `assets/tiles/wildfall-building-utilities.png` | 160×32 | 5 cols (torch, bed, chest, farm_soil, fence) | 5 generated 1024×1024 single-object frames, resampled to 32 |
| `assets/tiles/wildfall-crafting-stations.png` | 128×32 | 4 cols (campfire, furnace, workbench, anvil) | 4 generated 1024×1024 frames; replaces the procedural pixels (generator kept as missing-file fallback) |

One regeneration was needed: the first fence tile was a 7%-of-frame
thin strip (two posts + one rail, invisible once resampled to 32 px).
The re-prompt forced a chunky posts-and-rails block filling ~80% of
the frame; the landed tile is 47% opaque, consistent with its
utility-sheet neighbours.

Harness: **230 → 239 checks**, 0 failures, 0 script errors. The 9 new
checks: roster sheet is exactly 2688×1024; `CreatureVisual.COLUMNS ==
7`; all 7 species present; **no two species share a roster column**;
parts atlas is exactly 64×288; every one of the 18 parts-atlas cells
contains artwork; utilities atlas is exactly 160×32; all 5 utility
cells contain artwork; all 4 station cells contain artwork.

Notes:
- Per-cell "contains artwork" is a per-cell opaque-pixel scan (32×32
  each, ~28k pixel reads total) — cheap enough to stay in the harness.
- The exit-time "ObjectDB instances leaked / resources still in use"
  count grew slightly (119 → 150 instances, 2 → 3 resources): the
  same pre-existing SceneTree-script quit artifact (see Notes below),
  now with a few more cached atlas textures. The normal game exit
  path remains the clean one.

## Historical verification record (2026-09-10)

The sections below preserve the earlier 2026-09-10 verification checkpoint.
Its feature counts (including 62 items and 40 recipes) are historical; use
the current summary above for the present project state.

### Baseline (before the 2026-09-10 review fixes)

The earlier "all tests pass" report was not accurate. A clean run of the
pre-fix code produced:

- **157,518 runtime SCRIPT ERRORs** across the boot sequence:
  - 104,258× `Cannot call method 'get_noise_2d' on a null value` —
    `NoiseLayers.initialize()` aborted on an invalid `fractal_persistence`
    property (Godot 4.x names it `fractal_gain`), leaving the moisture and
    temperature noise layers null for every chunk.
  - 26,629× `Nil to Vector2` + 26,629× `Nil to String` — biome definitions
    were built from bare `Resource.new()` and registered under a null key,
    so every biome lookup scored against nothing.
- The world rendered as a **monochrome swamp** (no biome variation).
- HUD health/hunger bars threw per-frame errors (wrong node paths).
- The crafting panel threw per-recipe errors during refresh.
- 6 scripts failed to parse at all (A1–A6), aborting the old test harness.

### Result (after fixes, 2026-09-10)

**50/50 checks passed, 0 script errors, exit code 0.**

A separate 35-second run of the real game (main scene, no test script) also
completed with **0 errors, 0 warnings, 0 leaked objects** at exit —
including live creature spawning/wander/flee, which runs on every chunk
generation.

| # | Section | Checks | Result |
|---|---------|--------|--------|
| 1 | Scene loading | 9 | 9/9 required nodes present (GameEventBus, WorldGenerator, ChunkSystem, TerrainRenderer, ResourceSpawner, ItemDatabase, Player, CameraController, SeedInput, HUD) |
| 2 | World generation | 7 | chunk (0,0) data present; 4× chunk-coord checks on **pixel** positions with floor semantics (incl. negatives — regression guard, see below); chunk→world start; biome map varied (4 distinct biomes across 49 sampled points) |
| 3 | Terrain rendering | 2 | 12,544 tiles rendered for the initial 7×7 chunk ring; resources spawned |
| 4 | Item database | 2 | 62 items, 40 recipes loaded |
| 5 | Crafting panel | 4 | all 40 recipes displayed — Phase 3 (creature + plant drops, stone_brick, flour) closed every obtainability gap, so no ghost recipes remain; plank & wooden_axe visible; panel count matches the recipe database |
| 6 | Camera | 2 | target set from player; lerp converges over frames |
| 7 | Seed input | 6 | `change_seed` action exists (T); editor opens on T; buffer pre-filled; Escape cancels and keeps the old seed |
| 8 | Save/load | 3 | save after moving succeeds; load restores exact player position (123.0, -77.0) |
| 9 | Chunk lifecycle (B3) + regen | 8 | generating a far chunk spawns its resources via the real signal path; unloading frees nodes and spawner records; re-entering re-spawns identically (449 nodes); `set_seed(42)` regenerates and updates the HUD seed label |
| 10 | Dynamic input phase (new) | 7 | panel starts hidden (doesn't cover the game); C opens it; second C press closes it; player actually walks 1050 px; ChunkSystem's nominal chunk tracks the player's real chunk after walking; the chunk under the feet stays loaded; terrain cells still rendered under the feet |

## Notes

- **Test-harness exit artifact**: the `--script` harness reports
  "ObjectDB instances leaked / 2 resources still in use" at exit. This is a
  side effect of the SceneTree-script quit path (the loaded PackedScene /
  tileset remain in the resource cache). The normal game exit path is fully
  clean (verified with a 30-second game run: zero leaks).
- The biome-diversity check is a regression guard: with the old
  null-noise/null-biome state it fails (1 distinct biome), with the fixed
  code it passes (≥ 2 distinct biomes; 4 observed on the boot seed).
- The test runs the **real** main scene end-to-end (real noise, real
  spawner, real renderer, real save files under `user://`).

## Phase 3 pre-push verification (2026-09-10)

The Phase 3 creature work (wiring `CreatureSpawner` + live `Creature` nodes
into chunk generation, closing recipe obtainability gaps) was interrupted
by a context compaction that dropped its final fix. A pre-push re-run of
the harness caught it:

| # | Issue | Fix |
|---|-------|-----|
| C1 | `creature.gd` used `Circle2D` — abstract in Godot 4 (a `_draw()` helper class, not instantiable) — so `Creature.new()` threw on every chunk generation (the one failing check; 40/41) | Placeholder body rebuilt as a filled `Polygon2D` circle approximation (`_circle_points()`) |
| C2 | Test harness still asserted the pre-Phase-3 expectation ("7 ghost recipes hidden") while `Main`'s obtainability filter now (correctly) un-hides the hunting recipes via creature drops — a direct contradiction | Check replaced with a Phase 3 guard: panel must show **all** recipes in the database (any future hidden recipe = a new ghost) |

Post-fix verification: harness **41/41, 0 script errors, exit 0**; 35 s
live headless run **0 errors**. The 34 unwired future-phase scripts
(see ARCHITECTURE.md) still do not parse — unchanged, intentional, zero
runtime impact.

## Post-push gameplay-bug fixes (player-reported)

The first real play-through surfaced two runtime bugs the harness could not
see (it teleports the player instead of walking):

| # | Issue (as reported) | Root cause | Fix |
|---|---------------------|-----------|-----|
| G1 | "When I move the character the terrain disappears" | `ChunkSystem.world_to_chunk_coords()` divided **pixel** input by 16 (CHUNK_SIZE) — tile-unit math applied to pixel positions. A real chunk is 512 px wide (32 px tile × 16), so the system believed a chunk boundary was crossed every 16 px, re-centred the 7×7 ring on every stride, and unloaded the chunk under the player ~64 px into the walk | Chunk coords now floor **pixel** positions by `PIXELS_PER_CHUNK` (512); `player.gd`'s debug-label coordinate and `main.gd`'s overlay use the same function |
| G2 | "A big crafting list is over the top of everything" at startup | The `CraftingPanel` node in `main.tscn` had no `visible = false` (40 recipe rows anchored over the HUD), and **no input action existed to toggle it at all** | Panel now starts hidden; new `toggle_crafting` action (C key) → `GameEventBus.toggle_crafting_ui` → `Main._on_toggle_crafting_ui()` flips `visible` (same wiring pattern as the I-key inventory) |

The old harness had **blessed the wrong contract**: its chunk-math checks
asserted tile-unit semantics (`world_to_chunk_coords(16, 0) == (1, 0)`), so
41/41 runs were green while the runtime was broken. Those are replaced by
four pixel/floor unit checks (origin, last pixel of chunk (0,0), first pixel
of (1,1), negatives) plus the section-10 live-input phase: the player
actually walks 1050 px (two real 512-px boundaries) and the test then
verifies the nominal chunk, the chunk-loaded state and the rendered terrain
cell are all still under the player's feet.

Post-fix verification: harness **50/50, 0 script errors, exit 0**; 35 s
live headless run **0 errors**. The dynamic phase drives real input
(`Input.action_press` / `action_release` with per-frame state polling, since
"just pressed" edges land on the frame *after* the press, and a
release-then-press must be separate frames to register twice).

## Pre-fix known issues — all resolved by the 2026-09-10 review

| # | Issue | Status |
|---|-------|--------|
| A1–A6 | Six scripts failed to parse (Godot 3.x syntax in v4 project) | Fixed |
| B1–B13 | Boot order, seed handling, chunk reload, HUD wiring (details in review report) | Fixed |
| B14 | HUD referenced non-existent `Overlay/HBoxContainer` bar paths (per-frame errors, bars never updated) | Fixed |
| B15 | Crafting panel called `set_data` before `add_child` → null `@onready` labels | Fixed |
| B16 | `FastNoiseLite.fractal_persistence` does not exist in Godot 4.x (`fractal_gain` does) — aborted noise init, 104k null-noise errors | Fixed |
| B17 | Biomes built from bare `Resource` → `set()` no-ops → all 6 biomes registered under a null key → monochrome swamp, 53k biome errors | Fixed (`BiomeDefinition` resources) |
| B18 | `NoiseLayers` created with `.new()` but never added to the tree → ObjectDB leak at exit | Fixed (added as child of WorldGenerator) |
| B19 | `MAX_RECIPES = 20` capped the panel below the 30 obtainable recipes — 10 recipes unreachable in the UI | Fixed (cap raised to 40) |
