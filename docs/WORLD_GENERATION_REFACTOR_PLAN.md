# Riftwake World-Generation: Current State and Handoff Plan

**Status:** active incremental refactor. This document records what is actually
in the project as of 2026-09-12, then breaks the remaining work into small,
independently reviewable cards suitable for a coding handoff.

## Permanent architecture contract

> **Code defines systems. Data defines content.**

Keep ordinary biome, resource, cave-type, and POI names out of generation
source. Generator code may implement coordinate fields, deterministic seed
derivation, chunk lifecycle, distributions, water masks, and cave algorithms.
Godot Resource assets under `data/world/` define the content interpreted by
those systems. A normal new biome or resource must be an asset-only addition.

The surface world is finite and chunk-streamed today, but all generation APIs
must remain coordinate based so it can later become effectively infinite.
Water is a physical world system rather than a biome. Caves are separately
generated spaces reached through stable surface entrances; cave generation is
deliberately separate from the not-yet-decided reset/depletion policy. Saves
reconstruct the deterministic base world plus a mutation ledger.

Read [AGENTS.md](../AGENTS.md) before changing any generation work.

## Current implementation: delivered foundation

### Configuration, content, and determinism

- `WorldGenerationConfig` is a versioned Resource, with a current asset at
  `data/world/world_generation_config.tres`. It supplies world seed, finite
  chunk bounds, chunk size, streaming radius, environmental field scales, and
  water/lake controls. The default world is 128 by 128 chunks of 16 tiles,
  centred on chunk `(0, 0)`.
- `WorldGenerationContext` derives stable world, chunk, tile, POI, and cave
  seeds. The same seed, coordinates, config, and content produces the same
  base result.
- `WorldContentRegistry` discovers and validates Resource assets. The current
  content set contains six biome definitions, eight resource definitions, one
  cave definition, and one cave-entrance POI definition.
- Existing scene, terrain-rendering, runtime-spawn, and save wiring has been
  retained rather than replaced.

### Surface pipeline

`WorldGenerator.generate_chunk()` currently runs this pipeline:

1. Sample large-scale elevation, moisture, temperature, and regional fields.
2. Build the water mask (ocean/coast and deterministic inland-lake influences).
3. Select data-driven biome values from environmental ranges, rarity, regional
   affinity, preferred neighbours, and transition parameters.
4. Return basic terrain feature metadata (currently water-tile count).
5. Produce deterministic cave/POI candidates for the chunk.
6. Let runtime population create terrain visuals and eligible content.

Biome regions are now large-scale field driven rather than tiny independent
tile rolls. The current water stage supports oceans, coastlines, and inland
lakes. It does not yet construct connected river systems.

### Surface content and chunk lifecycle

- `ChunkSystem` loads only chunks within the configurable player radius and
  unloads distant runtime nodes. Generation remains deterministic after reload.
- `ResourceSpawner` interprets generic `ResourceDefinition` fields:
  environment/biome restrictions, surface or underground placement,
  abundance, spacing, clustering, distribution mode, depletion data, and
  progression metadata.
- Data rules now exclude mineral resources from normal surface spawning. The
  generator does not use names such as copper or iron to make that decision.
- Generic distribution modes exist for uniform, sparse, clustered, patch,
  vein, edge-biased, and elevation-biased placement. The existing visual
  resources and vegetation are preserved through migrated definitions.
- The save system keeps a mutation ledger for destroyed deterministic spawns;
  untouched base-world objects are regenerated instead of serialized.

### POIs and caves

- POI and cave definitions are Resources, and cave entrance candidates have
  stable deterministic identities derived from world data and coordinates.
- Cave suitability is data driven through POI and cave-definition constraints.
  The shipped content places the existing cave type only where its data allows.
- `CaveSpaceGenerator`, `CaveSpace`, and `CaveEntrance` establish a
  separate generated cave scene. A cave seed derives from the world seed,
  cave identity, entrance location, and cave type.
- The mutation ledger records cave discovery and reserves `cave_changes` for
  future cave state. No reset or depletion policy has been selected.

### Verification already in place

