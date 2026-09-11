# Wildfall Test Results

## Test Run Summary
- **Date**: 2026-09-10
- **Godot Version**: 4.6.stable (linux.x86_64, official)
- **Test Script**: `tests/test_game.gd` (SceneTree harness: boots the real `main.tscn`, runs 41 assertions over ~10 frames, exits with the failure count as the exit code)

### Test command
```bash
HOME=/tmp/godot_home /tmp/godot/Godot_v4.6-stable_linux.x86_64 \
  --headless --path /home/guy/2d-icarus --script tests/test_game.gd
```

## Baseline (before the 2026-09-10 review fixes)

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

## Result (after fixes, 2026-09-10)

**41/41 checks passed, 0 script errors, exit code 0.**

A separate 35-second run of the real game (main scene, no test script) also
completed with **0 errors, 0 warnings, 0 leaked objects** at exit —
including live creature spawning/wander/flee, which runs on every chunk
generation.

| # | Section | Checks | Result |
|---|---------|--------|--------|
| 1 | Scene loading | 9 | 9/9 required nodes present (GameEventBus, WorldGenerator, ChunkSystem, TerrainRenderer, ResourceSpawner, ItemDatabase, Player, CameraController, SeedInput, HUD) |
| 2 | World generation | 6 | chunk (0,0) data present; 3× chunk↔world coordinate math; biome map varied (4 distinct biomes across 49 sampled points) |
| 3 | Terrain rendering | 2 | 12,544 tiles rendered for the initial 7×7 chunk ring; resources spawned |
| 4 | Item database | 2 | 62 items, 40 recipes loaded |
| 5 | Crafting panel | 4 | all 40 recipes displayed — Phase 3 (creature + plant drops, stone_brick, flour) closed every obtainability gap, so no ghost recipes remain; plank & wooden_axe visible; panel count matches the recipe database |
| 6 | Camera | 2 | target set from player; lerp converges over frames |
| 7 | Seed input | 6 | `change_seed` action exists (T); editor opens on T; buffer pre-filled; Escape cancels and keeps the old seed |
| 8 | Save/load | 3 | save after moving succeeds; load restores exact player position (123.0, -77.0) |
| 9 | Chunk lifecycle (B3) + regen | 6 | generating a far chunk spawns its resources via the real signal path; unloading frees nodes and spawner records; re-entering re-spawns identically (475 nodes); `set_seed(42)` regenerates and updates the HUD seed label |

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
