## Focused Active Build Plan M3 coverage: active-story ownership, vertical
## connector traversal, story-bit collision filtering, the aligned cutaway
## presentation policy, and a full two-floor house build.
## Run: godot --headless --path . --script tests/test_building_stairs.gd
extends SceneTree

var _failures := 0
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_connector_data()
	_test_stairwell_reservation()
	_test_traversal()
	_test_story_collision_bits()
	_test_presentation_policy()
	_test_two_floor_house()
	print("Building stairs failures: %d (%d checks)" % [_failures, _checks])
	quit(_failures)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures += 1
		push_error("[FAIL] %s" % label)

func _make_manager() -> BuildingManager:
	var manager := BuildingManager.new()
	root.add_child(manager)
	return manager

func _make_inventory(quantities: Dictionary) -> InventoryComponent:
	var inventory := InventoryComponent.new()
	var database := ItemDatabase.new()
	database.initialize()
	var stack_sizes: Dictionary = {}
	for item_id in database.items:
		stack_sizes[item_id] = int(database.items[item_id].stack_size)
	inventory.set_stack_sizes(stack_sizes)
	for item_id in quantities:
		inventory.add_item(str(item_id), int(quantities[item_id]))
	return inventory

func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(tile) * 32.0 + Vector2(16.0, 16.0)

# --- Connector data ---

func _test_connector_data() -> void:
	var manager := _make_manager()
	var stairs := manager.get_definition("wooden_stairs") as BuildingDefinition
	_check(stairs != null and stairs.connector_profile != null
			and stairs.connector_profile.upper_story_offset == 1
			and stairs.connector_profile.reserve_stairwell,
			"Wood stairs are a data-defined vertical connector (one story up, stairwell reserved)")
	var stone := manager.get_definition("stone_stairs") as BuildingDefinition
	_check(stone != null and stone.connector_profile != null,
			"Stone stairs are a data-defined vertical connector")
	_check(stairs.effective_placement_layer() == "connector",
			"Stairs derive the connector placement layer")
	manager.queue_free()

# --- Stairwell reservation and atomic placement ---

func _test_stairwell_reservation() -> void:
	var manager := _make_manager()
	var inventory := _make_inventory({
		"wooden_stairs": 4, "wooden_floor": 4, "wooden_foundation": 4,
	})
	manager.place_record("wooden_foundation", Vector2i(5, 5), inventory, 0)
	# A floor above blocks the stairwell: placement must refuse.
	_check(manager.place_record("wooden_floor", Vector2i(5, 5), inventory, 1),
			"Supported floor places above before the stairwell test")
	var floors := inventory.get_item_quantity("wooden_floor")
	_check(not manager.place_record("wooden_stairs", Vector2i(5, 5), inventory, 0),
			"A stair cannot place under an existing floor (no stairwell opening)")
	_check(inventory.get_item_quantity("wooden_floor") == floors,
			"The refused stair consumed nothing")
	# Remove the blocking floor; the stair places and reserves the opening.
	manager.demolish_at(Vector2i(5, 5), 1)
	_check(manager.place_record("wooden_stairs", Vector2i(5, 5), inventory, 0),
			"The stair places once the stairwell is clear")
	var record := manager.get_record_at(Vector2i(5, 5), 0, "connector")
	_check(record != null, "The stair occupies the connector layer")
	var opening_key := BuildingRecord.tile_key(Vector2i(5, 5), 1, "floor")
	_check(manager.get_record_for_key(opening_key) == record,
			"The stair's reservation owns the floor slot above (the stairwell opening)")
	var later_floors := inventory.get_item_quantity("wooden_floor")
	_check(not manager.place_record("wooden_floor", Vector2i(5, 5), inventory, 1),
			"No floor can later block the reserved stairwell opening")
	_check(inventory.get_item_quantity("wooden_floor") == later_floors,
			"The blocked floor placement consumed nothing")
	# Demolishing the stair frees both landings.
	manager.demolish_at(Vector2i(5, 5), 0)
	_check(manager.get_record_for_key(opening_key) == null
			and manager.get_record_at(Vector2i(5, 5), 0, "connector") == null,
			"Demolishing the stair releases the connector slot and the opening above")
	_check(manager.place_record("wooden_floor", Vector2i(5, 5), inventory, 1),
			"The freed opening accepts a floor again")
	manager.queue_free()

# --- Traversal ---

