## Global event bus singleton for game-wide communication.
extends Node

# --- Game State Events ---
signal game_started
signal game_paused
signal game_resumed
signal game_over
signal world_seed_set(seed: int)

# --- World Events ---
signal chunk_loaded(chunk_coords: Vector2i)
signal chunk_unloaded(chunk_coords: Vector2i)
signal biome_changed(biome_id: String)

# --- Player Events ---
signal player_spawned(position: Vector2)
signal player_died
signal health_changed(current: float, max_health: int)
signal hunger_changed(current: float, max_hunger: float)

# --- Inventory Events ---
signal inventory_changed
signal item_added(item_id: String, quantity: int)
signal item_removed(item_id: String, quantity: int)
signal inventory_full
signal durability_changed(item_id: String, current: int, max: int)
signal tool_broken(item_id: String)

# --- Crafting Events ---
signal recipe_crafted(recipe_id: String)
signal recipe_failed(recipe_id: String, reason: String)

# --- Debug Events ---
signal toggle_debug
signal toggle_inventory_ui
signal toggle_crafting_ui
signal toggle_build_ui
signal toggle_missions_ui

# --- Mission Events ---
signal mission_accepted(mission_id: String)
signal mission_completed(mission_id: String)
signal missions_changed

# --- Combat Events ---
signal entity_hit(entity_id: String, damage: float)
signal entity_died(entity_id: String)
signal projectile_fired(origin: Vector2, direction: Vector2)

# --- World presentation ---
signal time_changed(hour: float, day: int)
signal weather_changed(weather_name: String)
signal building_placed(building_id: String, coords: Vector2i)
