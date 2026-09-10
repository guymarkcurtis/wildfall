# Item System Documentation

## Overview

All items in the game are defined by `ItemDefinition` resources. These define properties like stack size, weight, category, and icon.

## Item Definition Fields

| Field | Type | Description |
|-------|------|-------------|
| id | String | Unique stable ID (never change) |
| display_name | String | Name shown to player |
| description | String | Tooltip text |
| category | String | Grouping (tool, food, etc.) |
| stack_size | int | Max items per stack (64 default) |
| weight | float | Weight in game units |
| auto_pickup | bool | Auto-collect on touch |
| is_tool | bool | Can be used as tool |
| is_weapon | bool | Can be used as weapon |
| is_consumable | bool | Can be eaten/used |
| icon_path | String | Path to icon texture |
| value | int | Base currency value |
| custom_data | Dictionary | Extended properties |

## Categories

| Category | Description | Examples |
|----------|-------------|----------|
| resource | Raw materials | wood, stone, iron_ore |
| material | Processed materials | plank, iron_ingot |
| tool | Crafting tools | axe, pickaxe |
| weapon | Combat weapons | spear, sword |
| food | Consumable food | berry, cooked_meat |
| consumable | Other consumables | potion, seed |
| building | Placeable structures | wall, door |
| component | Crafting components | gear, circuit |
| armor | Protective equipment | leather_armor |
| seed | Plantable seeds | wheat_seed |

## Inventory Integration

Items are stored in `InventoryComponent` as:
```gdscript
{
    "item_id": "wood",
    "quantity": 25,
    "max_stack": 64
}
```

Operations:
- `add_item(item_id, quantity)` → returns unadded quantity
- `remove_item(item_id, quantity)` → returns removed quantity
- `get_item_quantity(item_id)` → returns current quantity
- `has_item(item_id, quantity)` → checks availability

## Creating New Items

1. Create a new `.tres` resource file
2. Set `id` to a unique string
3. Set `display_name` and `description`
4. Set appropriate `category`
5. Configure `stack_size` and `weight`
6. (Optional) Add `icon_path`

Example:
```gdscript
# In Godot editor:
# Create new Resource → ItemDefinition
# Set id = "iron_ingot"
# Set display_name = "Iron Ingot"
# Set category = "material"
# Set stack_size = 64
# Set weight = 5.0
```