func _test_traversal() -> void:
	var manager := _make_manager()
	var inventory := _make_inventory({"wooden_stairs": 2})
	manager.place_record("wooden_stairs", Vector2i(8, 8), inventory, 0)
	var player := Player.new()
	root.add_child(player)
	manager.player = player
	player.global_position = _tile_center(Vector2i(8, 8)) + Vector2(50, 0) # outside the zone

	# Walk in: the edge-trigger fires exactly once, up.
	player.global_position = _tile_center(Vector2i(8, 8))
	manager._update_connector_traversal()
	_check(manager.active_story == 1 and player.collision_mask == (1 | (BuildingRecord.STORY_COLLISION_BASE << 1)),
			"Entering the stair traverses up one story and retargets collision")
	# Standing still must not bounce back down.
	manager._update_connector_traversal()
	manager._update_connector_traversal()
	_check(manager.active_story == 1, "Standing on the stair never re-triggers")
	# Walk away, walk back: now the edge goes down.
	player.global_position = _tile_center(Vector2i(9, 8))
	manager._update_connector_traversal()
	_check(manager.active_story == 1, "Stepping off the landing keeps the story")
	player.global_position = _tile_center(Vector2i(8, 8))
	manager._update_connector_traversal()
	_check(manager.active_story == 0, "Re-entering from the upper landing traverses down")
	# Velocity is cleared on every story change.
	player.velocity = Vector2(100, 0)
	player.global_position = _tile_center(Vector2i(9, 8))
	manager._update_connector_traversal()
	player.global_position = _tile_center(Vector2i(8, 8))
	manager._update_connector_traversal()
	_check(player.velocity == Vector2.ZERO, "Story transitions clear player velocity")
	# Demolishing the stair while the player is upstairs: no crash, story kept,
	# and the sandbox selector is the escape hatch.
	manager.set_active_story(1)
	manager.demolish_at(Vector2i(8, 8), 0)
	_check(manager.active_story == 1, "Demolishing the stair under the player cannot strand-crash the game")
	manager.set_active_story(0)
	_check(manager.active_story == 0, "The sandbox story selector restores ground floor")
	player.queue_free()
	manager.queue_free()

# --- Story collision bits ---

func _test_story_collision_bits() -> void:
	var manager := _make_manager()
	var inventory := _make_inventory({"wooden_wall": 2, "wooden_foundation": 2})
	manager.place_record("wooden_wall", Vector2i(10, 10), inventory, 0, "north")
	manager.place_record("wooden_foundation", Vector2i(11, 10), inventory, 0)
	manager.place_record("wooden_wall", Vector2i(11, 10), inventory, 1, "north")
	var ground_wall := manager.get_record_at(Vector2i(10, 10), 0, "edge", "north")
	var upper_wall := manager.get_record_at(Vector2i(11, 10), 1, "edge", "north")
	_check(ground_wall.node.collision_layer == BuildingRecord.STORY_COLLISION_BASE,
			"Story-0 collidables own the base building bit")
	_check(upper_wall.node.collision_layer == BuildingRecord.STORY_COLLISION_BASE << 1,
			"Story-1 collidables own their own bit")
	var player := Player.new()
	root.add_child(player)
	_check(player.collision_mask == 1 | BuildingRecord.STORY_COLLISION_BASE,
			"A ground-floor player's mask never includes the story-1 bit")
	player.set_active_story(1)
	_check(player.collision_mask == 1 | (BuildingRecord.STORY_COLLISION_BASE << 1),
			"set_active_story retargets collision filtering to the new story")
	_check(player.z_index == BuildingRecord.STORY_Z_STRIDE / 2 + BuildingRecord.STORY_Z_STRIDE,
			"set_active_story moves the player into the story's render band")
	player.set_active_story(7)
	_check(player.collision_mask == 1 | (BuildingRecord.STORY_COLLISION_BASE << 3),
			"Story values clamp to the four-story limit")
	player.queue_free()
	manager.queue_free()

# --- Presentation policy ---

