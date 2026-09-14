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
## one key per covered cell; edge records reserve exactly one edge key.
func reserved_keys() -> Array[String]:
	var keys: Array[String] = []
	if layer == "edge":
		keys.append(canonical_edge_key(tile, story, orientation))
		return keys
	for dx in range(footprint.x):
		for dy in range(footprint.y):
			keys.append(tile_key(tile + Vector2i(dx, dy), story, layer))
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
		capability_state = state_value
