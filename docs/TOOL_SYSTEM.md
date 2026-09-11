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
Repeated actions have a 0.45-second cooldown. This is an initial balance pass;
durability and authored character/tool animation sheets are still future work.

Verification: `godot --headless --path . --script tests/test_harvesting.gd`
exercises quick-bar selection, wood and stone collection, and crafting planks
from harvested wood through the real main scene.
