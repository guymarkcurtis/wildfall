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
| `visual_family_id`, `atlas_path`, `atlas_cell` | Presentation metadata (column,row) on the atlas sheet. |
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
   empty to use the legacy colour placeholder).
4. Reference shared profiles from `data/interactables/` if the object should
   store, craft, burn, glow, or open.
5. Run the headless harness; validation problems name your file.

The shipped definitions were generated once from the former hard-coded table
by `tools/generate_building_definitions.gd`, which is retained as a reference
for the exact field usage.
