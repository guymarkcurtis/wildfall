## Data-driven building definition.
@icon("res://assets/icons/building_icon.svg")
class_name BuildingDefinition
extends Resource

## Unique stable ID.
@export var id: String = ""

## Display name.
@export var display_name: String = "Unnamed Building"

## Width in tiles.
@export var width: int = 1

## Height in tiles.
@export var height: int = 1

## Structural role. Parts share a grid cell only across different stories;
## this makes a floor plan easy to read in Wildfall's top-down cutaway view.
@export_enum("foundation", "floor", "wall", "window", "door", "roof", "stair", "ramp", "pillar", "utility") var part_type: String = "utility"

## Progression tier and future technology gate. The building system already
## reads this metadata; the technology-tree UI will enforce the gate next.
@export_enum("primitive", "wood", "stone", "metal") var tier: String = "wood"
@export var technology_id: String = ""

## Upper stories need a structural piece directly beneath the same tile.
@export var requires_lower_support: bool = true

## Floors, ramps, and most utilities are walkable; walls/doors/pillars block.
@export var blocks_movement: bool = false

## Description.
@export var description: String = ""

## Build cost: list of {item_id, quantity}.
@export var build_cost: Array[Dictionary] = []

## Requires crafting station.
@export var station_id: String = ""

## Max HP.
@export var max_health: int = 100

## Whether this building can be picked up (returns resources).
@export var pickup_returns_resources: bool = true

## Sprite path.
@export var sprite_path: String = ""

## Custom data.
@export var custom_data: Dictionary = {}

# --- Generic placement model (consumed from milestone M2 onward) ---

## Which placement layer the part occupies: ground, floor, edge, object,
## overhead, or connector. Empty derives from part_type (see
## effective_placement_layer) so legacy assets stay valid. (A plain String,
## not @export_enum: the empty string is the meaningful "derive" sentinel.)
@export var placement_layer: String = ""

## Orientations this part may be placed in (e.g. ["north", "east", "south",
## "west"] for edge parts). Empty = a single, non-orientable default.
@export var allowed_orientations: PackedStringArray = PackedStringArray()

## Support vocabulary this part PROVIDES to parts above it (e.g. "structure",
## "cover"). M2's support validator consumes these tags generically.
@export var support_tags: PackedStringArray = PackedStringArray()

## Support vocabulary this part REQUIRES beneath it when
## requires_lower_support is set (checked on upper stories only). Empty with
## requires_lower_support=true means "any placed part below counts".
@export var required_support_tags: PackedStringArray = PackedStringArray()

## Replacement policy when another part already occupies this definition's
## slot: "none" (reject) this pass; "edge_fixture" (wall -> door/window) is
## reserved for M2 and must not be authored before that lands.
@export_enum("none", "edge_fixture") var occupancy_replacement: String = "none"

## Render band offset within the story; -1 derives from placement_layer.
@export var render_band: int = -1

# --- Presentation ---

## Visual family grouping material variants (e.g. "wood", "stone").
@export var visual_family_id: String = ""

## Atlas sheet this part renders from; empty uses the legacy defaults.
@export var atlas_path: String = ""

## [column, row] cell on atlas_path; (-1, -1) = no atlas cell.
@export var atlas_cell: Vector2i = Vector2i(-1, -1)

# --- Generic capability references (never selected by item id in code) ---

@export var interaction_profile: InteractionProfile = null
@export var container_profile: ContainerProfile = null
@export var station_profile: StationProfile = null
@export var fuel_profile: FuelProfile = null
@export var light_profile: LightProfile = null
@export var appearance_profile: AppearanceProfile = null

## Derive the placement layer from part_type when the asset leaves
## placement_layer blank (legacy compatibility).
func effective_placement_layer() -> String:
	if not placement_layer.is_empty():
		return placement_layer
	match part_type:
		"foundation":
			return "ground"
		"floor":
			return "floor"
		"wall", "window", "door":
			return "edge"
		"roof":
			return "overhead"
		"stair", "ramp":
			return "connector"
		_:
			return "object"

## True when this definition carries any capability reference at all.
func has_capabilities() -> bool:
	return interaction_profile != null or container_profile != null \
			or station_profile != null or fuel_profile != null \
			or light_profile != null or appearance_profile != null

func is_valid() -> bool:
	return id != ""

## Data-level validation; the BuildingContentRegistry calls this and prefixes
## each message with the asset path so the author can find the file.
func validate() -> Array[String]:
	var errors: Array[String] = []
	if width <= 0 or height <= 0:
		errors.append("footprint %dx%d must be positive on both axes" % [width, height])
	if max_health <= 0:
		errors.append("max_health (%d) must be positive" % max_health)
	if not placement_layer.is_empty() and placement_layer not in ["ground", "floor", "edge", "object", "overhead", "connector"]:
		errors.append("placement_layer '%s' is not a supported layer" % placement_layer)
	for index in range(build_cost.size()):
		var entry: Dictionary = build_cost[index] if typeof(build_cost[index]) == TYPE_DICTIONARY else {}
		if str(entry.get("item_id", "")).is_empty():
			errors.append("build_cost[%d] has no item_id" % index)
		elif int(entry.get("quantity", 0)) <= 0:
			errors.append("build_cost[%d] (%s) has a non-positive quantity" % [index, str(entry.get("item_id"))])
	for profile_name in ["interaction_profile", "container_profile", "station_profile", "fuel_profile", "light_profile", "appearance_profile"]:
		var profile: Variant = get(profile_name)
		if profile != null and profile.get_script() == null:
			errors.append("%s must reference a profile Resource with a script" % profile_name)
	if interaction_profile != null:
		errors.append_array(_prefixed("interaction_profile", interaction_profile.validate()))
	if container_profile != null:
		errors.append_array(_prefixed("container_profile", container_profile.validate()))
	if station_profile != null:
		errors.append_array(_prefixed("station_profile", station_profile.validate()))
	if fuel_profile != null:
		errors.append_array(_prefixed("fuel_profile", fuel_profile.validate()))
	if light_profile != null:
		errors.append_array(_prefixed("light_profile", light_profile.validate()))
	if appearance_profile != null:
		errors.append_array(_prefixed("appearance_profile", appearance_profile.validate()))
	return errors

func _prefixed(profile_name: String, profile_errors: Array[String]) -> Array[String]:
	var prefixed: Array[String] = []
	for message in profile_errors:
		prefixed.append("%s: %s" % [profile_name, message])
	return prefixed
