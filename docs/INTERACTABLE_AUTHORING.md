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

> **Status: Phase 0 skeleton.** The contract sections below (data‑driven rule,
> asset locations, stable identity, save policy, slot grid, initial content) are
> agreed and final for this pass. The per‑object authoring walkthroughs and the
> validation/error‑message details are marked **Pending** and will be filled in
> as their phases land (Phases 1‑5). See
> `INTERACTABLES_STORAGE_AND_LIGHTING_PLAN.md` for the phase breakdown.

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
| A placed object (building) | `wood_chest.tres` (Phase 3) | `data/buildings/` |
| An interaction profile | a shipped `InteractionProfile` | `data/interactables/` |
| A container (storage) profile | the chest `ContainerProfile` (Phase 3) | `data/interactables/` |
| A station profile (recipes) | the workbench `StationProfile` (Phase 4) | `data/interactables/` |
| A fuel profile | the campfire `FuelProfile` (Phase 5) | `data/interactables/` |
| A light profile | the torch `LightProfile` (Phase 5) | `data/interactables/` |
| An appearance/state‑sheet profile | the chest `AppearanceProfile` (Phase 3) | `data/interactables/` |

## The data‑driven rule (final)

Code may define: the interaction router, slot inventories and the single
authoritative transfer routine, fuel‑burn cadence, light emission, animation
state machines, and the save/load serializers. Code may **not** special‑case an
object's identity to pick a capability. Every capability a placed object has is
declared on its content Resources and interpreted by one generic runtime path.
A container, a workbench, a campfire, a furnace, and a torch differ only by
their authored profile data and their saved runtime state — not by code branches.

## Stable identity (final)

A placed object's identity is derived from its placement, not from its node:

```
placement_key = "%d:%d:%d" % [tile.x, tile.y, story]
```

The key is stable for the life of that placed building and is the key used for
UI ownership (which panel is open for which object) and for save data. Do **not**
use a `NodePath`, creation order, or a random ID — all three are unstable across
save/load and would break panel ownership and state restoration.

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
| Station ingredient inputs | **station‑defined** | Per `StationProfile`; workbench/campfire/furnace differ |
| Station output | **1 slot** | Disabled/read‑only until a craft fills it |

These are **UI slot capacities**. They are separate from the player's existing
limit of 50 unique item *types*; raising one does not change the other.

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
| Furnace | station, fuel, toggle, light | powered recipes; immediate craft only this pass |
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
- [ ] **Phase 2** — the interaction router: how `InteractionProfile` range/verb
      map to the HUD prompt and to `Player._handle_interaction()` priority.
- [ ] **Phase 3** — author a chest end‑to‑end (`.tres` + 27‑slot container +
      open/close appearance + save `state`).
- [ ] **Phase 4** — author a station (workbench/campfire/furnace) and route its
      recipes through the `StationProfile` (removing `CRAFTING_STATION_IDS`).
- [ ] **Phase 5** — author fuel and light (`FuelProfile`, `LightProfile`,
      animated state sheets); the shared light mask and the light budget.
- [ ] **Phase 6** — art contract (PixelLab state sheets + shared
      `GradientTexture2D` light mask) and the texture‑pack manifest entries.
