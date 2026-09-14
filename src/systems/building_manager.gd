## Layered, story-aware building placement for Wildfall's top-down cutaway.
## Placement occupancy is a record index over canonical keys (six layers,
## normalized tile edges — see BuildingRecord), so floors, walls, roofs, and
## furniture coexist around one tile while an identical slot stays exclusive.
## Placement and demolition are transactional: the whole footprint validates
## before anything is consumed, and failures change nothing. All behaviour
## comes from BuildingDefinition data — no item-id branches.
class_name BuildingManager
extends Node2D

const TILE_SIZE := 32
const CRAFTING_STATION_RANGE := 72.0
## Cosmetic local-light budget. Selection is deterministic (distance, then
## stable placement key) so identical saves render the same surviving lights.
const MAX_VISIBLE_LOCAL_LIGHTS := 32

## Deterministic lookup priority for the ambiguous tile+story query.
const LAYER_QUERY_PRIORITY := ["object", "connector", "floor", "ground", "edge", "overhead"]

var records: Dictionary = {} # canonical key -> BuildingRecord (shared per footprint)
var _record_list: Array[BuildingRecord] = [] # authoritative iteration set
var definitions: Dictionary = {} # item_id -> BuildingDefinition resource
var content_registry: BuildingContentRegistry = null
var world_generator: WorldGenerator = null
var build_mode := false
var selected_item_id := ""
var selected_story := 0

## The story the player is actually ON. Shared owner for collision
## filtering, presentation focus, and interaction gating; the build
## palette's `selected_story` stays an independent construction value.
var active_story := 0

## Sandbox-only roof visibility override (R key in Building Sandbox).
var roofs_visible := true

var _connector_under_player: BuildingRecord = null

var player: Player = null
var item_database: ItemDatabase = null
var technology_system: TechnologySystem = null

## Refund target for API-driven placement/demolition without a player
## (test harnesses). Live play always refunds through player.inventory.
var refund_inventory: InventoryComponent = null

var _ghost: Polygon2D = null
var _owned: PackedStringArray = []
var _select_index := 0

signal building_placed(building_id: String, coords: Vector2i)
signal building_removed(building_id: String, coords: Vector2i)
signal build_mode_changed(enabled: bool, selected_item_id: String)
signal build_story_changed(story: int)
signal active_story_changed(story: int)
signal placement_failed(reason: String)
signal demolition_blocked(record: BuildingRecord, reason: String)

func _physics_process(delta: float) -> void:
	_update_connector_traversal()
	if item_database != null:
		for record in _record_list:
			FuelConsumer.tick(record, delta, item_database)
	_refresh_local_light_budget()

## Keep expensive PointLight2D nodes bounded in dense player builds. The
## player-centered margin matches the per-building local cull; a camera that
## follows the player therefore sees all candidates it can meaningfully show.
func _refresh_local_light_budget() -> void:
	var candidates: Array[BuildingRecord] = []
	for record in _record_list:
		if record.node == null or not is_instance_valid(record.node) \
				or not record.node.has_local_light():
			continue
		if player != null and is_instance_valid(player) \
				and record.node.global_position.distance_to(player.global_position) > Building.LIGHT_CULL_RADIUS_PX:
			record.node.set_light_budget_allowed(false)
			continue
		candidates.append(record)
	candidates.sort_custom(func(a: BuildingRecord, b: BuildingRecord) -> bool:
		var origin := player.global_position if player != null and is_instance_valid(player) else Vector2.ZERO
		var a_distance := a.node.global_position.distance_squared_to(origin)
		var b_distance := b.node.global_position.distance_squared_to(origin)
		return a_distance < b_distance if not is_equal_approx(a_distance, b_distance) else a.placement_key() < b.placement_key()
	)
	for index in candidates.size():
		candidates[index].node.set_light_budget_allowed(index < MAX_VISIBLE_LOCAL_LIGHTS)

## Generic vertical-connector traversal: when the player ENTERS a connector's
## landing zone (edge-triggered, so standing still never re-triggers), the
## active story moves to the paired landing — up from the lower story, down
## from the upper one. Traversal pauses in build mode.
func _update_connector_traversal() -> void:
	if player == null or not is_instance_valid(player) or build_mode:
		_connector_under_player = null
		return
	var found := _connector_record_at(player.global_position, active_story)
	if found != null and found != _connector_under_player and found.definition != null \
			and found.definition.connector_profile != null:
		var upper: int = found.story + found.definition.connector_profile.upper_story_offset
		if active_story == found.story:
			set_active_story(upper)
		elif active_story == upper:
			set_active_story(found.story)
	_connector_under_player = found

