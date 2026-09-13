# World Generation Documentation

## Current architecture (Riftwake refactor)

World generation is now a reusable engine driven by data assets. The source
code owns field sampling, deterministic seed mixing, chunk lifecycle, water
masking, distribution algorithms, and generation stages. Biome, resource, cave,
POI, terrain-feature, and world-balance content is discovered from
`data/world/` Resource assets.
Adding an ordinary biome or resource should therefore not require modifying
`WorldGenerator` or `ResourceSpawner`; see `WORLD_CONTENT_AUTHORING.md`.

The current world is finite and chunk-streamed using the dimensions and radius
in `data/world/world_generation_config.tres`. Coordinates and seed derivation
remain independent of those bounds so a future effectively infinite world can
reuse the same generation APIs. Water is a physical system, not a normal biome: a coastline/inland-lake
mask, a per-tile class (land / shore / coast / deep_water), an origin
(ocean or lake), and a Chebyshev shore-distance field that content can
constrain against (see the WG-05 section below), plus a connected
river/stream flow mask derived from the same water mask and elevation
(see the WG-06 section below).

POI candidate generation is a generic stage: every discovered
`POIDefinition` contributes candidates from its own spacing grid, biome and
environment constraints, and `spawn_weight`. Cave entrances are one consumer
of that stage, not a special path — a POI that a cave definition links to
additionally scales its placement chance by the biome's
`cave_entrance_suitability` and carries the stable cave identity. Cave spaces
themselves are generated separately by `CaveSpaceGenerator`; cave
reset/depletion policy is intentionally not part of that generator.

