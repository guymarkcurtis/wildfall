# World Content Authoring

World generation follows **code defines systems, data defines content**.
Normal content additions should not require editing the generator or spawner.
The registry automatically discovers `.tres` assets below `data/world/`.

## Before you start

Make normal content changes by duplicating a nearby `.tres` asset in the
matching `data/world/` subdirectory, then editing it in Godot's Inspector. Do
not add the asset to a source registry or write an `if id == ...` branch. IDs
are stable, lowercase identifiers: changing one after players have saved a
world is a content migration, not a cosmetic rename.

Use the nearest shipped asset as a working example:

| You are adding | Start from | Put the new asset in |
|---|---|---|
| Biome | `grassland.tres` or `mountain.tres` | `data/world/biomes/` |
| Surface resource | `berry_bush.tres`, `tree.tres`, or `rock.tres` | `data/world/resources/` |
| Underground resource | `iron_ore.tres` | `data/world/resources/` |
| POI | `survey_marker.tres` | `data/world/pois/` |
| Cave type | `mountain_cave.tres` | `data/world/caves/` |

## Add a biome, start to finish

1. Duplicate a biome `.tres` into `data/world/biomes/`. Set a unique `id` and
   player-facing `display_name` first. The registry discovers the file on the
   next seed change or launch.
2. Set `elevation_range`, `moisture_range`, and `temperature_range` to a
   realistic normalized range (0.0–1.0). Start with a deliberately broad
   range, then narrow it after checking a seed. `rarity_weight` breaks ties
   when several biomes match; it does not create a biome outside its ranges.
3. Give the biome reusable `environment_tags`, for example `rocky`, `open`,
   or `humid`. Resources, POIs, and caves consume these generic tags. Do not
   invent a code path for the biome name.
4. Set adjacency by ID: `preferred_neighbors` are the most natural border
   partners; `transition_biome_ids` are acceptable softer transitions. Every
   referenced biome must already exist. These fields shape both regional
   selection and coherent-region merges.
5. Assign terrain presentation with `terrain_tile_id`, `ground_color`, and,
   where useful, `high_elevation_terrain_tile_id` plus its threshold. Use one
   of the renderer's current terrain vocabulary: `grass`, `forest`, `sand`,
   `stone`, `snow`, or `mud`. A normal biome may choose any of those without a
   generator change; adding an entirely new terrain *art type* is separate
   renderer/presentation work.
6. List eligible **surface** resource IDs in `resource_types`; list creature
   and vegetation IDs only when their respective systems have definitions for
   them. Resource selection uses each resource's `spawn_weight`; duplicate an
   ID in this list does not add extra weight.
7. Set `cave_entrance_suitability` only if cave-entrance POIs should be more
   or less likely here. Set `minimum_region_size` only if small raw fragments
   should merge into neighbours (0 keeps the biome out of that stage).
8. Optionally set `min_distance_to_water` / `max_distance_to_water` in
   Chebyshev tiles (`-1` means unconstrained). The values must be -1 or
   non-negative and `min <= max`.

At this point the biome is complete data content: no generator, spawner, or
central source registry edit is needed.

Biome adjacency is data the generator interprets two ways: low-frequency
regional selection biases a tile toward its regional context and the
coherent-region stage uses it to pick the receiver a too-small raw fragment
merges into. Configure `preferred_neighbors` and `transition_biome_ids` with
biome asset IDs; tune the shared regional scale and biases (and
`region_cell_size_tiles`) in `world_generation_config.tres`, never with
name-specific generator branches.

## Add a resource, start to finish

1. Duplicate a `ResourceDefinition` asset into `data/world/resources/`; give
   it a unique stable `id` and `display_name`.
2. Choose where it can exist. Set `surface_spawnable` for normal terrain
   nodes, `underground_spawnable` for cave deposits, or both only when that is
   intentional. Restrict it with `allowed_biomes` and/or
   `required_environment_tags`; empty lists mean no restriction. A mineral is
   normally surface-disabled and underground-enabled.
