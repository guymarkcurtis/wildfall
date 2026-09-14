## One placed building as a logical record: a definition instance anchored at
## a tile/story on one placement layer, reserving a deterministic set of
## canonical occupancy keys. BuildingManager's index maps every reserved key
## to its record; multi-tile footprints simply reserve more keys, and edge
## parts normalize their key so the east edge of one tile IS the west edge of
## its neighbour (no doubled walls, no save-order ambiguity).
##
## Key formats (canonical, save-safe):
##   tile layers:  "<x>:<y>:<story>:<layer>"
##   edge layer:   "<x>:<y>:<story>:edge:<n|w>"  — always normalized to the
##                 NORTH edge (horizontal) or WEST edge (vertical) of a tile,
##                 so E of (x,y) == W of (x+1,y) and S of (x,y) == N of (x,y+1).
class_name BuildingRecord
extends RefCounted

# --- Shared placement-model vocabulary (single source; no cycles) ---

## Validated story limit (M0 scope freeze).
const MAX_STORIES := 4
## Aligned top-down render bands: story N occupies z [N*STRIDE, N*STRIDE+LAYER Z).
const STORY_Z_STRIDE := 20
## First collision bit owned by building stories (bit 4 = value 16). Bits 0-3
## stay with terrain and creatures; stories 0-3 map to bits 4-7.
const STORY_COLLISION_BASE := 16

## Within-band z offsets by placement layer.
const LAYER_Z := {"ground": 0, "floor": 1, "object": 2, "connector": 3, "edge": 4, "overhead": 5}

var definition: BuildingDefinition = null
var item_id: String = ""
var tile: Vector2i = Vector2i.ZERO
var footprint: Vector2i = Vector2i.ONE
var story: int = 0
var layer: String = "object"
var orientation: String = "" # "" or one of allowed_orientations (edge parts: N/E/S/W)
var health: int = 50
var capability_state: Dictionary = {} # saved as `state` on the building entry

var node: Building = null # the visual/physical node; null between scenes

## Runtime container contents for records whose definition declares a
## ContainerProfile (seeded lazily on first open). Its indexed contents are
## persisted in this building entry's `state.container` payload. UI open state
## deliberately never lives here: it is transient InteractionManager state.
var container_storage: InventoryStorage = null

## Persistent station surfaces, owned by StationProfile rather than a station
## name. M6's panel and immediate craft service use these real inventories;
## M7 will add the fuel surface beside them without changing this shape.
var station_input_storage: InventoryStorage = null
var station_output_storage: InventoryStorage = null

## Seed (or return) the record's indexed container storage from its authored
## ContainerProfile. Returns null when the definition has no container.
func get_container_storage() -> InventoryStorage:
	if container_storage != null:
		return container_storage
	if definition == null or definition.container_profile == null:
		return null
	var profile := definition.container_profile
	container_storage = InventoryStorage.new(profile.slot_count, profile.max_weight)
	var restored_container := false
	# State is hostile-input territory on load. Only accept the exact indexed
	# shape this profile owns; arbitrary-size arrays must not reshape a chest.
	var saved_container: Variant = capability_state.get("container", null)
	if typeof(saved_container) == TYPE_DICTIONARY:
		var saved_slots: Variant = saved_container.get("slots", null)
		if typeof(saved_slots) == TYPE_ARRAY and saved_slots.size() == profile.slot_count:
			container_storage.deserialize({"slots": saved_slots, "max_weight": profile.max_weight})
			restored_container = true
		else:
			# Drop malformed container data safely. Other capability fields remain
			# available for their owning milestones.
			capability_state.erase("container")
	# Default contents fill their slots in authored order (JSON-safe data).
	if not restored_container:
		var index := 0
		for entry in profile.default_contents:
			if index >= container_storage.slot_count():
				break
			var item_id := str(entry.get("item_id", ""))
			var quantity := int(entry.get("quantity", 0))
			if item_id == "" or quantity <= 0:
				continue
			container_storage.add_item(item_id, quantity)
			index += 1
	return container_storage

## True when this record owns a container with any contents. This remains
## data-driven; BuildingManager uses it to protect every such object from
## demolition, not a named chest branch.
func has_nonempty_container() -> bool:
	var storage := get_container_storage()
	if storage != null and storage.occupied_count() > 0:
		return true
	var inputs := get_station_input_storage()
	var outputs := get_station_output_storage()
	return (inputs != null and inputs.occupied_count() > 0) \
			or (outputs != null and outputs.occupied_count() > 0)

func get_station_input_storage() -> InventoryStorage:
	return _get_station_storage("inputs", true)

func get_station_output_storage() -> InventoryStorage:
	return _get_station_storage("outputs", false)

func _get_station_storage(state_key: String, inputs: bool) -> InventoryStorage:
	if definition == null or definition.station_profile == null:
		return null
	if inputs and station_input_storage != null:
		return station_input_storage
	if not inputs and station_output_storage != null:
		return station_output_storage
	var profile: StationProfile = definition.station_profile
	var slot_count := profile.input_slot_count if inputs else profile.output_slot_count
	var storage := InventoryStorage.new(slot_count, profile.max_weight)
	var station_state: Variant = capability_state.get("station", null)
	var saved_storage: Variant = station_state.get(state_key, null) if typeof(station_state) == TYPE_DICTIONARY else null
	if typeof(saved_storage) == TYPE_DICTIONARY:
		var slots: Variant = saved_storage.get("slots", null)
		if typeof(slots) == TYPE_ARRAY and slots.size() == slot_count:
			storage.deserialize({"slots": slots, "max_weight": profile.max_weight})
		else:
			# Preserve unrelated station state while rejecting only the malformed
			# indexed surface.
			(station_state as Dictionary).erase(state_key)
	if inputs:
		station_input_storage = storage
	else:
		station_output_storage = storage
	return storage