At chunk-runtime population, candidates are routed by their data fields, not
by content names: a candidate carrying a cave definition link becomes a
`CaveEntrance` with its deterministic identity intact; any other candidate
becomes a plain `PoiMarker` runtime node (a generic surface marker carrying
the POI's identity, category, and display name). Interacting with an entrance
opens `cave_space.tscn`, generated from the world seed, stable entrance
identity, and cave definition. The cave is placed in a separate runtime
coordinate space, so surface terrain, collisions, streamed objects, and cave
geometry cannot overlap. Leaving restores the exact surface position. This is
a deliberately small cave foundation: it renders deterministic rooms, tunnels,
and data-defined underground deposit markers, and records discovery. Deposit
candidate generation is separate from runtime harvesting, depletion, and reset
policy, which remain intentionally undecided.

Every POI — cave-linked or not — uses its data-defined `min_spacing_tiles` to
derive stable world-space anchor cells. This avoids per-chunk scattering and
prevents adjacent chunks from producing overlapping candidates, while
preserving independent generation and reload of each chunk.

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

## Coherent-region stage

Biome selection is per-tile, so the raw map can leave small fragments of a
biome that the data says deserves broader regions. A final stage over the
per-tile map fixes that, driven entirely by biome data:

- The map is divided into world-aligned **region cells** of
  `region_cell_size_tiles` × `region_cell_size_tiles` tiles (config, default
  8). Because 8 divides the 16-tile chunk size, every chunk holds exactly a
  disjoint 2×2 of cells, so no cell straddles a chunk boundary and a cell's
  content can never differ between two neighbouring chunks.
- Each cell's **dominant biome** is the most common biome among the cell's
  land tiles (water tiles are excluded — water is a physical mask, not a
  biome). All-water cells stay water. Ties break toward the regional biome at
  the cell centre, then toward the smallest biome id.
- A biome that declares `minimum_region_size M > 0` in its
  `BiomeDefinition` takes part in the stage; a biome with `M = 0` does not.
  For a participating biome the generator measures the cell's 8-connected
  fragment of raw cells on the shared raw map, clipped to a square window of
  radius `W = ceil(sqrt(K) / 2)` cells, where `K = ceil(M / cell²)`. If the
  windowed fragment holds fewer than `K` cells, the raw fragment is smaller
  than the declared floor and the cell is **merged**: its land tiles take the
  dominant biome of a chosen neighbouring cell.
- The merge receiver is scored from the raw biome's authored adjacency: a
  preferred neighbour's dominant scores +2.0, a transition neighbour's
  dominant +1.0, plus +0.1 per adjacent cell of the same dominant; ties
  break toward the smallest id. With up to four manhattan neighbours this
  ordering guarantees a preferred receiver always beats a transition one,
  which always beats a plain-adjacency one — no content name is special in
  code. With no eligible neighbour the cell is kept as-is.

The stage is **single-pass** (one merge round over the raw map), and it
rewrites **land tiles only**: water tiles keep their raw biome both in the
chunk payload and in on-demand queries, so water stays the physical system
the mask describes. Every cell decision is a pure function of world
coordinates, memoised in a generator-level cache that chunk payloads and
`get_biome_at_world` share; payloads therefore carry a `region_cells` array
(recording each of the chunk's cells with its raw and post-stage biome and
a `kept`/`merged`/`water` source), and a chunk generated alone is byte-
identical to the same chunk generated inside a box — adjacent chunks always
match at their shared boundary. When no biome declares `M > 0` the stage is
dormant: no `region_cells` records and a byte-identical biome map.
The authored `M` also maps to a visual transition band of `M/2` tiles: a
merged fragment's land tiles sit at most that many tiles from a genuine edge
of the raw biome.

## Terrain-feature candidate stage

Terrain features (cliffs, clearings, scree, ...) are **content**, placed by
the same generic machinery as POIs. The stage runs after coherent regions and
before the POI stage, and is driven entirely by discovered
`TerrainFeatureDefinition` assets (`data/world/terrain_features/`): each
feature contributes candidates from its own spacing grid
(`min_spacing_tiles`, a per-feature deterministic grid offset), its biome /
environment eligibility, and its `spawn_weight` roll. Adding a feature is an
asset-only change to `WorldGenerator`.

- **Anchors and footprints.** A candidate is anchored on one tile and claims
  a square footprint of `footprint_radius_tiles` around it (0 = single-tile
  marker). Because a footprint can cross a chunk boundary, a chunk's payload
  also carries **halo candidates** anchored in neighbouring chunks whose
  footprint intersects the chunk; out-of-world anchors are skipped (features
  exist only inside the finite world).
- **Ownership.** Every candidate records whether its anchor lies in the
  reporting chunk (`in_chunk`). The runtime spawns exactly one
  `TerrainFeatureMarker` per candidate — in the owning chunk — so each
  feature exists once in the world; halo entries exist only to keep every
  chunk's local view of the mask complete.
- **Mask consumption.** Candidates carry the asset's `influence_tags`.
  Consumer systems own small tag vocabularies: the `ResourceSpawner` vetoes
  surface-resource spawns on any tile covered by a candidate whose tags
  include its `no_spawn` tag (the check consumes no random rolls, so allowed
  tiles roll exactly as before). Terrain *presentation* influence (colour,
  texture, collision modifiers) is the same seam — a documented tag the
  renderer will consume; it is not wired this stage.
- **Determinism.** Anchor, eligibility, and roll depend only on the anchor
  tile and the asset's data (world-pure), so payloads are identical
  generated alone vs inside a box, in any generation order, and stable
  across regeneration. `influence_tags` are copied into the payload, never
  shared with the asset.
- **Dormancy.** The shipped world carries no feature assets: the stage emits
  nothing and payloads are unchanged apart from an empty `feature_candidates`
  key, so live placement and rendering are byte-identical to the pre-stage
  world.

Chunk payloads therefore carry a `feature_candidates` array (per candidate:
feature id/category/name, stable `id@x,y` identity, anchor, radius, owner
flag, copied influence tags, and the anchor tile's biome).

## Water classification and shore distance (WG-05)

Water is a physical system, not a biome, and the generator now says so
in its data:

- **Class** — every tile of every chunk carries a `water_class`,
  recounted from the water mask by 8-neighbourhood: a water tile is
  `coast` when any of its 8 neighbours is land, else `deep_water`; a
  land tile is `shore` when any of its 8 neighbours is water, else
  `land`.
- **Origin** — water tiles additionally carry a `water_origin`:
  `ocean` when the tile's elevation is strictly below `water_level`,
  `lake` at or above it (a lake is elevation water — water above sea
  level). In the live world the lake level (0.24) sits below the water
  level (0.30), so every live water tile is structurally ocean-origin;
  fixture worlds may raise the lake level above the water level to
  exercise both.
- **Shore distance** — every chunk also carries a `distance_to_water`
  field (Chebyshev, in tiles): 0 on water tiles, 1..cap-1 exact, and
  the cap value when no water lies within cap - 1 tiles (saturated).
  The cap comes from
  `world_generation_config.tres:distance_to_water_cap_tiles` (live 16;
  0 disables the field). The field is computed inside the existing
  per-chunk rect pass — the rect extends cap tiles past the chunk, and
  tiles outside the finite world are sampled from the same noise field —
  so every core tile's distance is exact with no second pass, and one
  BFS per chunk feeds both the payload and the on-demand queries.

All three values ride the chunk payload as new keys (see Chunk Structure
below) and are mirrored by the public on-demand queries
`get_water_class_at_world`, `get_water_origin_at_world`, and
`get_distance_to_water_at_world`. The on-demand distance BFS is
memo-gated on the registry instance and runs only once at least one
content definition actually constrains a distance to water; an
unconstrained world reads -1 from those queries.

Content consumes the field through the generic `min_distance_to_water`
/ `max_distance_to_water` fields (per-side -1 = unconstrained,
min <= max, validated by `WorldContentRegistry`; a `surface_spawnable`
resource pinned to max distance 0 is rejected as impossible). Biome
selection and the resource spawner veto distance-failing candidates
before any RNG roll, so placements stay deterministic; a -1 side never
vetoes — water tiles pass the -1 input, so unconstrained content is
never vetoed. No generation branch special-cases a water name; the
generator's only "water" awareness is the generic mask/class/field
itself.

Live-world impact: the shipped live world has no content that constrains
a distance to water, so every live selection input stays -1, the
on-demand BFS stays dormant, and live content (biomes, POIs, features,
resources, caves) is byte-identical to the pre-WG-05 world — payloads
only gain the three new keys. Not wired this card: renderer
presentation of the new classes (water still renders from the mask) and
exact (unsaturated) distances beyond the cap.

## Rivers and streams (WG-06)

Water is also a source of flow: connected rivers and streams are computed
as a bounded deterministic stage over the same elevation and water-mask
fields (no new noise layer, no content-name knowledge):

- **Configuration.** `world_generation_config.tres` carries two new
  fields: `river_halo_tiles` (R; live 24, fixture 16; 0 disables the
  stage) and `river_accumulation_threshold` (K; 32 in both configs). R
  plays both roles: it is the maximum length of a flow path *and* the
  radius (Chebyshev) inside the chunk core that makes a land tile a
  flow source.
- **Flow.** A source tile flows to the strictly-lower minimum elevation
  among its 8 in-rect neighbours, ties broken by a fixed neighbour
  order (NW, N, NE, W, E, SW, S, SE — the order is part of the
  definition); a local minimum (no lower neighbour) instead flows to
  the overall minimum inside the rect; the one-ring border of the rect
  has no destination (paths stop there). Water tiles are counted when a
  path reaches them, but paths never enter water — water is the
  terminal of the connected system, not part of the river mask.
- **Accumulation.** Every source traces at most R steps downstream,
  deduplicated per source by a visited set, and each distinct visit
  increments the visited tile's source count. A core land tile is a
  **river tile** when at least K distinct sources have visited it;
  water tiles are never river tiles.
- **Boundedness / seam-safety.** The stage runs on the chunk core
  grown 2R+1 tiles per side (unclamped at the world edge; the shared
  environmental rect is grown to the larger of the WG-05 shore cap and
  2R+1, so the extra halo is free). A core tile's river status depends
  only on that (2R+1)-grown rect — its sources sit inside its R-ball
  and its at-most-R-step paths stay inside the one-ring margin — so a
  chunk generated alone is byte-identical to the same chunk generated
  inside a box, in any order, and per-chunk masks equal a world-wide
  reference tile-for-tile. A corner chunk's unclamped stage rect still
  lands inside the world reference rect (touching its edge), so corner
  flows are identical too. The harness pins all of this (fresh
  instance / lone corner chunk / reversed order, plus a 162×162
  world-wide reference over the 96×96 fixture: 299 river tiles, none
  on water, and a downstream fate audit of 151 drain to water / 0
  exit the window / 148 meander in closed basins).
- **Payload + on-demand.** The mask rides the chunk payload as
  `river_mask` (0/1 over the chunk core; the key is present but empty
  while the stage is disabled) and is mirrored by the public query
  `is_river_at_world`, which re-samples its own (2R+1)-grown rect on
  demand and returns -1 while the stage is disabled.

Not wired this card: rendering and gameplay effects — nothing consumes
`river_mask` yet (payload-only, like WG-05), and the card explicitly
defers wetlands and waterfalls. Two documented limitations: (1) paths
that exhaust their R steps or leave the stage rect are not traced
further, so very long streams may not appear end-to-end; (2) closed
basins whose floor never reaches water inside the halo meander and
recirculate
instead of draining — present in the fixture (148 of the 299 river
tiles) and prominent in the live world (at K=32 essentially every live
river path ends in a closed-basin meander). A veto for closed basins
was trialled and rejected: vetoing paths that return to their source
within R steps was vacuous (basin meanders return further than R), and
extending the veto trace to 4R would break the seam-safety argument
above. The live world's R=48 variant was also probed and rejected:
+13 river tiles at roughly 4× the per-chunk flow cost (473 ms vs
134 ms per chunk).

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
    "water_class": PackedStringArray,   # WG-05: land/shore/coast/deep_water
    "water_origin": PackedStringArray,  # WG-05: "" on land, ocean/lake on
                                         # water tiles
    "distance_to_water": PackedInt32Array,  # WG-05: 0 on water, 1..cap-1
                                         # exact, cap = no water within
                                         # cap - 1 tiles
    "river_mask": PackedInt32Array,      # WG-06: 0/1 connected-hydrology
                                         # river flag per core tile (water
                                         # tiles 0; empty while the flow
                                         # stage is disabled)
    "biomes": PackedStringArray,        # per-tile biome ids (post-stage)
    "region_cells": Array,              # coherent-region stage: one entry per
                                         # world-aligned cell of this chunk —
                                         # {cell, raw, biome, source} with
                                         # source kept/merged/water; empty
                                         # while no biome declares a minimum
                                         # region size
    "feature_candidates": Array,        # terrain-feature stage: one entry per
                                         # feature whose footprint touches this
                                         # chunk (halo entries included) —
                                         # {feature_id, feature_category,
                                         # feature_name, feature_identity
                                         # (id@x,y), x, y, footprint_radius_tiles,
                                         # in_chunk, influence_tags, biome};
                                         # empty while no feature assets exist
    "poi_candidates": Array,            # generic POI candidates; cave-linked
                                         # ones carry cave_type_id/cave_id
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