3. Set the occurrence controls. `spawn_weight` decides its relative choice
   when a biome lists several eligible resources. `surface_resource_density`
   in the world config is the global baseline; this asset's `abundance` and
   `density_multiplier` scale it. `min_spacing_tiles` is honoured across
   chunk borders, not merely inside a visible chunk.
4. Choose `distribution_mode`: `uniform` is even; `sparse` leaves more gaps;
   `clustered` and `patch` make local groups; `vein` forms elongated groups;
   `edge-biased` favours distribution-field edges; and `elevation-biased`
   favours suitable height. `cluster_radius` controls the relevant grouped
   modes. The registry rejects an unknown mode, so a typo never silently
   changes the distribution.
5. Apply optional water-distance constraints. Use -1 for an open side; a
   surface resource with `max_distance_to_water = 0` is impossible because
   distance zero is physical water and is rejected at validation.
6. Set `base_health` and `yields`, for example
   `[{"item_id":"my_item", "min_qty":1, "max_qty":3, "chance":1.0}]`.
   Add environment-specific drops under `biome_yields`, keyed by biome ID,
   instead of teaching harvesting about a biome name. Set `harvest_group` when
   a tool should recognise a content family (for example `tree`, `mineral`, or
   `forage`) instead of requiring an ID-specific tool rule.
   `visual_texture_path` and `visual_ground_anchor` are optional data-authored
   presentation fields for bespoke sprites; leave them empty/false to use the
   normal atlas or fallback presentation.
7. Add the resource ID to each biome's `resource_types` for surface use, or
   to a cave's `resource_ids` for underground use. The referenced resource
   must have the matching spawn flag enabled.
8. Check presentation. Biome ground visuals are fully data-authored in the
   biome asset. Existing resource IDs use the shipped resource artwork; an
   otherwise valid new ID receives the generic fallback visual. New raster
   game art must be generated through the PixelLab.ai MCP, using a related
   shipped PixelLab asset as a style reference where possible. Supplying a new
   bespoke resource sprite is presentation work, not a world-generation
   registration step—do not solve it with a resource-name branch in generation
   code.

The density field samples coordinates directly, so changing a resource field
changes future deterministic placement for that seed. Existing saves retain
only harvested/depleted locations, not a snapshot of untouched resource nodes.

## Validate and verify a seed

1. Start the project or run the headless harness. Startup validation names the
   exact asset path and invalid field; generation intentionally refuses to
   produce chunks until every content error is fixed.
2. Enter a known seed with **T**, then use **F3** while standing in the target
   region. Record the seed, tile, biome, field values, and water readout. This
   is enough for another developer to reproduce the location exactly.
3. Walk across at least one chunk boundary and confirm the biome/resource
   transition has no seam or duplicate nodes. For density/spacing work, check
   both sides of the boundary rather than only the initial chunk.
4. Run the harness before handing off. Its fixed-seed checks catch accidental
   changes to environment, water, biome, and candidate layers independently.

## Add a POI

POI placement is generic: drop a `POIDefinition` asset into
`data/world/pois/` and the generator discovers it, emits deterministic
candidates from it, and loads them at runtime — no source change required.
For a normal landmark, set `id`, `display_name`, `category`, `spawn_weight`,
and a spacing that makes sense at world scale, then optionally limit it by
biome, environment tag, or water distance. Validate and inspect the chosen
seed with F3 as described above. The asset drives:

- `min_spacing_tiles` — a stable world-space anchor grid; this is what
  guarantees spacing across chunk boundaries.
- `spawn_weight` — the placement chance per anchor (clamped to 0..1 at
  generation time).
- `allowed_biomes` (empty = all biomes) and `required_environment_tags`
  (every listed tag must be present on the host biome); candidates are
  never placed on physical water tiles.
- `min_distance_to_water` / `max_distance_to_water` (per-side -1 =
  unconstrained) — anchors whose tile falls outside the range are simply not
  candidates; the check consumes the chunk's Chebyshev shore-distance field,
  with no water-name branching (see Validation at startup below).