## The connector record whose landing zone contains `world_position` on the
## given story (a stair record spans its own story and the upper landing).
func _connector_record_at(world_position: Vector2, story: int) -> BuildingRecord:
	for record in _record_list:
		if record.layer != "connector" or record.definition == null \
				or record.definition.connector_profile == null:
			continue
		var profile := record.definition.connector_profile
		if story < record.story or story > record.story + profile.upper_story_offset:
			continue
		if record.node == null or not is_instance_valid(record.node):
			continue
		var center := record.node.global_position + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
		if center.distance_to(world_position) <= profile.trigger_radius_px:
			return record
	return null

func _ready() -> void:
	_load_definitions()
	_ghost = Polygon2D.new()
	_ghost.polygon = PackedVector2Array([
		Vector2(2, 2), Vector2(30, 2), Vector2(30, 30), Vector2(2, 30)
	])
	_ghost.color = Color(0.4, 0.9, 0.4, 0.35)
	_ghost.visible = false
	_ghost.z_index = 40
	add_child(_ghost)

func _process(_delta: float) -> void:
	if not build_mode:
		_ghost.visible = false
		return
	_refresh_owned()
	if _owned.is_empty():
		selected_item_id = ""
		_ghost.visible = false
		return
	if selected_item_id == "" or not _owned.has(selected_item_id):
		_select_index = 0
		selected_item_id = _owned[0]
		build_mode_changed.emit(true, selected_item_id)
	var tile := _mouse_tile()
	_ghost.position = Vector2(tile * TILE_SIZE)
	# The ghost floats just above the construction story's band.
	_ghost.z_index = selected_story * BuildingRecord.STORY_Z_STRIDE + int(BuildingRecord.LAYER_Z.get("edge", 4)) + 1
	_ghost.visible = true
	_ghost.color = Color(0.3, 0.85, 0.35, 0.4) if can_place(tile) else Color(0.85, 0.25, 0.2, 0.4)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_build"):
		set_build_mode(not build_mode)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("demolish"):
		_demolish_near_player()
		get_viewport().set_input_as_handled()
		return
	# Building Sandbox debug controls: the [ / ] keys move the ACTIVE story
	# when the build palette is closed, and R toggles roof visibility. Never
	# available in survival — a normal player must not phase through floors.
	if GameSession.is_building_sandbox() and not build_mode:
		if event.is_action_pressed("build_level_up"):
			set_active_story(active_story + 1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("build_level_down"):
			set_active_story(active_story - 1)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("toggle_roofs") and GameSession.is_building_sandbox():
		roofs_visible = not roofs_visible
		_apply_presentation()
		get_viewport().set_input_as_handled()
		return
	if not build_mode:
		return
	if event.is_action_pressed("build_level_up"):
		set_selected_story(selected_story + 1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("build_level_down"):
		set_selected_story(selected_story - 1)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if not mouse.pressed:
			return
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			try_place_at(_mouse_tile())
			get_viewport().set_input_as_handled()
		elif mouse.button_index == MOUSE_BUTTON_RIGHT:
			set_build_mode(false)
			get_viewport().set_input_as_handled()
		elif mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			cycle_selection(-1)
			get_viewport().set_input_as_handled()
		elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cycle_selection(1)
			get_viewport().set_input_as_handled()

func set_build_mode(enabled: bool) -> void:
	build_mode = enabled
	if build_mode:
		_refresh_owned()
		if not _owned.is_empty():
			_select_index = clampi(_select_index, 0, _owned.size() - 1)
			selected_item_id = _owned[_select_index]
		else:
			selected_item_id = ""
	else:
		selected_item_id = ""
		if _ghost:
			_ghost.visible = false
	# Build mode switches the presentation focus between the construction
	# story (blueprint view) and the active story.
	_apply_presentation()
	build_mode_changed.emit(build_mode, selected_item_id)

func set_selected_story(story: int) -> void:
	var next_story := clampi(story, 0, BuildingRecord.MAX_STORIES - 1)
	if selected_story == next_story:
		return
	selected_story = next_story
	_apply_presentation()
	build_story_changed.emit(selected_story)

## Move the player between stories (connector traversal or the sandbox
## selector). Updates the player's collision mask/render band, republishes
## the cutaway focus, and emits for the HUD.
func set_active_story(story: int) -> void:
	var next_story := clampi(story, 0, BuildingRecord.MAX_STORIES - 1)
	if active_story == next_story:
		return
	active_story = next_story
	if player != null and is_instance_valid(player):
		player.set_active_story(active_story)
	_apply_presentation()
	active_story_changed.emit(active_story)

func cycle_selection(step: int) -> void:
	_refresh_owned()
	if _owned.is_empty():
		selected_item_id = ""
		return
	_select_index = posmod(_select_index + step, _owned.size())
	selected_item_id = _owned[_select_index]
	build_mode_changed.emit(build_mode, selected_item_id)

func select_item(item_id: String) -> bool:
	_refresh_owned()
	var index := _owned.find(item_id)
	if index < 0:
		return false
	_select_index = index
	selected_item_id = item_id
	build_mode_changed.emit(build_mode, selected_item_id)
	return true

func get_owned_building_items() -> Array[String]:
	_refresh_owned()
	var result: Array[String] = []
	for item_id in _owned:
		result.append(item_id)
	return result

func get_definition(item_id: String) -> Variant:
	return definitions.get(item_id)

# --- Occupancy queries ---

## Every placed record (authoritative iteration set, no key duplicates).
func get_all_records() -> Array[BuildingRecord]:
	return _record_list.duplicate()

## Every placed Building node (compatibility view for callers that only
## iterate placed parts).
func get_all_buildings() -> Array:
	var result: Array = []
	for record in _record_list:
		if record.node != null and is_instance_valid(record.node):
			result.append(record.node)
	return result

## The record occupying one exact slot (tile layers) or one canonical edge.
func get_record_for_key(key: String) -> BuildingRecord:
	return records.get(key) as BuildingRecord

## Record on a specific layer/edge at a tile+story. Edge orientations are
## normalized through the canonical key, so "east" finds the record placed
## from the neighbouring tile's "west".
func get_record_at(tile: Vector2i, story: int, layer: String, orientation: String = "") -> BuildingRecord:
	if layer == "edge":
		return records.get(BuildingRecord.canonical_edge_key(tile, story, orientation)) as BuildingRecord
	return records.get(BuildingRecord.tile_key(tile, story, layer)) as BuildingRecord

## Ambiguous tile+story query (compatibility): the topmost record by the
## deterministic layer priority. New callers should prefer get_record_at.
func get_building_at(tile: Vector2i, story: int = selected_story) -> Building:
	var record := _top_record_at(tile, story)
	return record.node if record != null else null

func _top_record_at(tile: Vector2i, story: int) -> BuildingRecord:
	for layer in LAYER_QUERY_PRIORITY:
		var record := get_record_at(tile, story, layer)
		if record != null:
			return record
	return null

func get_building_count() -> int:
	return _record_list.size()

## The record that owns a given placed Building node (UI ownership, panel
## state, capability storage).
func get_record_for_building(building: Building) -> BuildingRecord:
	if building == null:
		return null
	for record in _record_list:
		if record.node == building:
			return record
	return null

# --- Placement ---

func can_place(tile: Vector2i, story: int = selected_story) -> bool:
	return _placement_failure(selected_item_id, tile, story, _orientation_for_mouse(tile)) == ""

## Place the selected structural part on the active construction story,
## orienting edge parts to the nearest tile edge under the cursor.
func try_place_at(tile: Vector2i) -> bool:
	var orientation := _orientation_for_mouse(tile)
	var reason := _placement_failure(selected_item_id, tile, selected_story, orientation)
	if reason != "":
		placement_failed.emit(reason)
		return false
	return place_record(selected_item_id, tile, null, selected_story, orientation)

## Test/API placement. A story of -1 means the active construction plane.
## Edge parts use `orientation` ("north"/"east"/"south"/"west"; "" defaults
## to north). Consumes exactly one item on success.
func place_building_item(item_id: String, tile: Vector2i, inventory: InventoryComponent = null, story: int = -1) -> bool:
	return place_record(item_id, tile, inventory, story, "")

## Full transactional placement: validate the complete footprint, then
## reserve every key, consume the item, and spawn the node — or change
## nothing and report the exact failure reason.
func place_record(item_id: String, tile: Vector2i, inventory: InventoryComponent = null, story: int = -1, orientation: String = "") -> bool:
	var target_story: int = selected_story if story < 0 else story
	var inv: InventoryComponent = inventory if inventory != null else (player.inventory if player != null else null)
	var reason := _placement_failure_for(item_id, tile, target_story, orientation, inv)
	if reason != "":
		placement_failed.emit(reason)
		return false
	var definition := get_definition(item_id) as BuildingDefinition
	var record := _make_record(definition, item_id, tile, target_story,
			_resolve_orientation(definition, orientation))
	# Edge replacement: an edge fixture (door/window) takes over a plain
	# wall's edge, refunding it exactly. Both policies are authored data.
	var replaced: BuildingRecord = null
	var keys := record.reserved_keys()
	if record.layer == "edge":
		var existing := records.get(keys[0]) as BuildingRecord
		if existing != null:
			replaced = existing
	for key in keys:
		records[key] = record
	_record_list.append(record)
	if inv != null:
		inv.remove_item(item_id, 1)
	if replaced != null:
		_remove_record(replaced, true, inv)
	_spawn_node(record)
	_apply_presentation()
	building_placed.emit(item_id, tile)
	return true

# --- Demolition ---

func demolish_at(tile: Vector2i, story: int = selected_story) -> bool:
	var record := _top_record_at(tile, story)
	if record == null:
		return false
	if _demolition_is_blocked(record):
		return false
	_remove_record(record, true)
	return true

func get_nearby_station_ids(world_position: Vector2, interaction_range: float = CRAFTING_STATION_RANGE) -> PackedStringArray:
	var nearby := PackedStringArray()
	for record in _record_list:
		if record.definition == null or record.definition.station_profile == null:
			continue
		if record.node == null or not is_instance_valid(record.node):
			continue
		var station_center: Vector2 = record.node.global_position + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
		var group: String = record.definition.station_profile.recipe_group
		if station_center.distance_to(world_position) <= interaction_range and not nearby.has(group):
			nearby.append(group)
	nearby.sort()
	return nearby

func has_station_near(station_id: String, world_position: Vector2, interaction_range: float = CRAFTING_STATION_RANGE) -> bool:
	return get_nearby_station_ids(world_position, interaction_range).has(station_id)

func refresh_texture_pack() -> void:
	for record in _record_list:
		if record.node != null and is_instance_valid(record.node) and record.node.has_method("reload_visual_texture"):
			record.node.reload_visual_texture()

# --- Save round-trip (v8 layered records) ---

func serialize() -> Array:
	var out: Array = []
	for record in _record_list:
		out.append(record.serialize())
	return out

func deserialize(data: Variant) -> void:
	clear_all()
	if typeof(data) != TYPE_ARRAY:
		return
	for entry in data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var item_id := str(entry.get("item_id", ""))
		var tile := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		restore_building(item_id, tile, int(entry.get("health", 50)), int(entry.get("story", 0)),
				str(entry.get("layer", "")), str(entry.get("orientation", "")), entry)

## Spawn a saved building without consuming inventory. layer/orientation/state
## default from the definition when the save predates v8.
func restore_building(item_id: String, tile: Vector2i, health: int = 50, story: int = 0,
		layer: String = "", orientation: String = "", entry: Dictionary = {}) -> bool:
	var definition := get_definition(item_id) as BuildingDefinition
	if definition == null:
		return false
	var record := BuildingRecord.new()
	record.deserialize(entry, definition)
	record.item_id = item_id
	record.tile = tile
	record.story = story
	record.health = clampi(health, 0, int(definition.max_health))
	if not layer.is_empty():
		record.layer = layer
	if not orientation.is_empty():
		record.orientation = orientation
	var keys := record.reserved_keys()
	for key in keys:
		if records.has(key):
			return false # occupied slot in the save; skip rather than merge
	for key in keys:
		records[key] = record
	_record_list.append(record)
	_spawn_node(record)
	_apply_presentation()
	building_placed.emit(item_id, tile)
	return true

func clear_all() -> void:
	for record in _record_list:
		if record.node != null and is_instance_valid(record.node):
			record.node.queue_free()
	records.clear()
	_record_list.clear()
	_connector_under_player = null
	set_build_mode(false)

# --- Transaction internals ---

## The exact placement failure reason, or "" when the placement would
## succeed. Everything is checked before anything mutates.
func _placement_failure(item_id: String, tile: Vector2i, story: int, orientation: String) -> String:
	var inv: InventoryComponent = player.inventory if player != null else null
	return _placement_failure_for(item_id, tile, story, orientation, inv)

func _placement_failure_for(item_id: String, tile: Vector2i, story: int, orientation: String, inv: InventoryComponent) -> String:
	if item_id == "":
		return "No building part selected"
	if story < 0 or story >= BuildingRecord.MAX_STORIES:
		return "That story is out of range"
	var definition := get_definition(item_id) as BuildingDefinition
	if definition == null:
		return "That item is not a placeable building part"
	if inv == null or not inv.has_item(item_id, 1):
		return "You do not have that building part"
	if not _is_item_unlocked(item_id):
		var technology_id := str(definition.technology_id)
		var technology_name := technology_id.replace("_", " ").capitalize()
		if technology_system != null:
			var technology := technology_system.get_definition(technology_id)
			if technology != null:
				technology_name = technology.display_name
		return "Research %s before building this" % technology_name
	if definition.connector_profile != null \
			and story + definition.connector_profile.upper_story_offset >= BuildingRecord.MAX_STORIES:
		return "There is no story above for this stairwell"
	var resolved_orientation := _resolve_orientation(definition, orientation)
	var probe := _make_record(definition, item_id, tile, story, resolved_orientation)
	var keys := probe.reserved_keys()
	for key in keys:
		var existing := records.get(key) as BuildingRecord
		if existing == null:
			continue
		if probe.layer == "edge" and str(definition.occupancy_replacement) == "edge_fixture" \
				and existing.definition != null \
				and str(existing.definition.occupancy_replacement) == "none":
			continue # the fixture will replace this wall
		return "That slot is already occupied"
	if story == 0 and probe.layer == "ground" and not _terrain_is_buildable(tile):
		return "Foundations need solid land, not water"
	if story > 0 and bool(definition.requires_lower_support) and not _support_ok(probe):
		var required := definition.required_support_tags
		if required.is_empty():
			return "Upper stories need a placed part directly below"
		return "Upper stories need %s support directly below" % ", ".join(required)
	return ""

## Orientation resolved against the definition: non-orientable parts always
## get the single default; edge parts keep only allowed orientations.
func _resolve_orientation(definition: BuildingDefinition, orientation: String) -> String:
	if definition.allowed_orientations.is_empty():
		return ""
	return orientation if definition.allowed_orientations.has(orientation) else "north"

func _make_record(definition: BuildingDefinition, item_id: String, tile: Vector2i, story: int, orientation: String) -> BuildingRecord:
	var record := BuildingRecord.new()
	record.definition = definition
	record.item_id = item_id
	record.tile = tile
	record.story = story
	record.footprint = Vector2i(maxi(definition.width, 1), maxi(definition.height, 1))
	record.layer = definition.effective_placement_layer()
	record.orientation = orientation
	record.health = int(definition.max_health)
	return record

## Conservative direct-support rule: every footprint cell needs a placed
## record directly below whose definition provides one of the required tags.
func _support_ok(probe: BuildingRecord) -> bool:
	var required: PackedStringArray = probe.definition.required_support_tags
	for dx in range(probe.footprint.x):
		for dy in range(probe.footprint.y):
			var cell := probe.tile + Vector2i(dx, dy)
			var supported := false
			for layer in LAYER_QUERY_PRIORITY:
				var below := get_record_at(cell, probe.story - 1, layer)
				if below == null or below.definition == null:
					continue
				if required.is_empty():
					supported = true
				else:
					for tag in required:
						if below.definition.support_tags.has(tag):
							supported = true
				if supported:
					break
			if not supported:
				return false
	return true

func _terrain_is_buildable(tile: Vector2i) -> bool:
	if world_generator == null:
		return true # test contexts without a world; terrain gating is live-game behaviour
	var center := Vector2(tile) * float(TILE_SIZE) + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	var water_class := world_generator.get_water_class_at_world(int(center.x), int(center.y))
	return water_class == "land" or water_class == "shore"

func _remove_record(record: BuildingRecord, refund: bool, refund_to: InventoryComponent = null) -> void:
	for key in record.reserved_keys():
		if records.get(key) == record:
			records.erase(key)
	_record_list.erase(record)
	var target := refund_to
	if target == null and player != null:
		target = player.inventory
	if target == null:
		target = refund_inventory
	if refund and target != null and record.item_id != "":
		target.add_item(record.item_id, 1)
	if _connector_under_player == record:
		_connector_under_player = null
	building_removed.emit(record.item_id, record.tile)
	if record.node != null and is_instance_valid(record.node):
		record.node.queue_free()
	record.node = null
	_apply_presentation()

func _demolish_near_player() -> void:
	if player == null:
		return
	var nearest: BuildingRecord = null
	var best: float = 56.0
	for record in _record_list:
		if record.node == null or not is_instance_valid(record.node) or record.story != selected_story:
			continue
		var dist: float = record.node.position.distance_to(player.global_position)
		if dist < best:
			best = dist
			nearest = record
	if nearest != null:
		if _demolition_is_blocked(nearest):
			return
		_remove_record(nearest, true)

## Containers are never silently deleted by player demolition. The record
## knows whether it has storage from its authored definition, so this applies
## equally to future crates, hoppers, and stations with persistent inputs.
func _demolition_is_blocked(record: BuildingRecord) -> bool:
	if record == null or not record.has_nonempty_container():
		return false
	var reason := "Empty %s before demolishing it." % record.display_name()
	placement_failed.emit(reason)
	demolition_blocked.emit(record, reason)
	return true

## Orientation for a live edge placement: the nearest tile edge under the
## cursor (deterministic; API placements default to north).
func _orientation_for_mouse(tile: Vector2i) -> String:
	var definition := get_definition(selected_item_id) as BuildingDefinition
	if definition == null or definition.allowed_orientations.is_empty():
		return ""
	var world := player.get_global_mouse_position() if player != null else Vector2(tile) * float(TILE_SIZE)
	var center_offset := world - Vector2(tile) * float(TILE_SIZE) - Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	if absf(center_offset.x) >= absf(center_offset.y):
		return "east" if center_offset.x > 0.0 else "west"
	return "south" if center_offset.y > 0.0 else "north"

## Republish the cutaway policy: build mode focuses the construction story
## (blueprints above), normal play focuses the player's active story.
func _apply_presentation() -> void:
	var focus := selected_story if build_mode else active_story
	for record in _record_list:
		if record.node != null and is_instance_valid(record.node):
			record.node.set_presentation(focus, build_mode, roofs_visible)

func _mouse_tile() -> Vector2i:
	var world := player.get_global_mouse_position() if player != null else Vector2.ZERO
	return Vector2i(int(floor(world.x / float(TILE_SIZE))), int(floor(world.y / float(TILE_SIZE))))

func _refresh_owned() -> void:
	_owned = PackedStringArray()
	if player == null or player.inventory == null or item_database == null:
		return
	var items := player.inventory.get_all_items()
	for item_id in items:
		if definitions.has(str(item_id)) and int(items[item_id]) > 0 and _is_item_unlocked(str(item_id)):
			_owned.append(str(item_id))
	_owned.sort()

func _is_item_unlocked(item_id: String) -> bool:
	var definition: Variant = get_definition(item_id)
	if definition == null:
		return false
	var technology_id := str(definition.get("technology_id"))
	return technology_id.is_empty() or technology_system == null or technology_system.is_unlocked(technology_id)

## Discover and validate data-authored building definitions. One bad asset
## removes only itself from the palette; every problem is logged with the
## asset path so the author can fix it without a restart hint.
func _load_definitions() -> void:
	content_registry = BuildingContentRegistry.new()
	content_registry.discover()
	definitions = content_registry.definitions
	for message in content_registry.validation_errors:
		push_error("Building content: %s" % message)

func _spawn_node(record: BuildingRecord) -> void:
	var building := Building.new()
	building.setup(record.item_id, record.display_name(), record.tile, record.health,
			record.story, record.definition, record.layer, record.orientation)
	building.placement_key = record.placement_key()
	building.capability_state = record.capability_state
	building.building_destroyed.connect(_on_building_destroyed.bind(record))
	add_child(building)
	record.node = building

func _on_building_destroyed(record: BuildingRecord) -> void:
	_remove_record(record, false)
