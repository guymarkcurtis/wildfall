# Interactable Authoring

Interactable placed objects (chests, workbenches, campfires, furnaces, torches,
and later doors/loot props) follow **code defines systems, data defines content**.
Generic runtime code owns the *systems* — the interaction router, the slot
inventory, transfers, fuel burn, and light emission. Authored **Resources** own
the *content* — which objects exist, what they can do, how many slots they have,
what fuel they burn, and what light they cast. Adding a normal new interactable
is an **asset‑only** change: duplicate a nearby `.tres`, edit it in the Inspector,
and do **not** add a branch such as `if building_id == "chest"` or
`match station_id` to decide that an object stores items, burns fuel, emits
light, or lists recipes.

> **Status: complete through M10 (2026-09-15).** The contract sections below
> describe the shipped data-driven interaction, storage, station, fuel, light,
> art, save, and texture-pack paths. See `ACTIVE_BUILD_PLAN.md` for the
> completed verification record and deliberate deferrals.

## Before you start

Make normal content changes by duplicating a nearby `.tres` asset under
`data/buildings/` (or the related `data/interactables/` profile it references)
and editing it in Godot's Inspector. Do **not** add the asset to a source
registry and do **not** write an `if id == ...` / `match` branch for a
capability. IDs are stable, lowercase identifiers: changing one after players
have saved a world is a content migration, not a cosmetic rename.

Capabilities are attached through small inspector‑authored profile Resources that
a `BuildingDefinition` references — never through hard‑coded item‑ID lookups in
gameplay code. The runtime reads the profile and behaves generically.

| You are adding | Start from | Put the new asset in |
|---|---|---|
| A placed object (building) | a nearby `BuildingDefinition` | `data/buildings/` |
| An interaction profile | a shipped `InteractionProfile` | `data/interactables/` |
| A container (storage) profile | `chest_container.tres` | `data/interactables/` |
| A station profile (recipes) | `workbench_station.tres` | `data/interactables/` |
| A fuel profile | `fuelled.tres` | `data/interactables/` |
| A light profile | `light_torch.tres` (the wood-tier baseline) | `data/interactables/` — **generator-owned**: shared profiles are written by `tools/generate_building_definitions.gd`, which re-runs idempotently and touches only its own files |
| An appearance/state‑sheet profile | `chest_appearance.tres` | `data/interactables/` |

## The data‑driven rule (final)

Code may define: the interaction router, slot inventories and the single
authoritative transfer routine, fuel‑burn cadence, light emission, animation
state machines, and the save/load serializers. Code may **not** special‑case an
object's identity to pick a capability. Every capability a placed object has is
declared on its content Resources and interpreted by one generic runtime path.
A container, a workbench, a campfire, a furnace, and a torch differ only by
their authored profile data and their saved runtime state — not by code branches.

## Stable identity (final)

A placed record's identity is derived from its placement, not from its node:

```
tile record: "%d:%d:%d:<layer>"
edge record: "%d:%d:%d:edge:<orientation>"
```

The key is stable for the life of that placed record and is the key used for UI
ownership (which panel is open for which object), occupancy, and save data.
Edge keys are canonical, so east/west and north/south spellings of one physical
span cannot double-book. Do **not** use a `NodePath`, creation order, or a
random ID — all three are unstable across save/load and would break state
restoration.

## Save policy (final)

Saves stay JSON, versioned, and module‑based. This pass bumps `SAVE_VERSION`
to **8** (v6 and v7 were taken by the world `generation_version` and map
exploration fields; the layered building record lands with the same bump —
see the ACTIVE_BUILD_PLAN decision log) and **extends the existing
`buildings` module** — it does **not** add a parallel, position‑unsafe object
registry. Each saved building entry gains a `state` dictionary holding only
the non‑default runtime state for the capabilities that building's profile
actually uses:

```json
{
  "item_id": "chest", "x": 3, "y": 3, "story": 0, "health": 50,
  "state": {
    "enabled": true,
    "container": { "slots": [null, {"item_id": "wood", "quantity": 12}], "max_weight": 200.0 }
  }
}
```

