# Wildfall Test Results

## Test Run Summary
- **Current verification**: 239 checks passed, 0 failures, 0 script errors (Godot 4.7.2 headless run after the generated-art pass; the two new atlases and the 7-column roster imported cleanly)
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
