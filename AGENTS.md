# Riftwake Agent Guidance

## World-generation architecture

Riftwake uses a deterministic, finite, chunk-streamed procedural world. The
generation APIs must remain coordinate-based and seed-stable so the configured
finite bounds can later expand toward effectively infinite worlds without a
generator rewrite.

The permanent rule is:

> Code defines systems. Data defines content.

World-generation code may define field sampling, seed derivation, chunk
lifecycle, distribution algorithms, water masks, POI stages, and cave-space
algorithms. It must not hard-code the names or special behavior of ordinary
biomes, resources, cave types, or POIs. Content belongs in discoverable Godot
Resources under `data/world/` and is interpreted through generic fields.

In particular, do not add branches such as `if biome == "..."`,
`if resource == "..."`, or name-based `match` statements to generation code.
Adding a normal biome or resource should normally be an asset-only change.

Biome adjacency, terrain presentation, resource restrictions/distributions,
and cave-entrance suitability are data. Water is a physical world system, not
an ordinary biome. Caves are separate generated spaces reached through stable
surface entrance identities; cave generation must remain separate from the
undecided cave reset/depletion policy.

Preserve the existing mutation-ledger save model: reconstruct the deterministic
base world and persist player/world changes such as harvested spawns, builds,
loot, cave discovery, and future cave changes. Do not serialize every untouched
procedural object. Keep content authoring independent from engine edits and
avoid unrelated gameplay rewrites.

When changing generation, update the relevant authoring documentation, preserve
old save loading through migrations, and run the Godot headless harness plus a
launch/parser check before handing off.