Rules: JSON‑safe primitive dictionaries/arrays only; JSON `null` is permitted for
an empty indexed slot; a non‑empty chest inventory must never be omitted; the
v7→v8 migration maps every old flat building record to its equivalent
layered placement **and** adds an empty `state` (or an exactly‑equivalent
loader default), preserving every existing building, player, mission, cave,
and world‑ledger field. Migration must **never** invent chest contents or
turn an old placed campfire on.

## Inventory representation choice (final)

The player inventory moves from the current compact `item_id → {quantity, ...}`
model to a **fixed indexed‑slot** model (`InventoryStorage`): ordered slots,
per‑slot stack limits, weight limits, filter predicates, serialize/deserialize,
and change signals. The **public player‑inventory API is preserved** (Player,
harvesting, crafting, missions, hotbar, and tests keep calling the same
functions); the slot model sits behind that interface. Hotbar ownership/format is
**unchanged** this pass. On load, the old compact inventory migrates into
deterministic indexed slots (full durability for pre‑v5 durable tools); the
compact save format itself is written unchanged until the v8 milestone
switches the player module to the indexed form.

### Slot grid (final — UI capacities, not the item‑type limit)

| Surface | Capacity | Notes |
|---|---|---|
| Chest / general container | **27 slots (9×3)** | Player‑placed storage; contents survive save/load |
| Fuel input | **1 slot** | Accepts items carrying the `fuel` tag |
| Station ingredient inputs | **station‑defined** | Per `StationProfile`: furnace **3**, campfire **3** (their recipes need up to 3 distinct ingredients), workbench **2**, anvil **2**. The panel shows only the slots the selected recipe needs |
| Station output | **1 slot** | Take‑only: results wait here for pickup; drops never land |

These are **UI slot capacities**. They are separate from the player's existing
limit of 50 unique item *types*; raising one does not change the other.
Growing a station's authored input count is save‑safe: older saves with a
shorter validated slot array restore and pad up to the profile count.

### Item tags (final)

`ItemDefinition` gains `tags: PackedStringArray`. This pass tags existing
burnables (`wood`, `coal`, `charcoal`, …) with `fuel` in **data**. A fuel source
accepts items by querying that tag — to be added in Phase 1. Fuel acceptance is always a
data query over tags, never a named item list in gameplay code.

## Initial content set (final — first authored assets)

| Object | Capabilities | Initial rules |
|---|---|---|
| Wood chest | container, open/close animation | 27 slots; contents survive save/load |
| Workbench | station, input/output containers | station recipes; no fuel required |
| Campfire | station, fuel, toggle, light | burns while enabled; lit only while powered |
| Furnace | station, fuel, toggle, light | powered recipes; timed craft with per-recipe `craft_time` |
| Torch | fuel/toggle/light (or perpetual variant) | no container UI unless it needs fuel |

## Schema reference for the profile Resources

Small inspector‑authored Resource types (scripts created and validated in
Phase 1; authored instances from Phase 3 on):

| Resource | Generic responsibility |
|---|---|
| `BuildingDefinition` | placement, footprint, health, collision, appearance, and a reference to an interaction profile |
| `InteractionProfile` | verb, range, prompt, UI kind, allowed capabilities, animation metadata |
| `ContainerProfile` | slot count, max weight, item/tag allow‑list, transfer rules, default contents |
| `StationProfile` | recipe tags/IDs, input/output slot layout, queue policy, powered requirement |
| `FuelProfile` | accepted item tags, seconds/value, capacity, consume cadence, manual toggle |
| `LightProfile` | radius, colour, energy, texture, flicker, daytime policy, requires‑powered |
| `AppearanceProfile` | sprite path, grid layout, named states, frame rate, open/close and idle sequences |

**Light tiers (data, not code).** Light strength scales with building tier
through the profile values each `BuildingDefinition` references — there are
no tier branches in runtime code. The shipped ladder: wood tier
`light_torch` (80 px / energy 1.0) → stone tier `light_stone`
(112 px / 1.35) → metal tier `light_metal` (144 px / 1.7). The primitive
profiles are pinned separately (`light_campfire` 96 px / 1.1,
`light_furnace` 64 px / 0.9) and are not part of the tier ladder. To move a
building to a different tier, re-point its `BuildingDefinition`'s
`light_profile` reference in `data/buildings/*.tres`; to change a whole tier,
edit the profile values in the generator and re-run it. All placed lights
share one centred radial mask — an explicit `FILL_RADIAL` on the 128×128
texture with `fill_from (0.5, 0.5)` → `fill_to (0.5, 0.0)` (a bare
`FILL_RADIAL` defaults to a corner-anchored quarter disc) — with the
player's held light, so tiers read as the same round halo at different
strengths.

