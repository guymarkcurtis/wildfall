# Building & Interactable Art Requests (M9)

Status: **complete** — M9 art was packed and M10 release-verified on
2026-09-15. This file is the
authoritative per-cell production contract for every new raster asset the
milestone ships. Before generation, re-read §1 (pipeline) and §2 (global
rules); every prompt in §3/§4 starts from the shared style preamble in §2.3.

Scope covered here:

- **Family A — building atlases** (per the building plan's "Initial art
  production contract"): `structural_<tier>.png`, `boundaries_<tier>.png`,
  `interior_<tier>.png` for each of the three tiers, plus one shared
  `exterior_props.png`. 10 sheets total.
- **Family B — interactable state sheets** (per the interactables plan's
  "PixelLab.ai art-production brief"): `wood_chest.png`, `campfire.png`,
  `furnace.png`, `workbench.png`, `torch.png`, plus one shared sheet the
  brief's table does not list (see deviation D1): `hearth.png`. 6 sheets
  total.
- The shared PointLight2D **light mask is not art**: it stays a Godot
  `GradientTexture2D` built in code (`building.gd::_setup_light`, 128×128
  radial white→transparent). Nothing in this document generates a light mask.
- Legacy atlases `wildfall-building-parts.png` (2×9),
  `wildfall-building-utilities.png` (5×1) and
  `wildfall-crafting-stations.png` (4×1) are **not modified** — no frames
  are inserted into either legacy file. After the def migrations in §6 the
  2×9 parts atlas is a shipped reference sheet with no remaining definition
  references. The 5×1 sheet keeps only its torch (0,0) and chest (2,0)
  cells, and the 4×1 sheet keeps all four, as the documented fallback /
  palette-base references for those parts (their in-world presentation is
  the state sheet, §4); bed, fence and farm_soil move off the 5×1 onto
  the new sheets in §6.2.

---

## 1. Production pipeline (all cells)

1. **Generator.** PixelLab MCP only (`create_image_pro_flash`, poll
   `get_image`), per the global AGENTS.md rule. No other image generator,
   no hand-painted substitutes. `no_background: true` on every call.
2. **Style references.** Every job passes `style_image` base64 references:
   the exported stock contact card plus the original sheet(s) named in the
   per-family "Reference assets" notes (§3.0/§4). Re-export the stock
   reference card first (Options → Export Stock Texture Card + Reference)
   so the card includes the 16 new sheets' *intended* layout — the card is
   regenerated from `TexturePackManager.PACK_ASSETS` and is part of box 3.
3. **One job per source.** Never ask the model for a whole labelled atlas
   (building plan rule). One job per *master cell* (§3) or per *frame*
   (§4). Within a state sheet, frame 0 is the canonical pose: generate
   frame 0 first, review it, then pass frame 0's own PNG as the primary
   `style_image` for frames 1..N so the base object's silhouette, position,
   and lighting stay identical across the strip; only the state detail
   (lid, flame, glow) may change.
4. **Concurrency.** Tier-2 account caps at 10 concurrent jobs. Submit
   **≤ 8 per wave** and wait for the full wave to settle before the next.
   Log every `job_id` to a driver log immediately; a crash recovery pass
   re-parses that log (M8 precedent — do not resubmit blind).
5. **Review at native scale.** Every output is inspected at 32 px (native
   camera zoom, no upscaling) before it is allowed into a pack. A master
   cell that fails review is regenerated (up to 2 attempts per cell);
   after that it is escalated, not averaged into the sheet.
6. **Mechanical packing only.** Post-generation processing may pack, crop,
   or rotate. It may never repaint, rescale with smoothing, add an opaque
   background, or reorder frames. Derivation of E/S/W orientation cells by
   90° rotation of the north master is the one sanctioned rotation and is
   defined in §2.4.
7. **Commit gate.** A sheet is committed only after: exact canvas
   dimensions match the contract below, transparency is intact (no
   checkerboard/white bake-in), every USED slot holds art and every
   RESERVED slot is fully transparent, `--headless --import` succeeds, the
   harness is green, and `tools/verify_texture_pack.gd` passes on the
   exported pack.

---

## 2. Global art rules

### 2.1 Canvas and grid

- One logical tile = **32×32 px**. Every cell and frame is exactly that.
- All new sheets are **RGBA PNG with true alpha**; the background is fully
  transparent unless a cell is a *fill* (a floor/foundation/path tile), in
  which case the whole 32×32 is opaque and the pattern must tile
  edge-to-edge with no visible seam.
- View: **orthographic top-down**, straight down, no perspective, no
  side-angle. This is Wildfall's fixed camera.
- Freestanding props are centered in their cell with ≥1 px transparent
  margin and a small contact shadow that never leaves the cell.

### 2.2 Sheet inventory (exact canvases)

| Sheet | Path | Canvas | Grid (cols×rows) |
|---|---|---|---|
| Structural timber | `assets/tiles/building/structural_wood.png` | 256×256 | 8×8 |
| Structural stone | `assets/tiles/building/structural_stone.png` | 256×256 | 8×8 |
| Structural reinforced | `assets/tiles/building/structural_metal.png` | 256×256 | 8×8 |
| Boundaries timber | `assets/tiles/building/boundaries_wood.png` | 256×128 | 8×4 |
| Boundaries stone | `assets/tiles/building/boundaries_stone.png` | 256×128 | 8×4 |
| Boundaries reinforced | `assets/tiles/building/boundaries_metal.png` | 256×128 | 8×4 |
| Interior timber | `assets/tiles/building/interior_wood.png` | 256×128 | 8×4 |
| Interior stone | `assets/tiles/building/interior_stone.png` | 256×128 | 8×4 |
| Interior reinforced | `assets/tiles/building/interior_metal.png` | 256×128 | 8×4 |
| Exterior props (shared) | `assets/tiles/building/exterior_props.png` | 256×128 | 8×4 |
| Chest states | `assets/tiles/interactables/wood_chest.png` | 32×96 | 1×3 |
| Campfire states | `assets/tiles/interactables/campfire.png` | 32×160 | 1×5 |
| Furnace states | `assets/tiles/interactables/furnace.png` | 32×96 | 1×3 |
| Workbench states | `assets/tiles/interactables/workbench.png` | 32×64 | 1×2 |
| Torch states | `assets/tiles/interactables/torch.png` | 32×128 | 1×4 |
| Fuelled-vessel states | `assets/tiles/interactables/hearth.png` | 32×64 | 1×2 |

Slot coordinates in this document are `(col, row)` with col 0 = leftmost,
row 0 = top row. Slot index = `row × 8 + col` for the 8-wide building
sheets (1-wide state sheets are just frame indices top→bottom).

### 2.3 Shared style preamble (prefix of every prompt)

> Warm, painterly frontier-settlement pixel art in the style of the
> attached Wildfall reference sheets. Orthographic top-down view, straight
> down, no perspective. One single 32×32 px tile or prop on a fully
> transparent background (true alpha, no checkerboard, no white). Crisp
> chunky pixels, 2–3 px dark outline accents, soft ambient shading, no
> anti-aliasing blur, no text, no watermark, no border frame. The subject
> must fit entirely inside the 32×32 canvas. Material palettes by tier —
> **wood/timber**: warm brown oak planks, dark grain, iron fittings;
> **stone**: grey-brown hewn blocks with lighter mortar joints;
> **metal/reinforced**: cool blue-grey riveted iron with subtle rust and
> a faint warm highlight where it catches lantern light.

### 2.4 Orientation policy: one north master, derived rotations

Edge parts (walls, windows, doors, rails, fences, gates, stairs) read
their placed orientation (`north`/`east`/`south`/`west`, stored per
building record) as which tile edge their strip sits on. The runtime never
rotates or mirrors sprites and **never reinterprets a saved orientation**
— each orientation must resolve to a *cell in the atlas*. So: each edge part is
generated as **one north-facing master cell** (art composed against the
top edge of its 32×32 canvas), and the packer deterministically derives the
other three orientations by rotating that master:

| Placed orientation | Cell content |
|---|---|
| north | the generated master (0°) |
| east | master rotated 90° clockwise |
| south | master rotated 180° |
| west | master rotated 90° counter-clockwise |

Rotation is a mechanical transform (pattern-preserving, alpha-preserving,
frame-order-preserving) and is explicitly sanctioned by the production
contract. Asymmetric details on a band (hinges, latches, rail joints,
arrow cues) are composed at the **left end** of the north band; after
rotation they sit consistently at the segment's start for every
orientation. If a native-zoom review shows a derived orientation reading
wrong (e.g. a shadow that now points the wrong way), that orientation is
regenerated as its own master in the refinement pack — the grid slot
layout never changes, only which slot is generated vs derived.

Stairs additionally encode **direction** (up vs down) as two separate row
halves: the up-stair master occupies the left half of the stair row, the
down-stair master the right half (see §3.1 row 4); each half follows the
same 4-orientation derivation.

### 2.5 Slot status vocabulary

Every slot in every grid is documented below with exactly one status:

- **USED** — owned by a named definition; must contain art at commit.
- **DERIVED** — filled by the packer by rotating a named master slot;
  never generated, must be non-empty at commit.
- **RESERVED** — documented layout capacity for future content; must be
  **fully transparent** at commit. A reserved slot becomes USED by a data
  change only (new or repointed definition), which the harness then
  enforces.

The per-sheet slot maps below are also written to data as
`AtlasFamilyMap` resources under `data/buildings/families/` (box 3): the
packer tool and the harness read the maps from data, so no cell map exists
as a duplicated GDScript constant (building plan rule).

---

## 3. Family A — building atlases

### 3.0 Reference assets and consuming code (all Family A sheets)

- **Reference assets (style_image):** the stock contact card
  (`user://texture_packs/stock_reference/…`) plus
  `assets/tiles/wildfall-building-parts.png` (the incumbent 2×9 wood/stone
  structural sheet — direct style donor for every structural/boundary
  row) and, for boundaries and exterior, the fence/soil/torch cells of
  `assets/tiles/wildfall-building-utilities.png`.
- **Consuming code, common to all four sheet families:**
  - `src/world/building.gd` — `_definition_atlas()` reads a
    definition's `atlas_path`/`atlas_cell`; `_setup_visuals()` builds the
    32×32 `Sprite2D` region; `reload_visual_texture()` re-resolves on
    texture-pack reload. Box 3 extends `_definition_atlas()` to resolve
    the per-orientation `atlas_cells` map (§6.4) and to render the state
    sheet as the in-world sprite when one is present (§4.3).
  - `src/systems/building_manager.gd` — ghost preview and placement
    (box 4/5 make the ghost draw the part's own cell for the pending
    orientation plus its reservations; the 4-orientation cell map is what
    makes that possible).
  - `src/ui/build_palette.gd` — group/filter presentation (box 4).
  - `src/systems/texture_pack_manager.gd` — `PACK_ASSETS` gains all 16
    sheet paths; stock reference export, manifest, editable refinement
    pack, and the live-refresh path pick them up automatically.
  - `tools/verify_texture_pack.gd` — automatically covers the new sheets
    once they are in `PACK_ASSETS` (it iterates the list).
  - Harness: `tests/test_game.gd` (legacy-atlas assertions updated per
    §8.1) + new `tests/test_building_art.gd` (contract checks §8.2).
- **Definition migration** — the complete old→new reference table for
  all 55 migrated definitions (29 structural + 26 boundary/interior/
  exterior) is §6; after it lands, **no definition references
  `wildfall-building-parts.png`** (harness-enforced).

### 3.1 `structural_<tier>.png` — 8 columns × 8 rows, 256×256

Fixed role per row (identical across the three tier sheets; the tier
changes materials, not layout):

| Row | Slot (col 0..7) | Role |
|---|---|---|
| 0 | 0–7 | Ground fills: foundation / floor / porch / deck / reserved×4 |
| 1 | 0–7 | Wall edge: (0)=master north, (1..3)=derived E/S/W, (4..7) reserved |
| 2 | 0–7 | Window edge: (0)=master north, (1..3)=derived E/S/W, (4..7) reserved |
| 3 | 0–7 | Door edge: (0)=master north, (1..3)=derived E/S/W, (4..7) reserved |
| 4 | 0–7 | Stairs: (0)=up-north master, (1..3)=up E/S/W derived, (4)=down-north master, (5..7)=down E/S/W derived |
| 5 | 0–7 | Roof / cover: (0)=roof, (1)=awning or canopy, (2..7) reserved |
| 6 | 0–7 | Supports: (0)=post, (1)=pillar, (2..7) reserved (no arches this pass) |
| 7 | 0–7 | Ramp: (0)=ramp, (1..7) reserved (non-orientable; no rotation) |

Wall/window/door/rail edge cells follow the §2.4 band composition:
**the strip occupies the top (north) 6–8 px of the cell, full width;
everything below the strip is transparent** (a ≤2 px contact shadow may
touch the first row under the strip). The runtime nudges the whole sprite
6 px outward along the placed orientation (`EDGE_VISUAL_OFFSET` in
`building.gd`), so the band art must be composed as "edge strip of the
tile", not a freestanding wall in the middle of the cell.

Per-tier slot owners and generation counts:

| Slot | wood (14 generated) | stone (11) | metal (7) |
|---|---|---|---|
| (0,0) foundation | `wooden_foundation` | `stone_foundation` | `reinforced_floor` |
| (1,0) floor | `wooden_floor` | `stone_floor` | `metal_grate` (open grate over a solid base) |
| (2,0) porch | `wooden_porch` | `stone_patio` (flagstone patio) | — RESERVED |
| (3,0) deck | `wooden_deck` | — RESERVED | — RESERVED |
| (0,1) wall master | `wooden_wall` | `stone_wall` | `reinforced_wall` |
| (1,1)–(3,1) wall E/S/W | DERIVED from (0,1) | DERIVED | DERIVED |
| (0,2) window master | `wooden_window` | `stone_window` | `shuttered_window` (shutters half-closed, bolt detail) |
| (1,2)–(3,2) window E/S/W | DERIVED | DERIVED | DERIVED |
| (0,3) door master | `wooden_door` | `stone_door` | — RESERVED (no metal-door def) |
| (1,3)–(3,3) door E/S/W | DERIVED | DERIVED | DERIVED |
| (0,4) stair up-N master | `wooden_stairs` | `stone_stairs` | `metal_stair` |
| (1,4)–(3,4) up E/S/W | DERIVED | DERIVED | DERIVED |
| (4,4) stair down-N master | `wooden_stairs_down` (new def §6.5) | `stone_stairs_down` | `metal_stair_down` |
| (5,4)–(7,4) down E/S/W | DERIVED | DERIVED | DERIVED |
| (0,5) roof | `wooden_roof` (shingle) | `stone_roof` (slate) | `metal_roof` (corrugated) |
| (1,5) awning/canopy | `awning` | — RESERVED (no stone awning def) | — RESERVED (canopy variant) |
| (0,6) post | `corner_post` | — RESERVED | — RESERVED |
| (1,6) pillar | `wooden_pillar` | `stone_pillar` | — RESERVED |
| (0,7) ramp | `wooden_ramp` | `stone_ramp` | — RESERVED |

Corner cells are deliberately **not** generated: two adjacent edge strips
meet at a corner tile and read correctly as a corner; boundary corner
slots live in §3.2 and stay RESERVED until a fence-corner def exists.
"Stairwell rim" from the plan's content table is not a slot this pass.

**Per-cell prompt focus (per tier):**

- **Row 0 fills** — "seamless 32×32 floor tile, fully opaque, pattern
  tiles edge-to-edge with no visible seam. Timber: plank boards running
  left-right with staggered joints. Foundation: rough laid logs/beam
  ends. Porch: boards on two visible post bases at the bottom corners.
  Deck: lighter plank boardwalk with gaps. Stone: flagstone slabs with
  mortar. Patio: small cobbles in a running bond. Reinforced floor:
  steel plate with a bolt-grid texture. Grate: dark iron bars over an
  open dark base, bars running left-right."
- **Row 1 wall** — "a wall edge strip along the top edge of the tile:
  full width, 7 px deep. Timber: vertical plank end-grain with a beam
  line. Stone: a course of block ends. Metal: steel plate edge with
  rivets. Below the strip: transparent. A 2 px soft shadow under the
  strip. A small iron bracket detail at the left end of the strip."
- **Row 2 window** — "same top-edge strip position as the wall, but with
  a window set into the middle of the strip: a 12 px wide glazed opening
  (pale blue-grey glass, thin cross muntins). Timber: plank wall with a
  framed window. Stone: stone wall with a rectangular opening and iron
  bars. Metal: steel wall with a narrow slit window and half-closed
  bolted shutter over the right half."
- **Row 3 door** — "same top-edge strip position, with a 12 px wide door
  opening in the middle: a solid plank slab (timber) / heavy slab with a
  lintel (stone) / steel hatch with a wheel (metal), clearly readable as
  a gap in the wall with a handle detail on the left end of the opening."
- **Row 4 stairs** — "a straight staircase filling the 32×32 tile, seen
  from directly above. The **up** master ascends toward the top (north)
  edge: highest tread a full-width band at the top rows, treads stepping
  down toward the bottom edge, each tread a lighter board/slab with a
  dark riser shadow under it — direction readable without any text or
  arrow. Timber: wooden treads on two side stringers. Stone: stone
  steps. Metal: steel grating treads. The **down** master is the mirrored
  composition: highest tread at the bottom edge."
- **Row 5 roof** — "fully opaque 32×32 overhead cover seen straight from
  above, seamless and tileable. Timber: overlapping shingle courses
  running left-right with a ridge line at the top. Stone: slate slabs in
  a header-wrong bond. Metal: corrugated panels running left-right with
  a central seam. Awning: a lighter fabric canvas over a timber frame,
  canvas scalloped along the bottom edge, slightly see-through weave."
- **Row 6 supports** — "one freestanding post centered in the cell:
  corner_post is a square timber post with iron corner bands, slightly
  thicker than a plain post. Pillar: a round timber post (wood) / a
  stone column with a capital ring (stone). Small contact shadow,
  transparent around it."
- **Row 7 ramp** — "a fully opaque 32×32 walkable ramp tile, seamless:
  tread lines running left-right, the tile shaded darker at the bottom
  edge and lighter at the top edge so the slope reads without text.
  Timber boards / stone slabs per tier."

### 3.2 `boundaries_<tier>.png` — 8 columns × 4 rows, 256×128

| Row | Slot (col 0..7) | Role |
|---|---|---|
| 0 | 0–7 | Fence: (0)=straight-north master, (1..3)=derived E/S/W, (4)=corner RESERVED, (5..7) reserved |
| 1 | 8–15 | Gate: (8)=gate-north master, (9..11)=derived E/S/W, (12)=corner RESERVED, (13..15) reserved |
| 2 | 16–23 | Rail: (16)=rail-north master, (17..19)=derived E/S/W, (20)=corner RESERVED, (21..23) reserved |
| 3 | 24–31 | Fence posts / pen posts: all RESERVED (no def this pass) |

Band composition per §2.4: top-edge strip, **thinner than the structural
wall strip (4–5 px)** — boundaries are low. Gate = the fence strip with a
12 px passable opening in the middle (open lattice/planks, a small latch
at the left end). Rail = a single thin top rail with a post bump at the
left end/joint at the left end of the strip.

| Slot | wood (3 generated) | stone (2) | metal (3) |
|---|---|---|---|
| (0,0) fence straight master | `fence` | — RESERVED (no stone fence def; the plan's "stone wall" boundary is the structural `stone_wall`) | `metal_fence` |
| (1,0)–(3,0) | DERIVED | — | DERIVED |
| (8,1) gate master | `fence_gate` | `stone_gate` | `metal_gate` |
| (9,1)–(11,1) | DERIVED | DERIVED | DERIVED |
| (16,2) rail master | `wooden_railing` | `stone_railing` | `metal_railing` |
| (17,2)–(19,2) | DERIVED | DERIVED | DERIVED |

Per-cell prompt focus: **fence** — "a low wooden palisade fence strip
along the top edge, 4–5 px deep: two horizontal rails with vertical picket
ends, full width. Stone: a low dry-stone wall course. Metal: a steel
palisade of thin vertical bars on a top rail." **Gate** — "the same
boundary strip with an open 12 px gate in the middle: timber gate:
hinged plank gate swung slightly open into the room side with a latch;
stone: two block piers flanking an opening with an iron bar; metal: a
steel gate with a diagonal brace." **Rail** — "a slim 2 px top rail
along the top edge with a small post block at the left end; timber /
stone / metal per tier."

### 3.3 `interior_<tier>.png` — 8 columns × 4 rows, 256×128

| Row | Slot (col 0..7) | Role |
|---|---|---|
| 0 | 0–7 | Freestanding 1×1 furniture (object layer) |
| 1 | 8–15 | RESERVED — future 1×1 furniture |
| 2 | 16–17 | 2×1 horizontal footprint (spans cols 0–1 of rows 2) — RESERVED |
|   | 18–23 | RESERVED |
| 3 | 24–27 top half + 16,17 (row 2) | 2×2 footprint (rows 2–3, cols 0–1) — RESERVED |
|   | 28–31, 20–23 | RESERVED |

All furniture cells are **non-orientable** (no rotation, no band
composition): a single centered prop on transparent ground, drawn
straight-down, with a small contact shadow.

| Slot | wood (6 generated) | stone (2) | metal (2) |
|---|---|---|---|
| (0,0) | `bed` (repointed from the legacy utilities sheet, §6.2) | — RESERVED: `hearth` keeps its sheet, §4.6 | `workshop_cabinet` |
| (1,0) | — RESERVED: `chest` presentation is the state sheet (§4.1); no static cell | `cabinet` | `metal_locker` |
| (2,0) | `wooden_table` | `bookcase` | — RESERVED |
| (3,0) | `chair` | — RESERVED | — RESERVED |
| (4,0) | `shelf` | — RESERVED | — RESERVED |
| (5,0) | `rug` (ground-layer flat tile, opaque, tileable border pattern) | — RESERVED | — RESERVED |
| (6,0) | `wardrobe` | — RESERVED | — RESERVED |
| (7,0) | — RESERVED | — RESERVED | — RESERVED |

Per-cell prompt focus: **bed** — "a single bed seen from directly above,
centered: pillow at the top (north) end, a folded blanket across the lower
half, timber frame edges; fits in ~26×30 px". **table** — "a square plank
dining table from above with a small bowl at its center". **chair** — "a
single wooden chair from above: seat square, backrest bar at the top
edge, four legs as corner dots". **shelf** — "a low wooden shelf with
three visible object silhouettes (jar, book, cloth) in its compartments".
**rug** — "a flat woven rug filling the cell: warm geometric border
pattern on a darker field, fully opaque, tileable". **wardrobe** — "a
tall wooden wardrobe from above: lid planks with a central clasp and
corner iron". **cabinet** (stone) — "a low stone storage cabinet: hewn
block body with a darker inset door panel and iron ring". **bookcase**
(stone) — "a stone bookcase: two shelf lines of book spines in muted
colours on a grey frame". **workshop_cabinet** (metal) — "a steel
workshop cabinet from above: four drawer faces with handle bars on a
riveted frame". **metal_locker** — "a tall steel locker from above: a
door with a vent slot row and a latch".

### 3.4 `exterior_props.png` — shared sheet, 8 columns × 4 rows, 256×128

One shared sheet for all tiers (building plan contract: "single shared:
paths, planters, lanterns, steps, yard props"); rows are tier sections.

| Row | Slot (col 0..7) | Role |
|---|---|---|
| 0 (timber) | 0–7 | (0) path, (1) steps, (2) planter, (3..7) reserved |
| 1 (stone) | 8–15 | (0) path, (1) well, (2) planter, (3..7) reserved |
| 2 (metal) | 16–23 | (0) path RESERVED, (1) pole, (2..7) reserved |
| 3 (primitive) | 24–31 | (0) crop soil, (1) pen fence RESERVED, (2..7) reserved |

**Seamless ground props** (path, crop soil) are fully opaque tileable 32×32
tiles (like §3.1 row 0 fills) — even though they live on the shared
props sheet, because they are ground-layer fills. **Freestanding props**
(steps, planter, well, pole) are centered transparent cells.

| Slot | Owner def | Prompt focus |
|---|---|---|
| (0,0) | `wooden_path` (repointed from structural fills) | "seamless dirt path tile with a few light stepping-stone slabs and worn edges; opaque, tileable" |
| (1,0) | `steps` | "a freestanding 2-step timber landing (a small porch step) centered in the cell, contact shadow" |
| (2,0) | `planter_box` | "a square wooden planter box from above: plank rim, dark rich soil, a small green plant cluster" |
| (0,1) | `stone_path` | "seamless flag: packed cobbles in a worn pattern; opaque, tileable" |
| (1,1) | `well` | "a round stone well from above: block ring, dark water center with a faint highlight, a roofed frame arc and a rope+bucket at the top" |
| (2,1) | `stone_planter` | "a hewn stone planter basin from above: block rim, dark soil, a green plant cluster" |
| (1,2) | `signal_pole` | "a utility/signal pole seen from above: small riveted iron base plate, the pole as a small circle with a signal disc and a tiny lamp glow at top" |
| (0,3) | `farm_soil` (repointed from the legacy utilities sheet) | "a tilled crop-soil patch: dark furrow rows running left-right with a few pale seed dots; opaque, tileable" |

Note: `yard_lantern` / `metal_lantern` / `brazier` / `torch` have **no
exterior cell** — their in-world presentation is the state sheet from §4
and their definitions carry no atlas cell (a missing sheet falls back to
the neutral family tint, which is the documented pre-M9 state and the
post-M9 missing-file fallback).

### 3.5 Generation count, Family A

Masters actually sent to PixelLab: structural 14 (wood) + 11 (stone) +
7 (metal) = 32; boundaries 3 + 2 + 3 = 8; interior 6 + 2 + 2 = 10;
exterior 3 + 3 + 1 + 1 = 8. **Total Family A: 58 generated sources.**
Everything else in the 10 sheets is either DERIVED (rotated at pack time)
or RESERVED (transparent).

---

## 4. Family B — interactable state sheets

### 4.0 Reference assets and consuming code (all Family B sheets)

- **Reference assets (style_image):** the stock contact card plus the
  incumbent legacy cell of each object — chest:
  `wildfall-building-utilities.png` cell (2,0); torch: cell (0,0);
  campfire: `wildfall-crafting-stations.png` cell (0,0); furnace: cell
  (1,0); workbench: cell (2,0); hearth/vessel: the torch cell (flame
  style) plus the parts-atlas stone wall (material). Frame 0's own output
  is then chained as primary reference for frames 1..N (§1.3).
- **Consuming code, common:** `building.gd::_setup_appearance_visual`
  builds the sheet sprite (region = one 32×32 frame from the vertical
  strip); `set_appearance_state` moves the region per the profile's
  `first_frame`; `set_interaction_open` drives open/close transitions;
  `_update_light` couples light visibility to the same powered state.
  The five station/interactable definitions carry the profiles
  (`data/interactables/*.tres`). Box 3 changes (see §4.3): profile
  `sheet_path`/state frame data are filled in (data-only), the shared
  `fuelled_appearance` is split where the brief demands dedicated sheets,
  and the in-world sprite policy flips to *sheet-first* (§4.3).
- **Light mask:** no asset. `GradientTexture2D` (128×128 radial) stays
  code-built in `building.gd::_setup_light` — the brief's "shared light
  mask" row is satisfied by existing code, not a PNG.

### 4.1 `wood_chest.png` — 32×96, 1 column × 3 frames

| Frame | State | Prompt focus |
|---|---|---|
| 0 | `closed` (canonical pose) | "A sturdy hand-built frontier wooden chest, visible lid and brass/iron clasp, orthogonal top-down prop, same silhouette across lid states, transparent background" + preamble. Centered, ~26×26 px, lid seam horizontal across the middle, clasp at the near (south) end. |
| 1 | `opening` / `half-open` | Frame 0 chained as reference; "identical chest base and pose; the lid is now hinged open about 40 degrees, the dark interior just visible as a thin band" |
| 2 | `open` | "identical chest base and pose; the lid is fully open and folded flat against the back edge, revealing a dark interior with a small gold-and-cloth loot glint" |

Profile mapping (data edit, `chest_appearance.tres`): `closed`→frame 0,
`opening`→frame 1, `open`→frame 2, `closing`→frame 1 (close plays
reverse, per the brief). Consumer def: `chest`.

### 4.2 `campfire.png` — 32×160, 1×5

| Frame | State | Prompt focus |
|---|---|---|
| 0 | `unlit` (canonical) | "A stone-ring campfire with wooden fuel, seen top-down: a circle of small stone blocks with crossed logs inside, transparent background" + preamble. The stone ring is the canonical silhouette — every later frame keeps it pixel-identical in position. |
| 1 | `ignition` | Ring identical; "a small orange ignition glow between the logs with two tiny flame tips" |
| 2 | `burn A` | Ring identical; "a compact 3-lobed orange-yellow flame rising in the center, warm glow spilling 2 px onto the ring stones, restrained" |
| 3 | `burn B` | Ring identical; "the same flame, one frame later in its flicker: lobes shifted and slightly taller, glow shifted with them" |
| 4 | `burn C` | Ring identical; "the same flame, a third variant: one lobe split, glow slightly narrower" |

Profile mapping (new `campfire_appearance.tres`, split from the shared
`fuelled_appearance`): `initial_state`/`unpowered` = `unlit`→0;
`powered` = `burn A`→2; loop frames 2–4 at the profile's fps;
`ignition` (1) is the one-frame transition shown on light-up. Consumer
def: `campfire`.

### 4.3 `furnace.png` — 32×96, 1×3

| Frame | State | Prompt focus |
|---|---|---|
| 0 | `cold` (canonical) | "A compact stone frontier furnace seen top-down: a hewn-block body with an arched mouth at the south edge, a dark unlit mouth, a chimney block at the north; transparent background" + preamble. Body silhouette canonical across frames. |
| 1 | `heating` | Body identical; "the mouth now shows a dim red-brown glow, a few ember dots inside" |
| 2 | `lit` | Body identical; "the mouth glows warm orange with a visible fire pattern inside; a soft 1–2 px glow ring around the mouth" (the brief allows a shader/alpha flicker at runtime instead of further frames — profile loops this single frame) |

New `furnace_appearance.tres` (split from shared states get dedicated sheet):
`unpowered`→`cold` 0, `powered`→`lit` 2 (with `heating` 1 as the
ramp state on first light). Consumer def: `furnace`.

### 4.4 `workbench.png` — 32×64, 1×2

| Frame | State | Prompt focus |
|---|---|---|
| 0 | `idle` (canonical) | "A practical wooden workbench from above: a plank top with a hammer, an anvil block and a tool tray; sturdy timber legs at the corners; transparent background" + preamble |
| 1 | `active` / in-use | Bench identical; "a subtle in-use cue: a fresh wood shaving curl and a chisel laid across the top, no character present" |

New `workbench_appearance.tres`: `initial_state` `idle`→0, `active`→1
(no loop). The workbench definition gains this profile in box 3 and the
station manager toggles `active` while the player is crafting at that
station (small code wiring; the state machine itself is already generic).
Consumer def: `workbench`.

### 4.5 `torch.png` — 32×128, 1×4

| Frame | State | Prompt focus |
|---|---|---|
| 0 | `unlit` (canonical) | "A wall/ground torch appropriate to the existing utility tile: a short iron socket post with a wrapped torch head, unlit grey wick; seen top-down as a compact round base with a small head; transparent background" + preamble |
| 1 | `ignition` | Base identical; "the wick catches: a small orange spark cluster at the head" |
| 2 | `flame A` | Base identical; "a compact 2-lobed warm flame at the head with a soft 2 px glow ring; high readability at 32 px" |
| 3 | `flame B` | Base identical; "the flame one frame later in its flicker: lobes shifted, one tip longer" |

New `torch_appearance.tres`: `unlit`→0, `ignition` 1, `powered` =
`flame A`→2, loop 2–3. Consumer def: `torch`.

### 4.6 `hearth.png` — 32×64, 1×2 (deviation D1)

| Frame | State | Prompt focus |
|---|---|---|
| 0 | `unlit` (canonical) | "A round stone fuel vessel seen top-down: a hewn stone bowl with crossed dry logs inside, a small iron lip; transparent background" + preamble. One silhouette serves four fixtures. |
| 1 | `lit` | Vessel identical; "the bowl now glows: warm orange ember light between the logs with a 2 px glow ring on the stone rim" |

The existing **shared** `fuelled_appearance.tres` is the consumer of this
sheet (box 3 sets its `sheet_path` and moves its `lit` state to frame 1).
It is shared by four definitions — `hearth`, `brazier`, `yard_lantern`,
`metal_lantern` — which is exactly why one sheet serves all of them:
their M8 data decision was one shared unlit/lit vessel presentation.
State names stay `unlit`/`lit`; the runtime coupling
(`unpowered_state`/`powered_state` → `unlit`/`lit`) is unchanged.

**Deviation D1 (recorded in the plan's decision log at closeout):** the
interactables brief's table lists five state sheets. Four of the game's
fuelled fixtures share one appearance profile, so the profile needs a
sheet of its own for its states to resolve; this sixth 2-frame sheet
closes that gap without touching the brief's five sheets, whose frame
contracts are implemented verbatim.

**Total Family B: 3 + 5 + 3 + 2 + 4 + 2 = 19 generated frames.**

### 4.7 Frame consistency rule

For every multi-frame sheet: frame 0 is generated alone and reviewed at
native scale; frames 1..N are generated with frame 0's PNG as primary
style reference and a prompt that names *exactly* what changes
(lid angle, flame lobe shape, glow radius) and *exactly* what must not
(the base object's silhouette, position, and shading). A frame that
drifts in base-object geometry is regenerated, not accepted, because the
runtime crossfades nothing — frame swaps must be silhouette-stable.

---

## 5. Master cell → orientation derivation (pack-time)

The deterministic packer (box 3, `tools/build_building_art_pack.gd`,
patterned on `build_pixellab_comparison_pack.gd`) receives generated
masters named `<sheet>/<slot_index>.png` in a working directory and
writes the final sheets by:

1. blitting every generated master into its documented slot;
2. filling every DERIVED slot by rotating the named master
   (E = 90° CW, S = 180°, W = 90° CCW — `Image.transpose`,
   pattern-preserving, alpha preserved);
3. leaving every RESERVED slot transparent;
4. validating the output (canvas size, alpha presence, USED slots
   non-empty, RESERVED slots empty) and refusing to write a sheet that
   fails;
5. writing the state sheets by blitting frame strips top-to-bottom into
   the contracted canvas (32×96 / 32×160 / 32×64 / 32×128) after the
   same validation.

The per-slot master→derived map the packer uses is read from the
`AtlasFamilyMap` data resources (box 3), not from constants in the tool.

---

## 6. Definition migration (data changes the new art implies)

### 6.1 Structural sheet owners (29 defs) — old reference → new cell

(The three new down-stair defs from §6.5 also own the (4,4) master of
each tier; they are new defs, not part of this 65-def migration.)

| Def | Old reference (2×9 parts cell; "—" = no reference today) | New sheet | New cell |
|---|---|---|---|
| wooden_foundation | (0,0) | structural_wood | (0,0) |
| wooden_floor | (0,1) | structural_wood | (1,0) |
| wooden_porch | — (placeholder) | structural_wood | (2,0) |
| wooden_deck | — (placeholder) | structural_wood | (3,0) |
| wooden_wall | (0,2) | structural_wood | (0,1) |
| wooden_window | (0,3) | structural_wood | (0,2) |
| wooden_door | (0,4) | structural_wood | (0,3) |
| wooden_roof | (0,5) | structural_wood | (0,5) |
| awning | — (placeholder) | structural_wood | (1,5) |
| wooden_stairs | (0,6) | structural_wood | (0,4) |
| corner_post | — (placeholder) | structural_wood | (0,6) |
| wooden_ramp | (0,7) | structural_wood | (0,7) |
| wooden_pillar | (0,8) | structural_wood | (1,6) |
| stone_foundation | (1,0) | structural_stone | (0,0) |
| stone_floor | (1,1) | structural_stone | (1,0) |
| stone_patio | — (placeholder) | structural_stone | (2,0) |
| stone_wall | (1,2) | structural_stone | (0,1) |
| stone_window | (1,3) | structural_stone | (0,2) |
| stone_door | (1,4) | structural_stone | (0,3) |
| stone_roof | (1,5) | structural_stone | (0,5) |
| stone_stairs | (1,6) | structural_stone | (0,4) |
| stone_ramp | (1,7) | structural_stone | (0,7) |
| stone_pillar | (1,8) | structural_stone | (1,6) |
| reinforced_floor | — (placeholder) | structural_metal | (0,0) |
| metal_grate | — (placeholder) | structural_metal | (1,0) |
| reinforced_wall | — (placeholder) | structural_metal | (0,1) |
| shuttered_window | — (placeholder) | structural_metal | (0,2) |
| metal_roof | — (placeholder) | structural_metal | (0,5) |
| metal_stair | — (placeholder) | structural_metal | (0,4) |

(The "—" rows: defs that currently render from the family-tint
placeholder; the migration gives them their first real cells.)

### 6.2 Boundary + interior + exterior sheet owners (26 defs)

| Def | Old reference | New sheet | New cell |
|---|---|---|---|
| fence | utilities (4,0) | boundaries_wood | (0,0) |
| fence_gate | utilities (4,0) | boundaries_wood | (0,1) |
| wooden_railing | — (placeholder) | boundaries_wood | (0,2) |
| stone_gate | — (placeholder) | boundaries_stone | (0,1) |
| stone_railing | — (placeholder) | boundaries_stone | (0,2) |
| metal_fence | — (placeholder) | boundaries_metal | (0,0) |
| metal_gate | — (placeholder) | boundaries_metal | (0,1) |
| metal_railing | — (placeholder) | boundaries_metal | (0,2) |
| bed | utilities (1,0) | interior_wood | (0,0) |
| wooden_table | — (placeholder) | interior_wood | (2,0) |
| chair | — (placeholder) | interior_wood | (3,0) |
| shelf | — (placeholder) | interior_wood | (4,0) |
| rug | — (placeholder) | interior_wood | (5,0) |
| wardrobe | — (placeholder) | interior_wood | (6,0) |
| cabinet | — (placeholder) | interior_stone | (1,0) |
| bookcase | — (placeholder) | interior_stone | (2,0) |
| workshop_cabinet | — (placeholder) | interior_metal | (0,0) |
| metal_locker | — (placeholder) | interior_metal | (1,0) |
| wooden_path | — (placeholder) | exterior_props | (0,0) |
| stone_path | — (placeholder) | exterior_props | (0,1) |
| farm_soil | utilities (3,0) | exterior_props | (0,3) |
| well | — (placeholder) | exterior_props | (1,1) |
| stone_planter | — (placeholder) | exterior_props | (2,1) |
| planter_box | — (placeholder) | exterior_props | (2,0) |
| steps | — (placeholder) | exterior_props | (1,0) |
| signal_pole | — (placeholder) | exterior_props | (1,2) |

### 6.3 Unchanged references (10 defs)

`chest` (utilities (2,0)), `torch` (utilities (0,0)), `campfire`
(stations (0,0)), `furnace` (stations (1,0)), `workbench` (stations
(2,0)), `anvil` (stations (3,0)) keep their legacy cells as the
**documented fallback + palette/ghost base reference** while their state
sheets (§4) are the in-world presentation. `brazier`, `yard_lantern`,
`metal_lantern`, `hearth` keep **no** atlas cell (placeholder-tint
fallback; the hearth sheet, §4.6, is their in-world presentation).

(29 + 26 + 10 = 65: every definition is accounted for exactly once.)

### 6.4 Per-orientation cell maps (new `atlas_cells` field)

Box 3 adds `atlas_cells: Dictionary` to `BuildingDefinition`
(orientation → Vector2i cell on `atlas_path`; `""` or an absent key
falls back to `atlas_cell`). `building.gd::_definition_atlas()` resolves:
`atlas_cells.get(orientation, atlas_cell)`. Saved records are never
rewritten — an existing placed north wall keeps rendering from the north
cell; the map only governs which cell a *given saved orientation* reads.

Sixteen edge defs get the full 4-key map: the eight orientable
structural parts (wall and window on all three tiers; door on wood and
stone — the metal tier has no door def, so its (0,3) slot stays
RESERVED) plus the eight boundary masters from §6.2 — e.g.
`wooden_wall`: `{"north": (0,1), "east": (1,1), "south": (2,1),
"west": (3,1)}`). Stair defs get direction-aware maps: the up defs map
orientations to row-4 cols 0–3; the new down defs (§6.5) map to row-4
cols 4–7.

### 6.5 New definitions (3) — stairs down

`wooden_stairs_down`, `stone_stairs_down`, `metal_stair_down`: same
cost/tech/layer as their up counterparts, `connector_profile` pointing
at a new `data/interactables/stair_connector_down.tres`
(`upper_story_offset = -1`, same reservation/trigger fields),
`allowed_orientations` = the four edges, `atlas_cells` per §6.4, palette
display "Stairs (down)". Their inventory items reuse the up-stair icon
paths (no new icons, no new generation — a 180°-rotated icon would read
identically to the existing one at 32 px; noted here so it is a decision,
not an accident). The up-stair defs gain the same orientation field.
(Verify in box 3 that the connector system accepts a negative
`upper_story_offset`; if it hard-asserts positive, that assert becomes a
data check — no per-ID branch.)

### 6.6 Appearance profile changes (data)

- `chest_appearance.tres`: frames per §4.1 (`opening`→1, `open`→2,
  `closing`→1), `sheet_path` = the chest sheet.
- New `campfire_appearance.tres`, `furnace_appearance.tres`,
  `torch_appearance.tres`, `workbench_appearance.tres` with the state
  tables in §4.2–4.5; the four consumer defs repoint from the shared
  profile to their own.
- `fuelled_appearance.tres`: `sheet_path` = the hearth sheet;
  `states.lit.first_frame` 0→1 (the `unlit`/`lit` names and the
  unpowered/power coupling are unchanged, so hearth, brazier,
  yard_lantern and metal_lantern pick the sheet up with no further edit).

---

## 7. Family map data (`data/buildings/families/`)

One `AtlasFamilyMap` resource per sheet (7 maps: 3 structural, 3
boundaries, 1 shared exterior; the interior sheet is documented here and
in the harness because no runtime code consumes its cell addresses
beyond the def references) with fields: `id`, `atlas_path`, `columns`,
`rows`, `cell_size`, and `slots: Dictionary` mapping slot index →
`{role, owner (def id, "" when reserved), status (master/derived/
reserved), master reference, master_of, generated}`, plus
`orientation_slots` for the 4-way parts. The new `resources/
atlas_family_map.gd` (tiny, no per-ID logic) backs it; the packer tool
and `test_building_art.gd` both read it, so the cell map lives in data
exactly as the building plan requires.

---

## 8. Verification and acceptance

### 8.1 `tests/test_game.gd` (updated in box 3)

- Keep: the 2×9 parts atlas exists at 64×288 and every cell holds art
  (the sheet still ships as stock reference art).
- Keep: 5×1 utilities and 4×1 stations dimension + full-cell checks
  (both files are byte-frozen by contract).
- Add: **no `BuildingDefinition` references the legacy 2×9 parts
  atlas** (migration complete).

### 8.2 `tests/test_building_art.gd` (new suite)

For every `AtlasFamilyMap` in data: (a) the sheet exists and its canvas
equals the contracted dimensions; (b) every slot marked generated or
owned is non-empty (≥1 opaque pixel); (c) every reserved slot is fully
transparent; (d) every def `atlas_cell`/`atlas_cells` reference for that
sheet resolves inside the sheet. For the six state sheets: exact canvas
size; each consumer profile's `sheet_path` points at an existing file in
`PACK_ASSETS`; every `first_frame + frame_count - 1` in the profile's
states is within the sheet's frame count; every frame strip is
non-empty and the sheet has an alpha channel. The stock manifest
(regenerated from `PACK_ASSETS` in `test_ground_pack`) therefore covers
all 16 new sheets automatically.

### 8.3 Review workflow (manual, native scale)

1. Generate wave → review each master at 32 px against the reference
   sheets (side-by-side in the stock reference card export).
2. Pack → open each sheet at 1:1 (native camera zoom; no editor
   upscaling) and walk every row: fills must tile (checker two cells),
   edge bands must align, derived orientations must read as the correct
   orientation, reserved slots must be empty.
3. In-game: the building sandbox capture tool
   (`tools/capture_building_sandbox.gd`) is run on a reference
   four-story build after the data migration — the resulting screenshots
   are the playtest evidence that the art reads at the actual camera
   zoom, including the ghost previews and orientation changes (boxes
   4–5).
4. `--headless --import`, full harness, `verify_texture_pack.gd` on the
   exported stock pack, then commit.

---

## 9. Generation budget and wave plan

| Family | Sheets | Generated sources |
|---|---|---|
| Structural masters | 3 | 32 |
| Boundary masters | 3 | 8 |
| Interior cells | 3 | 10 |
| Exterior cells | 1 | 8 |
| State-sheet frames | 6 | 19 |
| **Total** | **16 sheets** | **77** |

77 jobs at ≤8 concurrent → **10 waves** (1–4: the 32 structural
masters; 5: the 8 boundary masters; 6–8: the 10 interior + 8 exterior
cells plus the six state-sheet frame-0s; 9–10: the remaining 13
state frames, chain-ordered per §4.7). Frame 0 of each state sheet
settles before its frames 1..N are submitted; the 58 Family A masters
wave freely in tier order wood → stone → metal so each tier's pack and
review is a unit. Budget: ~1.5 account points per flash job (M8
preference) ≈ 116 of the remaining ~3,990.

---

## 10. Deviation log (carried into the plan's decision log at closeout)

- **D1** — sixth state sheet (`hearth.png`, 1×2) beyond the brief's
  five, required because four defs share the `fuelled_appearance`
  profile whose states need a sheet to resolve (§4.6).
- **D2** — orientation cells are one generated north master plus
  pack-time 90° rotations, not four generated variants per part. The
  contract's "generate a reviewed source per family or cell" is satisfied
  (one source per logical part; the derivation is mechanical, which the
  production rules sanction), and it is what keeps 16 edge parts inside
  budget while guaranteeing cross-orientation consistency. A
  per-orientation regeneration remains the refinement path if a derived
  orientation reads wrong at native zoom.
- **D3** — railings live in the *boundaries* sheets (the plan's content
  table lists "rail" under Boundary), so the structural grid keeps only
  wall/window/door as edge rows; the build palette still files rails
  under "stairs/rails" as a player-facing group — presentation, not
  atlas layout.
- **D4** — paths (and the crop-soil patch) are seamless ground fills and
  therefore live on the shared `exterior_props.png` tier rows rather than
  the per-tier structural fill rows, following the contract's "single
  shared" exterior sheet; porches/deck/patio stay structural fills
  because they are room-adjacent flooring.
- **D5** — the chest and hearth get **reserved** (empty) interior slots
  instead of generated static cells: their in-world presentation is the
  state sheet, and a second static cell would double-draw under it. The
  legacy atlas cell remains each sheet-part's documented
  fallback/base reference.
- **D6** — count reconciliation (document-internal, no design change):
  re-verifying the 65-definition list against `data/buildings/` shows
  the metal tier has **no door definition**, so its (0,3) structural
  slot is RESERVED rather than a generated `metal_door` master, and the
  stone tier carries 11 masters (its (3,0) fill slot stays RESERVED —
  no stone deck def). Corrected totals: 32 structural + 8 boundary +
  10 interior + 8 exterior = 58 Family A sources, **77 generated jobs
  overall** (the draft said 79). The §6 def partition is exactly
  29 + 26 + 10 = 65, and at closeout 65 + 3 down-stair defs = 68.
- **D7** — sheet-count reconciliation (document-internal, no design
  change): the §2.2 inventory lists exactly 16 new sheets (10 Family A:
  3 structural + 3 boundaries + 3 interior + 1 shared exterior; 6 state
  sheets). The draft's totals said 11 Family A / 17 overall — an
  off-by-one the D6 source-count audit (which fixed 58/77) did not reach.
  Corrected: **10 Family A sheets, 16 new sheets total, 77 generated
  sources**. PACK_ASSETS gains all 16 paths.
- **D8v3** — driver defect in generation run 3 (production, not design):
  58 masters verified pass, but **all 19 state-frame fill jobs failed**
  because the driver sent `no_background: true` on every call, while fill
  jobs must run with `no_background: false` (an opaque base is exactly
  what they need). Separately, the four "fixed" wave-4 masters were
  never actually re-verified: a loop bug in the driver's fix/verify path
  skipped their check, so their pass status was recorded without
  evidence. No sheet was packed from run 3's state frames.
- **D8v4** — run 4 with the corrected driver flag (`no_background: not
  fill` — opaque for fill jobs, transparent for master/derived jobs):
  **77/77 jobs verified pass on the first attempt** (transparency, exact
  dims, and ink per §8). The contract closed without a fifth round, and
  the option-B fallback (flattening the chained state frames into
  independent per-frame generations) was never needed.
