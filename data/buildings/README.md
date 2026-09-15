# Building Content Authoring

Every placeable building part is a `BuildingDefinition` Resource in this
directory — discovered automatically by `BuildingContentRegistry` at startup
(sorted by filename; `id` must be unique and stable). Runtime code interprets
generic fields; it never branches on an id such as `if building_id ==
"chest"`. Adding a normal part is an asset-only change: duplicate a nearby
`.tres`, edit it in the Inspector, and restart or re-seed.

## Definition fields that matter

| Field | Meaning |
|---|---|
| `id` | Stable lowercase identifier; also the `ItemDatabase` item id the part is placed from. Changing it after saves exist is a content migration. |
| `part_type` | Legacy structural role (drives atlas rows and the current support check). New parts should also set `placement_layer`. |
| `placement_layer` | Ground/floor/edge/object/overhead/connector slot for the layered grid (M2). Empty derives from `part_type`. |
| `blocks_movement` / `requires_lower_support` | Current placement rules consumed by `BuildingManager`. |
| `build_cost` | Placement cost entries `{item_id, quantity}`. |
| `technology_id` | Research gate; empty = always available. |
| `support_tags` | What this part PROVIDES to parts above it (`structure`, `cover`). |
| `allowed_orientations` | Orientations offered at placement; empty = single default. |
| `visual_family_id`, `atlas_path`, `atlas_cell` | Presentation metadata: the (column,row) cell on the atlas sheet. `visual_family_id` (wood/stone/metal/primitive) also selects the family placeholder tint while no atlas cell is assigned. |
| `placeholder_color` | Optional per-definition override of the family placeholder tint (clear = use the family colour). |
| `*_profile` references | Capability data: `interaction_profile`, `container_profile`, `station_profile`, `fuel_profile`, `light_profile`, `appearance_profile`, `connector_profile` (vertical traversal — stairs; later ladders/hatches/portals). |

## Capability profiles

Shared profiles live in `res://data/interactables/` and are referenced by
definitions (several parts can share one profile asset). See
`docs/INTERACTABLE_AUTHORING.md` for the authoring rules and the full
data-driven contract. A definition with no profiles is a purely structural or
decorative part.

## Validation

The registry validates every asset at startup: missing/duplicate ids, broken
footprints, malformed build costs, invalid capability profile data, and
unrecognized profile scripts all fail with `"<asset path>: <problem>"`
messages. An errored asset removes only itself from the build palette; the
errors are logged loudly. See `BuildingContentRegistry`.

## Adding a new part (checklist)

1. Duplicate the closest existing `.tres` in this directory and rename it to
   the new stable id.
2. Set `display_name`, `part_type`/`placement_layer`, health, costs, tier,
   and technology gate.
3. Point `atlas_path`/`atlas_cell` at real art (or leave the atlas fields
   empty to use the family placeholder tint, optionally overridden by
    `placeholder_color`).
4. Reference shared profiles from `data/interactables/` if the object should
   store, craft, burn, glow, or open.
5. Run the headless harness; validation problems name your file.

The shipped definitions were generated once from the former hard-coded table
by `tools/generate_building_definitions.gd`, which is retained as a reference
for the exact field usage.

## M8 timber homestead examples

`fence`, `fence_gate`, and `wooden_railing` are all edge-layer assets; the gate
uses the generic `edge_fixture` replacement policy rather than a fence-specific
placement path. `wooden_porch`, `wooden_deck`, and `wooden_path` demonstrate
ground/floor surfaces, while `planter_box` and `wooden_table` are ordinary
object-layer props. `yard_lantern` composes the existing interaction, fuel,
light, and appearance profiles entirely through Resource references.

The Tier 2 `stone_gate`, `stone_railing`, `stone_patio`, `stone_path`, and
`stone_planter` follow the exact same layer and replacement vocabulary with
the `stone_building` research gate; existing stone IDs are not renamed.

The first reinforced family (`reinforced_floor`, `reinforced_wall`,
`metal_roof`, `metal_gate`, `metal_railing`, `metal_grate`) uses only the
existing `metalworking` gate and placement vocabulary. It is content, not a
parallel metal-building system; balance values remain subject to M8 sandbox
playtesting.

## M8 furniture catalogue

Nineteen homestead pieces complete the catalogue, authored as data against the
finished capability system.

The `wood_building` interior set: `chair`, `shelf`, `wardrobe`, and `steps`
are ordinary object-layer props; `rug` is the one walkable piece — placed on
the ground layer with movement left unblocked; `awning` is a roof-part
overhead cover keeping the default below-support rule; `corner_post` is a
pillar that provides the `structure` support tag.

The `stone_building` interior set: `hearth` and `brazier` compose the same
interaction/fuel/light/appearance profile set as `yard_lantern` (the brazier
takes a secondary iron ingredient but keeps the stone research gate);
`cabinet`, `bookcase`, and `well` are decorative object-layer props.

The `metalworking` furniture set: `shuttered_window` uses the same
edge-layer + `edge_fixture` replacement contract as the wood/stone windows;
`metal_stair` reuses the existing stair `connector_profile`; `metal_fence`
is an oriented edge boundary with no lower-support requirement;
`signal_pole`, `metal_lantern` (walkable), `workshop_cabinet`, and
`metal_locker` are object-layer props — the cabinet and locker intentionally
have no container profile in this pass; a future storage variant is an
asset-only profile reference, not a separate runtime path.

Every new part carries a native 32×32 pickup icon in
`TexturePackManager.PACK_ASSETS` and a hand-crafted recipe, so each is
placeable from the C-key panel and grantable from the Building Sandbox supply
store with no further wiring. Metal costs were sandbox-verified against the
reinforced family's 1–4 ingot range (iron chain: 2 ore → 1 ingot at the
furnace, pre-placed in the sandbox yard; the store grants ingots directly)
and needed no tuning.
