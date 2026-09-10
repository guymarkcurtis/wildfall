# Crafting System Documentation

## Overview

Crafting allows players to combine resources into new items using recipes defined by `RecipeDefinition` resources.

## Recipe Definition Fields

| Field | Type | Description |
|-------|------|-------------|
| id | String | Unique recipe ID |
| display_name | String | Name in UI |
| description | String | Recipe description |
| station_id | String | Required crafting station (empty = hand) |
| tech_id | String | Required technology unlock |
| craft_time | float | Seconds to craft |
| unlocked | bool | Unlocked by default |
| ingredients | Array[Dict] | Required items |
| outputs | Array[Dict] | Resulting items |
| consume_ingredients | bool | Remove ingredients on craft |

## Ingredient/Output Format

```gdscript
{
    "item_id": "wood",
    "quantity": 3
}
```

## Crafting Flow

1. Player opens crafting UI
2. System shows available recipes
3. Player selects a recipe
4. System checks ingredients
5. If valid: consume ingredients, produce output
6. Signal `recipe_crafted` emitted

## Crafting Stations

Some recipes require a station:
- `crafting_table` → Basic recipes
- `furnace` → Smelting
- `anvil` → Metalworking

If `station_id` is empty, recipe can be crafted by hand.

## Technology Integration

Recipes can be locked behind technology:
```gdscript
tech_id = "metalworking"
```
Player must unlock the technology before the recipe becomes available.

## Creating New Recipes

1. Create `RecipeDefinition` resource
2. Set `id` and `display_name`
3. Add `ingredients` array
4. Add `outputs` array
5. Set `craft_time` (0.0 for instant)
6. (Optional) Set `station_id` and `tech_id`

## Example: Wooden Plank

```
Recipe ID: plank
Name: Wooden Plank
Ingredients: [{item_id: "wood", quantity: 2}]
Outputs: [{item_id: "plank", quantity: 3}]
Craft time: 1.0
```
