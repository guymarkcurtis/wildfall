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
| 4 | Added `world_state`: destroyed resource and creature spawn tiles persist without serializing deterministic chunks |
| 5 | Added tool durability and mission modules; cave ledgers remain optional world-state fields |
| 6 | Added `world.generation_version` (the world-generation version that built the world, WG-12) |
| 7 | Added `map_exploration`: revealed chunk identities and explored POI markers |
| 8 | Building entries became **layered records**: `layer`, optional `orientation`/`footprint`, and an optional `state` payload for capability state (containers, fuel, stations). v1–v7 entries load with the layer derived from the part's definition and empty state |

## Current format (v8)

```json
{
  "format": "wildfall-save",
  "version": 8,
  "kind": "manual",
  "game_mode": "survival",
  "timestamp": 1730000000,
  "modules": {
    "world": { "seed": 12345, "generation_version": 2 },
    "map_exploration": { "revealed_chunks": [], "markers": [] },
    "world_state": {
      "destroyed_resources": [{ "x": 4, "y": -2 }],
      "destroyed_creatures": [{ "x": 7, "y": 1 }],
      "discovered_caves": [],
      "cave_changes": {}
    },
    "time": { "current_hour": 8.5, "current_day": 1 },
    "weather": { "weather": 0, "intensity": 0.0, "duration": 40.0, "next_change": 40.0 },
    "status": {},
    "technology": { "unlocked": ["wood_building", "stone_building"] },
    "buildings": [
      {
        "item_id": "wooden_wall", "x": 3, "y": 3, "story": 0,
        "layer": "edge", "orientation": "north", "health": 100,
        "state": {}
      }
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

### Building entries (v8 layered records)

Each entry describes one placed record: `item_id`, tile `x`/`y`, `story`,
`layer` (one of `ground`, `floor`, `edge`, `object`, `overhead`,
`connector`), optional `orientation` (edge parts: `north`/`east`/`south`/
`west`), `health`, optional `footprint: [w, h]` for multi-tile objects, and
an optional `state` dictionary reserved for capability state (M5+: container
slots; `enabled`; `fuel` indexed slots plus `fuel_seconds_remaining`; station
inputs/outputs). Edge orientations are
canonical in the runtime index — the east edge of one tile is the same slot
as the west edge of its neighbour — so saved orientation + coordinates
unambiguously identify the slot.

`state` holds only non-default runtime state for the capabilities that
building's definition actually declares; JSON-safe primitives only, and a
non-empty container inventory must never be omitted. Loaders default missing
`layer`/`orientation`/`state` (exactly the v7→v8 migration: derive the layer
from the definition's placement model, single default orientation, empty
state) and must never invent contents or enable an old placed fire.

Apply order on load: `world` (regenerates chunks) → `world_state` (suppresses
mutated deterministic spawns) → `time` → `weather` →
`status` → `technology` → `buildings` → `player` → `camera`. World regen happens first so
player position and buildings are restored after spawn reset.

Cave fields are optional extensions to the existing world-state ledger, so old
saves load with empty cave state. Cave geometry is regenerated from the world
seed and stable cave identity. `discovered_caves` contains only stable cave
IDs, while `cave_changes` is reserved for future player-caused cave mutations;
neither serializes untouched cave geometry. Reset/depletion policy is not
embedded in the generator.

## Adding a new system later

In `Main._register_save_modules()`:

```gdscript
save_system.register_module("quests", _collect_quests, _apply_quests)
```

Collect returns JSON-safe Dictionary/Array. Apply must tolerate missing
keys. Bump `SAVE_VERSION` whenever the persisted schema changes, then add
the required migration defaults in `migrate()`.

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
