# Riftwake Active Build Plan — Buildings, Interactables, Storage, Lighting

This is the single active deployment plan for the current development pass.
It merges and supersedes the *schedules* of:

- `docs/TOP_DOWN_MULTILEVEL_BUILDING_PLAN.md` (multilevel, layered building
  system) — retained as the detailed design reference for placement layers,
  stairs, presentation, and the building content catalogue.
- `docs/INTERACTABLES_STORAGE_AND_LIGHTING_PLAN.md` (interaction, storage,
  stations, fuel, lighting) — retained as the detailed design reference for
  capability profiles, the interaction router, transfer semantics, the PixelLab
  art brief, and the save `state` payload.

Read those two documents for the fine-grained contracts; this document owns
the order of work, the merged checklist, and the progress record. Where the
source plans conflict, this plan and its decision log at the bottom win.

## How to work this plan

1. Work milestones in order. Each is independently runnable and shippable.
2. At the end of a milestone: tick its checkboxes, run the verification
   matrix, append a row to the progress log (date, milestone, status,
   evidence), record real results in `docs/TEST_RESULTS.md`, and commit.
3. Do not rewrite completed items to hide deferred work — log deviations in
   the decision log with a date.
4. Keep every guarantee in “Standing contracts” true at all times. A change
   that violates one needs a dated decision-log entry.

**Plan status:** `ACTIVE`
**Current milestone:** M4 — Interaction router and shared object UI
**Last updated:** 2026-09-14 (M3 complete)

## Groundwork already in place

- **Building Sandbox test surface** (commit `5d6cc79`): third game mode —
  5×3-chunk land-only yard, all tech/recipes unlocked, pre-placed
  campfire/workbench/furnace/anvil, Supply Store, fixed time of day, sandbox
  save toolbar, hunger paused. Primary test surface for this pass
  (`tests/test_building_sandbox.gd`).
- **Interactables Phase 0** (complete, logged in the source plan): baseline
  harness recorded, `docs/INTERACTABLE_AUTHORING.md` scaffolded, container
  slot decisions fixed (27-slot 9×3 chest, 1 fuel slot, station-defined
  ingredient slots, 1 output slot).
- **Harness state:** 436 checks, 0 failures, 0 script errors (2026-09-14).
  The 4 cave-map failures from the original Phase 0 baseline were resolved by
  the WG-12 cave presence/coverage guarantees.
- **Save format is v7** (v6 = world `generation_version`, v7 = map
  exploration). The interactables plan's “bump to v6” predates those bumps;
  this pass bumps to **v8** once, in M2 (see decision log).

## Milestone map

| # | Milestone | Merged from |
|---|-----------|-------------|
| M0 | Baseline and scope lock | Building P0 + Interactables P0 |
| M1 | Content foundation: registry, definitions, capability profiles, slot inventory | Building P1 + Interactables P1 |
| M2 | Layered grid, atomic placement, save v8 records | Building P2 |
| M3 | Active story and playable stairs | Building P3 |
| M4 | Interaction router and shared object UI | Interactables P2 |
| M5 | Chests and persistent storage | Interactables P3 |
| M6 | Station panels and recipe inputs/outputs | Interactables P4 |
| M7 | Fuel, on/off state, illumination | Interactables P5 |
| M8 | Build catalogue expansion (timber/stone/reinforced) | Building P4 |
| M9 | Art, UX, and presentation | Building P5 + Interactables P6 (art) |
| M10 | Save verification, playtest, docs, handoff | Building P6 + Interactables P6 (release) |

Ordering rationale: the content foundation (M1) is shared by both plans, so it
merges. The interaction router (M4) and all capability state (M5–M7) land
*after* the layered placement model (M2) and stairs (M3), so nothing targets
or serializes a placement model that is about to be replaced. The catalogue
expansion (M8) comes after stations/fuel/light, so every new part is authored
purely as data against the finished capability system. Art (M9) covers both
plans in one PixelLab pass.

## Standing contracts (true at every commit)

1. **Code defines systems; data defines content.** No
   `if building_id == "chest"` / `match station_id` / named-content branches
   in runtime code. New objects are asset-only additions under `data/`.
