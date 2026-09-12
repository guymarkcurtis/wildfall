# World Generation Documentation

## Current architecture (Riftwake refactor)

World generation is now a reusable engine driven by data assets. The source
code owns field sampling, deterministic seed mixing, chunk lifecycle, water
masking, distribution algorithms, and generation stages. Biome, resource, cave,
POI, and world-balance content is discovered from `data/world/` Resource assets.
Adding an ordinary biome or resource should therefore not require modifying
`WorldGenerator` or `ResourceSpawner`; see `WORLD_CONTENT_AUTHORING.md`.

The current world is finite and chunk-streamed using the dimensions and radius
in `data/world/world_generation_config.tres`. Coordinates and seed derivation
remain independent of those bounds so a future effectively infinite world can
reuse the same generation APIs. Water is produced as a physical mask with
coastline and inland-lake rules, not as a normal biome. Cave entrances are
data-driven POI candidates, while cave spaces are generated separately by
`CaveSpaceGenerator`; cave reset/depletion policy is intentionally not part of
that generator.

At chunk-runtime population, a candidate carrying a cave definition link
becomes a `CaveEntrance` with its deterministic identity intact. Interacting
with it opens `cave_space.tscn`, generated from the world seed, stable entrance
identity, and cave definition. The cave is placed in a separate runtime
coordinate space, so surface terrain, collisions, streamed objects, and cave
geometry cannot overlap. Leaving restores the exact surface position. This is
a deliberately small cave foundation: it renders deterministic rooms, tunnels,
and data-defined underground deposit markers, and records discovery. Deposit
candidate generation is separate from runtime harvesting, depletion, and reset
policy, which remain intentionally undecided.

POIs use their data-defined `min_spacing_tiles` to derive stable world-space
anchor cells. This avoids per-chunk scattering and prevents adjacent chunks
from producing overlapping candidates, while preserving independent generation
and reload of each chunk.

## Overview

The world is generated deterministically using configurable environmental
noise layers (elevation, moisture, temperature, and a low-frequency water
field).
Same world seed = identical world, regardless of generation order.
Biomes, terrain and resources all derive from per-tile noise values.

Biome selection combines those local values with a lower-frequency regional
sample. The regional sample picks the broad environmental context; its selected
biome receives a configurable score bias, while that asset's
`transition_biome_ids` and `preferred_neighbors` receive smaller data-defined
transition biases. This produces broad, reproducible regions without encoding
any particular biome relationship in source. The regional scale and all three
weights are authored in `world_generation_config.tres`.

## Generation Layers

The `FastNoiseLite` instances (Godot 4.x API), all using
`NoiseType.TYPE_SIMPLEX` (the v3 `NOISE_SIMPLEX` constant was removed):

| Layer | Frequency | Fractal octaves | Fractal gain | Seed offset |
|-------|-----------|-----------------|--------------|-------------|
| Elevation | 0.005 | 4 | 0.5 | seed + 0 |
| Moisture | 0.003 | 3 | 0.5 | seed + 1000 |
| Temperature | 0.002 | 2 | 0.5 | seed + 2000 |
| Water field | 0.0015 | 2 | 0.5 | seed + 3000 |

All values are normalized to 0.0–1.0 (`get_noise_2d` output remapped).
> Note: Godot 3.x used `fractal_persistence`; in Godot 4.x the property
> is `fractal_gain`. Assigning the v3 name is a runtime error that aborts
> the initializer (see B16 in TEST_RESULTS.md).

## Biome Selection

The shipped content currently defines **6 biomes**. A chunk's biome is chosen from the chunk's
*average* noise values; individual tiles are then re-evaluated with
*per-tile* values via `WorldGenerator.get_biome_at_world(x, y)`, so
biome borders follow the noise field instead of chunk edges. Local field scores
are blended with the data-defined regional and adjacency weights described
above (unregistered/empty ids are skipped).

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

Biome assets also drive:
- **terrain mapping** — elevation bands (water < 0.3, sand 0.3–0.4,
  then biome-flavoured ground tiles up to snow)
- **resource placement** — each biome has a data-defined `resource_types`
  table. Candidate water tiles are rejected, so every spawned resource is on
  reachable terrain; rocky ground itself is intentionally walkable. Resource
  definitions marked underground-only are excluded from this surface stage.
- **resource yields** — base and biome-specific yield additions live on the
  resource assets, not in the spawner.

## Chunk Structure

Each chunk is 16×16 tiles (TILE_SIZE = 32 px). `WorldGenerator` returns
a chunk data dictionary:

```gdscript
{
    "elevation":   PackedFloat32Array,  # 256 values
    "moisture":    PackedFloat32Array,  # 256 values
    "temperature": PackedFloat32Array,  # 256 values
    "water_mask": PackedByteArray,      # 256 physical water flags
    "biomes": PackedStringArray,        # per-tile biome ids
    "poi_candidates": Array,            # data-driven POI candidates; cave
                                         # candidates carry cave_type_id/cave_id
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
chunk_seed = stable arithmetic mix(world_seed, chunk_x, chunk_y, stream)
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
world_start = chunk_coords * chunk_size_tiles  # top-left tile of the chunk
chunk_coord = floor(world_pos / (chunk_size_tiles * tile_size_pixels))
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
