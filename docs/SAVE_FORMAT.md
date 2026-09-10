# Save Format Documentation

## Overview

Games are saved as JSON files in the user directory. The save system tracks version for forward compatibility.

## Save Path

```
user://savegame.json
```

## Version History

| Version | Changes |
|---------|---------|
| 1 | Initial format: player position, health, hunger, inventory, world seed |

## Save Format (v1)

```json
{
    "version": 1,
    "timestamp": 1234567890,
    "player": {
        "position": {"x": 0.0, "y": 0.0},
        "health": {
            "max_health": 100,
            "current_health": 85.0,
            "is_dead": false
        },
        "hunger": {
            "max_hunger": 100.0,
            "current_hunger": 75.0
        },
        "inventory": {
            "slots": {
                "wood": {"quantity": 25, "max_stack": 64},
                "stone": {"quantity": 10, "max_stack": 64}
            },
            "max_weight": 100.0,
            "max_slots": 50
        }
    },
    "world": {
        "seed": 12345,
        "chunks": {
            "0,0": { /* chunk data */ },
            "1,0": { /* chunk data */ }
        }
    },
    "game_time": 3600.0,
    "day_number": 30
}
```

## Migration

When loading an older save:
1. Check `version` field
2. Apply migration functions for each older version
3. Save as current version

## Save/Load Functions

```gdscript
# Save
save_system.save_game("user://savegame.json")

# Load
save_system.load_game("user://savegame.json")

# Check exists
save_system.has_save("user://savegame.json")

# Delete save
save_system.delete_save("user://savegame.json")

# List saves
var saves := save_system.list_saves()
```

## Best Practices

1. Always include `version` field
2. Use stable IDs, not display names
3. Don't save computed/reconstructible data
4. Validate save data before applying
5. Handle missing fields gracefully