The headless harness covers deterministic field/chunk generation, finite
bounds, data loading, generic resource restrictions, cave identities, cave
generation, save migration, chunk streaming, and character/gameplay
regressions. The latest baseline is recorded in
[TEST_RESULTS.md](TEST_RESULTS.md). Run the harness and a Godot parser/editor
check after every handoff card.

## Known gaps and intentional limitations

These are not reasons to rewrite the foundation:

- `minimum_region_size` exists in biome data but is not enforced by a region
  post-process. Current transitions are weighted scoring, not explicit masks.
- Terrain features are only a metadata seam today. There is no generic,
  data-driven feature layer yet for clearings, cliffs, scree, or rocky patches.
- Water has ocean/lake classification but no river, stream, wetland, waterfall,
  or proper shoreline-feature pipeline.
- POI placement is presently cave-linked. The candidate pipeline contains a
  cave-specific gate, so ordinary ruins, camps, and landmarks cannot yet
  materialize through the same generic system.
- Surface placement still uses bounded per-chunk attempts and a runtime spacing
  scan. It needs deterministic density fields and a neighbour-aware spatial
  index before very dense content scales comfortably.
- Cave spaces currently prove deterministic identity/layout and deposit
  candidates, but they are not yet a complete playable underground loop with
  collision, harvestable runtime deposits, and mutation application.
- Debug visibility is limited. There is no in-game overlay for field, biome,
  water, or chunk diagnostics, and no fixed-seed visual regression suite.

## Handoff protocol for Qwen 3.8

Give Qwen **one card at a time**. Every card must begin by reading
`AGENTS.md`, this plan, the referenced scripts, and the current git diff.
Preserve unrelated working-tree changes. Do not rename/reformat unrelated code.

For every card:

1. Keep content-specific decisions in Godot Resources, never string-name
   branches in generator code.
2. Extend the existing pipeline; do not bypass it with an alternate generator.
3. Add focused headless tests before claiming completion.
4. Update the relevant authoring documentation when an asset workflow changes.
5. Run `godot --headless --path . --script res://tests/test_game.gd`,
   `godot --headless --path . --editor --quit`, and `git diff --check`.
6. Report changed files, test totals, limitations, and the recommended next
   card. Stop after that card; do not silently start the next one.

## Ordered bite-sized implementation cards

### WG-01 — Validate content assets at startup — COMPLETE (2026-09-12)

Delivered: per-asset and cross-asset validation in `WorldContentRegistry`
(duplicate ids, missing ids, unloadable/wrong-type assets, inverted or
out-of-bounds environment ranges, unsupported terrain ids, invalid distribution
modes, impossible surface/underground combinations, and dangling biome/cave/POI
references), each reported as `"<asset path>: <problem>"`. The generator logs
the problems once and refuses to generate chunks while any remain; discovery
re-runs on every (re)seed, so fixed assets recover without a restart. Shipped
content validates clean; 20 new fixture-backed harness checks
(`tests/fixtures/world_validation/`) pass — **291/291, exit 0**. Rules are
documented in `WORLD_CONTENT_AUTHORING.md`.

**Goal:** make invalid content fail clearly before it produces bad worlds.

Extend `WorldContentRegistry` validation for duplicate identifiers, invalid
environment ranges, missing scene/visual references, missing adjacency IDs,
invalid distribution modes, invalid cave/POI links, and impossible
surface/underground combinations. Return useful asset paths and messages.
Add a small invalid-fixture test set and document the validation rules in
`WORLD_CONTENT_AUTHORING.md`.

**Done when:** shipped assets validate, each important failure is covered by a
test, and generator code still contains no normal content-name checks.

### WG-02 — Make the POI layer genuinely generic — COMPLETE (2026-09-12)