2. **Stable placement identity.** A placed object's key is derived from its
   placement (grid, story, layer, edge/orientation when relevant). Never
   NodePath, creation order, or random IDs. UI ownership and save data key on
   it.
3. **Transactional everything.** Transfers never remove from a source until
   the destination accepts; placements validate the whole footprint before
   consuming anything; demolitions refund exactly; failed operations leave
   inventory, occupancy, and world state untouched.
4. **Interactions are mutually exclusive.** One open object UI at a time; it
   locks movement, blocks firing/harvesting/building, closes safely from every
   listed reason, and every close path is idempotent.
5. **Top-down, one active story.** No isometric conversion; all stories align
   in X/Y; `active_story` owns movement/queries/rendering priority; `[` / `]`
   remain construction-level selection.
6. **Save model.** Deterministic base world + mutation ledger. Only
   player-caused state serializes; procedural chunks are never dumped. Old
   saves migrate; malformed fields are ignored safely, never invented.
7. **Art rule.** All new raster game art via the PixelLab.ai MCP with existing
   Wildfall assets as style references; mechanical packing only afterwards.
8. **Verification discipline.** Headless harness + focused tests + import/
   launch check before any milestone is marked complete; results recorded in
   `docs/TEST_RESULTS.md`.

---

## M0 — Baseline and scope lock

- [x] Run headless harness + import/launch check; record baseline in
      `docs/TEST_RESULTS.md` (done for both source plans; cave-map failures
      resolved by WG-12).
- [x] Read both source plans together; record deliberate deviations in the
      decision log (done — this document).
- [x] Confirm and document container slot grid: 27-slot (9×3) chest, 1 fuel
      slot, station-defined ingredient slots, 1 output slot.
- [x] Confirm interactables scope: no generated loot chests, no multiplayer
      locks, no timed production queue, no gameplay effects from light.
- [x] Capture three sandbox screenshots of the current four-story prototype
      (ground build, upper-story build, save/load) as regression context.
      Done: `docs/sandbox_baseline/` (`ground_build.png`,
      `upper_story_build.png`, `save_load.png`), captured 2026-09-14 with a
      15-building save/load round-trip; note they show the current
      `STORY_RISE`-shifted presentation that M3 replaces.
- [x] Freeze first-pass scope: four total stories, adjacent-story stairs, no
      structural collapse, no multiplayer permissions, no procedural
      buildings, no isometric conversion. Frozen 2026-09-14 (recorded here
      and in the decision log).

**Exit:** clean baseline, scope frozen, no unresolved conflict between the
two source designs.

## M1 — Content foundation: registry, definitions, profiles, slot inventory

*No player-facing interaction changes in this milestone. COMPLETE 2026-09-14.*

- [x] Implement `BuildingContentRegistry`: loads `BuildingDefinition` assets
      from `data/buildings/` in deterministic sorted order; validates IDs,
      atlas references, footprints, recipes, and capability cross-references;
      invalid references fail at startup with actionable paths (existing
      content-validation style).
- [x] Extend `BuildingDefinition` with generic fields: placement layer,
      allowed orientations, footprint/reservations, multi-story offsets,
      occupancy-replacement policy, support tags, collision/walkability,
      render band, `visual_family_id` + atlas path/cell, ghost/cutaway
      metadata, and optional generic capability references (interaction,
      container, station, fuel, light, appearance, connector, decorative).