- `required_environment_tags` + `guarantee_min_eligible_cells` +
  `guarantee_per_spacing_cell` + `guarantee_fallback_biome` (all optional,
  default dormant at 0 / "") — opt the POI into a **presence/coverage
  guarantee** (WG-12). With `required_environment_tags` set,
  `guarantee_min_eligible_cells` > 0 guarantees the world holds at least that
  many region cells whose dominant biome carries those tags (a world that
  generated none gets one forced), and `guarantee_per_spacing_cell` > 0
  guarantees one placement per spacing cell (`min_spacing_tiles` square) that
  contains an eligible cell. `guarantee_fallback_biome` names the biome a
  deficient anchor is forced onto (when empty, the tag-matching biome with
  the highest `cave_entrance_suitability` is derived from data). The overlay
  only ever *adds* — it never removes a natural placement — so it is a
  superset change and old saves keep loading. The shipped `cave_entrance`
  declares `required_environment_tags = ["rocky"]` with both guarantees at 1
  and `guarantee_fallback_biome = "mountain"`: at least one rocky area and an
  entrance in every rocky 48×48 cell. Full mechanics in WORLD_GENERATION.md
  (WG-12).

If no cave definition references the POI id, its candidates load as plain
`PoiMarker` runtime nodes (a generic surface marker carrying the POI's
identity, category, and display name). The shipped `survey_marker` asset is a
minimal example of exactly that.

## Add a terrain feature

Terrain-feature placement is generic in exactly the same sense as POIs: drop
a `TerrainFeatureDefinition` asset into `data/world/terrain_features/` and
the generator discovers it, validates it at startup, and emits deterministic
feature candidates from it — no source change required. The asset drives:

- `min_spacing_tiles` — a stable world-space anchor grid (owning per-feature
  grid offset), guaranteeing spacing across chunk boundaries.
- `footprint_radius_tiles` — the square mask radius around each anchor
  (0 = single-tile marker). Footprints crossing a chunk boundary appear in
  the neighbour's payload as halo entries, so every chunk's local mask is
  complete.
- `spawn_weight` — the placement chance per anchor (clamped to 0..1).
- `allowed_biomes` (empty = all biomes) and `required_environment_tags`
  (every listed tag must be present on the anchor biome); candidates are
  never placed on physical water tiles.
- `min_distance_to_water` / `max_distance_to_water` (per-side -1 =
  unconstrained) — anchors whose tile falls outside the range are not
  candidates, so e.g. a shore-hugging feature pins to the coastline while
  placement stays fully data-driven.
- `influence_tags` — the seam into consumer systems. Tag **vocabularies are
  owned by the consumers**: the `ResourceSpawner` understands `no_spawn`
  (its footprint is not a valid surface-resource spawn site); any other tag
  is free vocabulary for a future consumer (e.g. the renderer's presentation
  modifiers) to interpret. Listing a tag no consumer reads is legal — the
  feature just has no effect from it yet.

Runtime, one neutral `TerrainFeatureMarker` node spawns per candidate in the
chunk that owns the anchor (a generic outline sized to the footprint plus a
name label; per-category presentation is future scene content, not
placement code). The shipped world currently carries no feature assets, so
the stage is dormant there and adding your first feature changes placement
only where your asset's tags are consumed.

## Rivers and streams (WG-06)

Rivers are a physical world system like the water mask, not content: there
is no per-river asset and no per-biome authoring. Placement is entirely
derived from the elevation and water fields — a land tile is a river tile
when enough nearby land sources drain through it in the bounded flow stage
(see `WORLD_GENERATION.md`, "Rivers and streams"). To tune or disable
rivers you edit `world_generation_config.tres`, not content assets:
`river_halo_tiles` (R; 0 disables the stage) and
`river_accumulation_threshold`
(K; the distinct-source count that makes a tile a river tile). No
`data/world/` asset change, registry validation, or content migration is
involved.

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
produces deterministic base deposit candidates. Runtime harvesting uses the
same harvestable nodes as the surface. When a deposit is depleted, only its
stable cave candidate ID is stored under `cave_changes`; re-entering rebuilds
the base cave with that candidate absent. Reset policy remains separate.