Delivered: `_generate_poi_candidates` now iterates every discovered
`POIDefinition` — shared water/biome eligibility plus each asset's
`min_spacing_tiles` grid and spawn weight — with cave entrances as one
consumer (candidates scale by the host biome's `cave_entrance_suitability`
and carry the stable `"<cave>@<x>,<y>"` identity) and unlinked POIs routing
to plain `PoiMarker` runtime nodes (spawn, unload, reset, and cave
visibility all handled). RNG consumption for cave-linked POIs is
byte-identical to the old special path, so existing cave placements and
saves are unchanged. `data/world/pois/survey_marker.tres` is the minimal
non-cave shipped POI. Harness 291 → **301 checks, exit 0**: live-region
checks (discovery from data alone, cross-region stability, boundary claims,
spacing, live-node/payload agreement) plus a `poi_consumers` fixture world
that proves the cave consumer directly. Limitation: the live seed can leave
no tag-eligible biome near the origin, so the cave-presence guarantee lives
in the fixture world, and `POIDefinition` has no distribution field yet, so
"generic distribution" means the existing weight/spacing interpretation.

**Goal:** remove the cave-only placement gate while preserving cave entrances.

Refactor POI candidate generation to interpret generic `PoiDefinition`
placement constraints, spacing, distribution, and eligibility. Cave entrances
should become one consumer of a generic POI candidate, not a special path.
Add one minimal non-cave test POI fixture (a debug marker is enough; do not add
game content) and test stable IDs, chunk-border behaviour, and spacing.

**Done when:** a POI with no cave definition can be discovered, generated, and
loaded deterministically using only data.

### WG-03 — Enforce coherent regions and transitions — COMPLETE (2026-09-12)

Delivered: a memoised coherent-region stage in `WorldGenerator` runs after
per-tile biome selection. World-aligned region cells (side
`region_cell_size_tiles`, default 8; 8 divides 16, so a chunk holds a
disjoint 2x2 of cells) compute their dominant biome over land tiles; a
cell whose dominant declares `minimum_region_size M > 0` and whose
8-connected cell fragment is smaller than `ceil(M / cell^2)` cells is
merged into a neighbouring cell's biome, scored by the raw biome's
authored adjacency (preferred +2.0, transition +1.0, then adjacent-cell
count, then id). Cells are world-coordinate pure and memoised in a
generator-level cache shared by chunk payloads and on-demand
`get_biome_at_world`, so adjacent chunks provably carry identical
records for shared cells and seam chunks generate byte-identically
alone or inside a box. Merged cells rewrite their land tiles only; the
query path keeps the raw biome under water, so payload and query agree
tile-for-tile. Dormant (byte-identical map, empty `region_cells`)
whenever no biome declares `M > 0`. `BiomeDefinition.minimum_region_size`
is now operative region-scale metadata, and the renderer's per-tile hot
path reads the payload `biomes` array with the on-demand query as
fallback. Harness 301 → **312 checks, exit 0**: a `region_coherence`
fixture world (two M=256 biomes, one out of stage) with checks for data
validation, the 2x2 world-aligned cell grid, no sub-floor raw fragments
surviving, metadata-respecting merge receivers, tile-for-tile
payload/query agreement, seam-chunk stability, reversed-order
stability, and a live-seed dormant no-op on the shipped world.
Limitations: the merge is single-pass over the raw map (no re-iteration,
so a merge cannot create a new sub-floor fragment), the transition band
is derived as `M/2` tiles rather than independently authored, and the
harness measures fragments through the generator's own shared raw map,
so a bug in raw selection itself (WG-01 territory) is out of scope.

**Goal:** turn existing biome region metadata into measurable geography.

Add a deterministic, coordinate-safe region/mask stage after initial biome
selection. Use data-defined `minimum_region_size`, transition widths, and
allowed/preferred-neighbour metadata to merge or smooth impractical fragments.
Keep this bounded around chunk edges or sample a deterministic halo so adjacent
chunks agree without requiring all chunks to load.

**Done when:** fixed-seed tests show no tiny prohibited islands, neighbouring
chunks agree at borders, and adding a biome remains an asset-only workflow.

### WG-04 — Add a generic terrain-feature candidate layer — COMPLETE (2026-09-12)

