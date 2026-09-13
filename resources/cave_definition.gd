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
## WG-09 optional geometry controls. Zero vectors retain the legacy fixed
## room_size/tunnel_length values, so existing cave assets remain unchanged.
@export var room_size_min: Vector2i = Vector2i.ZERO
@export var room_size_max: Vector2i = Vector2i.ZERO
## Inclusive [min, max] tunnel length. Vector2i.ZERO uses tunnel_length.
@export var tunnel_length_range: Vector2i = Vector2i.ZERO
@export_range(0.0, 1.0) var branching_chance: float = 0.0
@export var environment_tags: PackedStringArray = PackedStringArray(["underground"])
@export var resource_ids: PackedStringArray = []
@export var resource_min_deposits: int = 0
@export var resource_max_deposits: int = 0
@export var resource_attempt_multiplier: int = 4
@export var poi_ids: PackedStringArray = []
## Reserved data seams for cave variety. WG-08 only interprets resource_ids
## into harvestable deposits; these values are emitted/validated as content
## metadata for later generic runtime consumers, never special-cased by ID.
@export var hazard_ids: PackedStringArray = []
@export var enemy_ids: PackedStringArray = []
@export var underground_water_chance: float = 0.0
@export var underground_water_tags: PackedStringArray = []
@export var feature_tags: PackedStringArray = []
## Optional weighted deposit/loot data tables. Entries are author-owned
## dictionaries for future generic table consumers; resource_ids remains the
## active WG-08 deposit list for backward-compatible content.
@export var deposit_tables: Array[Dictionary] = []
@export var loot_tables: Array[Dictionary] = []
@export var reset_policy: String = "unspecified"
@export var custom_data: Dictionary = {}

func is_valid() -> bool:
	return not id.is_empty()
