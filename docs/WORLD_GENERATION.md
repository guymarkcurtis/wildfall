# World Generation Documentation

## Overview

The world is generated deterministically using three noise layers.
Same world seed = identical world, regardless of generation order.
Biomes, terrain and resources all derive from per-tile noise values.

## Generation Layers

Three `FastNoiseLite` instances (Godot 4.x API), all using
`NoiseType.TYPE_SIMPLEX` (the v3 `NOISE_SIMPLEX` constant was removed):

| Layer | Frequency | Fractal octaves | Fractal gain | Seed offset |
|-------|-----------|-----------------|--------------|-------------|
| Elevation | 0.005 | 4 | 0.5 | seed + 0 |
| Moisture | 0.003 | 3 | 0.5 | seed + 1000 |
| Temperature | 0.002 | 2 | 0.5 | seed + 2000 |

All values are normalized to 0.0–1.0 (`get_noise_2d` output remapped).
> Note: Godot 3.x used `fractal_persistence`; in Godot 4.x the property
> is `fractal_gain`. Assigning the v3 name is a runtime error that aborts
> the initializer (see B16 in TEST_RESULTS.md).

## Biome Selection

There are **6 biomes**. A chunk's biome is chosen from the chunk's
*average* noise values; individual tiles are then re-evaluated with
*per-tile* values via `WorldGenerator.get_biome_at_world(x, y)`, so
biome borders follow the noise field instead of chunk edges. Selection
scores each registered biome by how far inside its ranges the values
fall (closest range wins; unregistered/empty ids are skipped).

| Biome | Elevation | Moisture | Temperature | Ground color |
|-------|-----------|----------|-------------|--------------|
| temperate_forest | 0.3 – 0.6 | 0.4 – 0.7 | 0.3 – 0.6 | (0.15, 0.45, 0.15) |
| grassland | 0.3 – 0.5 | 0.3 – 0.5 | 0.3 – 0.6 | (0.30, 0.65, 0.20) |
| mountain | 0.6 – 0.9 | 0.2 – 0.5 | 0.2 – 0.5 | (0.50, 0.50, 0.50) |
| desert | 0.2 – 0.4 | 0.0 – 0.2 | 0.6 – 1.0 | (0.80, 0.70, 0.40) |
| arctic | 0.4 – 0.8 | 0.3 – 0.6 | 0.0 – 0.2 | (0.85, 0.90, 0.95) |
| swamp | 0.2 – 0.4 | 0.7 – 1.0 | 0.4 – 0.7 | (0.30, 0.40, 0.20) |

(The old table listed 4 biomes incl. "Tundra" — the game has 6 with an
"arctic" biome, and the ranges above are the real values.)

Biomes also drive:
- **terrain mapping** — elevation bands (water < 0.3, sand 0.3–0.4,
  then biome-flavoured ground tiles up to snow)
- **resource placement** — each biome has a `resource_types` list
  (e.g. desert: rock×2 + coal; mountain: rock, iron_ore, coal,
  gold_ore; arctic: rock, iron_ore). Candidate water tiles are rejected,
  so every spawned resource is on reachable terrain; rocky ground itself is
  intentionally walkable.
- **resource yields** — rock yields add sand in desert, copper_ore in
  mountain, tin_ore in arctic

## Chunk Structure

Each chunk is 16×16 tiles (TILE_SIZE = 32 px). `WorldGenerator` returns
a chunk data dictionary:

```gdscript
{
    "elevation":   PackedFloat32Array,  # 256 values
    "moisture":    PackedFloat32Array,  # 256 values
    "temperature": PackedFloat32Array,  # 256 values
    "biome":   String,   # chunk-level biome id (from averages)
    "seed":    int,      # chunk-local seed
    "version": int       # generator version
}
```

(Terrain tiles, vegetation and resources are not stored in this dict —
the TerrainRenderer and ResourceSpawner derive them from the noise
arrays + biome, keyed by the same chunk seed.)

## Deterministic Seeding

```
chunk_seed = world_seed * 73856093
           + chunk_x * 19349663
           + chunk_y * 83492791
```
(a large-prime linear combination — NOT a `hash()` call, so the value
is stable across platforms and Godot versions).

This ensures:
- Same world always generates the same terrain per chunk
- Generation order doesn't matter
- Chunks can be generated, unloaded and regenerated identically
  (verified by test: unload → reload yields the same 9 resources)

## Chunk Coordinates

```
world_start = chunk_coords * 16          # top-left tile of the chunk
chunk_coord = floor(world_pos / 16)
```
(`ChunkSystem.world_to_chunk_coords` / `chunk_coords_to_world_start`
implement this; both covered by the test suite.)

## Viewport System

Only chunks within `viewport_radius` (default 3 → 7×7 = 49 chunks) of
the player are loaded. Unloading frees the chunk's resource nodes,
clears its spawner records and removes its rendered tiles; re-entering
regenerates everything deterministically from the seed (no data loss —
see B3/B9 in the review).

## Seed Change Flow

T key → `SeedInput` editor (0–999999, Enter confirms, Escape cancels) →
`seed_changed` signal → `Main._generate_world(new_seed)` →
WorldGenerator + ResourceSpawner re-initialize → player returned to
origin → chunks regenerated → HUD seed label updated.