For geometry, `room_size` and `tunnel_length` are the legacy fixed values.
Set `room_size_min` / `room_size_max`, `tunnel_length_range` and
`branching_chance` to author a varied layout; zero vectors preserve fixed
geometry. `hazard_ids`, `enemy_ids`, `poi_ids`, `underground_water_chance`,
`underground_water_tags`, `feature_tags`, `deposit_tables`, and `loot_tables`
are generic, validated authoring seams. Only geometry and underground resource
deposits have runtime consumers today; the remaining fields travel with the
generated cave snapshot for future systems rather than triggering named cave
behaviour.

To add a cave type: first add or choose its entrance POI, then duplicate a
cave asset and set a unique `id`, `entrance_poi_id`, eligible biome/tag rules,
room/deposit ranges, and only `underground_spawnable` resource IDs. Verify its
entrance on a fixed seed, enter it twice, harvest one deposit, and confirm the
same deposit remains absent after re-entry. Do not select a cave reset policy
in the generator: depletion is a runtime/save concern.

## Surface resource density (WG-07)

Surface resources no longer use repeated random attempts. Each land tile has a
stable coordinate candidate, selected from the biome's `resource_types` and
then accepted by the world config's `surface_resource_density`, the resource's
`density_multiplier`, `abundance`, distribution mode, environment/water rules,
and terrain-feature masks. `min_spacing_tiles` is resolved against a bounded
neighbourhood using stable priority, so it holds across chunk borders regardless
of which chunk loads first. Use `density_multiplier` to make a normal resource
more or less common without changing the global baseline.

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
- The WG-12 guarantee fields (`guarantee_min_eligible_cells`,
  `guarantee_per_spacing_cell`) are editor-range constrained (`@export_range`
  0..4096 and 0..16) but are not part of startup validation — a value outside
  range in a hand-edited asset is clamped by the editor and otherwise treated
  as-is. `guarantee_fallback_biome` is likewise optional; if it names a biome
  that is missing or lacks the POI's `required_environment_tags`, the generator
  logs a non-fatal warning and derives a fallback from data (the tag-matching
  biome with the highest `cave_entrance_suitability`) rather than failing.
- Distance-to-water constraints on biomes, POIs, terrain features, and
  resources: each side must be -1 or >= 0 (`min < -1` or `max < -1` is
  rejected), and `min <= max`; a `surface_spawnable` resource pinned to
  `max_distance_to_water = 0` is rejected as an impossible combination
  (every distance-0 tile is water).
- Biome `minimum_region_size` is not yet machine-validated (the planned
  validation card will add that); the coherent-region stage interprets 0 as
  "out of stage" and any positive value as a tile floor for the biome's
  regions, so negative or nonsensical values would silently weaken it.
- Cross-references must resolve: biome `preferred_neighbors` /
  `transition_biome_ids` / `resource_types`, cave `entrance_poi_id`,
  `allowed_biomes`, `resource_ids`, and `poi_ids`, and POI `allowed_biomes`,
  and terrain-feature `allowed_biomes` (plus a per-feature check that
  `min_spacing_tiles`, `footprint_radius_tiles`, and `spawn_weight` stay in
  their legal ranges).
  A biome listing a resource that is not `surface_spawnable`, or a cave
  listing a resource that is not `underground_spawnable`, is reported as an
  impossible combination.

The fixture scenarios under `tests/fixtures/world_validation/` cover each rule
family and are run by the headless harness; add a fixture there when you add a
new validation rule. WG-05 added the distance-constraint rejections there (the
`inverted_shore_distance` scenario exercises each of the four) and a
`water_classification` fixture world (6x6 chunks, both water origins, cap 8)
that exercises the fields end-to-end.

## Reproducibility

Use the debug overlay (F3) to record the displayed world seed, config/version,
tile and chunk coordinates when reporting a generation bug. Include its biome,
field and water readout when relevant; the panel gives the exact chunk bounds
too. The same seed, configuration, content assets, and chunk coordinate must
produce the same base data regardless of load order.
