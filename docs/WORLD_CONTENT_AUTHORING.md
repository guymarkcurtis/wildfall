# World Content Authoring

World generation follows **code defines systems, data defines content**.
Normal content additions should not require editing the generator or spawner.
The registry automatically discovers `.tres` assets below `data/world/`.

## Add a biome

1. Duplicate a biome asset in `data/world/biomes/` and give it a unique `id`.
2. Set its elevation, moisture, and temperature ranges, rarity, environment
   tags, and optional `preferred_neighbors`/`transition_biome_ids` metadata.
3. Choose a renderer terrain ID (`grass`, `forest`, `sand`, `stone`, `snow`,
   `mud`, or another ID supported by `TerrainRenderer`). Use the optional high
   elevation terrain ID for cliffs/rocky uplands.
4. List vegetation/resource IDs in `resource_types`. These are looked up in the
   resource registry; duplicate IDs may be used as authoring weight hints.
5. Set `cave_entrance_suitability` and environment tags when the biome should
   host eligible cave entrances.
6. Launch or run the harness. No procedural-generation source registration is
   required.

Biome adjacency is metadata used by future transition/region improvements; the
generator interprets it now through low-frequency regional selection. Configure
`preferred_neighbors` and `transition_biome_ids` with biome asset IDs; tune the
shared regional scale and biases in `world_generation_config.tres`, never with
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

## Caves and POIs

POI and cave assets are separate from surface biomes. A cave definition names
its `entrance_poi_id`, allowed environment tags, room/tunnel parameters, and
resource IDs. Create the matching `POIDefinition` under `data/world/pois/` and
use its ID from the cave asset; its category and presentation metadata stay in
that POI asset. The world generator emits deterministic entrance candidates
with a stable cave ID. Its `min_spacing_tiles` creates stable cross-chunk POI
anchor cells, and its `spawn_weight`, allowed biomes, and required tags control
eligibility without a generator edit. `CaveSpaceGenerator` reconstructs the
same separate cave layout from that identity whenever entered. Do not encode a
reset/depletion policy in cave-generation logic: that remains a save/runtime
policy decision. Configure `environment_tags`, resource IDs, deposit counts,
and attempt multiplier on the cave asset. The generator only accepts linked
resources with `underground_spawnable = true` whose required tags match, then
produces deterministic base deposit candidates. Runtime harvesting and whether
those candidates later persist, reset, or evolve are deliberately separate.

## Reproducibility

Use the displayed world seed and chunk coordinates when reporting a generation
bug. The same seed, configuration, content assets, and chunk coordinate must
produce the same base data regardless of load order.
