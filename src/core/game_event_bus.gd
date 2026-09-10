## Global event bus singleton for game-wide communication.
## Load this as an autoload in project settings.
extends Node

# --- Game State Events ---
signal game_started
signal game_paused
signal game_resumed
signal game_over
signal world_seed_set(seed: int)
signal chunk_loaded(chunk_coords: Vector2i)
signal chunk_unloaded(chunk_coords: Vector2i)

# --- Player Events ---
signal player_spawned(position: Vector2)
signal player_died
signal health_changed(current: float, max_health: int)
signal hunger_changed(current: float, max_hunger: float)
signal status_effect_applied(effect_name: String)
signal status_effect_removed(effect_name: String)

# --- Inventory Events ---
signal inventory_changed
signal item_added(item_id: String, quantity: int)
signal item_removed(item_id: String, quantity: int)
signal inventory_full

# --- Crafting Events ---
signal recipe_crafted(recipe_id: String)
signal recipe_failed(recipe_id: String, reason: String)
signal station_used(station_id: String)

# --- World Events ---
signal biome_changed(biome_id: String)
signal weather_changed(weather_id: String)
signal season_changed(season_name: String)
signal day_night_cycle_changed(day_ratio: float)

# --- Building Events ---
signal building_placed(building_id: String, chunk_coords: Vector2i)
signal building_destroyed(building_id: String, chunk_coords: Vector2i)

# --- Combat Events ---
signal entity_hit(entity_id: String, damage: float)
signal entity_died(entity_id: String)
signal entity_healed(entity_id: String, amount: float)

# --- Technology Events ---
signal technology_unlocked(tech_id: String)
signal technology_failed(tech_id: String, reason: String)

# --- UI Events ---
signal toggle_inventory_ui
signal toggle_crafting_ui
signal toggle_debug_ui
signal debug_mode_toggled(enabled: bool)

# --- Save Events ---
signal game_saved(path: String)
signal game_loaded(path: String)
signal save_failed(reason: String)
