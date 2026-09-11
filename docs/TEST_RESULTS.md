# Wildfall Test Results

## Test Run Summary
- **Current verification**: 178 checks passed, 0 failures (macOS Godot 4.7.2 headless run)
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
