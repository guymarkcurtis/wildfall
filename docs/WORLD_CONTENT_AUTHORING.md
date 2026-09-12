# World Content Authoring

World generation follows **code defines systems, data defines content**.
Normal content additions should not require editing the generator or spawner.
The registry automatically discovers `.tres` assets below `data/world/`.

## Add a biome

1. Duplicate a biome asset in `data/world/biomes/` and give it a unique `id`.
2. Set its elevation, moisture, and temperature ranges, rarity, environment
   tags, and `preferred_neighbors`/`transition_biome_ids` adjacency metadata.
3. Choose a renderer terrain ID (`grass`, `forest`, `sand`, `stone`, `snow`,
   `mud`, or another ID supported by `TerrainRenderer`). Use the optional high
   elevation terrain ID for cliffs/rocky uplands.
4. List vegetation/resource IDs in `resource_types`. These are looked up in the
   resource registry; duplicate IDs may be used as authoring weight hints.
5. Set `cave_entrance_suitability` and environment tags when the biome should
   host eligible cave entrances.
6. Optionally set `minimum_region_size` (tiles, default 0). A positive value
   enforces the biome's region scale in the coherent-region stage: raw
   fragments smaller than the value are merged into neighbouring cells using
   this biome's adjacency metadata (preferred receivers always beat
   transition, which beat plain adjacency); a value of 0 opts the biome out
   of the stage. See `WORLD_GENERATION.md`, "Coherent-region stage".
7. Launch or run the harness. No procedural-generation source registration is
   required.

Biome adjacency is data the generator interprets two ways: low-frequency
regional selection biases a tile toward its regional context and the
coherent-region stage uses it to pick the receiver a too-small raw fragment
merges into. Configure `preferred_neighbors` and `transition_biome_ids` with
biome asset IDs; tune the shared regional scale and biases (and
`region_cell_size_tiles`) in `world_generation_config.tres`, never with
name-specific generator branches.

## Add a resource

1. Create a `ResourceDefinition` asset in `data/world/resources/` with a unique
   `id`.
2. Configure `surface_spawnable`, `underground_spawnable`, allowed biomes or
   environment tags, abundance, spawn weight, distribution mode, spacing, and
   cluster radius.
3. Put normal yields in `yields`; put environment-specific additions in
   `biome_yields` rather than adding biome checks to code.
4. Add the resource ID to the relevant biome asset, or to a future cave asset
   for underground content.

Metallic/mineral resources should be marked `surface_spawnable = false` and
`underground_spawnable = true`. The current surface spawner filters them by
the definition, so their future cave distribution can be added independently.

## Add a POI

POI placement is generic: drop a `POIDefinition` asset into
`data/world/pois/` and the generator discovers it, emits deterministic
candidates from it, and loads them at runtime — no source change required.
The asset drives:

- `min_spacing_tiles` — a stable world-space anchor grid; this is what
  guarantees spacing across chunk boundaries.
- `spawn_weight` — the placement chance per anchor (clamped to 0..1 at
  generation time).
- `allowed_biomes` (empty = all biomes) and `required_environment_tags`
  (every listed tag must be present on the host biome); candidates are
  never placed on physical water tiles.

If no cave definition references the POI id, its candidates load as plain
`PoiMarker` runtime nodes (a generic surface marker carrying the POI's
identity, category, and display name). The shipped `survey_marker` asset is a
minimal example of exactly that.

## Caves and POIs

POI and cave assets are separate from surface biomes. A cave definition links
one of those POI ids via its `entrance_poi_id` — that link is what makes the
POI a cave entrance instead of a plain marker: the linked POI's candidates
additionally scale by the host biome's `cave_entrance_suitability` and each
candidate carries a stable cave ID. Create the matching `POIDefinition` under
`data/world/pois/` if it does not exist yet; the POI's category and
presentation metadata stay in that POI asset. The cave definition also names
allowed environment tags, room/tunnel parameters, and resource IDs. The POI's
`min_spacing_tiles` creates stable cross-chunk anchor cells, and its
`spawn_weight`, allowed biomes, and required tags control eligibility without
a generator edit. `CaveSpaceGenerator` reconstructs the
same separate cave layout from that identity whenever entered. Do not encode a
reset/depletion policy in cave-generation logic: that remains a save/runtime
policy decision. Configure `environment_tags`, resource IDs, deposit counts,
and attempt multiplier on the cave asset. The generator only accepts linked
resources with `underground_spawnable = true` whose required tags match, then
produces deterministic base deposit candidates. Runtime harvesting and whether
those candidates later persist, reset, or evolve are deliberately separate.

## Validation at startup

`WorldContentRegistry` validates every asset it discovers below `data/world/`
before the generator will build any chunks. On startup the generator logs each
problem once, as `"<asset path>: <problem>"`, and while any problem remains
`generate_chunk()` returns an empty chunk: the world boots and the query APIs
stay safe, but no content is generated until the assets are fixed. Re-seeding
or starting a new world re-runs discovery, so fixing the assets and
regenerating recovers automatically — no restart is required.

Rules checked (all generic; no content names appear in the checks):

- Every asset must have a non-empty `id`; duplicate ids are reported with
  **both** file paths (the later file wins at runtime, exactly as before).
- An asset that fails to load, or whose `.tres` uses the wrong script type, is
  reported with its path instead of being skipped silently.
- Biome `elevation_range`, `moisture_range`, and `temperature_range` must be
  non-inverted and inside the normalized 0..1 field.
- `terrain_tile_id` must be set and must be a terrain id the renderer
  supports; `water` is rejected as biome terrain (water is a physical world
  system, not a biome). A non-empty `high_elevation_terrain_tile_id` must be
  supported too. `cave_entrance_suitability` must be within 0..1.
- Resource `distribution_mode` must be one the spawn engine supports
  (`uniform`, `sparse`, `clustered`, `patch`, `vein`, `edge-biased`,
  `elevation-biased`); a resource that is neither `surface_spawnable` nor
  `underground_spawnable` can never spawn and is reported; yield entries need
  an `item_id`.
- Caves must have `min_rooms <= max_rooms`, a positive `room_size`, and
  `resource_min_deposits <= resource_max_deposits`.
- POI `min_spacing_tiles` must be non-negative.
- Biome `minimum_region_size` is not yet machine-validated (the planned
  validation card will add that); the coherent-region stage interprets 0 as
  "out of stage" and any positive value as a tile floor for the biome's
  regions, so negative or nonsensical values would silently weaken it.
- Cross-references must resolve: biome `preferred_neighbors` /
  `transition_biome_ids` / `resource_types`, cave `entrance_poi_id`,
  `allowed_biomes`, `resource_ids`, and `poi_ids`, and POI `allowed_biomes`.
  A biome listing a resource that is not `surface_spawnable`, or a cave
  listing a resource that is not `underground_spawnable`, is reported as an
  impossible combination.

The fixture scenarios under `tests/fixtures/world_validation/` cover each rule
family and are run by the headless harness; add a fixture there when you add a
new validation rule.

## Reproducibility

Use the displayed world seed and chunk coordinates when reporting a generation
bug. The same seed, configuration, content assets, and chunk coordinate must
produce the same base data regardless of load order.
