## Central event bus for decoupled communication between systems.
## All game-wide events are defined as static constants here.
extends Node

# --- Game State Events ---
signal player_died
signal player_spawned(position: Vector2)
signal chunk_loaded(chunk_coords: Vector2i)
signal chunk_unloaded(chunk_coords: Vector2i)
signal world_seed_set(seed: int)

# --- Player Events ---
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

# --- Debug Events ---
signal debug_mode_toggled(enabled: bool)

## Emit an event with a name and optional arguments.
## Use typed signals above instead of this generic method when possible.
static func emit_game_event(event_name: String, args: Array = []) -> void:
	EventBus.emit(event_name, args)

## Check if a particular event has been registered.
static func has_event(event_name: String) -> bool:
	return EventBus.has_signal(event_name)
