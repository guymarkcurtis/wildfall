# Art Requests (Gemini image pipeline)

Brief for the generated-art pass that finishes the sprite-polish task
(PROJECT_STATE.md, NEXT TASK 1). Each request gives the exact output
path, the sheet layout the game code slices, style references, and the
code that consumes the sheet.

Status per request: **PENDING** until the PNG lands in the repo, then the wiring
pass consumes it (creature map update, building-atlas hookup, harness
checks). Flip each to **DONE + date** as files arrive.

## Conventions (apply to every request)

- **Style**: match the existing Wildfall sheets — painterly,
  warm frontier-explorer palette. References:
  `assets/tiles/wildfall-terrain-atlas.png` (world art) and the
  concept images in `assets/concepts/`.
- **Background**: transparent PNG. Each subject should fill roughly
  80–90% of its cell, centered. Note the character sheets bake a light
  checkerboard that `CharacterVisual` strips at load — the creature
  roster loader does **not** strip, so roster backgrounds must be
  true alpha.
- Sheets are sliced by pure grid math (width/columns, height/rows),
  so cell counts must be exact and cells exactly even.

## Request 1 — Creature roster v2 [DONE 2026-09-11]

Sheet landed (2688×1024, cols 0–3 kept from the old sheet, cols 4–6
generated) and `CreatureVisual` was re-wired to the 7-column grid.

- **Output**: `assets/creatures/alien-creature-roster.png`
  (replaces the current sheet)
- **Layout**: 7 columns × 2 rows, **384×512 px per cell**
  (whole sheet 2688×1024). Row 0 = idle pose, row 1 = moving pose
  (same pose family per species).
- **Column order is a code contract — do not reorder**:

  | Col | Species | Note |
  |-----|----------|------|
  | 0 | boar (plated dusk stalker) | keep current art |
  | 1 | deer (moss-backed grazer) | keep current art |
  | 2 | rabbit (quick bone-shell scavenger) | keep current art |
  | 3 | vulture (hovering spore predator) | keep current art |
  | 4 | **wolf** | NEW — aggressive pack predator, dusk-stalker family |
  | 5 | **polar bear** | NEW — large, bulky, pale arctic brute |
  | 6 | **fish** | NEW — swimming alien fish, must read as aquatic even at 32 px |

  Today wolf/polar bear/fish share the boar/deer/vulture sprites
  (the code maps 7 species onto 4 columns); this sheet gives each
  species its own column.
- **Orientation**: art faces +Y (head toward the bottom of the cell)
  — the game rotates the whole sprite toward the movement direction.
- **Reference**: `assets/concepts/alien-creature-roster-concept.png`
- **Consumed by**: `src/entities/creature_visual.gd`
  (`SPECIES_COLUMNS` map + grid constants — the wiring pass updates
  it to the 7-column layout).

## Request 2 — Building parts atlas [DONE 2026-09-11]

Sheet landed (64×288) and `Building` now renders all 18 structural
parts from atlas cells (wood column 0, stone column 1).

- **Output**: `assets/tiles/wildfall-building-parts.png` (new file)
- **Layout**: 2 columns × 9 rows of **32×32 px cells**
  (whole sheet 64×288).
  - Columns: 0 = wood tier, 1 = stone tier.
  - Rows (top → bottom): foundation, floor, wall, window, door, roof,
    stair, ramp, pillar.
- **Style**: top-down orthogonal tile art matching
  `wildfall-terrain-atlas.png`. Each part must read as a single 32px
  grid tile that stacks across the four-story cutaway (walls/floors
  read as tile edges, not freestanding objects). Wood and stone tiers
  must stay visually distinct at 32 px.
- **Background**: transparent (the tile body is inset 2 px and the
  terrain shows through).
- **Reference**: `assets/concepts/frontier-explorer-bases-walk-concept.png`
- **Consumed by**: `src/world/building.gd` — these 18 parts
  (9 part types × wood/stone tiers) used to render as flat colored
  rectangles (`_color_for`); the wiring pass maps part_type + tier → cell.

## Request 3 — Utility building sprites [DONE 2026-09-11]

Sheet landed (160×32); the five utilities now render from their cells
instead of flat color rectangles.

- **Output**: `assets/tiles/wildfall-building-utilities.png`
  (new file)
- **Layout**: 5 columns × 1 row of **32×32 px cells**
  (whole sheet 160×32): 0 torch, 1 bed, 2 chest, 3 farm_soil,
  4 fence. Small props sitting on a tile — transparent background.
  (The campfire / furnace / workbench / anvil stations already have
  art — see Request 4.)
- **Consumed by**: `src/world/building.gd`

## Request 4 — Crafting station atlas v2 [DONE 2026-09-11]

Hand-made sheet landed (128×32, same cell order). One small code
change was still required: `TexturePackManager.get_stock_image()`
generated the station atlas procedurally unconditionally, so it now
loads the repo PNG when present and falls back to the procedural
pixels only when the file is missing.

- **Output**: `assets/tiles/wildfall-crafting-stations.png`
  (replaces the code-generated sheet)
- **Layout**: 4 columns × 1 row of **32×32 px cells**
  (whole sheet 128×32). **Cell order is a contract — do not
  reorder**: 0 campfire, 1 furnace, 2 workbench, 3 anvil.
- The current sheet is generated procedurally in code
  (`TexturePackManager._create_crafting_station_atlas`); a
  hand-made PNG at the same path drops straight in with zero code
  changes.

## After the sheets land (wiring pass — code, not art) [DONE 2026-09-11]

1. `CreatureVisual`: `COLUMNS` 4 → 7; `SPECIES_COLUMNS` now maps
   wolf → 4, polar_bear → 5, fish → 6 (boar/deer/rabbit/vulture keep
   0–3).
2. `Building`: `_atlas_cell()` maps part_type + tier → parts-atlas
   cell and the five utilities → their utility-sheet cell; buildings
   with a cell render a regioned `Sprite2D` and keep the flat
   `_color_for` rectangle only as a fallback (missing art file or no
   cell for the part). `reload_visual_texture()` refreshes the new
   sprites on texture-pack switches.
3. `TexturePackManager`: parts + utilities atlases added to
   `PACK_ASSETS` so packs can override them; the station atlas
   generator is now a missing-file fallback (see Request 4).
4. Harness: 9 new checks (roster 2688×1024, 7 columns, no two species
   share a column, parts atlas 64×288 with all 18 cells drawn,
   utilities atlas 160×32 with all 5 cells drawn, all 4 station
   cells drawn) — 239/239 passing.
