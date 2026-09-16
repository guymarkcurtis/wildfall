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
const LAYER_QUERY_PRIORITY := ["object", "connector", "floor", "ground", "edge", "fixture", "overhead"]

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

## Sandbox-only roof visibility override (F5 key in Building Sandbox; R was
## repointed at building rotation by M9 box 5).
var roofs_visible := true

## Shelter is an enclosed room: a floor underfoot on the active story, a
## perimeter edge fixture (wall, door, or window) in all four cardinal
## directions before the floor ends, and a roof overhead one story up.
## The seal walk is bounded — a floor run longer than this is an open
## deck, which counts as outdoors. Record lookups only: code defines the
## system, data defines the parts.
const SHELTER_SEAL_DEPTH := 16

## The shelter answer is cached per (tile, story) and recomputed when the
## player steps to a new tile/story or the record set changes, so the
## per-frame player speed path never scans the building index.
var _shelter_cache_key := ""
var _shelter_cache_value := false
var _shelter_dirty := true

## Per-story occupancy of tile cells ("<story>:<x>:<y>" -> true) plus the
## exterior shell classification derived from it: the records a viewer
## outside a structure sees — every roof, and every wall/fixture whose face
## is not backed by built-up space on that story (see
## _rebuild_exterior_classification). Rebuilt only when the record set
## changes, so the per-frame path never scans it.
var _occupied_cells: Dictionary = {}
var _shell_records: Dictionary = {}
var _exterior_dirty := true

## The connected structure the player currently stands in — the interior
## cutaway follows only this component, not every building in the world.
## Cached against a cheap signature (player tile + story + the anchor
## record they touch) and the record generation, so walking between
## adjacent structures re-keys the view without a per-frame BFS.
var _player_structure: Dictionary = {}
var _structure_signature := ""
var _structure_generation := -1
var _record_generation := 0

## The presentation mode the building nodes were last republished in, so a
## doorway crossing (sheltered <-> not) republishes without waiting for a
## placement.
var _presentation_sheltered := false

var _connector_under_player: BuildingRecord = null

var player: Player = null
var item_database: ItemDatabase = null
var technology_system: TechnologySystem = null

## Refund target for API-driven placement/demolition without a player
## (test harnesses). Live play always refunds through player.inventory.
var refund_inventory: InventoryComponent = null

var _ghost: Node2D = null
## (item | resolved orientation | story) signature of the built ghost, so
## markers are rebuilt only when the placement contract actually changes.
var _ghost_signature := ""
var _orientation_label: Label = null
var _owned: PackedStringArray = []
var _visible: PackedStringArray = []
var _select_index := 0

## Build-palette filter: the build_group the palette shows ("") = every
## group. Presentation only — placement, support, and save data never read
## it, and a saved game never records it (it resets to "" on next boot).
var build_filter := ""

## The orientation the player explicitly chose with R/Q while the current
## part is selected ("") = follow the nearest tile edge under the cursor.
## Transient presentation state: live placement and the ghost compass
## consume it, and it resets when build mode is (re)entered or the
## selection changes. Saved building records always keep the orientation
## they were placed with — rotation never reinterprets a placed part.
var pending_orientation := ""

signal building_placed(building_id: String, coords: Vector2i)
signal building_removed(building_id: String, coords: Vector2i)
signal build_mode_changed(enabled: bool, selected_item_id: String)
signal build_story_changed(story: int)
signal active_story_changed(story: int)
signal placement_failed(reason: String)
signal demolition_blocked(record: BuildingRecord, reason: String)

func _physics_process(delta: float) -> void:
	_update_connector_traversal()
	_update_outdoor_story_reset()
	_sync_sheltered_presentation()
	if item_database != null:
		for record in _record_list:
			FuelConsumer.tick(record, delta, item_database)
			StationCrafting.tick(record, delta, item_database)
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
		var landing: int = found.story + found.definition.connector_profile.upper_story_offset
		if active_story == found.story:
			set_active_story(landing)
		elif active_story == landing:
			set_active_story(found.story)
	_connector_under_player = found

## Leaving a building: there is no "upper story outside" state. When the
## player is no longer standing on a floor of the active story and is not
## crossing a connector (traversal owns the story during the crossing), the
## active story returns to the ground — so leaving a house from an upper
## floor lands the view back on the ground level. Unroofed decks and open
## porches keep their floor underfoot, so a balcony stays on its story and
## only reads as outdoors. The sandbox is exempt: its [ / ] keys deliberately
## park the active story as a viewing tool.
func _update_outdoor_story_reset() -> void:
	if player == null or not is_instance_valid(player):
		return
	if GameSession.is_building_sandbox():
		return
	if active_story <= 0 or _connector_under_player != null:
		return
	var tile := Vector2i(
			int(floor(player.global_position.x / float(TILE_SIZE))),
			int(floor(player.global_position.y / float(TILE_SIZE))))
	if has_layer_covering(tile, active_story, "floor"):
		return
	set_active_story(0)