- [x] Add the capability Resource scripts with validation:
      `InteractionProfile`, `ContainerProfile`, `StationProfile`,
      `FuelProfile`, `LightProfile`, `AppearanceProfile` (connector profile
      arrives with M3's stair work).
- [x] Migrate all `BuildingManager._init_definitions()` entries into `.tres`
      assets preserving existing item IDs and recipes exactly; delete the
      hard-coded initializer (done in the same milestone — no fallback
      shipped).
- [x] Add `ItemDefinition.tags: PackedStringArray` (or equivalent); tag
      burnables `fuel` in data; no ID-based fuel lookups anywhere.
- [x] Add `InventoryStorage` (or refactor `InventoryComponent` behind a
      compatible interface): fixed indexed slots, per-slot stack limits,
      weight limits, filter predicates, serialize/deserialize, change
      signals. Preserve the public player inventory API used by Player,
      harvesting, crafting, missions, hotbar, and tests.
- [x] Migrate the compact `{item_id: {quantity, ...}}` player inventory in
      old saves into deterministic indexed slots (with full durability for
      pre-v5 durable tools). No hotbar format change. (Migration happens at
      load; `serialize()` still writes the compact format until the v8 bump
      in M2 — decision log.)
- [x] Implement `InventoryTransfer.transfer(source, source_slot, target,
      target_slot, requested_quantity)` as the single authoritative transfer
      routine: merge, swap, split, filtered rejection, max stack, max weight,
      partial acceptance.
- [x] Extend `Building` with a runtime capability-state dictionary and a
      stable placement key; keep collision/placement/story behaviour intact.
- [x] Author `data/buildings/README.md` (IDs, atlas cell references, support
      tags, asset-only variant workflow) and flesh out
      `docs/INTERACTABLE_AUTHORING.md`.
- [x] Tests: registry determinism + validation failures; storage
      serialization; legacy player-inventory migration; complete/partial/
      rejected transfers; slot filters; definition validation. v5/v6/v7 saves
      still load. (`tests/test_building_content.gd`, 69 checks; full harness
      436/0; sandbox harness 18/0; live headless boot 0 script errors.)

**Exit:** data can define a storage or fuelled object; old saves load; no
live gameplay behaviour change needed yet.

## M2 — Layered grid, atomic placement, save v8 records

*COMPLETE 2026-09-14.*

- [x] Replace the `Vector3i(x, y, story) -> Building` single-slot model with a
      `BuildingRecord`/placement index supporting the six layers (`ground`,
      `floor`, `edge`, `object`, `overhead`, `connector`), canonical edge keys
      (east edge of `(x,y)` == west edge of `(x+1,y)`), multi-key atomic
      reservations, and fast query by active story.
- [x] Keep a compatibility API for `get_building_at()` while migrating
      callers; add precise layer/edge query APIs (`get_record_at`,
      `get_record_for_key`, `get_all_records`); retire ambiguous calls
      deliberately.
- [x] Refactor placement, ghost preview, demolition, health/destroy
      callbacks, selection, proximity checks, and serialization to operate on
      complete records/footprints transactionally.
- [x] Implement floor + edge + object + overhead coexistence, wall→door/
      window edge replacement where data allows, multi-tile object
      reservations, and exact refund handling.
- [x] Implement the conservative support validator (upper floors need
      support at the same X/Y below; ground floors need valid land; roof needs
      cover below and never collides) with exact failure reasons.
- [x] **Bump save format to v8**: building entries become layered records
      (item, x, y, story, layer, orientation where relevant, health) with an
      optional `state` payload reserved for M5–M7 capability state. v7→v8
      migration maps every old flat record to its equivalent
      layer/slot/orientation at the same coordinates and story. v1–v7 saves
      keep loading.
- [x] Update `docs/SAVE_FORMAT.md` with the v8 schema and migration.
- [x] Tests: same tile/story accepts floor+object+overhead and rejects
      duplicate identical slots; canonical edge identity blocks doubled
      wall/fence spans; rotation changes only rotatable definitions; upper
      floors reject missing support and accept a supported 2×2 room;
      demolition refunds exactly once; old-save migration; mixed-layer
      round-trip. (`tests/test_building_placement.gd`, 55 checks; full
      harness 438/0 incl. new v8 checks; content suite 69/0; sandbox 0
      failures; live boot 0 script errors.)

**Exit:** floor + four edge walls + roof + furniture form one usable room
with no overlaps or duplicate edges; all failures leave inventory and
occupancy untouched; old saves load.

## M3 — Active story and playable stairs

*COMPLETE 2026-09-14.*

- [x] Introduce an active-story owner shared by Player, `BuildingManager`,
      interaction queries, and HUD; construction story (build palette) stays a
      separate value. (`BuildingManager.active_story` + `active_story_changed`;
      the player's collision mask, render band, and story-0 interaction gate
      all follow it.)
- [x] Replace the shifted `STORY_RISE` presentation with aligned top-down
      render bands (`story * STORY_Z_STRIDE + layer_z`) and the documented
      opacity policy: active story full; below ≈20–35% while indoors/building;
      above hidden (blueprint outline in build mode); roofs cut away over the
      active room/landing/build target. No screen-position skew.
- [x] Implement generic `VerticalConnector` placement and traversal from
      definition data: paired landing triggers (edge-triggered, so standing
      still never re-fires), velocity clear, `active_story` set before the
      next physics query, safe handling when the linked record is demolished
      mid-link.
- [x] Stair placement is atomic: validate lower landing, upper landing, upper
      floor support, reserved stairwell opening, and all connector slots
      before consuming the item. (The stairwell opening is the connector
      record's own floor-slot reservation one story up — no floor can block
      it, and demolishing the stair frees it.)
- [x] Convert existing wood/stone stairs to connector definitions
      (`ConnectorProfile` assets; railings/stairwell trim deferred to the M8
      catalogue — decision log). The save model already carries any future
      connector (ladders, hatches, portals) without a schema change.
- [x] Implement automatic roof cutaway plus a sandbox-only visibility/debug
      control (`toggle_roofs`, R, Building Sandbox only); upper-story
      collision lives on per-story bits, so it can never block a
      ground-story player.
- [x] HUD/build-palette indicator distinguishing active story from selected
      construction story (world-info line shows `Floor L#` vs `Build L#`).
- [x] Tests: two-floor 4×4 house buildable; stairs traverse up/down exactly
      once; inactive-story collision and interaction queries are ignored;
      cutaway states match active story (normal play) / selected story (build
      mode); demolition of one stair side cannot strand or crash the player.
      (`tests/test_building_stairs.gd`, 37 checks; placement suite 55/0;
      content suite 69/0; full harness 440/0 incl. updated cutaway policy
      checks; sandbox 0 failures; live boot 0 script errors; fresh aligned
      screenshots in `docs/sandbox_baseline/m3_aligned_*.png`.)

**Exit:** a player can build, furnish, and walk a two-story house with stairs
and never collide with or target a hidden floor.

## M4 — Interaction router and shared object UI

- [ ] Add an `Interactable` runtime interface to placed buildings:
      `can_interact(player)`, prompt metadata, `interact(player)`,
      `close(reason)` — no type/name branches.
- [ ] Add an `InteractionManager` under Main as the single owner of current
      target / current open object: finds valid placed interactables in
      authored range, deterministic priority (distance, then stable key),
      publishes the HUD prompt (`E Open Chest`).
- [ ] Insert the router into `Player._handle_interaction()` after cave
      entrance priority, before resource/creature handling; preserve
      build-mode suppression, cave handling, durability rules, UI blocking.
- [ ] Add an `InteractablePanel` scene/script: title, close button, backdrop,
      contextual help, player inventory view, content area supplied by the
      active profile. No per-object duplicate inventory rendering.
- [ ] Extract one shared slot-grid control from `InventoryPanel`; player,
      chest, fuel, ingredient, and output storage all use it: left-click
      select, drag/drop, shift-click quick transfer, deterministic split
      (right click → half or quantity picker), read-only output slots,
      tooltips.
- [ ] Define and implement close behaviour for: Escape, close button,
      opening another object, out of range, entering a cave, loading/new
      seed, building removal/damage, death, pause/title transition, scene
      shutdown. Each safe when fired twice.
- [ ] Accessibility path: focus stays in UI, Escape always closes the topmost
      panel, world clicks never leak through an open panel.
- [ ] Tests: targeting priority, prompt visibility, input lock, every close
      reason (each twice), direct object-to-object switching, using a
      data-authored test fixture (not a chest) to prove genericity.

**Exit:** a data-authored empty container opens/closes via E with no double
input, stuck movement, or world-interaction leak.

## M5 — Chests and persistent storage

- [ ] Author `data/buildings/wood_chest.tres`: 27-slot (9×3) container
      profile, `Open` prompt, chest appearance profile, existing stable
      `chest` item ID, zero special-case code.
- [ ] Wire the chest panel: player inventory and chest side by side;
      drag/drop both ways, quick transfer both ways, merge/swap/split,
      tooltips, empty state, capacity/weight feedback.
- [ ] Chest open/close animation states; logically open only once the opening
      transition begins; forced closes (range/load/removal) still play or
      reverse the transition.
- [ ] Serialize per-building runtime state into its v8 building entry's
      `state` payload: `{container: <indexed storage>, enabled, ...}` —
      JSON-safe primitives only; omit defaults, never omit a non-empty
      inventory; loader rejects malformed fields safely.
- [ ] Demolition policy: **block demolishing a non-empty chest** with a clear
      message and panel close; never silently refund or delete contents.
- [ ] Tests: craft→place→open→fill→empty; exact contents survive
      save→quit/reload→open; UI-open state is not saved as gameplay state;
      loading clears stale panels; non-empty chest refuses demolition.

**Exit:** nothing is lost across save/load; a non-empty chest cannot be
demolished.

## M6 — Station panels and recipe inputs/outputs

- [ ] Split C-key crafting: C remains the *hand-crafting* panel for
      station-less recipes; station recipes open only via E-interaction with
      that station. No silent removal of the hand-crafting path.
- [ ] Author `StationProfile` assets for workbench/campfire/furnace/anvil;
      recipe eligibility by profile tags/IDs; delete the hard-coded
      `CRAFTING_STATION_IDS` list and all named station branches.
- [ ] Station view: recipe list/filter/detail, player inventory, station
      ingredient slots, output slot, contextual status, close controls.
      Input/fuel/output containers are persistent inventories, not visual
      counters.
- [ ] Deterministic immediate-craft semantics: inputs fill via normal
      transfers or pre-placed ingredients; Craft consumes exactly those
      inputs and inserts into the output slot; Craft disables when the output
      cannot accept the result.
- [ ] Workbench: ship a representative set of existing workbench recipes via
      an adapter over current `RecipeDefinition`s (preserve IDs, research
      gates, game-mode policy; no duplicated definitions).
- [ ] Furnace/campfire: show powered/unpowered state and fuel capacity; timed
      queues stay deferred; the immediate pipeline uses the same input/output
      containers timed jobs will later use.
- [ ] Tests: station-gated recipes open only from the station; ingredients
      visibly move through station slots; output-full rejection; research
      gates; station input/output save/load.

**Exit:** a workbench recipe is craftable only by interacting with a placed
workbench, and no station recipe consumes or produces items invisibly.

## M7 — Fuel, on/off state, illumination

- [ ] `FuelConsumer` runtime driven only by `FuelProfile`: accepts tagged
      items in its fuel storage, tracks `fuel_seconds_remaining`, consumes at
      a documented cadence, emits state changes, never ticks while disabled.
      Use game time (paused game does not burn) and document it.
- [ ] Explicit on/off control in the interaction panel; panel shows disabled /
      lit / out-of-fuel / remaining burn time / accepted-fuel hint. A
      non-fuelled profile may opt out of fuel but keeps the generic enabled
      state.
- [ ] `LightEmitter` on `Building`: owns a `PointLight2D`, reads
      `LightProfile`, follows the building, shares one radial
      `GradientTexture2D` mask, enables only at night/twilight when the
      profile allows and the building is enabled/powered. `WorldModulate`
      remains the ambient source.
- [ ] Data-driven animated visual states (fires: unlit/ignite/burning/
      extinguish; torches: off/on/flicker) driven by fuel and toggle events,
      never building-ID checks; texture-pack refresh reloads frames without
      resetting fuel/enabled state.
- [ ] Performance budget: process/enable emitters only within camera
      visibility + margin; pool the shared light texture; cap visible dynamic
      lights with deterministic nearest-first selection; verify the cap on
      the target machine.
- [ ] Persist `enabled`, fuel container/state (and future light state) in the
      building `state` payload; reload restores visual + light state before
      player control resumes.
- [ ] Tests: valid/invalid fuel, partial transfer, burn countdown,
      depletion, pause behaviour, on/off, save/load mid-burn, night/day
      enablement, texture-pack refresh, many-lights performance smoke.

**Exit:** torch/campfire/furnace state is visibly correct after save/load;
fuel cannot be duplicated; night lighting is readable and responsive.

## M8 — Build catalogue expansion

- [ ] Tier 1 timber complete: structural, stair/rail, boundary, exterior, and
      initial interior sets per the catalogue table in the building plan.
- [ ] Tier 2 stone equivalents and upgrades; stable item IDs preserved for
      existing stone pieces.
- [ ] Tier 3 reinforced/metal as data + a technology gate following
      `metalworking`; costs sandbox-tested before balance approval.
- [ ] Migrate stations, chest, torch, and bed onto the generic capability
      references (no parallel storage/fuel/light behaviour).
- [ ] Paths, gates, fences, planters, yard lights, porch/deck pieces, and
      non-functional furniture for homestead layout testing.
- [ ] Recipe, item icon, pickup art, research, tooltip, texture-pack, and
      sandbox-supply coverage for **every** new placeable; every survival
      recipe has an obtainable ingredient chain.

**Exit:** Building Sandbox can build distinct cabins, stone houses, fenced
yards, workshops, and furnished two-story homes without starvation.

## M9 — Art, UX, and presentation

- [ ] Write `docs/BUILDING_ART_REQUESTS.md` naming every cell, dimensions,
      orientation, transparency rule, reference assets, and consuming code —
      covering **both** the building families (structural/boundaries/interior/
      exterior atlases per the building plan) **and** the interactable state
      sheets (chest/campfire/furnace/workbench/torch frames per the
      interactables art brief; shared light mask is a Godot
      `GradientTexture2D`, not PixelLab art).
- [ ] Produce all art through PixelLab with existing Wildfall sheets as style
      references; review at native camera zoom before packing; mechanical
      pack/crop only; verify transparency + exact dimensions before commit.
- [ ] Add every new image to `TexturePackManager.PACK_ASSETS`, stock contact
      card, exported manifest, editable refinement pack, and live refresh
      path; extend `tools/verify_texture_pack.gd` and harness contract checks.
- [ ] Build-palette groups/filters: structure, roof/cover, stairs/rail,
      doors/windows, furniture, stations, boundaries, exterior.
- [ ] Orientation/rotation controls with visible compass/edge preview; rotate
      only when the definition permits; never reinterpret saved orientations.
- [ ] Ghost previews show all reserved tiles/edges, support failures, stair
      endpoints, and roof cutaways — not just a green/red square.
- [ ] Interaction highlight/focus, concise prompts, capacity/fuel errors,
      craft success/failure feedback, animation readable at 32 px.
- [ ] Small Building Sandbox tutorial card: layers, orientation, construction
      story, active story, stairs, roof cutaway, demolish/refund, save/load.

**Exit:** the system is understandable without developer knowledge; art is
readable at native gameplay scale; the pack contract covers every new asset.

## M10 — Save verification, playtest, docs, handoff

- [ ] Verify save/load for a mixed wood/stone, furnished, multi-story house
      (orientation, connector links, health, container/fuel/station state);
      verify a partly demolished staircase cannot strand the player.
- [ ] Run the full verification matrix (below); add the regression coverage
      from both source plans that is not yet present, using data-authored
      fixtures rather than name-based assertions.
- [ ] Real launch/parser check; `git diff --check`; record actual commands,
      dates, and check counts in `docs/TEST_RESULTS.md`.
- [ ] Manual smoke path A (building): place floor/walls/roof → multi-story +
      stairs → walk both floors → demolish/refund → save/load.
- [ ] Manual smoke path B (interactables): craft/place chest → store items →
      save/load → workbench station crafting through slots → fuel a campfire →
      night light test → toggle/extinguish → save/load.
- [ ] Structured sandbox playtest: cabin, two-story cottage, fenced farmyard,
      stone workshop, three-story stress layout; record bugs, screenshots,
      performance.
- [ ] Update `docs/PROJECT_STATE.md`, `docs/ITEM_SYSTEM.md`,
      `docs/SAVE_FORMAT.md`, `docs/TEXTURE_PACKS.md`,
      `docs/INTERACTABLE_AUTHORING.md`, `docs/ROADMAP.md`, and this plan's
      progress log with verified facts only.

**Exit:** clean automated verification, old saves load, authoring docs
describe asset-only additions, sandbox ready for human building experiments.

---

## Verification matrix

Run at the end of every milestone it touches; full matrix at M10.

```text
godot --headless --path . --import
godot --headless --path . --script tests/test_game.gd
godot --headless --path . --script tests/test_building_sandbox.gd
godot --headless --path . --editor --quit   (occasional)
git diff --check
```

Harness additions must cover (accumulating across milestones): generic content
assets load and invalid capability references fail clearly; v1–v8 migration
chain loads and v8 round-trips layered records + capability state; transfers
never lose/duplicate items on partial/full/filtered/split/merge/swap; every
interaction close reason (each twice); non-empty storage demolition policy;
station recipe gates, inputs, output-full failure, technology gates;
fuel acceptance/consumption/toggle/depletion/pause/save-load; ambient +
powered local-light visibility and the light budget smoke; texture-pack export
and live refresh of every new state-sheet path; layered occupancy, canonical
edges, support validation, stair links, active-story collision.

## Explicit deferrals (unchanged from the source plans)

Timed crafting/smelting queues and offline fuel burn; generated/POI loot
containers and loot tables; locks/ownership/multiplayer permissions; dropping
contents on destruction and loot bags; light-driven AI/stealth/warmth/growth
and shadow gameplay; structural physics/collapse; multiplayer construction;
procedural buildings; basements/caves as ordinary stories; unlimited tower
height (four stories is the validated limit); doors, beds, farms beyond the
catalogue's first-pass cosmetic/functional split — later ones arrive as new
profile assets, never parallel interaction code.

---

## Progress log

Append one row per completed milestone. Do not rewrite history.

| Date | Milestone | Status | Evidence / notes |
|------|-----------|--------|------------------|
| 2026-09-14 | M0 | Partially complete | Both source-plan baselines recorded; interactables Phase 0 complete (slot grid fixed, authoring scaffold, scope confirmed); WG-12 resolved the 4 baseline cave-map failures (harness 436/0 on 2026-09-14, commit `5d6cc79` state). Building Sandbox test surface landed in `5d6cc79`. Remaining M0 items: sandbox screenshots, scope-freeze sign-off. |
| 2026-09-14 | M0 | Complete | Sandbox regression screenshots captured (`docs/sandbox_baseline/`, 15-building save/load round-trip verified during capture). Scope frozen: four stories, adjacent-story stairs, no collapse/multiplayer/procedural buildings/iso. Harness 436/0 at start of M1. |
| 2026-09-14 | M1 | Complete | Building content moved to assets: 27 `BuildingDefinition` `.tres` under `data/buildings/` + 11 shared capability profiles under `data/interactables/` (generated by `tools/generate_building_definitions.gd`, values pinned to the old table), `BuildingContentRegistry` with startup validation, `BuildingManager._init_definitions()` deleted. `ItemDefinition.tags` + `fuel` tags. `InventoryStorage` (indexed slots, stack/weight/filter/serialize) now backs `InventoryComponent` behind the unchanged compact API and save format; legacy payloads migrate to deterministic slots on load; `InventoryTransfer` is the single transactional routine (fixed the old `transfer_to` overflow destruction). `Building.placement_key` + `capability_state` added. Verified: focused suite 69/69, full harness 436/0, sandbox 18/0, live headless boot 0 script errors. |
| 2026-09-14 | M2 | Complete | `BuildingRecord` + canonical-key occupancy index replaces the per-tile/story single slot: six layers, normalized edge keys (E==W of neighbour, S==N of the tile below), multi-key footprints, floor+object+overhead coexistence, door/window edge replacement with exact refund, conservative direct-support validator driven by `required_support_tags`/`support_tags`, water-vetoed ground placement, edge-strip collision (doors walkable), and save **v8** layered records with optional `state` (v7 entries migrate by deriving layer from the definition). Verified: placement suite 55/55, full harness 438/0, content suite 69/0, sandbox 0 failures, live boot 0 script errors. |
| 2026-09-14 | M3 | Complete | Active story owned by `BuildingManager` (player mask/z/velocity follow it; E-interaction gated to story 0 until M4). `STORY_RISE` removed: aligned `STORY_Z_STRIDE` render bands with the focus policy (active full / below 25% / above hidden or 14% blueprint in build mode / focus roofs 40%, sandbox R toggle). `ConnectorProfile` stairs: stairwell floor slot reserved by the record itself, edge-triggered up/down traversal with velocity clear, traversal paused in build mode, sandbox `[`/`]` moves the ACTIVE story as the anti-strand escape. Story collision bits (16<<story) make inactive stories unblockable by construction. Verified: stairs suite 37/37, placement 55/0, content 69/0, harness 440/0, sandbox 0, live boot 0. |
| 2026-09-14 | Plan | Created | This combined deployment plan created; source plans retained as design references; scheduling conflicts resolved in the decision log below. |

## Decision log

Dated entries for deliberate deviations from the source plans.

| Date | Decision | Reason / consequence |
|------|----------|----------------------|
| 2026-09-14 | Merged both plans into one milestone sequence (M0–M10). | The two passes modify the same subsystems (`BuildingManager`, save format, content model, art pipeline); a single schedule avoids double rework. |
| 2026-09-14 | Interaction router (M4) and capability state (M5–M7) land after the layered grid (M2) and stairs (M3). | Targeting, prompts, and serialized state must bind to the final placement-record model so nothing is migrated twice. |
| 2026-09-14 | Save bump target is **v8**, applied once at M2. | The interactables plan targeted v6, but v6 (world `generation_version`, WG-12) and v7 (map exploration) are already taken. The record schema changes at M2, so v8 lands there; chest/station/fuel `state` is defined as an optional v8 field from the start and filled in M5–M7 without a second bump. |
| 2026-09-14 | One combined art milestone (M9) and one `docs/BUILDING_ART_REQUESTS.md`. | Both plans require the same PixelLab pipeline, pack integration, and verification; one request file prevents duplicated atlas contracts. |
| 2026-09-14 | `_init_definitions()` migration happens once, in M1. | Both source plans claimed it; doing it twice would conflict. |
| 2026-09-14 | Catalogue expansion (M8) follows stations/fuel/light (M6–M7). | New parts (lanterns, gates, furniture) are then authored purely as data against the finished capability system. |
| 2026-09-14 | M1 keeps the player save payload in the compact format; only the in-memory representation moved to `InventoryStorage`. | Changing the payload without a version bump would break the versioned-save contract; the indexed player payload lands with the v8 bump in M2. `InventoryComponent.deserialize` already accepts both shapes, so v8 becomes a writer-side switch. |
| 2026-09-14 | Door definitions are now walkable (`blocks_movement = false`), and edge walls collide only along their oriented edge strip. | Under the edge model a door is the opening in a wall edge — a built room must be enterable. Data-only change; the save format and item ids are untouched. |
| 2026-09-14 | `BuildingManager` refund target falls back to `refund_inventory` when no player is attached. | API/test placements draw from an explicit inventory; the replacement/demolition refund must pay back into that same inventory, not only `player.inventory`. |
| 2026-09-14 | Railings and stairwell trim content deferred to the M8 catalogue; the connector save model carries them today. | M3's scope is the traversal mechanism; rail families are catalogue authoring and would duplicate M8 work. |
| 2026-09-14 | In Building Sandbox only, `[` / `]` outside build mode move the ACTIVE story and `R` toggles roofs. | The plan's anti-strand debug selector: a demolished stair can leave the player upstairs in tests; survival never offers the escape so no player can phase through floors. |
