# Crafting System Documentation

## Overview

Crafting lets the player combine resources into new items using recipes
defined by `RecipeDefinition` resources. All 56 recipes are created in
code by `ItemDatabase._load_recipes()` (see `ITEM_SYSTEM.md` for the
item side).

## Recipe Definition Fields

Exact fields of `resources/recipe_definition.gd`:

| Field | Type | Description |
|-------|------|-------------|
| recipe_id | String | Unique recipe ID |
| result_item_id | String | Item produced (must exist in the item database) |
| result_quantity | int | Units produced per craft |
| crafting_station | String | `""` (hand) / `campfire` / `furnace` / `anvil` |
| required_items | Dictionary | `{item_id: quantity}` — e.g. `{"wood": 2}` |
| craft_time | float | Seconds to craft (0 = instant) |
| technology_id | String | Required research ID; empty means available without research |
| unlocked | bool | Unlocked by default |

Helper methods on the resource:

- `can_craft(inventory: Dictionary) -> bool` — every `required_items`
  entry is met by the given `{item_id: quantity}` map
- `get_cost_string() -> String` — "2x wood, 1x fibre"
- `get_rarity() -> String` — derived from result quantity / craft time

> The older version of this table listed `station_id`, `tech_id`,
> `ingredients[]`, `outputs[]` and `consume_ingredients`. Those do not
> exist — the schema above is the real one. Stations are stored in
> `crafting_station`; research is stored in `technology_id`.

## Crafting Stations

Stations used by the current 56 recipes:

| Station | Recipes |
|---------|---------|
| hand (empty string) | 46 recipes — all tools, planks, charcoal, torch, all wood and stone structural parts, chest, fence, farm_soil, stone_brick, flour, and crafting the stations themselves (campfire, furnace, workbench, anvil) |
| furnace | glass, iron_ingot, gold_ingot, copper_ingot, potion_health, potion_mana |
| anvil | bronze_ingot |
| campfire | cooked_meat, cooked_fish, soup |

**Current behaviour**: `CraftingComponent.craft_recipe()` checks only
`can_craft()` — the station field is displayed in the panel but **not enforced**,
because stations are not placeable in the world yet (all stations are
craftable *items*, e.g. the `furnace` building). Enforcing proximity is
a planned task (see PROJECT_STATE.md).

## Recipe Database (56 recipes)

| Recipe | Result (qty) | Station | Costs |
|--------|--------------|---------|-------|
| plank | plank ×4 | hand | wood 1 |
| charcoal | charcoal ×1 | hand | wood |
| glass | glass ×1 | furnace | sand, coal |
| iron_ingot | iron_ingot ×1 | furnace | iron_ore, coal |
| gold_ingot | gold_ingot ×1 | furnace | gold_ore, coal |
| copper_ingot | copper_ingot ×1 | furnace | copper_ore, coal |
| bronze_ingot | bronze_ingot ×1 | anvil | copper_ingot 2, tin_ore 1 |
| wooden_axe / stone_axe / iron_axe | ×1 | hand | plank + (fibre / stone / iron_ingot) |
| wooden_pickaxe / stone_pickaxe / iron_pickaxe | ×1 | hand | plank + (fibre / stone / iron_ingot) |
| wooden_sword / stone_sword / iron_sword | ×1 | hand | plank + (fibre / stone / iron_ingot) |
| stone_hoe | ×1 | hand | plank 2, stone 3, fibre 2 |
| wooden_hammer / stone_hammer | ×1 | hand | plank + stone |
| torch | torch ×4 | hand | plank, charcoal, fibre |
| wooden foundation / floor / wall / window / door / roof / stairs / ramp / pillar | ×1 | hand | plank |
| stone foundation / floor / wall / window / door / roof / stairs / ramp / pillar | ×1 (floor ×4) | hand | stone_brick |
| stone_brick | ×2 | hand | stone 2 |
| flour | ×2 | hand | wheat 1 (grassland plant drop) |
| stone_wall | ×1 | hand | stone_brick |
| campfire / furnace / workbench / anvil | ×1 | hand | stone/wood/charcoal or plank/stone or iron_ingot/stone |
| bed | ×1 | hand | plank, hide, fibre (hide drops from rabbit/deer/boar/wolf/polar_bear) |
| farm_soil | ×4 | hand | sand, clay |
| cooked_meat / cooked_fish / soup | ×1 | campfire | meat / fish / meat+mushroom+herb (creature + plant drops) |
| bread | ×2 | hand | flour, berry |
| potion_health / potion_mana | ×1 | furnace | (glass) + herb (herb is a plant drop) |

\* exact quantities: see `src/systems/item_database.gd`.

### Ghost recipes

The crafting panel hides any recipe whose ingredients are not obtainable
from the current world (resource spawner drops across all biomes +
**creature spawner loot tables** + starting inventory + recursive craft
results). Phase 3 closed the last gaps — creature drops (meat, fish,
hide, feather, bone), plant drops (wheat, herb, mushroom), and the new
`stone_brick`/`flour` recipes — so unlocked recipes have complete ingredient
chains. The panel intentionally hides recipes behind unresearched technology
(stone construction, then metalworking), as well as any future recipe whose
ingredients no live system can provide.

## Crafting Flow

1. Player presses **C** to open the crafting UI — the panel starts
   hidden (it used to cover the HUD at startup with all 40 rows); C
   again closes it
2. `Main` gathers obtainable recipes → `CraftingPanel.refresh(list)`
3. Panel builds one `RecipeItemUI` row per recipe (name, cost, station,
   result, Craft button)
4. Player presses Craft → `CraftingComponent.craft_recipe(recipe_id, inventory)`
5. `can_craft()` fails → `recipe_failed` signal with a reason; succeeds →
   ingredients consumed, output added
6. `result_crafted` signal emitted → Main adds items to the inventory
   (and refreshes the panel)

The recipe panel is not yet scrollable, so long lists can overflow its
visual bounds. `MAX_DISPLAYED = 15` is the cap for its compact preview rows.

## Creating New Recipes

```gdscript
recipes["ruby_pickaxe"] = _create_recipe(
    "ruby_pickaxe", "ruby_pickaxe", 1, "",          # hand-crafted
    {"plank": 2, "ruby_shard": 3}, 5.0)
```
`_create_recipe(recipe_id, result_item_id, result_quantity,
crafting_station, required_items, craft_time = 0.0)`

The new recipe appears in the panel automatically once its ingredients
are obtainable.
