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

- [x] Tile-based terrain rendering (orthogonal 32px top-down tiles)
- [x] Resource node placement and pickup
- [x] Creature spawn + wander/flee AI (7 types, biome-gated, E-to-kill, loot)
- [x] Player collision with terrain (stone cliffs solid; water slows)
- [x] Mouse-aimed ranged combat (face cursor, LMB fires bow/arrows)
- [x] View rotation while moving (`,` / `.` 45° snaps, middle-mouse free rotate, Home reset)
- [x] Screen-relative WASD under a rotated camera
- [x] Creature AI (pathfinding, aggression / chase-attack for wolf, boar, polar bear)
- [x] Building placement and destruction (B to build, LMB place, F demolish)
- [x] Weather system
- [x] Day/night cycle
- [x] Status effects

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
