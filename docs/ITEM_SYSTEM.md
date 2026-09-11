# Item System Documentation

## Overview

All items in the game are defined by `ItemDefinition` resources. The 62
items currently in the game are created **in code** by
`src/systems/item_database.gd` (`ItemDatabase` is a Node in `main.tscn`,
not a .tres file). Items define stack size, weight, category, bonuses and
tool behaviour.

## Item Definition Fields

Exact fields of `resources/item_definition.gd`:

| Field | Type | Description |
|-------|------|-------------|
| item_id | String | Unique stable ID (never change) |
| display_name | String | Name shown to player |
| description | String | Tooltip text |
| category | String | Grouping (see table below) |
| stack_size | int | Max items per stack (64 default) |
| weight | float | Weight per item in game units |
| rarity | String | common / uncommon / rare / epic / legendary |
| texture_path | String | Path to icon texture (empty = placeholder) |
| health_bonus | float | Healing when consumed |
| hunger_bonus | float | Satiety when consumed |
| damage_bonus | float | Extra damage when used as a tool/weapon |
| durability | int | Hit points before the tool breaks (0 = no durability system) |
| tool_type | String | axe / pickaxe / sword / hammer / hoe / "" (not a tool) |

> The older version of this table listed `auto_pickup`, `is_tool`,
> `is_weapon`, `is_consumable`, `icon_path`, `value` and `custom_data`.
> None of those exist in `ItemDefinition` — use the fields above.

## Categories (as defined in the item database)

| Category | Count | Items |
|----------|-------|-------|
| resource | 18 | wood, stone, fibre, clay, sand, leaf, bone, hide, feather, coal, iron_ore, gold_ore, copper_ore, tin_ore, charcoal, seed_wheat, wheat, herb |
| building | 13 | torch, wooden_wall, wooden_door, stone_wall, stone_floor, campfire, furnace, workbench, anvil, chest, bed, farm_soil, fence |
| food | 9 | berry, cooked_meat, cooked_fish, bread, soup, fish, meat, apple, mushroom |
| material | 8 | plank, stone_brick, iron_ingot, gold_ingot, copper_ingot, bronze_ingot, glass, flour |
| tool | 9 | wooden/stone/iron axe, wooden/stone/iron pickaxe, stone_hoe, wooden/stone hammer |
| weapon | 3 | wooden_sword, stone_sword, iron_sword |
| consumable | 2 | potion_health, potion_mana |

## Inventory Integration

Items are stored in `InventoryComponent` (a RefCounted owned by Player)
as a dictionary keyed by item id:
```gdscript
{ "wood": 25, "stone": 10 }
```
plus per-stack `max_stack` tracking. Operations:

- `add_item(item_id, quantity)` → returns the quantity that did NOT fit
- `remove_item(item_id, quantity)` → removes up to the requested amount
- `get_item_quantity(item_id)` → current quantity
- `has_item(item_id, quantity)` → availability check
- `get_all_items()` / `get_all_item_ids()` → full maps
- `get_total_weight()` → compared against `max_weight` (100)
- Signals: `inventory_changed`, `item_added`, `inventory_full`

Constraints: `max_slots = 50`, `max_weight = 100`.

## Creating New Items

Add a call in `ItemDatabase._load_items()` (items are defined in code,
not in .tres files):

```gdscript
items["ruby_shard"] = _create_item("ruby_shard", "Ruby Shard", "material",
    16, 1.0, "", 0.0, 0.0, 0.0, 0, "")
```

Signature:
`_create_item(item_id, display_name, category, stack_size, weight,
rarity, health_bonus, hunger_bonus, damage_bonus, durability, tool_type)`

Rules:
- `item_id` is a stable identifier — recipes, saves and spawner yields all
  key off it. Never reuse or rename an id.
- Only add an item to the world if something can produce it (spawner
  yield, craft result or starting inventory), otherwise any recipe that
  consumes it will be hidden by the crafting panel's obtainability filter.
