# Tool use and harvesting

Select an axe or pickaxe using its quick-bar number (1–9), approach a
resource, face it with the mouse, and hold left-click or E. Matching tools
harvest faster: axe for trees, pickaxe for rock and ore. Selecting a bow
makes left-click fire arrows instead.

Tools have a visible procedural held shape and a short swing animation.
Resources flash on impact and show remaining health. Materials enter the
inventory when the node is depleted and can immediately be used for crafting.
Resource harvesting takes priority over nearby creatures. Open inventory,
crafting, research, and building mode block harvesting.

Matching tool damage is five times its item damage bonus (minimum 10).
Hands or mismatched items deal 5; forage receives at least 25 damage.
Repeated actions have a 0.45-second cooldown.

# Durability

Every tool (axe, pickaxe, sword, bow) carries a durability counter taken
from its `ItemDefinition.durability` — e.g. the wooden axe is 50. Rules:

- One point is consumed per swing that actually lands on a resource or
  creature, and per arrow fired from a bow. Merely selecting or equipping
  a tool on the quick-bar costs nothing.
- Current durability is shown next to the tool in the inventory and on the
  quick-bar slots, and decreases live as the tool is used.
- At zero the tool breaks: its inventory slot is cleared, a toast notifies
  the player, and the player automatically falls back to bare hands (no
  swing, no damage bonus) until a replacement is equipped.
- There is no repair in v1 — a broken tool is gone. Crafting another one
  (the recipe stays unlocked) gives a fresh tool at full durability.

Durability state lives in the inventory component (per-slot `current` /
`max`), not in the player or the tool visuals, so it persists naturally:
save format v5 stores per-slot durability and restores it on load, and
pre-v5 saves are migrated by backfilling tools at full durability.

Verification: `tests/test_game.gd` (full harness, sections "Tool
durability" and "Missions") covers definition values, consumption on
use, break-at-zero with the bare-hand fallback, re-crafting at full,
non-durable items, and the save/load round trip. The standalone
`godot --headless --path . --script tests/test_harvesting.gd` run
exercises quick-bar selection, wood and stone collection, and crafting
planks from harvested wood through the real main scene.
