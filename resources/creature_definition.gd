## Data-driven creature definition.
@icon("res://assets/icons/creature_icon.svg")
class_name CreatureDefinition
extends Resource

## Unique stable ID.
@export var id: String = ""

## Display name.
@export var display_name: String = "Unnamed Creature"

## Creature type (passive, neutral, predator, boss).
@export_enum("passive", "neutral", "predator", "boss") var type: String = "passive"

## Base health points.
@export var health: int = 10

## Movement speed in tiles per second.
@export var speed: float = 1.0

## Detection range in tiles.
@export var detection_range: float = 8.0

## Aggression range in tiles.
@export var aggression_range: float = 5.0

## Attack damage.
@export var attack_damage: float = 1.0

## Attack cooldown in seconds.
@export var attack_cooldown: float = 1.0

## Whether this creature is hostile.
@export var hostile: bool = false

## Loot table: list of {item_id, min_qty, max_qty, chance}.
@export var loot_table: Array[Dictionary] = []

## Spawn weight (higher = more common).
@export var spawn_weight: float = 1.0

## Biome IDs where this creature can spawn.
@export var allowed_biomes: PackedStringArray = []

## Sprite path for placeholder rendering.
@export var sprite_path: String = ""

## Custom data.
@export var custom_data: Dictionary = {}

func is_valid() -> bool:
	return id != ""
