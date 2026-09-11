# Texture Packs

Wildfall can switch its presentation assets without changing terrain data,
collision, buildings, inventories, or saves. The active pack is selected in
**Options** from either the title screen or the in-game **Pause → Options**
menu; it applies immediately to the running world.

## Workflow for AI-assisted refinement

1. Open **Options** and select **Export Stock Texture Card + Reference**.
2. Use **Open Texture Pack Folder**. The exported `stock_texture_card.png`
   is a contact card of every source sheet, while `stock_reference/` contains
   the separate original PNGs and `manifest.json`.
3. Feed the contact card or the individual reference sheets to your editor.
4. Choose **Create / Open Editable Refinement Pack**. It creates
   `refinement/` as an editable copy of the stock assets and selects it.
5. Replace only the PNGs you changed, keeping their paths, dimensions, and
   atlas cell ordering. Return to Options and switch to another pack or back
   to Stock at any time.

Packs live under `user://texture_packs/`. The menu’s folder button opens the
actual platform folder, so this works in the editor and exported game builds.

## Pack contract

An override pack mirrors these paths below its own folder:

Visible biome backgrounds are exported as eight 256×256 images under
`assets/ground/`: `water.png`, `sand.png`, `grass.png`, `forest.png`,
`dirt.png`, `stone.png`, `snow.png`, and `mud.png`. These correspond to the
shared surfaces used by the six biomes (for example desert uses sand and
stone; arctic uses snow). They are sampled in world space and repeated every
256 world pixels. Keep opposite edges seamless when editing. Terrain blends
still apply, and the current low-resolution ground renderer softens fine detail.
The stock contact card includes these backgrounds before the original sheets.
Creating the refinement pack again adds missing files without replacing edits.

```text
assets/tiles/wildfall-terrain-atlas.png
assets/tiles/wildfall-water-animation.png
assets/tiles/wildfall-resources-atlas.png
assets/tiles/wildfall-ground-details.png
assets/resources/wildfall-forage-plants.png
assets/characters/explorer-base-walk.png
assets/characters/explorer-storm-walk.png
assets/creatures/alien-creature-roster.png
```

Partial packs are supported: missing images safely fall back to Stock.
`manifest.json` is written into every exported pack. It is a plain, easily
decoded JSON file with a schema name/version and one entry per PNG. Each entry
includes its export path, friendly name, in-game purpose, systems that use it,
atlas/sprite layout, and an editing note. Give this file to an image editor or
AI refinement tool alongside the contact card so it can identify every image
without guessing from the artwork.

Terrain and resource sheets are atlases. Keep their existing grid order and
dimensions—terrain 4×2, water 4×1, resources 4×2, ground details 4×2, and
forage 2×2. The game retains its TileSet cell IDs, water collision, and
automatic terrain-edge/corner blending while the artwork changes, so a pack
cannot accidentally change navigation or resource reachability.

## Live refresh scope

Switching packs rebuilds the terrain TileSet and rendered ground details, and
reloads live resources, the player, and streamed creatures. New chunks and
entities use the same selected pack automatically.
