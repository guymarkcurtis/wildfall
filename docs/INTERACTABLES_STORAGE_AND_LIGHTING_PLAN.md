# Interactables, Storage, Stations, Fuel, and Lighting Plan

> **Superseded as the active schedule.** Work order, merged checklist, and
> progress tracking now live in [`docs/ACTIVE_BUILD_PLAN.md`](ACTIVE_BUILD_PLAN.md)
> (this plan's Phases 1–6 map to milestones M1, M4–M7, M9, M10). This
> document remains the detailed design reference for capability profiles, the
> interaction router, transfer semantics, the PixelLab art brief, and the
> building `state` save payload. Note: its "bump to v6" predates save v6/v7;
> the combined plan bumps to v8 (see the combined plan's decision log).

## Purpose and current state

This is the implementation handoff for the next Riftwake development pass.
It adds a reusable interaction system for placed objects, beginning with
storage, crafting stations, and fuelled light sources. It is deliberately a
sequence of independently shippable phases: complete the checkbox list at the
end of a phase, run its verification, update the status block below, and only
then begin the next phase.

**Owner:** Quen 3.8

**Plan status:** `IN PROGRESS`

**Last reviewed:** 2026-09-14
**Current implementation checkpoint:** Phase 1 — General inventory and content foundation (Phase 0 complete)

### Existing systems to preserve

- `BuildingManager` owns all player-placed `Building` nodes and serializes
  them through the `buildings` save module.
- `Building` already has stable `item_id`, tile, story, health, collision, and
  atlas-backed visuals. Its utility/station identity is currently hard-coded;
  this pass must replace that *behavioural* lookup with content data rather
  than add more item-ID branches.
- `Player._handle_interaction()` currently prioritizes cave entrances, then
  resource harvesting/creature attacks. It has no generic placed-object
  interaction step.
- The player inventory is an `InventoryComponent`, but it is a compact
  `item_id -> stack` model. The existing InventoryPanel's slots are a display
  grid and hotbar-assignment UI, not independently addressable storage slots.
- Crafting is immediate, takes ingredients from the player's inventory, and
  only checks whether a matching placed station is within 72 pixels. The
  existing `CraftingStation`, `StationManager`, and `StationPanel` are legacy,
  unwired code; do not extend them.
- Day/night already controls `WorldModulate` via `DayNightCycle`. The old
  `LightingManager` targets a nonexistent scene node and is not wired; replace
  or retire it as part of the lighting phase rather than attempting to revive
  its old node path.
- Saves are JSON, versioned (`SAVE_VERSION = 5`), module based, and migrate
  old versions. Buildings are restored after the deterministic world has been
  regenerated. Player-created object state belongs in the placed-building
  save payload; do not serialize procedural chunks or untouched world data.

### Non-negotiable architecture decisions

1. **Code defines systems; Resources define content.** Do not write branches
   such as `if building_id == "chest"` or `match station_id` to decide that an
   object stores inventory, burns fuel, emits light, or shows recipes. Add
   generic capabilities to a content resource and author each object under
   `data/buildings/` (and any related `data/interactables/`) instead.
2. A placed object has a stable identity derived from its existing placement
   coordinates: `"%d:%d:%d" % [tile.x, tile.y, story]`. It is stable for the
   life of that placed building and is the key for UI ownership and save data.
   Do not use `NodePath`, creation order, or a random ID.
3. Use one generic `InteractableBuilding`/capability runtime path. A container,
   workbench, campfire, furnace, torch, and later doors/looting props differ
   only by authored capability data and their saved runtime state.
4. Interactions are mutually exclusive: an object UI locks player movement,
   blocks firing/harvesting/build placement, closes with Escape or moving out
   of range, and restores normal input exactly once. Opening another object
   closes the current one first.
5. Transfer operations are transactional. Never remove from the source until
   the destination has accepted the actual quantity. Overflow is returned to
   the source; it is never silently deleted or spawned into the world unless a
   future explicit drop action says so.
6. The first milestone supports *player-placed* objects only. Generated POIs
   and multiplayer ownership/locking are out of scope; the capability design
   must nevertheless not preclude them.

## Target player experience

- Press **E** while near a chest to open it. The chest animates open, the
  player sees backpack and chest side by side, and can click/drag or
  shift-click items in either direction. Escape, leaving range, demolition,
  death, loading, or opening another object closes it safely.
- Press **E** near a workbench to open a station window. It lists only the
  recipes available at that station, has explicit input/output inventory
  slots, and permits crafting only when those slots contain the recipe's
  ingredients. The initial crafting queue is immediate; timed jobs are a
  later extension point.
- Press **E** near a campfire/furnace to open its station window. Fuel can be
  deposited in a dedicated fuel slot, is consumed over authored burn time,
  and powers the light/active visual. A torch can be toggled on/off; fuelled
  emitters only shine while enabled and fuelled. A non-fuelled future light is
  an asset/data-only addition.
- Night has a readable ambient darkening layer and local pools of warm light.
  Lights are cosmetic in this pass: they do not yet change creature AI,
  stealth, temperature, growth, or world generation.

## Content model (implement before object-specific behaviour)

Create small, inspector-authored Resource types. Names below are suggested;
consistent equivalents are acceptable.

| Resource / field group | Generic responsibility | Example authored values |
| --- | --- | --- |
| `BuildingDefinition` | Placement, footprint, health, collision, appearance, and a reference to an interaction profile | chest, workbench, campfire, torch |
| `InteractionProfile` | `verb`, range, prompt, UI kind, allowed capabilities, animation metadata | `Open`, 64 px, `Chest`, `container` |
| `ContainerProfile` | slot count, max weight, item/tag allow-list, transfer rules, default contents | chest: 27 slots; fuel input: 1 slot and `fuel` tag |
| `StationProfile` | recipe tags/IDs, input/output slot layouts, queue policy, powered requirement | workbench recipe group; furnace requires powered |
| `FuelProfile` | accepted item tags, seconds/value, capacity, consume cadence, can manually toggle | wood/coal/charcoal, 300 s/unit |
| `LightProfile` | radius, colour, energy, texture, flicker, daytime policy, requires-powered | torch/campfire warm local light |
| `AppearanceProfile` | sprite path, grid layout, named states, frame rate, open/close and idle sequences | chest closed/open; fire unlit/ignite/burning |

Item data must expose tags (at minimum `fuel`; later `ore`, `food`, etc.) or a
generic equivalent. A campfire's fuel acceptance is a data query over those
tags, never a named list in gameplay code. Place these discoverable authored
assets under `data/buildings/` and `data/interactables/`, alongside README
authoring notes. Move the current runtime `_init_definitions()` entries into
assets as part of Phase 1 or make it a backward-compatible temporary fallback
that is deleted before Phase 2 is marked complete.

The first authored content set is:

| Object | Capabilities | Initial rules |
| --- | --- | --- |
| Wood chest | container, open/close animation | 27 slots; contents survive save/load and remain when closed |
| Workbench | station, input/output containers | station recipes; ingredient inputs + output; no fuel required |
| Campfire | station, fuel, toggle, light | accepts `fuel`; burns while enabled; supplies cooking recipes; lit only while powered |
| Furnace | station, fuel, toggle, light | accepts `fuel`; powered recipes; initial immediate craft only, with input/output slots ready for future timed smelting |
| Torch | fuel/toggle/light or explicitly authored perpetual-light variant | no container UI unless it needs fuel; emits only when on/powered |

## Phase plan and checklist

### Phase 0 — Confirm design contract and baseline

**Goal:** agree the boundaries before changing save or inventory code.

- [x] Read this plan and record any conscious design changes in the log below.
- [x] Run the existing headless harness and parser/import check; record their
  result in `docs/TEST_RESULTS.md` without rewriting older results.
- [x] Create a short `docs/INTERACTABLE_AUTHORING.md` skeleton that states the
  data-driven rule, asset locations, stable identity rule, and save policy.
- [x] Decide and document the initial container slot grid: use 27 general
  chest slots (9×3), one fuel slot, station-defined ingredient slots, and one
  output slot. These are UI capacities, separate from the player's 50 unique
  item-type limit.
- [x] Confirm scope: no generated loot chests, no multiplayer locks, no timed
  production queue, and no gameplay effects from light in this pass.

**Exit criteria:** the document names the migration target (save v6), the
inventory representation choice, the first content assets, and has a clean
baseline result.

### Phase 1 — General inventory and content foundation

**Goal:** enable real slot inventories and data-authored placed buildings
without changing player-facing interaction yet.

- [ ] Add `InventoryStorage` (or refactor `InventoryComponent` behind a
  compatible interface) with fixed indexed slots, per-slot stack limits,
  weight limits, filter predicates, serialize/deserialize, and change
  signals. Retain the public player inventory API used by Player, harvesting,
  crafting, missions, hotbar, and tests.
- [ ] Preserve current player save compatibility. Migrate the old compact
  `{item_id: {quantity, ...}}` player inventory into deterministic indexed
  slots, including full durability for pre-v5 durable tools. Do not change
  hotbar ownership/format in this phase.
- [ ] Implement `InventoryTransfer.transfer(source, source_slot, target,
  target_slot, requested_quantity)` as the single authoritative transfer
  routine. Cover merge, swap, split, filtered slot rejection, max stack,
  max weight, and partial acceptance.
- [ ] Add an explicit `ItemDefinition.tags: PackedStringArray` or equivalent;
  tag existing burnables as `fuel` in data and have no ID-based fuel lookup.
- [ ] Add generic interaction, container, station, fuel, light, and appearance
  Resource scripts and their validation methods. Make invalid references fail
  at startup with actionable resource paths, using the existing content
  validation style.
- [ ] Load `BuildingDefinition` assets from `data/buildings/` deterministically
  by stable ID. Migrate the current utility/station entries out of
  `BuildingManager._init_definitions()`; retain existing IDs so placement
  recipes and old saves still resolve.
- [ ] Extend `Building` with a runtime capability-state dictionary and stable
  placement key, but keep physical collision/placement/story behaviour intact.
- [ ] Add unit tests for storage serialization, legacy player inventory
  migration, complete/partial/rejected transfers, slot filters, and authored
  definition validation.

**Exit criteria:** no live gameplay behaviour changes are necessary yet, but
data can define a storage or fuelled object; old v5 saves load; all inventory
paths use the safe transfer API where relevant.

### Phase 2 — Interaction router and shared object UI

**Goal:** one reliable way to target, open, operate, and close an object.

- [ ] Add an `Interactable` runtime component/interface to placed buildings;
  it exposes `can_interact(player)`, prompt metadata, `interact(player)`, and
  `close(reason)` without type/name branches.
- [ ] Add an `InteractionManager` under Main (or equivalent) as the single
  owner of the current target/current open object. It finds valid placed
  interactables in authored range, resolves deterministic priority by
  distance then stable key, and publishes an HUD prompt such as `E Open
  Chest`.
- [ ] Insert this router into `Player._handle_interaction()` after cave
  entrance priority but before resource/creature handling. Preserve build-mode
  suppression, cave handling, tool durability rules, and UI input blocking.
- [ ] Add an `InteractablePanel` scene/script containing a title, close button,
  common backdrop, contextual help, player inventory view, and a content area
  supplied by the active profile. Do not duplicate an inventory rendering
  implementation per chest/station.
- [ ] Extract/reuse a slot-grid control from `InventoryPanel` so player,
  chest, fuel, ingredient, and output storage all use one drag/drop and
  tooltip implementation. Add left click select, drag/drop, shift-click
  quick transfer, deterministic stack split (right click opens a quantity
  picker or transfers half), and disabled/read-only output slots.
- [ ] Define close behaviour for Escape, close button, opening another object,
  moving outside authored range, entering a cave, loading/new seed, building
  removal/damage, death, pause/title transition, and scene shutdown. Ensure
  each is safe when it occurs twice.
- [ ] Add an accessibility-safe prompt/keyboard path: focus remains in UI;
  Escape always closes the topmost panel; world clicks cannot leak through.
- [ ] Test targeting priority, prompt visibility, input lock, every close
  reason, and switching directly from one object to another.

**Exit criteria:** a test-only/data-authored empty container can be opened and
closed by E without a double input, stuck movement, or world interaction.

### Phase 3 — Chests and persistent storage

**Goal:** finish a usable chest as the first complete vertical slice.

- [ ] Author `data/buildings/wood_chest.tres` (or matching established naming)
  with a 27-slot container profile, `Open` prompt, chest appearance profile,
  existing stable `chest` item ID, and no special-case code.
- [ ] Wire the chest panel to render player inventory and chest storage side by
  side. It must support drag/drop, quick transfer in both directions, stack
  merge/swap/split, item tooltips, empty state, and capacity/weight feedback.
- [ ] Add chest open/close animation states. The object should not become
  logically open until the opening transition begins; closing must reverse or
  play the close transition even when forced by range/load/removal.
- [ ] Serialize per-building runtime state inside its existing building entry:
  `state: {container: <serialized indexed storage>, enabled: true, ...}`.
  Omit empty/default state fields where practical, but never omit a non-empty
  chest inventory. Use JSON-safe primitive dictionaries/arrays only.
- [ ] Bump `SAVE_VERSION` to **6**. The v5→v6 migration adds an empty `state`
  dictionary to saved buildings (or loader-default behaviour that is exactly
  equivalent) and preserves every old building, player, mission, cave, and
  world ledger field.
- [ ] Define demolition/destruction behaviour now: **block demolition while a
  chest contains items**, show a clear message, and close the panel. Do not
  silently refund/delete contents. A future empty-on-destruction/drop-loot
  policy can be added deliberately later.
- [ ] Verify save → quit/reload → open chest retains exact contents; save with
  chest panel open must not save UI-open state as gameplay state; loading a
  save removes any stale active panel.

**Exit criteria:** a player can craft/place/open/fill/empty a chest and lose
nothing across save/load; a non-empty chest cannot be demolished.

### Phase 4 — Station panels and recipe inputs/outputs

**Goal:** turn placed workbenches and production stations into the way
players use their recipes.

- [ ] Replace C-key's global “nearby station” crafting experience with a clear
  split: C may remain a *hand-crafting* panel for recipes with no station;
  recipes requiring a station open only from E-interaction with that station.
  Do not silently remove a useful hand-crafting path.
- [ ] Author workbench/campfire/furnace/anvil `StationProfile` assets. Recipe
  eligibility is data-defined by profile IDs/tags; remove reliance on the
  hard-coded `CRAFTING_STATION_IDS` list and named station branches.
- [ ] Implement the station view: recipe list/filter/detail, player inventory,
  station ingredient slots, result output slot, contextual status, and close
  controls. Station input/fuel/output containers are actual persistent
  inventories, not temporary visual counters.
- [ ] Define deterministic immediate craft semantics: selecting a recipe fills
  authored input slots through normal transfers or uses already placed
  ingredients; Craft consumes exactly those inputs and inserts the result into
  the output slot. Disable Craft if the output cannot accept the result.
- [ ] For the workbench, ship a small representative set of existing
  workbench recipes. Preserve recipe IDs, research gates, and game-mode
  (creative/survival) policy. Create an adapter/migration so existing recipes
  continue to work instead of duplicating their definitions.
- [ ] For furnace/campfire, show powered/unpowered state and fuel capacity,
  but leave timed queues for the next milestone. The immediate pipeline must
  still use the same input/output containers that timed jobs will later use.
- [ ] Update all relevant crafting tests for station UI opening, recipe
  restriction, inputs, output-full rejection, research gates, and save/load
  of station inputs/outputs.

**Exit criteria:** the player must interact with a placed workbench to craft a
workbench recipe, ingredients are visibly moved through station slots, and no
station recipe can consume or produce items invisibly.

### Phase 5 — Fuel, on/off state, and illumination

**Goal:** make fires and placed lights legible, persistent, and efficient.

- [ ] Add a `FuelConsumer` runtime driven only by `FuelProfile`: it accepts
  valid tagged items in its fuel storage, tracks `fuel_seconds_remaining`,
  consumes fuel at a documented cadence, emits state changes, and never ticks
  while disabled. Use game time/day-night time deliberately and document
  whether fuel continues during pause and autosave (recommended: game time;
  paused game does not burn).
- [ ] Add explicit controls to turn an object on/off. The interaction panel
  must show disabled, lit, out of fuel, remaining burn time, and accepted fuel
  hint. A non-fuelled content profile may opt out of fuel but retains the same
  generic enabled state.
- [ ] Add a `LightEmitter` component to `Building`. It owns a `PointLight2D`
  (or chosen Godot 2D equivalent), reads `LightProfile`, follows the building,
  uses a shared radial `GradientTexture2D`/light mask, and only enables at
  night/twilight when the profile says so and the building is enabled/powered.
  Keep the scene's existing `WorldModulate` as the ambient-darkness source.
- [ ] Add data-driven animated visual states: unlit/idle/ignite/burning/extinguish
  for fires and off/on/flicker for torches. State changes from fuel and toggle
  events, not from building ID checks. Ensure texture-pack refresh reloads
  these frames without resetting fuel or enabled state.
- [ ] Establish a performance budget: only process/enable emitter nodes within
  camera visibility plus a small margin; pool/reuse the shared light texture;
  cap visible dynamic lights with deterministic nearest-first selection;
  verify the chosen cap on the target machine. Do not create one bespoke
  texture or per-frame tween for every placed torch.
- [ ] Persist generic `enabled`, fuel container/state, and any future light
  state in the building `state` payload. Reload must restore visual and light
  state before player control resumes.
- [ ] Add tests for valid/invalid fuel, partial fuel transfer, burn countdown,
  depletion, pause behaviour, on/off, save/load mid-burn, night/day light
  enablement, texture pack refresh, and a many-lights performance smoke test.

**Exit criteria:** torch/campfire/furnace state is visibly correct after save
load; fuel cannot be duplicated; night local lighting is visible; the test
scene remains responsive with the agreed number of emitters.

### Phase 6 — Art, polish, authoring docs, and release pass

**Goal:** finish production presentation and leave an extensible authoring
surface.

- [ ] Complete the PixelLab art requests below and add the new paths to
  `TexturePackManager.PACK_ASSETS`, its stock contact card, exported
  manifest, editable refinement pack, and live refresh path.
- [ ] Add interaction highlight/focus treatment, concise on-screen prompt,
  capacity/fuel errors, crafting success/failure feedback, and animation
  timing that remains readable at 32 px.
- [ ] Update `docs/INTERACTABLE_AUTHORING.md`, `docs/SAVE_FORMAT.md`,
  `docs/TEXTURE_PACKS.md`, `docs/PROJECT_STATE.md`, and `docs/ROADMAP.md`.
  State exactly what is complete, the new save version, how to author a new
  object, and the deliberate deferrals (timed jobs, generated loot, gameplay
  light effects).
- [ ] Add a regression section to `tests/test_game.gd` and focused tests where
  appropriate. Tests must use data-authored fixtures rather than relying on
  chest/campfire names to prove generic behaviour.
- [ ] Run the complete verification matrix below. Record the actual command
  results/date/check count in `docs/TEST_RESULTS.md`.
- [ ] Manually play the smoke path: craft/place chest → store items → save/load
  → place/interact with workbench → craft through station slots → add fuel to
  campfire → night test → toggle/extinguish → save/load.

**Exit criteria:** all phases are checked off, authoring docs describe an
asset-only addition, PixelLab art respects the pack contract, all automated
checks pass, and the manual smoke path has no data loss or input leak.

## PixelLab.ai art-production brief

Use the **PixelLab.ai MCP** for new raster game art. Do not use another image
generator for shipped Riftwake game assets. Start by exporting the stock
texture reference card in-game: **Options → Export Stock Texture Card +
Reference**, then **Create / Open Editable Refinement Pack**. Give PixelLab
the contact card plus the relevant original sheets from
`user://texture_packs/refinement/stock_reference/` as references. Preserve
the current warm, painterly frontier-explorer pixel style, top-down orthogonal
view, true alpha background, crisp nearest-neighbour pixels, and the exact
canvas/frame contract below.

PixelLab should produce each object as a separate transparent PNG. Mechanical
packing/cropping/resampling is allowed after generation, but it must not alter
frame order or add an opaque background. Before committing, inspect the PNG
at native size, verify transparency and exact dimensions, then place it in
both the stock asset path and an exported texture-pack reference/manifest
entry. Use the existing `tools/verify_texture_pack.gd` workflow and add
contract checks to the harness.

| Asset | Output path | Canvas and frame contract | PixelLab prompt focus |
| --- | --- | --- | --- |
| Chest states | `assets/tiles/interactables/wood_chest.png` | 32×96; 1 column × 3 frames, top→bottom: closed, half-open, open. Close plays reverse. | A sturdy hand-built frontier wooden chest, visible lid and brass/iron clasp, orthogonal top-down prop, same silhouette across lid states, transparent background. |
| Campfire states | `assets/tiles/interactables/campfire.png` | 32×160; 1×5 frames: unlit embers, ignition, burn A, burn B, burn C. Burning loops frames 2–4; extinguish reverses to 0. | Stone-ring campfire with wooden fuel, warm orange flame that reads against dark ground, restrained flicker, no smoke extending outside frame. |
| Furnace states | `assets/tiles/interactables/furnace.png` | 32×96; 1×3: cold, heating, lit. Lit may use a subtle shader/alpha flicker rather than additional art frames. | Compact stone frontier furnace, readable dark mouth when cold and warm glowing mouth when lit. |
| Workbench states | `assets/tiles/interactables/workbench.png` | 32×64; 1×2: idle, in-use/open. | Practical wooden workbench with tools/materials, top-down, a subtle active cue in second frame, no character. |
| Torch states | `assets/tiles/interactables/torch.png` | 32×128; 1×4: unlit, ignite, flame A, flame B. Burning loops 2–3. | Wall/ground torch appropriate to the existing utility tile, warm compact flame, high readability at 32 px. |
| Shared light mask | Godot `GradientTexture2D` resource, not PixelLab art | 128×128 soft radial alpha/white mask, shared by every PointLight2D. | Build this in Godot from a gradient so it is smooth, tintable, compact, and not an atlas asset. |

The existing `assets/tiles/wildfall-building-utilities.png` (5×1: torch,
bed, chest, farm soil, fence) and `wildfall-crafting-stations.png` (4×1:
campfire, furnace, workbench, anvil) remain legacy placement/preview atlas
contracts. Do not insert frames into either file. Once the new state sheets
are adopted, generic appearance data selects the appropriate state sheet at
runtime; keep an intentional fallback to the legacy cell only until all
profiles/art are present.

## Save schema target (v6)

Keep the existing `buildings` module and extend each entry instead of adding a
parallel, position-unsafe registry:

```json
{
  "item_id": "chest",
  "x": 3,
  "y": 3,
  "story": 0,
  "health": 50,
  "state": {
    "enabled": true,
    "container": { "slots": [null, {"item_id": "wood", "quantity": 12}], "max_weight": 200.0 },
    "fuel": { "slots": [null], "fuel_seconds_remaining": 0.0 },
    "station": { "inputs": {"slots": []}, "outputs": {"slots": []} }
  }
}
```

Only profiles that use a capability write that capability's non-default
payload. JSON `null` is permitted for an empty indexed slot. The deserializer
must reject/ignore malformed fields safely, preserve valid items, default
missing state, and validate item IDs/quantities/slot limits. Migration must
never invent chest contents or turn old placed campfires on.

## Verification matrix

Run at the end of every phase affected by the change and record final results
at Phase 6:

```text
godot --headless --path . --import --quit
godot --headless --path . --script tests/test_game.gd
godot --headless --path . --editor --quit
git diff --check
```

The harness additions must cover:

- generic content assets load and invalid capability references fail clearly;
- v1–v5 saves still migrate/load and v6 round-trips building state;
- player and chest slot transfer never loses/duplicates items on partial/full
  targets, invalid filters, split, merge, or swap;
- opening/closing/range/removal/load input-state safety;
- non-empty storage demolition policy;
- workbench recipe gate, inputs, output-full failure, and technology gate;
- fuel acceptance/consumption/toggle/depletion/pause/save-load behaviour;
- ambient day/night plus powered/unpowered local light visibility and light
  budget smoke test;
- texture-pack export and live refresh of every new state-sheet path.

## Implementation log

Update this block at the end of every completed phase. Keep completed items
checked above; do not rewrite the plan to hide deferred work.

| Date | Phase | Status | Evidence / notes |
| --- | --- | --- | --- |
| 2026-09-14 | 0 | Not started | Plan authored; repository still uses save v5, compact item-keyed inventory, global C-key nearby-station crafting, and day/night ambient modulation only. |
| 2026-09-14 | 0 | Complete | Baseline recorded on Godot 4.7.2 headless at HEAD `53dd78e`: `--import` exit 0, harness `tests/test_game.gd` 427 passed / 4 failed / 0 script errors, `--editor --quit` exit 0, `git diff --check` clean. All 4 failures are the new cave-map checks added in `53dd78e` (see TEST_RESULTS.md). Probe over 3 fresh random boot seeds (224031, 940267, 989406) shows map cave count == streamed-chunk cave count on every seed (9/9, 32/32, 13/13), so the map code is correct and the failures are a seed/coverage property: that run's random boot seed produced a finite world with zero cave entrances (mountain tiles ~0.86–2.5% of the 4.19M-tile world; cave entrances gated on rocky/mountain suitability), while the tests assert "at least one cave marker in the finite world". World-gen does not guarantee >=1 cave per seed. Routed to the world-gen workstream (guarantee >=1 cave entrance, or make the cave-map checks tolerant of a 0-cave world); out of scope for this interactables pass per AGENTS.md (cave generation/reset policy remains separate and undecided). Phase 0 deliverables: this log, the updated TEST_RESULTS.md baseline, and the `docs/INTERACTABLE_AUTHORING.md` scaffold. No Phase 1 code started. |

## Explicit deferrals after this pass

- Timed crafting/smelting queues, output collection automation, and offline
  fuel burn calculations.
- Generated/world-POI loot containers and deterministic loot tables.
- Locks, ownership, multiplayer concurrency, theft, and permissions.
- Dropping container contents on destruction and a loot-bag entity.
- Light-driven AI, stealth, warmth, crop growth, cave visibility mechanics,
  shadows, and large-scale lighting gameplay effects.
- Doors, beds, farms, and other interactables. They should be added later by
  new profile assets using this system, not by creating parallel interaction
  code.
