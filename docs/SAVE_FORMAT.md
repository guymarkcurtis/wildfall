# Save Format Documentation

## Overview

Saves are JSON files under `user://saves/`. The format is **versioned** and
split into **named modules** so new systems can be added without breaking
old files.

- Unknown modules on load are ignored (forward compatible).
- Missing modules keep runtime defaults (backward compatible).
- Each version bump has a `_migrate()` step in `SaveSystem`.

## Paths

```
user://saves/manual_<unix>.json     # player Save Game (unlimited)
user://saves/autosave_<unix>.json   # autosave (last 2 kept)
user://settings.json                # autosave enabled/disabled
```

Load Game lists both kinds, newest first. Autosave runs every 5 minutes
while playing (not while paused) if enabled in Options.

## Boot flow

The project main scene is `scenes/title.tscn`.

| Title button | Result |
|---|---|
| New Game | `GameSession.request_new_game()` → `main.tscn` generates a world |
| Load Game | Lists manual + autosave slots → `main.tscn` loads the chosen file |
| Options | Autosave every 5 minutes (keeps last 2) |
| Quit Game | `get_tree().quit()` |

`GameSession` is a static class (not an autoload). Main consumes the load
flag once in `_ready`. In-game: **Esc** pause menu (Continue / Save / Load /
Options / Return to Title / Quit). F5 save, F9 load still work.

## Version history

| Version | Changes |
|---------|---------|
| 1 | Flat JSON: player, world.seed, unused game_time/day_number |
| 2 | `format: wildfall-save`, `modules` map, migrations from v1 |
| 3 | Added the `technology` module; missing research data safely uses starting unlocks |

## Current format (v3)

```json
{
  "format": "wildfall-save",
  "version": 3,
  "kind": "manual",
  "game_mode": "survival",
  "timestamp": 1730000000,
  "modules": {
    "world": { "seed": 12345 },
    "time": { "current_hour": 8.5, "current_day": 1 },
    "weather": { "weather": 0, "intensity": 0.0, "duration": 40.0, "next_change": 40.0 },
    "status": {},
    "technology": { "unlocked": ["wood_building", "stone_building"] },
    "buildings": [
      { "item_id": "wooden_wall", "x": 3, "y": 3, "story": 0, "health": 100 }
    ],
    "player": {
      "position": { "x": 0.0, "y": 0.0 },
      "health": { "max_health": 100, "current_health": 100.0, "is_dead": false },
      "hunger": { "max_hunger": 100.0, "current_hunger": 100.0 },
      "inventory": { "slots": {}, "max_weight": 100.0, "max_slots": 50 },
      "equipped_tool": "wooden_bow",
      "hotbar": ["wooden_axe", "wooden_pickaxe", "wooden_sword", "wooden_bow", "arrow", "", "", "", ""],
      "active_hotbar_slot": 0
    },
    "camera": { "rotation": 0.0 }
  }
}
```

Apply order on load: `world` (regenerates chunks) → `time` → `weather` →
`status` → `technology` → `buildings` → `player` → `camera`. World regen happens first so
player position and buildings are restored after spawn reset.

## Adding a new system later

In `Main._register_save_modules()`:

```gdscript
save_system.register_module("quests", _collect_quests, _apply_quests)
```

Collect returns JSON-safe Dictionary/Array. Apply must tolerate missing
keys. Bump `SAVE_VERSION` only when the **shape of an existing module**
changes; then add `_migrate_vN_to_vN+1()` and call it from `migrate()`.

## v1 → v2 migration

Old files with a top-level `player` / `world` and no `modules` key are
wrapped into the v2 module map. Seed and player blob are preserved.

## API

```gdscript
save_system.save_manual()
save_system.save_autosave()             # then prunes to last 2
save_system.load_game(path)
save_system.list_save_entries()         # newest first, both kinds
SaveSystem.set_autosave_enabled(true)
save_system.migrate(old_dict)           # used by tests and the loader
save_system.register_module(name, collect, apply)
```
