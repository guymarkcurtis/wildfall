# Development Roadmap

## Phase 1: Foundation
- [x] Project structure
- [x] Core systems (EventBus, ChunkSystem, GameManager)
- [x] Data-driven resources
- [x] World generation (noise layers)
- [x] Inventory system
- [x] Crafting system
- [x] Player entity
- [x] Basic UI (HUD, Inventory panel, Crafting panel)
- [x] Save system

## Phase 2: Content
- [x] Tile set and terrain rendering (placeholder 32px orthogonal colors)
- [x] 20+ item definitions (62 items)
- [x] 15+ recipe definitions (40 recipes, all obtainable)
- [x] Creature definitions (7 types, wired)
- [ ] Building definitions (data exists, not wired)
- [ ] Technology tree (data exists, not wired)
- [ ] Placeholder art assets (colored shapes only; no sprites)

## Phase 3: Gameplay

Creature slice is wired (2026-09-10). The rest of this phase is not done.

- [x] Tile-based terrain rendering (orthogonal 32px top-down tiles)
- [x] Resource node placement and pickup
- [x] Creature spawn + wander/flee AI (7 types, biome-gated, E-to-kill, loot)
- [ ] Player collision with terrain
- [ ] Mouse-aimed ranged combat (face cursor, fire with LMB)
- [ ] View rotation while moving (`,` / `.` 45° snaps, middle-mouse free rotate, Home reset)
- [ ] Screen-relative WASD under a rotated camera
- [ ] Creature AI (pathfinding, aggression / chase-attack)
- [ ] Building placement and destruction
- [ ] Weather system
- [ ] Day/night cycle
- [ ] Status effects

## Phase 4: Polish
- [ ] Sound effects
- [ ] Music
- [ ] Particle effects
- [ ] UI polish
- [ ] Tutorial/intro sequence
- [ ] Balance tuning
- [ ] Performance optimization

## Phase 5: Expansion
- [ ] Multiplayer support
- [ ] Mod support
- [ ] Additional biomes
- [ ] Quest system
- [ ] Advanced crafting stations
- [ ] Vehicle system