Invalid references in any of these fail **at startup** with actionable resource
paths, using the existing content‑validation style (see the world‑content
registry).

## Scope for this pass (final)

Player‑**placed** objects only. Out of scope and deliberately deferred: generated
loot chests / world‑POI containers, multiplayer ownership/locks, timed
crafting‑or‑smelting queues, dropping container contents on destruction, and any
gameplay effects from light (AI, stealth, warmth, growth, cave visibility). The
capability design must not preclude any of these later.

## Authoring walkthroughs

*Filled in as each phase lands.*

- [x] **Phase 1** — `BuildingDefinition` + capability profiles are authored
      under `data/buildings/` and `data/interactables/` (see
      `data/buildings/README.md`). The shipped set was generated by
      `tools/generate_building_definitions.gd` with the exact values of the
      former hard-coded table, so placement, recipes, and old saves resolve
      unchanged; `BuildingManager._init_definitions()` is gone. Burnables
      (`wood`, `coal`, `charcoal`) carry the `fuel` tag in `ItemDefinition.tags`;
      fuel acceptance queries `ItemDatabase.get_items_with_tag("fuel")` /
      `ItemDefinition.has_tag`. Startup validation reports
      `"<asset path>: <problem>"` for every bad reference (see
      `BuildingContentRegistry`); an errored asset removes only itself from
      the palette. The player inventory is backed by indexed-slot
      `InventoryStorage` behind the unchanged compact API; legacy compact
      save payloads migrate into deterministic sorted slots on load (durable
      tools backfill to full), and `serialize()` still writes the compact
      format until the v8 milestone. All transfers go through the
      transactional `InventoryTransfer` (overflow stays in the source;
      nothing is destroyed on a partial target). Stable placement identity:
      `Building.placement_key` = `"%d:%d:%d" % [x, y, story]`, extended with
      the layer by M2.
- [x] **Phase 2** — the interaction router is `InteractionManager` (a plain
      node in `main.tscn`): it scans placed records whose definition carries
      an `InteractionProfile`, picks the nearest in `range_px` (ties broken
      by stable placement key), and publishes the HUD prompt
      (`verb + prompt-or-display-name`, e.g. "E Open Wood Chest").
      `Player._handle_interaction()` consults it after cave-entrance
      priority and before resources/creatures; E with a panel open closes it
      and is consumed. The shared `InteractablePanel` (chrome + player
      inventory view + content area) presents `ui_kind` "container" via the
      M4 view builder — stations register their own builder in Phase 4. The
      shared `StorageGridView` is the one drag/click/shift-click/right-click
      -split/tooltip implementation for every storage surface (read-only
      grids for output slots). All close reasons (escape, button, toggle,
      switched, out-of-range, cave, world reset, removal, damage, death,
      pause) run through one idempotent `InteractionManager.close(reason)`;
      an open panel blocks world clicks (full-rect STOP backdrop) and locks
      movement/firing/building. While open, the object's container storage is
      the record's `InventoryStorage` (seeded from its `ContainerProfile`,
      stack sizes copied from the player database) — moved only via
      `InventoryTransfer`.
- [x] **Phase 3** — the shipped `chest.tres` references the 27-slot
      `chest_container` and `chest_appearance` profiles. Container contents
      serialize only while non-empty as `state.container` (indexed slots and
      JSON-safe primitives); the profile owns the slot count and capacity on
      restore, and malformed container data is discarded safely. Interaction
      open state is transient and never saved. `AppearanceProfile` supplies
      the opening/open/closing/closed transition names, with the existing
      utility atlas used until content supplies a dedicated state sheet.
      Player demolition is generically blocked for any non-empty container,
      with a toast and panel close, so contents are never silently lost.
