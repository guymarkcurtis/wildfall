# Top-Down Multi-Level Building Plan

> **Superseded as the active schedule.** Work order, merged checklist, and
> progress tracking now live in [`docs/ACTIVE_BUILD_PLAN.md`](ACTIVE_BUILD_PLAN.md)
> (this plan's Phases 0–6 map to milestones M0–M3, M8–M10). This document
> remains the detailed design reference for placement layers, canonical edge
> keys, stairs/connectors, the top-down presentation contract, and the
> building content catalogue and art contracts.

## Purpose

Turn the current proof-of-concept building placement into the first playable
Riftwake building sandbox: freeform rooms and yards, furnished homes, fences,
and real multi-level houses in the existing **orthographic 2D top-down** game.

This is deliberately not an isometric conversion. A story is a logical world
layer, not a camera angle or a different map. The player builds and walks on a
single X/Y tile grid, then stairs transition their active story. Rendering makes
the active story clear and hides or ghosts the others. The result should feel
like a house floor-plan that the player can inhabit, not a dollhouse.

**Plan status:** `READY FOR IMPLEMENTATION`  
**Last reviewed:** 2026-09-14  
**Primary test surface:** Building Sandbox

## Existing foundation to preserve

The implementation must extend, rather than discard, these already-working
systems:

- The game is already orthographic top-down on 32 px square tiles.
- `BuildingManager` stores placed `Building` nodes by tile and `story`, caps
  structures at four stories, serializes `item_id`, `x`, `y`, `story`, and
  health, and applies a basic cutaway.
- `[` and `]` already select construction stories; the Building Sandbox is a
  compact land-only test yard with all technology and recipes available.
- `BuildingDefinition` exists, but definitions are still built in code and the
  runtime currently permits only one placed thing per tile/story.
- Wood and stone structural parts, a tiny utility atlas, recipes, technology
  gates, texture-pack export, and headless tests are already present.
- `docs/INTERACTABLES_STORAGE_AND_LIGHTING_PLAN.md` is the source of truth for
  generic storage, stations, fuel, light, object interaction, and its save
  migration. Do not duplicate or contradict it; this plan supplies the
  placement, story, visual, and content foundation those systems need.

## Non-negotiable design decisions

1. **Stay top-down.** No isometric map, camera, art projection, or fake 3D
   collision. All build positions snap to the existing 32 px square grid.
2. **One active story at a time.** The player's `active_story` determines
   movement collision, interactions, input targeting, and visual priority.
   The build palette may preview another story without moving the player.
3. **Stairs are real connectors, not a separate interior scene.** Walking onto
   an authored stair landing transfers the player between adjacent stories in
   the same structure. It switches `active_story`, updates collision/query
   filtering, and moves the player to the paired landing. It never loads a new
   world, generates a duplicate house, or relies on a screen-transition
   teleport.
4. **A house is composable.** Floors, wall edges, roofs, furniture, and yard
   objects must be able to coexist around one tile. The current one-object-per-
   tile/story dictionary is a prototype and cannot be the final occupancy
   model.
5. **Code defines building rules; Resources define pieces.** Runtime code may
   implement generic placement layers, support validation, stair links,
   rendering, collision, save migration, and crafting. It must not branch on
   names such as `if item_id == "wooden_stairs"` to grant normal building
   behaviour. Definitions under `data/buildings/` define part roles, tiers,
   assets, footprints, recipes, and capabilities.
6. **Existing saves remain valid.** Old placed parts map to an equivalent
   layer/slot at the same coordinates and story. Unchanged procedural world
   data remains deterministic; only player-built records and their runtime
   state are saved.
7. **Sandbox first, survival second.** The full content set lands unlocked and
   freely supplied in Building Sandbox before final survival recipes, research
   costs, balance, or progression gates are accepted.

## Player-facing model

### Build grid and placement layers

Replace the single cell slot with generic addressable slots. A placement key
contains grid coordinates, story, layer, and only when relevant an edge side
or orientation. It is deterministic and serializable.

| Layer | Grid address | Examples | Coexists with |
|---|---|---|---|
| `ground` | tile | foundation, patio, path | all other layers |
| `floor` | tile | plank floor, stone floor, stairwell opening | ground, edge, object, roof |
| `edge` | north/east/south/west edge of a tile | walls, windows, doors, fence rails, railing | floor and objects; not another edge in same span |
| `object` | tile | bed, chest, table, station, planter | floor/ground and surrounding edges |
| `overhead` | tile | roof, awning, ceiling trim | all lower layers; presentation can hide it |
| `connector` | linked lower/upper landing records | stairs, later ladder or hatch | its declared floor/edge reservations |

Use a canonical edge key so the east edge of `(x,y)` is the same slot as the
west edge of `(x+1,y)`; this prevents doubled walls, doubled fence segments,
and save-order bugs. Multi-tile objects reserve a generic footprint of keys in
one atomic placement transaction. No special item-name logic is permitted.

### Construction rules

- Ground-story foundations may be placed only on valid land terrain. The
  existing water restriction remains in effect.
- A floor requires suitable support beneath it except on story 0 where its
  definition determines whether a foundation is required.
- Edge walls, doors, windows, railings, and fence rails require an adjacent
  valid floor/ground edge as authored by their definition. A door/window is an
  alternate occupant of a wall edge, not an extra object on top of one.
- Upper floors require continuous authored support. For the first sandbox pass,
  use a conservative direct-support rule: every upper-floor tile needs a
  supporting floor/foundation/pillar at the same X/Y below. Do not attempt
  structural engineering, spans, collapse, or stress simulation yet.
- Roof/awning pieces require a covered floor or edge support, but do not affect
  player movement. They are visual structure, not an additional collision
  plane.
- Normal ground movement is blocked only by `blocks_movement` content data on
  the **active** story. Fences and walls do not collide with the player on an
  inactive story.
- Every placement validates the complete footprint, reserves all keys only on
  success, consumes inventory only after validation, and refunds the exact
  placed item on demolition. A failed placement changes nothing.

### Stair and story behaviour

Implement a generic `VerticalConnector` capability, authored by a building
definition rather than hard-coded per stair item.

1. A stair definition contains lower and upper story offsets, a direction,
   lower/upper landing offsets, required support slots, and any floor-hole/
   railing reservations. Initial connectors are one-story only; a player
   climbs one story at a time.
2. Placing stairs is atomic: validate lower landing, upper landing, the upper
   floor support, the reserved stairwell opening, and all connector slots
   before consuming the item.
3. A player entering the lower landing while facing/using the stair transitions
   to the paired upper landing; using the upper landing returns them below.
   Preserve world X/Y proximity, clear velocity, prevent instant bounce-back
   with a short directional/exit lock, and set `active_story` before the next
   physics query.
4. The existing `[ / ]` controls remain **construction-level selection**. Add
   an explicit debug/sandbox story selector only if needed for rapid testing;
   it must not silently move a normal survival player through solid floors.
5. First release: stairs only. Data must make later ladders, hatches, elevator
   platforms, basement entrances, and cave portals possible without changing
   the save model. Caves remain their own generated spaces and are out of this
   building pass.

### Top-down presentation contract

- Active player story: full opacity, normal colour, normal interaction hints,
  and the only collision/query layer for player movement.
- Stories below: visible at roughly 20–35% opacity while indoors or in build
  mode, optionally desaturated, and never obstructing the active floor. This
  preserves orientation without suggesting they are walkable now.
- Stories above: hidden during normal movement. In build mode, show their
  footprint as a low-alpha blueprint/outline, not a shifted pseudo-isometric
  floor.
- Roofs/awnings: shown when the building is viewed externally; fade/cut away
  over the active room, active stair landing, or active build target. A manual
  roof-visibility toggle is useful in the sandbox, but automatic occlusion
  behaviour must be the normal experience.
- Do not use `STORY_RISE` to move an upper story up the screen. Keep all stories
  aligned in X/Y. Distinguish them with z-order, opacity, line treatment, roof
  cutaways, and the UI's active-story indicator.
- Use deterministic render bands such as `story * STORY_Z_STRIDE + layer_z` so
  ground, floor, edge, object, connector, ghost, and UI rendering remain
  stable. Do not rely on incidental child creation order.

## Content and art target

Every ordinary part is data-authored under `data/buildings/`; its inventory
item/recipe is an economic representation, not the source of its behaviour.
Start with three visual tiers. Tier progression/costs can be tuned after the
sandbox test; IDs must be stable once shipped.

| Family | Tier 1: Timber | Tier 2: Stone | Tier 3: Reinforced / metal | Notes |
|---|---|---|---|---|
| Ground and floors | foundation, floor, porch, deck | foundation, flagstone floor, patio | reinforced floor, metal grate | 32×32 fill tiles with seamless edges |
| Wall edges | solid, half/open frame, window, door | solid, window, door | reinforced wall, shuttered window, gate | edge-oriented N/E/S/W variants, not freestanding square blocks |
| Supports | post, beam, pillar | column, arch/pillar | reinforced post | first pass uses direct support only |
| Roof/cover | shingle roof, awning | slate roof, awning | metal roof/canopy | auto-cutaway capable overhead art |
| Vertical | stair up/down, stairwell rim, railing | stone stair, stairwell rim, railing | metal stair, railing | connector art must clearly show direction from overhead |
| Boundary | low fence, fence gate, rail, corner post | stone wall, stone gate, rail | metal fence/gate | edge placement; gates reserve an edge slot |
| Exterior detail | steps, path, lantern post, planter | well, brazier, stone planter | signal/utility pole, metal lantern | placeable sandbox props; capabilities stay data-driven |
| Interior furniture | bed, chest, table, chair, shelf, rug, wardrobe | hearth, cabinet, bookcase | workshop cabinet, metal locker | begin cosmetic; hand interaction-capable assets to the interactables plan |
| Functional fixtures | campfire, workbench, furnace, anvil, torch | cooking hearth, kiln (later) | advanced bench (later) | existing four stations and lights migrate to data assets |
| Garden / homestead | planter box, crop soil, wood gate, animal pen fence | stone planter, paved path | irrigation/utility placeholder | no farming/animal simulation expansion in this pass |

### Initial art production contract

All new game raster art must use the repository's required PixelLab.ai MCP
pipeline, with existing Wildfall building/terrain art as style reference. Do
not substitute another image generator. Generate source art as transparent PNG
tiles/sprites, then mechanically pack/crop only to satisfy the listed atlas
contracts.

Create an authoring request file, `docs/BUILDING_ART_REQUESTS.md`, before
generation. It must name every cell, exact dimensions, orientation, transparent
background rule, reference assets, and consuming code. Do not ask an image
model to produce a whole labelled atlas; generate a reviewed source per family
or cell and pack deterministically.

Recommended first-pass texture contracts:

| Asset | Contract | Intended use |
|---|---|---|
| `assets/tiles/building/structural_<tier>.png` | 32×32 cells, a documented fixed grid for fills, edges, corners, doors/windows, roofs, supports, and stair components | primary material-specific structure atlas |
| `assets/tiles/building/boundaries_<tier>.png` | 32×32 cells; straight edge, corner, gate, post, rail variants | fences, gates, railings, low walls |
| `assets/tiles/building/interior_<tier>.png` | 32×32 cells plus explicitly declared 2×1/2×2 footprints | furniture and cosmetic fixtures |
| `assets/tiles/building/exterior_props.png` | 32×32 cells | paths, planters, lanterns, steps and yard props |
| `assets/items/pickups/<stable_item_id>.png` | one transparent 32×32 icon for every new placeable item | inventory, crafting and world pickup presentation |

Document every atlas cell map in data, not duplicated GDScript constants. Add
every new image to `TexturePackManager.PACK_ASSETS`, stock manifest metadata,
texture-pack export, reload handling, and asset completeness tests.

## Data architecture

### Resources and folders

Create discoverable folders with README authoring guidance:

```text
data/buildings/
  definitions/        # one BuildingDefinition .tres per placeable part
  families/           # material/visual-family data and atlas cell references
  connectors/         # VerticalConnectorProfile resources
  collision/          # reusable collision/occupancy profiles if warranted
  README.md
data/building_recipes/ # optional only if recipes leave ItemDatabase later
assets/tiles/building/
docs/BUILDING_ART_REQUESTS.md
```

Extend `BuildingDefinition` (or replace it with a backwards-compatible,
resource-backed equivalent) with generic fields such as:

- stable `id`, display name, description, item ID, tier, research ID and cost;
- placement layer, allowed orientation, footprint/reservations, multi-story
  offsets, and occupancy replacement policy;
- terrain/floor/edge/support requirements expressed by tags/profiles;
- collision, walkability, build selection footprint, and render band;
- `visual_family_id`, atlas path/cell or scene, rotation/mirroring policy, and
  ghost/cutaway presentation metadata;
- optional generic profiles: vertical connector, interaction, storage, station,
  fuel, light, bed/rest, or decorative. These are references, never named-ID
  switches in runtime code.

Build a deterministic `BuildingContentRegistry` that loads these resources,
validates IDs/atlas references/recipes, and returns definitions to
`BuildingManager`. Move the present `_init_definitions()` hard-coded entries
into `.tres` assets. A short-lived fallback is acceptable only during migration;
remove it before this plan is complete.

## Delivery sequence

Complete phases in order. Each phase is independently runnable and must update
the relevant authoring docs and `docs/TEST_RESULTS.md` with real results before
the next begins.

### Phase 0 — Baseline and design lock

- [ ] Run the current Godot headless harness and parser/launch check; record
  baseline counts and errors without overwriting historic results.
- [ ] Read this plan and the interactables plan together; record any deliberate
  deviations in a dated decision log at the bottom of this document.
- [ ] Capture three sandbox screenshots of the current four-story prototype:
  ground build, upper-story build, and save/load. They are regression context,
  not final art targets.
- [ ] Freeze the first-pass scope: four total stories, adjacent-story stairs,
  no structural collapse, no multiplayer permissions, no procedural buildings,
  and no isometric conversion.

**Exit:** a clean baseline and no unresolved conflict with the interactables
data/save migration sequence.

### Phase 1 — Resource-backed building content

- [ ] Implement `BuildingContentRegistry`; load and validate resources in a
  stable sorted order.
- [ ] Add the generic placement, visual, support, and capability reference
  fields to `BuildingDefinition`.
- [ ] Author data for every existing wood/stone structural part, fence, bed,
  chest, torch, campfire, furnace, workbench, and anvil. Preserve current item
  IDs and recipes exactly in this phase.
- [ ] Replace `BuildingManager._init_definitions()` as the production source;
  update build palette and technology checks to use definition data.
- [ ] Add `data/buildings/README.md` explaining IDs, atlas cell references,
  support tags, art conventions, and how to create an asset-only new variant.

**Exit:** adding a normal wall/furniture tier requires content assets and art,
not a named `if`/`match` branch in `BuildingManager` or `Building`.

### Phase 2 — Layered grid and atomic placement

- [ ] Replace the `Vector3i(x,y,story) -> Building` single-slot assumption with
  a `BuildingRecord`/placement index that supports the six documented layers,
  canonical edge keys, multi-key reservations, and fast query by active story.
- [ ] Keep a compatibility API for `get_building_at()` long enough to migrate
  existing callers; add precise layer/edge query APIs and retire ambiguous
  calls deliberately.
- [ ] Refactor placement, ghost preview, demolition, health/destroy callbacks,
  selection, proximity checks, and serialisation to operate on complete placed
  records/footprints transactionally.
- [ ] Implement generic floor + edge coexistence, wall-to-door/window edge
  replacement where allowed by data, multi-tile object reservations, and
  material refund handling.
- [ ] Implement the conservative support validator and exact failure reasons.

**Exit:** a floor, four edge walls, a roof, and furniture can form one usable
room without overlapping collisions or duplicate edge walls; all failures leave
inventory and occupancy untouched.

### Phase 3 — Active story and playable stairs

- [ ] Introduce an active-story owner shared by Player, `BuildingManager`,
  interaction queries, and the HUD. Construction story and player active story
  must be separate values.
- [ ] Replace shifted `STORY_RISE` presentation with aligned top-down render
  bands and the documented active/below/above opacity policy.
- [ ] Implement generic connector placement and `VerticalConnector` traversal
  with paired landing triggers, direction lock, collision/query switching, and
  robust handling when its linked record is demolished.
- [ ] Convert existing wood and stone stairs to connector definitions; add
  railings/stairwell trim as ordinary content.
- [ ] Implement automatic roof cutaway plus a sandbox-only visibility/debug
  control. Ensure upper story collision never blocks the ground player.
- [ ] Show a concise HUD/build palette indicator for active story and selected
  construction story; make the two states impossible to confuse.

**Exit:** a player can build a two-floor 4×4 house, walk up and down stairs,
interact with active-floor furniture, and never collide with or target a hidden
floor by mistake.

### Phase 4 — Build catalogue and first functional furniture

- [ ] Author Tier 1 timber content completely: structural, stair/rail,
  boundary, exterior, and initial interior set from the table above.
- [ ] Author Tier 2 stone equivalents and upgrades; preserve stable item IDs
  for existing stone pieces.
- [ ] Add Tier 3 reinforced/metal as a data-driven catalogue and a technology
  gate following `metalworking`; final costs are sandbox-tested before balance
  approval.
- [ ] Migrate current stations, chest, torch, and bed onto the generic
  capability references required by the interactables plan. Do not rebuild
  storage/fuel/light behaviour in a parallel system.
- [ ] Add paths, gates, fences, planters, yard lights, porch/deck pieces and
  non-functional furniture so players can test homestead layout as well as
  houses.
- [ ] Add recipe, item icon, pickup art, research, tooltip, texture-pack, and
  sandbox-supply coverage for every new placeable. Every survival recipe must
  have an obtainable ingredient chain.

**Exit:** Building Sandbox exposes a broad enough palette to make distinct
cabins, stone houses, fenced yards, workshops, and furnished two-story homes.

### Phase 5 — Art, UX, and sandbox playtest pass

- [ ] Write and fulfil `docs/BUILDING_ART_REQUESTS.md` through the required
  PixelLab pipeline; review at actual camera zoom before packing atlases.
- [ ] Build explicit build-palette groups and filters: structure, roof/cover,
  stairs/rail, doors/windows, furniture, stations, boundaries, exterior.
- [ ] Add orientation/rotation controls with a visible compass/edge preview;
  rotate only when the definition permits it and never reinterpret saved
  orientations.
- [ ] Make ghost previews display all reserved tiles/edges, support failures,
  stair endpoints, and roof cutaways—not merely a green/red square.
- [ ] Add a small tutorial card in Building Sandbox: layers, orientation,
  construction story, stairs, roof cutaway, demolish/refund, save/load.
- [ ] Conduct a structured sandbox pass: cabin, two-storey cottage, fenced
  farmyard, stone workshop, and three-storey stress layout. Record bugs,
  screenshots, and performance observations.

**Exit:** the system is understandable without developer knowledge and the
art remains readable at native gameplay scale.

### Phase 6 — Save migration, verification, and handoff

- [ ] Bump the versioned save format only when the serialized building record
  schema changes. Add a migration mapping old `item_id/x/y/story/health`
  records to their equivalent definition placement and default orientation.
- [ ] Tolerate missing new fields when loading old saves; preserve unknown
  future fields where the save architecture already permits it.
- [ ] Verify save/load for a mixed wood/stone, furnished, multi-story house;
  verify a partly demolished staircase cannot strand or crash the player.
- [ ] Run `tests/test_building_sandbox.gd`, the full headless harness, texture
  pack export/override tests, and a real launch/parser check. Add targeted
  regression cases listed below.
- [ ] Update `docs/PROJECT_STATE.md`, `docs/ITEM_SYSTEM.md`,
  `docs/SAVE_FORMAT.md`, `docs/TEXTURE_PACKS.md`, the building authoring README,
  and `docs/TEST_RESULTS.md` with only verified final facts.

**Exit:** clean automated verification, old saves load, the data authoring path
is documented, and the sandbox is ready for human building experiments.

## Required automated coverage

Add focused tests rather than relying only on screenshots or manual play:

- registry loads all building definitions deterministically; duplicate IDs,
  missing atlas cells, bad footprints, unknown capability references, and
  invalid support tags fail with actionable validation messages;
- same tile/story accepts floor + object + overhead and correctly rejects two
  occupants of an identical slot;
- canonical edge identity prevents placing the same wall/fence span from both
  adjacent tiles;
- rotation changes an allowed edge/object footprint and does not change a
  non-rotatable definition;
- upper floors reject missing support and accept a supported 2×2 room;
- a stair placement is atomic, creates a valid two-way link, traverses both
  directions exactly once, and rejects invalid/missing upper landing support;
- active-story collision and interaction queries ignore inactive stories;
- cutaway/roof states match active story in normal play and selected story in
  build mode without screen-position skew;
- wall/door/window and fence/gate replacement obey authored occupancy data;
- demolition refunds one complete item and safely removes dependent connector
  traversal; invalidation never duplicates items;
- old building save entries migrate, old saves load, new mixed-layer buildings
  round-trip including orientation, connector link data, health, and future
  capability state;
- all texture atlas cells used by authored content are non-empty at their
  declared dimensions and every new placeable has a pickup icon;
- Building Sandbox supplies every building item, exposes every planned tier,
  and remains free of survival resource/tech starvation.

## Out of scope for this pass

- Isometric rendering or a camera conversion.
- Structural physics, load distribution, collapse, weather damage, fire spread,
  electrical grids, room-temperature simulation, or zoning/ownership.
- Multiplayer construction permissions and concurrent edit resolution.
- Procedurally generated player houses or serialising untouched world chunks.
- Basements/caves as ordinary stories; cave generation and its mutation policy
  stay separate from surface buildings.
- Unlimited-height towers. Four stories is the validated first limit; revisit
  only after performance, UI, and navigation tests support it.

## Decisions to record during implementation

Add dated entries here only when deliberately changing a design decision above.

| Date | Decision | Reason / consequence |
|---|---|---|
| 2026-09-14 | Use aligned orthographic active-story cutaway rather than isometric presentation. | Preserves the existing camera, readable placement grid, and freeform building precision. |
| 2026-09-14 | First vertical connection is a real adjacent-story stair link. | Keeps a house coherent and avoids treating ordinary upper floors as separate maps. |
