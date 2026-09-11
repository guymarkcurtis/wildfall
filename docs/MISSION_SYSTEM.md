# Mission System

Data-driven missions that track **real player actions** (pickups, kills,
builds) rather than scripted events. Three pieces:

| Piece | Location | Role |
|---|---|---|
| `Mission` | `src/world/mission.gd` | Plain RefCounted value object: definition (code-defined) + runtime state. No signals, no scene-tree access. |
| `MissionManager` | `src/systems/mission_manager.gd` | Owns the catalog and all runtime state; the only part that touches the scene tree. A plain node in `main.tscn` (last child, next to the other systems). |
| `MissionPanel` | `src/ui/mission_panel.gd` | The journal UI under the HUD: sections for active, completed, and available missions with progress bars and an accept button. |

## How it is wired

`MissionManager._ready()` resolves its peers by relative path
(`../GameEventBus`, `../ItemDatabase`, `../Player`, `../TechnologySystem`),
loads the code-defined catalog (`_load_missions()` — data lives in code,
not .tres files, per project convention), and wires live bus signals into
its progress counters. `Main` owns four handlers: toggle (bus
`toggle_missions_ui` → panel), accept, and refresh on
`mission_completed` / `missions_changed`.

## Key flows

- **Open/close the journal** — player presses **M** →
  `GameEventBus.toggle_missions_ui` → `Main` → `MissionPanel.toggle()`
  (Escape closes while open).
- **Accept** — the panel's accept button (or the harness calling
  `accept_mission`) → `MissionManager.accept_mission(id)`: succeeds only
  if **every prerequisite mission is COMPLETED**; `AVAILABLE →
  IN_PROGRESS`. Accept into the manager's `_active` list. Progress only counts
  while a mission is IN_PROGRESS, so accepting is what "arms" it —
  pickups that happened before accepting do not count.
- **Progress** — real gameplay events (item picked up, creature killed,
  building placed, tech researched) flow over the bus; the manager
  forwards amounts only to IN_PROGRESS missions whose objective matches
  (`collect` → inventory item id, `kill` → creature type, `build` →
  building id, `research` → technology id). Progress caps at the
  objective count; reaching it flips the mission to COMPLETED.
- **Completion** — rewards are applied immediately: `reward_items` are
  added to the player's inventory, `reward_research` technologies are
  unlocked for free, then `mission_completed` + `missions_changed` are
  emitted on the bus for the panel and HUD toasts.

## Save / load (format v5)

The save's `missions` module stores only runtime state
(`mission_id → {state, progress}`); definitions stay in code. On a **new
world** the first main-chain mission (`main_1`) is auto-accepted. On a
**loaded game** the saved module overrides that default; saves older than
v5 simply lack the module and keep the fresh defaults. A completed
mission's progress is snapped back to its objective on restore.

## The catalog (7 missions)

| id | Title | Kind | Objective | Prerequisite | Rewards |
|---|---|---|---|---|---|
| `main_1` | First Steps | main (auto-accepted) | collect 15 wood | — | 10 stone |
| `main_2` | Foundations | main | collect 20 stone | main_1 | 15 clay + `stone_building` tech |
| `main_3` | Hunt & Gather | main | kill 3 rabbits | main_2 | 5 hide, 10 berry |
| `main_4` | Light in the Wild | main | build 1 campfire | main_3 | 5 coal + `metalworking` tech |
| `side_forage` | Fibre Forager | side | collect 10 fibre | — | 8 stone |
| `side_ore` | Prospector | side | collect 5 copper ore | — | 10 clay |
| `side_fish` | Angler | side | kill 3 fish | — | 8 clay, 8 berry |

The four main-chain missions form a gated chain (each unlocks the next
when completed); the three side missions are optional and can be accepted
at any time. All seven can be completed in a single session — the harness
asserts exactly that.

Verification: `tests/test_game.gd` "Missions" section (32 checks) covers
the M-key/bus toggle, the panel window, auto-accept on a new world,
lock + unmet-prerequisite reporting, progress from real pickups/kills/
builds, rewards (items + tech unlocks), completion capping, the full
7-of-7 chain, and persistence across a save/load cycle.