## Bring the runtime container into the JSON-safe capability payload just
## before serialization. Empty containers are omitted, but non-empty ones can
## never be omitted. The authored profile, rather than save input, owns the
## capacity/slot count.
func _sync_container_state() -> void:
	if container_storage == null:
		return
	if container_storage.occupied_count() > 0:
		capability_state["container"] = container_storage.serialize()
	else:
		capability_state.erase("container")

func _sync_station_state() -> void:
	if station_input_storage == null and station_output_storage == null:
		return
	var station: Dictionary = capability_state.get("station", {}).duplicate(true) if typeof(capability_state.get("station", {})) == TYPE_DICTIONARY else {}
	if station_input_storage != null:
		if station_input_storage.occupied_count() > 0:
			station["inputs"] = station_input_storage.serialize()
		else:
			station.erase("inputs")
	if station_output_storage != null:
		if station_output_storage.occupied_count() > 0:
			station["outputs"] = station_output_storage.serialize()
		else:
			station.erase("outputs")
	if station.is_empty():
		capability_state.erase("station")
	else:
		capability_state["station"] = station

static func canonical_edge_key(tile: Vector2i, story: int, orientation: String) -> String:
	match orientation:
		"north":
			return "%d:%d:%d:edge:n" % [tile.x, tile.y, story]
		"south":
			return "%d:%d:%d:edge:n" % [tile.x, tile.y + 1, story]
		"west":
			return "%d:%d:%d:edge:w" % [tile.x, tile.y, story]
		"east":
			return "%d:%d:%d:edge:w" % [tile.x + 1, tile.y, story]
		_:
			return "%d:%d:%d:edge:n" % [tile.x, tile.y, story]

static func tile_key(tile: Vector2i, story: int, layer: String) -> String:
	return "%d:%d:%d:%s" % [tile.x, tile.y, story, layer]

## True when the record occupies the tile cells of its footprint; false for
## edge records, which live between tiles (they still anchor on `tile`).
func occupies_tiles() -> bool:
	return layer != "edge"

## Every canonical key this record reserves. Multi-tile footprints reserve
## one key per covered cell; edge records reserve exactly one edge key;
## connectors with a stairwell also reserve the floor slot above (the
## opening), so no floor can later block the hole.
func reserved_keys() -> Array[String]:
	var keys: Array[String] = []
	if layer == "edge":
		keys.append(canonical_edge_key(tile, story, orientation))
		return keys
	for dx in range(footprint.x):
		for dy in range(footprint.y):
			keys.append(tile_key(tile + Vector2i(dx, dy), story, layer))
	if layer == "connector" and definition != null and definition.connector_profile != null \
			and definition.connector_profile.reserve_stairwell:
		keys.append(tile_key(tile, story + definition.connector_profile.upper_story_offset, "floor"))
	return keys

## Stable identity for UI ownership and save `state` (extends the M1
## x:y:story key with the layer; edges append the normalized edge side).
func placement_key() -> String:
	if layer == "edge":
		return "%d:%d:%d:edge:%s" % [tile.x, tile.y, story, orientation]
	return "%d:%d:%d:%s" % [tile.x, tile.y, story, layer]

func display_name() -> String:
	return str(definition.display_name) if definition != null else item_id

func blocks_movement() -> bool:
	return definition != null and bool(definition.blocks_movement)

## Serialize to the v8 building entry (capability state included verbatim;
## callers keep it JSON-safe).
func serialize() -> Dictionary:
	_sync_container_state()
	_sync_station_state()
	var entry: Dictionary = {
		"item_id": item_id,
		"x": tile.x,
		"y": tile.y,
		"story": story,
		"layer": layer,
		"health": health,
	}
	if not orientation.is_empty():
		entry["orientation"] = orientation
	if footprint != Vector2i.ONE:
		entry["footprint"] = [footprint.x, footprint.y]
	if not capability_state.is_empty():
		entry["state"] = capability_state
	return entry

## Restore from a v8 entry. Missing layer/orientation/state (v7 and older)
## default from the definition: layer derives from part_type, orientation is
## the single default, state starts empty.
func deserialize(entry: Dictionary, resolved_definition: BuildingDefinition) -> void:
	definition = resolved_definition
	item_id = str(entry.get("item_id", ""))
	tile = Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
	story = int(entry.get("story", 0))
	health = int(entry.get("health", 50))
	var footprint_value: Variant = entry.get("footprint", null)
	if typeof(footprint_value) == TYPE_ARRAY and footprint_value.size() == 2:
		footprint = Vector2i(int(footprint_value[0]), int(footprint_value[1]))
	elif resolved_definition != null:
		footprint = Vector2i(int(resolved_definition.width), int(resolved_definition.height))
	var layer_value := str(entry.get("layer", ""))
	if layer_value.is_empty() and resolved_definition != null:
		layer_value = resolved_definition.effective_placement_layer()
	layer = layer_value if not layer_value.is_empty() else "object"
	orientation = str(entry.get("orientation", ""))
	var state_value: Variant = entry.get("state", null)
	if typeof(state_value) == TYPE_DICTIONARY:
		# Duplicate so post-load state cleanup never mutates a caller's save
		# payload. The container itself receives stricter validation on access.
		capability_state = (state_value as Dictionary).duplicate(true)