- [x] **Phase 4** — stations use `StationProfile.recipe_group` to expose only
      matching recipes from their E-interaction panel; C remains hand-crafting
      only. Input/output surfaces are persistent indexed storage under
      `state.station`; autofill uses normal transfers, and immediate craft
      consumes only visible inputs after output can accept the result.
      `wooden_hammer` is the representative workbench recipe. Powered status
      is profile-driven; fuel capacity and timed queues arrive in Phase 5 on
      the same surfaces.
- [x] **Phase 5** — `FuelConsumer` burns only enabled, tagged fuel from its
      profile-owned storage and persists `enabled` / remaining seconds in the
      placed record. The shared panel shows fuel status, time, accepted tags,
      and a generic toggle. `Building` owns profile-driven local lights using
      one radial mask, range culling, and a deterministic nearest-first cap of
      32. Fuelled appearance profiles select authored powered/unpowered names;
      dedicated multi-frame sheets remain Phase 6/M9 art work.
- [x] **Phase 6 / M9–M10** — the PixelLab state sheets, shared
      `GradientTexture2D` light mask, texture-pack manifest/export/refresh
      path, focus frame, toast feedback, and release smoke paths are shipped.
      `tests/test_building_art.gd` validates the 16-sheet contract; M10 adds a
      mixed stateful save/load regression and sandbox layout smoke.
- [x] **Interaction UI overhaul + timed crafting** — the shared panel is
      rebuilt in the inventory's visual language: one centred window with a
      device column beside the player inventory grid, every slot rendered
      with the item icon, stack count, and tooltip. Stations show recipe
      cards (icon, name, craft time, cost tooltip); selecting one lays out
      **one filtered ingredient slot per distinct ingredient** with a
      have/need badge (extra slots hidden; unreturned strays stay visible),
      plus **Fill ingredients** and a primary **Craft** button whose status
      line names what is missing, unpowered, or blocking. Fuel devices show
      a single filtered fuel slot with live burn status and the on/off
      toggle. Crafting is **timed**: `RecipeDefinition.craft_time` (authored
      per recipe, scaling with item tier — glass 5 s … gold ingot 14 s) is
      consumed by `StationCrafting.start_craft`, which validates, consumes
      the inputs up front, and persists a `craft_job` payload in the
      record's capability state. `StationCrafting.tick` (driven from
      `BuildingManager._physics_process`, like `FuelConsumer`) advances the
      job, pauses on power loss, holds on a full output, and survives
      save/load and closed panels; a progress bar and completion toast keep
      the player informed. Results land in the station's **take-only**
      output slot — click, shift-click, drag, or Take moves them to the
      player, and nothing can be dropped back in. Opening any device panel
      closes the standalone inventory window (the panel already hosts the
      player's inventory grid).
- [x] **Round, tier-scaled local lights** — every placed-object light
      (campfire, furnace, torch, hearth, brazier, yard/metal lanterns) now
      renders the same centred round halo as the player's held light, and
      light strength scales with tier in data. `Building._setup_light()`
      anchors the shared 128×128 radial mask at the texture centre
      (`fill_from (0.5,0.5)` → `fill_to (0.5,0.0)`) and uses
      `BLEND_MODE_ADD`, matching the player light exactly (a bare
      `FILL_RADIAL` was corner-anchored and drew an off-centre quarter
      disc). The generator now owns the tier ladder — wood `light_torch`
      (80 px / 1.0), stone `light_stone` (112 px / 1.35), metal
      `light_metal` (144 px / 1.7) — with the primitives pinned
      (`light_campfire` 96 / 1.1,
      `light_furnace` 64 / 0.9). Re-pointing a building to a tier is a
      one-line `light_profile` edit in its `data/buildings/*.tres`
      (hearth + brazier → stone, metal_lantern → metal; yard_lantern +
      torch keep the wood baseline). The handheld lanterns follow the same
      tier scaling through their `ItemDefinition` light fields (common
      torch 200 / 1.25, uncommon stone_lantern 264 / 1.6, rare
      iron_lantern 336 / 2.0), which the player's held light already
      reads — no per-tier code. Covered by `tests/test_light_tiers.gd`
      (37/37).