## Presentation follows the shelter state AND the structure the player
## stands in: the moment they cross a doorway, walk between adjacent
## structures, or a roof is built or removed, the cutaway re-keys between
## the interior view (the level the player is on) and the exterior shell
## view without waiting for the next placement.
func _sync_sheltered_presentation() -> void:
	if player == null or not is_instance_valid(player):
		return
	var sheltered := is_player_sheltered()
	var signature := _player_structure_signature()
	# Do NOT pre-write `_structure_signature` here: the BFS cache inside
	# `_compute_player_structure` compares against it, so writing the new
	# signature first would make every walk between two structures a cache
	# hit and the cutaway would never re-key until a record changed. The
	# compute step owns the write; it runs only when the signature (or the
	# record generation) actually differs.
	if sheltered != _presentation_sheltered or signature != _structure_signature:
		_presentation_sheltered = sheltered
		_apply_presentation()

## The connector record whose landing zone contains `world_position` on the
## given story (a stair record spans its own story and its landing story,
## which may be above or below depending on the connector's offset).
func _connector_record_at(world_position: Vector2, story: int) -> BuildingRecord:
	for record in _record_list:
		if record.layer != "connector" or record.definition == null \
				or record.definition.connector_profile == null:
			continue
		var profile := record.definition.connector_profile
		var lo := mini(record.story, record.story + profile.upper_story_offset)
		var hi := maxi(record.story, record.story + profile.upper_story_offset)
		if story < lo or story > hi:
			continue
		if record.node == null or not is_instance_valid(record.node):
			continue
		var center := record.node.global_position + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
		if center.distance_to(world_position) <= profile.trigger_radius_px:
			return record
	return null

func _ready() -> void:
	_load_definitions()
	_ghost = Node2D.new()
	_ghost.visible = false
	add_child(_ghost)
	_orientation_label = Label.new()
	_orientation_label.add_theme_font_size_override("font_size", 14)
	_orientation_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	var label_style := StyleBoxFlat.new()
	label_style.bg_color = Color(0.06, 0.1, 0.08, 0.78)
	label_style.set_corner_radius_all(4)
	label_style.content_margin_left = 5.0
	label_style.content_margin_right = 5.0
	label_style.content_margin_top = 2.0
	label_style.content_margin_bottom = 2.0
	_orientation_label.add_theme_stylebox_override("normal", label_style)
	_orientation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_orientation_label.visible = false
	_orientation_label.z_index = 41
	add_child(_orientation_label)

