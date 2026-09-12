## Data-driven biome configuration.
@icon("res://assets/icons/biome_icon.svg")
class_name BiomeDefinition
extends Resource

## Unique stable ID.
@export var id: String = ""

## Display name.
@export var display_name: String = "Unnamed Biome"

## Elevation range (min, max) where this biome appears.
@export var elevation_range: Vector2 = Vector2(0.0, 1.0)

## Moisture range (min, max) where this biome appears.
@export var moisture_range: Vector2 = Vector2(0.0, 1.0)

## Temperature range (min, max) where this biome appears.
@export var temperature_range: Vector2 = Vector2(0.0, 1.0)

## Weight used when multiple definitions match the same environmental field.
@export var rarity_weight: float = 1.0

## Operative region-scale metadata for the coherent-region stage (WG-03).
## When greater than 0, raw biome fragments smaller than this many tiles
## (measured over the generator's world-aligned region cells) are merged
## into a neighbouring cell's biome. The allowed transition band is derived
## from the same number: minimum_region_size / 2 tiles. Leave 0 to keep the
## biome out of the stage — its fragments are never merged.
@export var minimum_region_size: int = 0

## Generic environment labels used by resources, POIs, and cave entrances.
@export var environment_tags: PackedStringArray = []

## IDs of environments this biome naturally prefers nearby. The generator
## uses these as metadata; it never hard-codes a biome relationship.
@export var preferred_neighbors: PackedStringArray = []
@export var transition_biome_ids: PackedStringArray = []

## Base terrain tile ID for this biome.
@export var terrain_tile_id: String = "grass"

## Optional high-elevation terrain replacement. Empty means keep the base tile.
@export var high_elevation_terrain_tile_id: String = ""
@export var high_elevation_threshold: float = 0.7

## Suitability for placing a cave entrance POI in this environment.
@export_range(0.0, 1.0) var cave_entrance_suitability: float = 0.0

## Primary ground color (for placeholder rendering).
@export var ground_color: Color = Color(0.2, 0.6, 0.2)

## Whether rain is common in this biome.
@export var rain_chance: float = 0.0

## Whether snow is common in this biome.
@export var snow_chance: float = 0.0

## List of resource node types that can spawn here.
@export var resource_types: PackedStringArray = []

## List of creature types that can spawn here.
@export var creature_types: PackedStringArray = []

## List of vegetation types that can spawn here.
@export var vegetation_types: PackedStringArray = []

## Custom data.
@export var custom_data: Dictionary = {}

func is_valid() -> bool:
	return id != ""
