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
   to Stock at any time. Choose a pack in the selector, then press its
   **Apply** button. The water/sand/grass preview confirms the active art in
   both the title-screen and in-game Options menu.

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
still apply. Active texture packs are composed at the native 32px-per-tile
source resolution, so pack detail remains crisp rather than being blurred into
broad colour blocks.
The stock contact card includes these backgrounds before the original sheets.
Creating the refinement pack again adds missing files without replacing edits.

```text
assets/tiles/wildfall-terrain-atlas.png
assets/tiles/wildfall-water-animation.png
assets/tiles/wildfall-resources-atlas.png
assets/tiles/wildfall-ground-details.png
assets/tiles/wildfall-crafting-stations.png
assets/resources/wildfall-forage-plants.png
assets/characters/explorer-base-walk.png
assets/characters/explorer-storm-walk.png
assets/characters/actions/male-axe.png
assets/characters/actions/male-pickaxe.png
assets/characters/actions/male-sword.png
assets/characters/actions/male-bow.png
assets/characters/actions/male-hoe.png
assets/characters/actions/male-hammer.png
assets/characters/actions/female-axe.png
assets/characters/actions/female-pickaxe.png
assets/characters/actions/female-sword.png
assets/characters/actions/female-bow.png
assets/characters/actions/female-hoe.png
assets/characters/actions/female-hammer.png
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

Character action sheets are optional four-frame strips. They are shared by
tool category, so `male-axe.png`, for example, plays for wooden, stone, and
iron axes alike. Each strip reads left to right as wind-up, impact/release,
follow-through, and recovery. Packs may replace only the character sheets and
these action strips, leaving all world art stock; switching to **Stock**
immediately restores the original explorer models and lightweight stock tool
drawings.

`wildfall-crafting-stations.png` is a 4×1 atlas of 32×32 cells in this exact
order: **campfire, furnace, workbench, anvil**. These are the visuals for the
placeable stations that enable nearby crafting recipes. The manifest repeats
this ordering for image tools, and it must be preserved when refining the art.

## Live refresh scope

Switching packs rebuilds the terrain TileSet and rendered ground details, and
reloads live resources, the player, streamed creatures, and placed crafting
stations. New chunks and entities use the same selected pack automatically.