func _process(_delta: float) -> void:
	if not build_mode:
		_ghost.visible = false
		_orientation_label.visible = false
		return
	_refresh_owned()
	if _visible.is_empty():
		selected_item_id = ""
		pending_orientation = ""
		_ghost.visible = false
		_orientation_label.visible = false
		return
	if selected_item_id == "" or not _visible.has(selected_item_id):
		pending_orientation = ""
		_select_index = 0
		selected_item_id = _visible[0]
		build_mode_changed.emit(true, selected_item_id)
	var tile := _mouse_tile()
	var orientation := _placement_orientation(tile)
	var signature := "%s|%s|%d" % [selected_item_id, orientation, selected_story]
	if signature != _ghost_signature:
		_ghost_signature = signature
		_rebuild_ghost(selected_item_id, orientation, selected_story)
	# The container anchors on the construction story's band; markers add
	# their layer offset (and a story offset for stairwell landings).
	_ghost.position = Vector2(tile * TILE_SIZE)
	_ghost.z_index = selected_story * BuildingRecord.STORY_Z_STRIDE
	_ghost.visible = true
	_update_ghost_colors(tile)
	_update_orientation_compass(tile)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_build"):
		set_build_mode(not build_mode)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("demolish"):
		_demolish_at_mouse()
		get_viewport().set_input_as_handled()
		return
	# Building Sandbox debug controls: the [ and ] keys move the ACTIVE story
	# when the build palette is closed, and F5 toggles roof visibility.
	# Never available in survival — a normal player must not phase through
	# floors. (R/Q became building-rotation controls in M9 box 5.)
	if GameSession.is_building_sandbox() and not build_mode:
		if event.is_action_pressed("build_level_up"):
			set_active_story(active_story + 1)
			_toast("Now viewing story %d" % (active_story + 1))
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("build_level_down"):
			set_active_story(active_story - 1)
			_toast("Now viewing story %d" % (active_story + 1))
			get_viewport().set_input_as_handled()
			return
	elif not build_mode and (event.is_action_pressed("build_level_up")
			or event.is_action_pressed("build_level_down")):
		# Survival has no free story movement: say how story editing works
		# instead of silently swallowing the press.
		_toast("Enter build mode (B), then press [ or ] to choose the story")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_roofs") and GameSession.is_building_sandbox():
		roofs_visible = not roofs_visible
		_apply_presentation()
		get_viewport().set_input_as_handled()
		return
	if not build_mode:
		return
	# R/Q rotate the pending orientation of the selected part (M9 box 5).
	# Works in every mode while the build palette is open; the compass
	# above the ghost shows the edge the next placement will use.
	if event.is_action_pressed("build_rotate_cw"):
		rotate_build_orientation(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("build_rotate_ccw"):
		rotate_build_orientation(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("build_level_up"):
		set_selected_story(selected_story + 1)
		_toast("Now building on story %d" % (selected_story + 1))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("build_level_down"):
		set_selected_story(selected_story - 1)
		_toast("Now building on story %d" % (selected_story + 1))
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
	# Every fresh build session (or return to normal play) starts from the
	# live mouse-edge default; a stuck rotation choice is a dead end.
	pending_orientation = ""
	if build_mode:
		_refresh_owned()
		if not _visible.is_empty():
			_select_index = clampi(_select_index, 0, _visible.size() - 1)
			selected_item_id = _visible[_select_index]
		else:
			selected_item_id = ""
	else:
		selected_item_id = ""
		if _ghost:
			_ghost.visible = false
		if _orientation_label:
			_orientation_label.visible = false
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
	# A new part means a new rotation context.
	pending_orientation = ""
	if _visible.is_empty():
		selected_item_id = ""
		return
	if selected_item_id != "" and _visible.has(selected_item_id):
		_select_index = posmod(_select_index + step, _visible.size())
	else:
		_select_index = 0
	selected_item_id = _visible[_select_index]
	build_mode_changed.emit(build_mode, selected_item_id)

func select_item(item_id: String) -> bool:
	_refresh_owned()
	var index := _visible.find(item_id)
	if index < 0:
		return false
	# A new part means a new rotation context.
	pending_orientation = ""
	_select_index = index
	selected_item_id = item_id
	build_mode_changed.emit(build_mode, selected_item_id)
	return true

## Palette filter (M9): show only the parts in one build group; "" shows
## every group. A group the player owns no parts of falls back to the full
## list, so a filter can never leave build mode without a selectable part.
func set_build_filter(group: String) -> void:
	var next_filter := group
	if not next_filter.is_empty():
		var any_owned := false
		for item_id in _owned:
			if get_build_group(item_id) == next_filter:
				any_owned = true
				break
		if not any_owned:
			next_filter = ""
	if next_filter == build_filter:
		return
	build_filter = next_filter
	_refresh_owned()
	_resync_selection()
	build_mode_changed.emit(build_mode, selected_item_id)

## Re-point the selection at the visible (filter-aware) list without
## emitting; the caller publishes the change.
func _resync_selection() -> void:
	if _visible.is_empty():
		selected_item_id = ""
		pending_orientation = ""
		return
	if selected_item_id == "" or not _visible.has(selected_item_id):
		# The re-pointed part is a new rotation context.
		pending_orientation = ""
		_select_index = 0
		selected_item_id = _visible[0]

func get_build_group(item_id: String) -> String:
	var definition: Variant = get_definition(item_id)
	if definition == null:
		return ""
	return str(definition.get("build_group"))

func get_owned_building_items() -> Array[String]:
	_refresh_owned()
	var result: Array[String] = []
	for item_id in _owned:
		result.append(item_id)
	return result

## The parts the palette currently shows: the owned set narrowed by the
## active build-filter (empty filter = the full owned set).
func get_visible_building_items() -> Array[String]:
	_refresh_owned()
	var result: Array[String] = []
	for item_id in _visible:
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

## Record on a specific layer/edge at a tile+story. Edge and fixture
## orientations are normalized through their canonical keys, so "east"
## finds the record placed from the neighbouring tile's "west".
func get_record_at(tile: Vector2i, story: int, layer: String, orientation: String = "") -> BuildingRecord:
	if layer == "edge":
		return records.get(BuildingRecord.canonical_edge_key(tile, story, orientation)) as BuildingRecord
	if layer == "fixture":
		return records.get(BuildingRecord.canonical_fixture_key(tile, story, orientation)) as BuildingRecord
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

# --- Shelter queries ---

## True when some record on `story` with the given layer has a footprint that
## covers the tile. Footprint-aware, so multi-tile floors and roofs cover
## whole rooms through the same lookup.
func has_layer_covering(tile: Vector2i, story: int, layer: String) -> bool:
	for record in _record_list:
		if record.layer != layer or record.story != story or not record.occupies_tiles():
			continue
		if tile.x >= record.tile.x and tile.x < record.tile.x + record.footprint.x \
				and tile.y >= record.tile.y and tile.y < record.tile.y + record.footprint.y:
			return true
	return false

## True when walking from `tile` on `story` toward `orientation`, an edge
## fixture (wall, door, or window) is met before the floor ends. Hitting a
## fixture on the starting tile counts as sealed; stepping off the floor
## counts as open; a run longer than SHELTER_SEAL_DEPTH is an open deck.
func _sealed_in_direction(tile: Vector2i, story: int, orientation: String) -> bool:
	var delta := Vector2i(0, 0)
	match orientation:
		"north":
			delta = Vector2i(0, -1)
		"south":
			delta = Vector2i(0, 1)
		"west":
			delta = Vector2i(-1, 0)
		"east":
			delta = Vector2i(1, 0)
	var current := tile
	for _step in range(SHELTER_SEAL_DEPTH):
		if get_record_at(current, story, "edge", orientation) != null:
			return true
		if not has_layer_covering(current, story, "floor"):
			return false
		current += delta
	return false

## True when the player stands inside an enclosed room: a floor underfoot on the
## active story, a perimeter edge fixture in all four directions, and a
## roof overhead one story up (the room's ceiling). Open decks, half-built
## shelters, and natural ground never count — story-0 terrain has no floor
## records, so a room only exists where the player placed one.
func is_player_sheltered() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var tile := Vector2i(
			int(floor(player.global_position.x / float(TILE_SIZE))),
			int(floor(player.global_position.y / float(TILE_SIZE))))
	var story := active_story
	var cache_key := "%d:%d:%d" % [tile.x, tile.y, story]
	if _shelter_dirty or cache_key != _shelter_cache_key:
		_shelter_cache_value = _compute_shelter(tile, story)
		_shelter_cache_key = cache_key
		_shelter_dirty = false
	return _shelter_cache_value

func _compute_shelter(tile: Vector2i, story: int) -> bool:
	if not has_layer_covering(tile, story, "floor"):
		return false
	for orientation in ["north", "south", "west", "east"]:
		if not _sealed_in_direction(tile, story, str(orientation)):
			return false
	return has_layer_covering(tile, story + 1, "overhead")

## Rebuild the two tables the exterior presentation reads: per-story
## tile-cell occupancy, and the shell classification. A record is part of
## the shell a viewer outside the structure sees when it is a roof (always —
## a roof is the exterior answer to "how tall is this structure?") or an
## edge/fixture
## part whose wall face is not backed by built-up space on that story. An
## edge whose spanned tiles are BOTH occupied is an interior partition: it
## stays ghosted even from outside. A freestanding wall (one or zero
## spanned tiles occupied) is shell — an unfinished house shows exactly what
## exists. Tile layers are mass, not skin: they never join the shell.
func _rebuild_exterior_classification() -> void:
	_occupied_cells.clear()
	for record in _record_list:
		if not record.occupies_tiles():
			continue
		for dx in range(record.footprint.x):
			for dy in range(record.footprint.y):
				_occupied_cells["%d:%d:%d" % [record.story, record.tile.x + dx, record.tile.y + dy]] = true
	_shell_records.clear()
	for record in _record_list:
		match record.layer:
			"overhead":
				_shell_records[record.placement_key()] = true
			"edge", "fixture":
				var spanned := BuildingRecord.edge_span_tiles(record.tile, record.orientation)
				if not _occupied_cells.has("%d:%d:%d" % [record.story, spanned[0].x, spanned[0].y]) \
						or not _occupied_cells.has("%d:%d:%d" % [record.story, spanned[1].x, spanned[1].y]):
					_shell_records[record.placement_key()] = true
	_exterior_dirty = false

## Live (lazily rebuilt) occupancy of one tile cell on one story.
func _cell_occupied(tile: Vector2i, story: int) -> bool:
	if _exterior_dirty:
		_rebuild_exterior_classification()
	return _occupied_cells.has("%d:%d:%d" % [story, tile.x, tile.y])

## The connected structure the player currently stands in (G4): BFS over the
## placed records, seeded by the records touching the player's
## (tile, story). Records are adjacent when their spanned cells are equal
## or orthogonally touching on the same story, or the same cell directly
## above/below. Deliberate about over-merging: adjacent single-storey sheds
## read as one structure — far better than opening two buildings at once.
## Cached against (signature, record generation); returns {} when the
## player is null or stands in open ground.
func _compute_player_structure() -> Dictionary:
	if player == null or not is_instance_valid(player):
		return {}
	var signature := _player_structure_signature()
	if signature == _structure_signature and _structure_generation == _record_generation:
		return _player_structure
	_structure_signature = signature
	_structure_generation = _record_generation
	_player_structure = {}
	var tile := Vector2i(
			int(floor(player.global_position.x / float(TILE_SIZE))),
			int(floor(player.global_position.y / float(TILE_SIZE))))
	var touching := _records_touching(tile, active_story)
	if touching.is_empty():
		return _player_structure
	var queue: Array[BuildingRecord] = []
	for record in touching:
		_player_structure[record.placement_key()] = record
		queue.append(record)
	while queue.size() > 0:
		var current: BuildingRecord = queue.pop_front()
		var current_cells := _record_span_cells(current)
		for neighbour in _record_list:
			if neighbour == current or _player_structure.has(neighbour.placement_key()):
				continue
			var story_delta := absi(neighbour.story - current.story)
			if story_delta > 1:
				continue
			if _cells_touch(current_cells, _record_span_cells(neighbour), story_delta == 0):
				_player_structure[neighbour.placement_key()] = neighbour
				queue.append(neighbour)
	return _player_structure

## The cells a record binds into the player's structure: every footprint
## cell for tile layers; for an edge/fixture part only the spanned cells
## that are actually built up. Counting a wall's open far side would let
## two structures across a yard gap merge through the gap — their facing
## exterior walls' far cells sit adjacent — so a wall binds only the side
## it is built on (both sides for an interior partition, none for a
## freestanding one).
func _record_span_cells(record: BuildingRecord) -> Array[Vector2i]:
	if record.layer == "edge" or record.layer == "fixture":
		var cells: Array[Vector2i] = []
		for cell in BuildingRecord.edge_span_tiles(record.tile, record.orientation):
			if _cell_occupied(cell, record.story):
				cells.append(cell)
		return cells
	var plain: Array[Vector2i] = []
	if record.occupies_tiles():
		for dx in range(record.footprint.x):
			for dy in range(record.footprint.y):
				plain.append(record.tile + Vector2i(dx, dy))
	return plain

## True when two record spans meet: the same cell (adjacent on the same
## story, or directly above/below), or orthogonally touching cells on the
## same story.
func _cells_touch(a: Array[Vector2i], b: Array[Vector2i], same_story: bool) -> bool:
	for cell_a in a:
		for cell_b in b:
			var diff := cell_a - cell_b
			if diff == Vector2i.ZERO:
				return true
			if same_story and absi(diff.x) + absi(diff.y) == 1:
				return true
	return false

## The cheap per-frame signature of the player's structure anchor: their
## tile and story plus the first record they touch. A record change is
## caught separately by the record generation counter.
func _player_structure_signature() -> String:
	if player == null or not is_instance_valid(player):
		return ""
	var tile := Vector2i(
			int(floor(player.global_position.x / float(TILE_SIZE))),
			int(floor(player.global_position.y / float(TILE_SIZE))))
	var touching := _records_touching(tile, active_story)
	var anchor := "-" if touching.is_empty() else str(touching[0].placement_key())
	return "%d:%d:%d|%s" % [tile.x, tile.y, active_story, anchor]

## Record changes invalidate the per-tile shelter answer AND the exterior
## shell tables, so a standing player is re-evaluated the moment a wall,
## door, roof, or fixture is built or demolished. The generation counter
## also invalidates the cached player-structure component.
func _invalidate_record_caches() -> void:
	_shelter_dirty = true
	_exterior_dirty = true
	_record_generation += 1

# --- Placement ---

func can_place(tile: Vector2i, story: int = selected_story) -> bool:
	return _placement_failure(selected_item_id, tile, story, _placement_orientation(tile)) == ""

## Playerless harness managers (tests) have no player to own the item, so
## the check falls back to the refund inventory — the same fallback chain
## the refund path uses.

## Place the selected structural part on the active construction story.
## Edge parts use the player's pending R/Q orientation when one is set,
## otherwise the nearest tile edge under the cursor.
func try_place_at(tile: Vector2i) -> bool:
	var orientation := _placement_orientation(tile)
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
	_invalidate_record_caches()
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
	_invalidate_record_caches()
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
	_invalidate_record_caches()
	_connector_under_player = null
	set_build_mode(false)

# --- Transaction internals ---

## The exact placement failure reason, or "" when the placement would
## succeed. Everything is checked before anything mutates.
func _placement_failure(item_id: String, tile: Vector2i, story: int, orientation: String) -> String:
	var inv: InventoryComponent = player.inventory if player != null else refund_inventory
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
	if definition.connector_profile != null:
		var landing := story + definition.connector_profile.upper_story_offset
		if landing < 0 or landing >= BuildingRecord.MAX_STORIES:
			return "There is no landing story for this stairwell here"
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
	if probe.layer == "fixture":
		var fixture_reason := _fixture_edge_failure(tile, story, resolved_orientation)
		if fixture_reason != "":
			return fixture_reason
	if story == 0 and probe.layer == "ground" and not _terrain_is_buildable(tile):
		return "Foundations need solid land, not water"
	if story > 0 and bool(definition.requires_lower_support) and not _support_ok(probe):
		var required := definition.required_support_tags
		if required.is_empty():
			return "Upper stories need a placed part directly below"
		return "Upper stories need %s support directly below" % ", ".join(required)
	return ""

## The exact wall-fixture placement failures, or "" when the fixture would
## mount: the physical edge must already hold a wall, door, or window, and
## it must face outside the built structure (an edge whose spanned tiles
## are both built up is an interior partition). The build ghost paints the
## same two failures red through this same helper.
func _fixture_edge_failure(tile: Vector2i, story: int, orientation: String) -> String:
	if get_record_at(tile, story, "edge", orientation) == null:
		return "Wall fixtures mount on a wall, door, or window edge"
	var spanned := BuildingRecord.edge_span_tiles(tile, orientation)
	if _cell_occupied(spanned[0], story) and _cell_occupied(spanned[1], story):
		return "That wall faces inside the building — fixtures mount on its outside"
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
	for dx in range(probe.footprint.x):
		for dy in range(probe.footprint.y):
			if not _cell_supported(probe.definition, probe.tile + Vector2i(dx, dy), probe.story):
				return false
	return true

## Per-cell version of the support rule, so the ghost can paint the specific
## unsupported cells red rather than one all-or-nothing colour.
func _cell_supported(definition: BuildingDefinition, cell: Vector2i, story: int) -> bool:
	if story <= 0:
		return true
	var required: PackedStringArray = definition.required_support_tags
	for layer in LAYER_QUERY_PRIORITY:
		var below := get_record_at(cell, story - 1, layer)
		if below == null or below.definition == null:
			continue
		if required.is_empty():
			return true
		for tag in required:
			if below.definition.support_tags.has(tag):
				return true
	return false

## M9 box 6: rebuild the ghost's child markers — one per reserved key — when
## the (item, orientation, story) signature changes. The preview must show the
## complete placement contract: every footprint cell, the exact edge an edge
## part occupies, and the stairwell landing a connector reserves.
func _rebuild_ghost(item_id: String, orientation: String, story: int) -> void:
	for child in _ghost.get_children():
		child.free()
	_ghost_signature = "%s|%s|%d" % [item_id, orientation, story]
	var definition := get_definition(item_id) as BuildingDefinition
	if definition == null:
		return
	var probe := _make_record(definition, item_id, Vector2i.ZERO, story,
			_resolve_orientation(definition, orientation))
	for entry in probe.reserved_key_descriptions():
		var layer := str(entry["layer"])
		var cell := entry["tile"] as Vector2i
		var marker_story := int(entry["story"])
		var marker := Polygon2D.new()
		if layer == "edge" or layer == "fixture":
			marker.polygon = _edge_strip_polygon(str(entry["side"]))
		else:
			marker.polygon = PackedVector2Array([
				Vector2(2, 2), Vector2(TILE_SIZE - 2, 2),
				Vector2(TILE_SIZE - 2, TILE_SIZE - 2), Vector2(2, TILE_SIZE - 2)
			])
		marker.position = Vector2(cell) * float(TILE_SIZE)
		marker.z_index = (marker_story - story) * BuildingRecord.STORY_Z_STRIDE \
				+ int(BuildingRecord.LAYER_Z.get(layer, 2)) + 1
		marker.set_meta("ghost_kind", "landing" if (layer == "floor" and marker_story != story) else layer)
		marker.set_meta("ghost_layer", layer)
		marker.set_meta("ghost_story", marker_story)
		marker.set_meta("ghost_side", str(entry["side"]))
		_ghost.add_child(marker)

## A 5px strip drawn on the given side of the anchor tile — the visual
## answer to "which of the four edges will this part take?":
func _edge_strip_polygon(side: String) -> PackedVector2Array:
	match side:
		"north":
			return PackedVector2Array([
				Vector2(0, 0), Vector2(TILE_SIZE, 0),
				Vector2(TILE_SIZE, 5), Vector2(0, 5)
			])
		"south":
			return PackedVector2Array([
				Vector2(0, TILE_SIZE - 5), Vector2(TILE_SIZE, TILE_SIZE - 5),
				Vector2(TILE_SIZE, TILE_SIZE), Vector2(0, TILE_SIZE)
			])
		"west":
			return PackedVector2Array([
				Vector2(0, 0), Vector2(5, 0),
				Vector2(5, TILE_SIZE), Vector2(0, TILE_SIZE)
			])
		_:
			return PackedVector2Array([
				Vector2(TILE_SIZE - 5, 0), Vector2(TILE_SIZE, 0),
				Vector2(TILE_SIZE, TILE_SIZE), Vector2(TILE_SIZE - 5, TILE_SIZE)
			])

## Per-frame ghost recolour: green while every reserved key is free (and
## supported), red on the specific occupied or unsupported cells, and a
## distinct blue for the stairwell landing a connector reserves.
func _update_ghost_colors(tile: Vector2i) -> void:
	var definition := get_definition(selected_item_id) as BuildingDefinition
	for marker in _ghost.get_children():
		var kind := str(marker.get_meta("ghost_kind", ""))
		var layer := str(marker.get_meta("ghost_layer", ""))
		var marker_story := int(marker.get_meta("ghost_story", 0))
		# The marker's local offset is its cell's offset from the probe
		# anchor, so the live key re-anchors it on the current mouse tile.
		var delta := Vector2i(
			int(marker.position.x / float(TILE_SIZE)),
			int(marker.position.y / float(TILE_SIZE)))
		var cell := tile + delta
		var key := ""
		var edge_failure := ""
		if layer == "edge":
			key = BuildingRecord.canonical_edge_key(cell, marker_story, str(marker.get_meta("ghost_side", "north")))
		elif layer == "fixture":
			key = BuildingRecord.canonical_fixture_key(cell, marker_story, str(marker.get_meta("ghost_side", "north")))
			edge_failure = _fixture_edge_failure(cell, marker_story, str(marker.get_meta("ghost_side", "north")))
		else:
			key = BuildingRecord.tile_key(cell, marker_story, layer)
		var occupied := get_record_for_key(key) != null or edge_failure != ""
		var unsupported := marker_story > 0 and definition != null \
				and bool(definition.requires_lower_support) \
				and not _cell_supported(definition, tile + delta, marker_story)
		if kind == "landing":
			marker.color = Color(0.85, 0.25, 0.2, 0.4) if (occupied or unsupported) else Color(0.45, 0.7, 1.0, 0.4)
		else:
			marker.color = Color(0.3, 0.85, 0.35, 0.4) if not (occupied or unsupported) else Color(0.85, 0.25, 0.2, 0.4)

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
	_invalidate_record_caches()
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
	# A wall that loses its edge (demolished — the edge key is now free)
	# takes the fixtures mounted on that edge with it, refunded like any
	# demolished part. An edge that is merely REPLACED (a door over a wall)
	# keeps its fixtures: the replacement already owns the edge key.
	if record.layer == "edge":
		var wall_key := BuildingRecord.canonical_edge_key(record.tile, record.story, record.orientation)
		if not records.has(wall_key):
			var mounted := records.get(BuildingRecord.canonical_fixture_key(record.tile, record.story, record.orientation)) as BuildingRecord
			if mounted != null:
				_remove_record(mounted, refund, refund_to)
				return
	_apply_presentation()

## F demolishes whatever the mouse points at, always taking the TOPMOST
## part: a column with a roof over a floor over a wall loses the roof
## first, one press per part. Edge parts (walls) anchor to the four
## canonical edges around the cursor tile, so any side of a wall is
## found. The cursor is the selector — no player-distance check.
func _demolish_at_mouse() -> void:
	if player == null:
		return
	_demolish_top_at_tile(_mouse_tile())

func _demolish_top_at_tile(tile: Vector2i) -> bool:
	var best: BuildingRecord = null
	var best_story := -1
	var best_key := ""
	for story in range(BuildingRecord.MAX_STORIES):
		for record in _records_touching(tile, story):
			var key := record.placement_key()
			if story > best_story or (story == best_story and key < best_key):
				best = record
				best_story = story
				best_key = key
	if best == null:
		return false
	if _demolition_is_blocked(best):
		return false # the block reason is already on the HUD toast lane
	_remove_record(best, true)
	return true

## Every record occupying one tile on one story: cell-anchored layers plus
## the edge and fixture records on the tile's four sides (walls and the
## fixtures mounted on them, between cells).
func _records_touching(tile: Vector2i, story: int) -> Array[BuildingRecord]:
	var found: Array[BuildingRecord] = []
	for layer in LAYER_QUERY_PRIORITY:
		if layer == "edge" or layer == "fixture":
			continue
		var record := get_record_at(tile, story, layer)
		if record != null and not found.has(record):
			found.append(record)
	# A wall's canonical key is the NORTH/WEST edge of an anchor tile, so the
	# south edge of `tile` is the north edge of the tile below, and the east
	# edge is the west edge of the tile to the right. Fixtures share a wall's
	# physical edge, so both layers query the same four canonical sides.
	var edge_queries := [
		[tile, "north"],
		[tile + Vector2i(0, 1), "north"],
		[tile, "west"],
		[tile + Vector2i(1, 0), "west"],
	]
	for layer in ["edge", "fixture"]:
		for query in edge_queries:
			var record := get_record_at(query[0], story, layer, str(query[1]))
			if record != null and not found.has(record):
				found.append(record)
	return found

func _toast(text: String) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var hud := parent.get_node_or_null("HUD")
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(text)

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

## The orientation a live placement (and its ghost/compass) uses: the
## player's pending R/Q choice when one is set and the selected definition
## allows it, otherwise the nearest tile edge under the cursor.
func _placement_orientation(tile: Vector2i) -> String:
	if not pending_orientation.is_empty():
		var definition := get_definition(selected_item_id) as BuildingDefinition
		if definition != null and definition.allowed_orientations.has(pending_orientation):
			return pending_orientation
	return _orientation_for_mouse(tile)

## Rotate the pending orientation of the selected part through its allowed
## orientations (R clockwise step +1, Q counter-clockwise step -1). The
## first press seeds the pending orientation from the live mouse-edge
## default so the compass and the placement stay honest; the choice then
## sticks — mouse movement no longer steers it — until the selection
## changes or build mode is (re)entered. Non-orientable parts are a no-op.
func rotate_build_orientation(step: int) -> void:
	if not build_mode:
		return
	var definition := get_definition(selected_item_id) as BuildingDefinition
	if definition == null or definition.allowed_orientations.is_empty():
		return
	if pending_orientation.is_empty():
		pending_orientation = _orientation_for_mouse(_mouse_tile())
	var allowed := definition.allowed_orientations
	var index := allowed.find(pending_orientation)
	if index < 0:
		index = 0
	pending_orientation = allowed[posmod(index + step, allowed.size())]

## Compass/edge preview (M9 box 5): while an orientable part is selected,
## float the resolved edge letter (N/E/S/W) above the ghost tile. It
## follows the mouse while no pending rotation is set and the pending
## choice once R/Q has been used.
func _update_orientation_compass(tile: Vector2i) -> void:
	if _orientation_label == null:
		return
	var definition := get_definition(selected_item_id) as BuildingDefinition
	if definition == null or definition.allowed_orientations.is_empty():
		_orientation_label.visible = false
		return
	var orientation := _placement_orientation(tile)
	_orientation_label.text = orientation.substr(0, 1).to_upper()
	_orientation_label.position = Vector2(tile * TILE_SIZE) + Vector2(6.0, -14.0)
	_orientation_label.z_index = int(_ghost.z_index) + int(BuildingRecord.LAYER_Z.get("overhead", 5)) + 2
	_orientation_label.visible = true

## Fallback orientation for a live edge placement: the nearest tile edge
## under the cursor (deterministic; API placements default to north).
func _orientation_for_mouse(tile: Vector2i) -> String:
	var definition := get_definition(selected_item_id) as BuildingDefinition
	if definition == null or definition.allowed_orientations.is_empty():
		return ""
	var world := player.get_global_mouse_position() if player != null else Vector2(tile) * float(TILE_SIZE)
	var center_offset := world - Vector2(tile) * float(TILE_SIZE) - Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	if absf(center_offset.x) >= absf(center_offset.y):
		return "east" if center_offset.x > 0.0 else "west"
	return "south" if center_offset.y > 0.0 else "north"

## Republish the presentation policy to every placed node. Build mode
## focuses the construction story (blueprints above). Normal play is
## location-aware: inside an enclosed room the player's own structure shows
## its interior cutaway (the level they stand on in full colour, every other
## story hidden), while every other structure keeps its exterior shell —
## standing outside a house shows its walls and roof at full colour on all
## stories, not its rooms. Outside any structure everything wears the
## exterior shell: shell parts (roofs, exterior-facing walls, fixtures) at
## full colour on every story, interior parts ghosted. The sandbox keeps the
## plain active-story interior focus: its [ / ] keys are an explicit viewing
## tool, so the location-aware focus and the outdoor reset both stand down
## there.
func _apply_presentation() -> void:
	if _exterior_dirty:
		_rebuild_exterior_classification()
	if build_mode:
		for record in _record_list:
			if record.node != null and is_instance_valid(record.node):
				record.node.set_presentation("build", selected_story, roofs_visible)
		_presentation_sheltered = is_player_sheltered()
		_structure_signature = _player_structure_signature()
		return
	var sheltered := is_player_sheltered()
	var structure: Dictionary = _compute_player_structure() if sheltered else {}
	for record in _record_list:
		if record.node == null or not is_instance_valid(record.node):
			continue
		var shell_part := _shell_records.has(record.placement_key())
		if GameSession.is_building_sandbox():
			record.node.set_presentation("interior", active_story, roofs_visible, shell_part)
		elif not sheltered:
			record.node.set_presentation("exterior", 0, roofs_visible, shell_part)
		elif structure.has(record.placement_key()):
			record.node.set_presentation("interior", active_story, roofs_visible, shell_part)
		else:
			record.node.set_presentation("exterior", 0, roofs_visible, shell_part)
	_presentation_sheltered = sheltered
	_structure_signature = _player_structure_signature()

func _mouse_tile() -> Vector2i:
	var world := player.get_global_mouse_position() if player != null else Vector2.ZERO
	return Vector2i(int(floor(world.x / float(TILE_SIZE))), int(floor(world.y / float(TILE_SIZE))))

func _refresh_owned() -> void:
	_owned = PackedStringArray()
	_visible = PackedStringArray()
	if player == null or player.inventory == null or item_database == null:
		return
	var items := player.inventory.get_all_items()
	for item_id in items:
		if definitions.has(str(item_id)) and int(items[item_id]) > 0 and _is_item_unlocked(str(item_id)):
			_owned.append(str(item_id))
	_owned.sort()
	# A filter naming a group the player no longer owns (last part placed
	# or refunded away) falls back to the full list so the selection and
	# ghost never dead-end.
	if not build_filter.is_empty():
		var group_still_owned := false
		for item_id in _owned:
			if get_build_group(item_id) == build_filter:
				group_still_owned = true
				break
		if not group_still_owned:
			build_filter = ""
	for item_id in _owned:
		if build_filter.is_empty() or get_build_group(item_id) == build_filter:
			_visible.append(item_id)

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