func _test_presentation_policy() -> void:
	var manager := _make_manager()
	var inventory := _make_inventory({"wooden_floor": 1, "wooden_roof": 1})
	manager.place_record("wooden_floor", Vector2i(12, 12), inventory, 0)
	manager.place_record("wooden_roof", Vector2i(12, 12), inventory, 1)
	var floor_node := manager.get_record_at(Vector2i(12, 12), 0, "floor").node
	var roof_node := manager.get_record_at(Vector2i(12, 12), 1, "overhead").node
	_check(floor_node.position.y == 12.0 * 32.0 and roof_node.position.y == 12.0 * 32.0,
			"Stories render aligned in world X/Y (no STORY_RISE skew)")
	_check(floor_node.z_index == int(BuildingRecord.LAYER_Z["floor"])
			and roof_node.z_index == BuildingRecord.STORY_Z_STRIDE + int(BuildingRecord.LAYER_Z["overhead"]),
			"Layers share one render band per story with deterministic offsets")
	# Normal play, ground focus: upper story hidden.
	floor_node.set_presentation(0, false, true)
	roof_node.set_presentation(0, false, true)
	_check(floor_node.visible and floor_node.modulate.a == 1.0, "Focus story is fully visible")
	_check(not roof_node.visible, "The story above is hidden during normal play")
	# Active upstairs: ground below ghosts, the roof overhead fades (cutaway).
	floor_node.set_presentation(1, false, true)
	roof_node.set_presentation(1, false, true)
	_check(floor_node.visible and absf(floor_node.modulate.a - 0.25) < 0.001,
			"The story below the focus ghosts at the documented opacity")
	_check(roof_node.visible and absf(roof_node.modulate.a - 0.4) < 0.001,
			"The focus story's own roof cuts away so interiors read")
	# Sandbox roof toggle hides the overhead completely.
	roof_node.set_presentation(1, false, false)
	_check(not roof_node.visible, "The sandbox roof toggle hides overheads outright")
	# Build mode: the story above the focus shows as a faint blueprint.
	floor_node.set_presentation(0, true, true)
	roof_node.set_presentation(0, true, true)
	_check(roof_node.visible and absf(roof_node.modulate.a - 0.14) < 0.01,
			"Build mode shows the story above as a faint blueprint")
	# Exterior view (the player is outside): the topmost layer renders in
	# full colour; stories below it ghost. The roof toggle still wins.
	floor_node.set_presentation(1, false, true, true)
	roof_node.set_presentation(1, false, true, true)
	_check(roof_node.visible and roof_node.modulate.a == 1.0,
			"Exterior view: the topmost layer (the roof) renders in full colour")
	_check(floor_node.visible and absf(floor_node.modulate.a - 0.25) < 0.001,
			"Exterior view: stories below the topmost layer ghost out")
	roof_node.set_presentation(1, false, false, true)
	_check(not roof_node.visible, "Exterior view: the roof toggle still hides the topmost layer's roof")
	manager.queue_free()

# --- Two-floor house ---

func _test_two_floor_house() -> void:
	var manager := _make_manager()
	var inventory := _make_inventory({
		"wooden_foundation": 16, "wooden_floor": 16, "wooden_wall": 24,
		"wooden_stairs": 1,
	})
	var tiles: Array[Vector2i] = []
	for x in range(4):
		for y in range(4):
			tiles.append(Vector2i(20 + x, 20 + y))
	var failures := 0
	# Ground story: foundations all around.
	for tile in tiles:
		if not manager.place_record("wooden_foundation", tile, inventory, 0):
			failures += 1
	# Stairs inside the front-left corner, punching the stairwell above.
	if not manager.place_record("wooden_stairs", tiles[0], inventory, 0):
		failures += 1
	# Upper floor everywhere except the stairwell opening.
	var upper_placed := 0
	for tile in tiles:
		if tile == tiles[0]:
			continue
		if manager.place_record("wooden_floor", tile, inventory, 1):
			upper_placed += 1
		else:
			failures += 1
	# Ground walls on the room's outer edges.
	for tile in tiles:
		if tile.y == 20 and not manager.place_record("wooden_wall", tile, inventory, 0, "north"):
			failures += 1
		if tile.y == 23 and not manager.place_record("wooden_wall", tile, inventory, 0, "south"):
			failures += 1
		if tile.x == 20 and not manager.place_record("wooden_wall", tile, inventory, 0, "west"):
			failures += 1
		if tile.x == 23 and not manager.place_record("wooden_wall", tile, inventory, 0, "east"):
			failures += 1
	_check(failures == 0, "A full two-floor 4x4 house builds without a single failure")
	_check(upper_placed == 15, "The upper floor covers every tile except the stairwell opening")
	_check(manager.get_building_count() == 16 + 1 + 15 + 16,
			"Every placed record is accounted for in the occupancy index")
	manager.queue_free()