Delivered: `TerrainFeatureDefinition` content (id, spacing grid, footprint
radius, spawn weight, biome/environment eligibility, influence tags)
discovered from `data/world/terrain_features/` and validated by
`WorldContentRegistry` like every other content kind. A new
`_generate_feature_candidates` stage in `WorldGenerator` sits between
coherent regions and the POI stage and emits per-chunk
`feature_candidates` (anchor, owner flag, copied influence tags) through
the same world-pure anchor-grid machinery as POIs, with a footprint halo
so neighbouring chunks' masks agree at borders. `ResourceSpawner` owns
the `no_spawn` influence tag and vetoes covered tiles (no extra RNG
consumption, so dormant worlds are byte-identical); `Main` books one
`TerrainFeatureMarker` per candidate in its owning chunk. The harness adds
a 2d section: two fixture feature assets generate deterministic masks with
zero generator code changes (the done-when seam), with checks for asset
discovery/validation, data-driven fields, regeneration + seam-chunk +
reversed-order stability, halo/owner invariants, min-spacing, the spawner
mask helper, an end-to-end veto (228 placed, 0 on vetoed tiles), live
dormancy, marker node identity, and a dangling-biome validation fixture.
Limitations: terrain-presentation influence is a documented tag seam not
yet consumed by the renderer this card; the shipped world ships no feature
assets, so live payloads are unchanged apart from an empty
`feature_candidates` key; the marker is a neutral placeholder outline, and
per-category presentation is future data/scene content.

**Goal:** create the seam for cliffs, clearings, scree, and similar structure.

Introduce feature definitions and data-driven feature candidates between biome
selection and vegetation placement. Initially implement only a minimal generic
feature marker/mask and one test fixture; do not create a content library.
Allow feature masks to influence spawn eligibility and terrain presentation
through generic tags/modifiers.

**Done when:** a content asset can add a deterministic feature mask without
modifying `WorldGenerator`.

### WG-05 — Complete water classification and shore influences — COMPLETE (2026-09-12)

Delivered: `WorldGenerator` now classifies every tile into a `water_class`
(land / shore / coast / deep_water by 8-neighbour recount) and a
`water_origin` (ocean when elevation is below the water level, lake above
it, water tiles only) inside the existing per-chunk rect pass, and adds a
Chebyshev `distance_to_water` field (0 on water, 1..cap - 1 exact, the cap
value when no water lies within cap - 1 tiles, driven by the new
`distance_to_water_cap_tiles` config, live 16 / fixture 8). Biome, POI,
terrain-feature and resource definitions each gained optional
`min_distance_to_water` / `max_distance_to_water` (per-side -1 =
unconstrained); `WorldContentRegistry` now rejects min < -1, max < -1,
min > max, and a surface_spawnable resource pinned to max distance 0.
Biome selection vetoes distance-failing candidates before the score loop —
water tiles keep their raw region-weighted biome, because a -1 input never
vetoes unconstrained content — the resource spawner vetoes
distance-failing definitions before any RNG roll, and the public on-demand
queries (`get_water_class_at_world`, `get_water_origin_at_world`,
`get_distance_to_water_at_world`) mirror the payload exactly; the on-demand
distance BFS only runs once at least one content definition uses the field
(live world: it stays closed and reads -1). Harness section 2e (28 checks)
covers a 6x6-chunk `water_classification` fixture world (independent
world-wide BFS + 8-neighbour recount over all 9,216 fixture tiles against
the halo-expanded 112x112 (12,544-tile) reference, all four
classes, both origins, deterministic / order-independent / lone-corner-chunk
regeneration, POI + feature + spawner consumption at probe-verified anchor
positions, open-gate on-demand agreement) and a live audit (payload keys,
biomes byte-identical to the pre-WG-05 selector, class/origin agreement,
on-demand class/origin agreement with distance dormant at -1) plus the
`inverted_shore_distance` invalid fixture. Limitations: cap-saturated tiles
read the cap rather than an exact distance; class recounts skip
out-of-bounds neighbours; water outside the finite world is still sampled
(unscaled rects); the live lake origin is structurally unreachable (lake
level 0.24 < water level 0.30); the renderer still presents water by mask
only; and no live content constrains the field (live payloads change only
by the three new keys).

**Goal:** improve physical water without treating it as a biome.

Separate ocean, lake, coastline, shore, and deep-water classifications in the
water result. Add generic distance-to-water/shore fields consumable by biomes,
features, POIs, and spawn rules. Preserve allowed rocky coast/mountain-lake
relationships by relying on data/environment values, never adjacency bans.

