## Data-only description of a generated cave space.
## Reset/depletion policy is intentionally not interpreted here.
class_name CaveDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = "Unnamed Cave"
@export var entrance_poi_id: String = "cave_entrance"
@export var allowed_environment_tags: PackedStringArray = []
@export var allowed_biomes: PackedStringArray = []
@export var entrance_weight: float = 1.0
@export var min_rooms: int = 4
@export var max_rooms: int = 8
@export var room_size: Vector2i = Vector2i(8, 8)
@export var tunnel_length: int = 8
@export var environment_tags: PackedStringArray = PackedStringArray(["underground"])
@export var resource_ids: PackedStringArray = []
@export var resource_min_deposits: int = 0
@export var resource_max_deposits: int = 0
@export var resource_attempt_multiplier: int = 4
@export var poi_ids: PackedStringArray = []
@export var reset_policy: String = "unspecified"
@export var custom_data: Dictionary = {}

func is_valid() -> bool:
	return not id.is_empty()