**Done when:** tests prove deterministic classifications and a content rule can
use shore distance without a water-name special case.

### WG-06 — Add deterministic rivers and streams

**Goal:** introduce connected hydrology as a world-system extension.

Create a bounded deterministic flow/path stage based on elevation and water
sinks. Generate river/stream masks across a sampling halo and expose the result
as water metadata. Keep rendering and gameplay effects minimal in this card;
the priority is seamless, reproducible paths across chunk borders.

**Done when:** a fixed seed produces identical cross-chunk paths after unload,
reload, and fresh launch. Do not add wetlands or waterfalls yet.

### WG-07 — Replace costly spawn attempts with density fields

**Goal:** make natural distributions intentional and scalable.

Move resource/environmental placement to deterministic candidate/density fields
that obey definition-provided mode, clustering, spacing, feature masks, and
environment constraints. Replace unbounded/global runtime spacing scans with a
deterministic neighbour-aware spatial hash or equivalent bounded lookup.
Keep existing visual nodes and mutation-ledger keys compatible.

**Done when:** results are stable across chunk order, spacing holds over chunk
borders, and a dense-content stress test remains bounded.

### WG-08 — Make the existing cave space playable

**Goal:** complete the minimum separate-space loop without deciding resets.

Use the existing stable cave identity/layout to add collision/navigation as
appropriate for the project, entry/return plumbing, and generic harvestable
underground resource nodes based on `ResourceDefinition` data. Apply cave
mutation-ledger entries on load so depleted deposits remain absent. Keep reset
policy behind an interface/config seam with no permanent default policy.

**Done when:** entering the same cave twice returns to the same deterministic
layout; harvesting a deposit persists through reload; no mineral resource names
appear in cave-generator source.

### WG-09 — Expand cave-definition expressiveness

**Goal:** prepare content authoring for future cave variety, not new caves.

Add optional data fields for room/tunnel ranges, branching, hazards, enemies,
POIs, underground water, feature tags, deposit tables, and loot tables. Only
implement generic interpretation where needed by WG-08; otherwise validate and
document fields as reserved extension points.

**Done when:** designers can author a second cave type asset without an engine
edit, even if it shares the first generator algorithm.

### WG-10 — Add compact generation diagnostics

**Goal:** make bad seeds observable and reproducible.

Provide development-only toggles or a small debug panel showing world seed,
chunk coordinates, biome, elevation, moisture, water classification, and chunk
boundaries. Add selectable field/biome/water visualizations if they can reuse
existing rendering. Keep it off by default and avoid polished UI work.

**Done when:** a developer can report a bad seed and precise location without
instrumenting source code.

### WG-11 — Establish fixed-seed regression and performance checks

**Goal:** protect determinism and large-world viability.

Add a compact set of golden coordinate samples and chunk fingerprints for a few
known seeds/configurations. Add a headless streaming stress scenario measuring
generation of a configured radius without fragile machine-specific thresholds.
Record generator/config/content versions in relevant save metadata only when a
migration requires it.

**Done when:** accidental changes to a fixed world are caught by tests and the
test output identifies the mismatched layer/coordinate.

### WG-12 — Finish content-authoring documentation

**Goal:** make asset-only content work practical for another developer.

Refresh `WORLD_CONTENT_AUTHORING.md` with a complete new-biome and
new-resource walkthrough: create Resource, set environmental and adjacency
data, configure distributions, assign visuals, run validation, and verify a
seed. Add short sections for POIs and cave types. Link the document from the
project architecture docs.

**Done when:** a developer can add a normal biome/resource definition without
editing procedural-generation source or a central source registry.

## Recommended sequencing

Run WG-01 first. Then use WG-02 → WG-03 → WG-04 → WG-05 → WG-06. WG-07 and
WG-08 can proceed independently once WG-01 is complete; WG-09 follows WG-08.
Finish with WG-10 → WG-11 → WG-12. Re-evaluate this plan after each completed
card instead of assuming every later card remains unchanged.

## Explicit non-goals for this handoff

Do not add a large biome set, an enormous cave catalogue, quest content, new
gameplay systems, or a full persistence policy. The work is to strengthen the
reusable world-generation engine using the current content as proof.
