## Focused Active Build Plan M2 coverage: the layered occupancy grid,
## canonical edge keys, transactional placement, edge replacement, the
## conservative support validator, and the v8 building-record save format.
## Run: godot --headless --path . --script tests/test_building_placement.gd
extends SceneTree

var _failures := 0
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_canonical_keys()
	_test_layer_coexistence()
	_test_edge_identity_and_replacement()
	_test_support_validator()
	_test_transactional_failure()
	_test_demolition_refund()
	_test_collision_rules()
	_test_save_round_trip()
	_test_container_persistence_and_safe_demolition()
	_test_m10_mixed_house_round_trip()
	_test_orientation_rotation()
	print("Building placement failures: %d (%d checks)" % [_failures, _checks])
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
	root.add_child(manager) # _ready discovers the shipped definitions
	return manager

## GDScript lambdas capture by value, so signal counters use a box.
func _make_placed_counter(manager: BuildingManager) -> Array:
	var counter := [0]
	manager.building_placed.connect(func(_id, _coords): counter[0] += 1)
	return counter

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

func _count(inventory: InventoryComponent, item_id: String) -> int:
	return inventory.get_item_quantity(item_id)

# --- Canonical keys ---

func _test_canonical_keys() -> void:
	_check(BuildingRecord.canonical_edge_key(Vector2i(5, 5), 0, "east") == "6:5:0:edge:w",
			"East edge of a tile canonicalizes to the west edge of its neighbour")
	_check(BuildingRecord.canonical_edge_key(Vector2i(5, 5), 0, "south") == "5:6:0:edge:n",
			"South edge of a tile canonicalizes to the north edge of its neighbour")
	_check(BuildingRecord.canonical_edge_key(Vector2i(5, 5), 2, "east")
			== BuildingRecord.canonical_edge_key(Vector2i(6, 5), 2, "west"),
			"Both spellings of one physical edge produce one canonical key")
	var record := BuildingRecord.new()
	record.deserialize({"item_id": "wooden_wall", "x": 5, "y": 5, "story": 1, "layer": "edge",
			"orientation": "north", "health": 90}, null)
	_check(record.placement_key() == "5:5:1:edge:north",
			"Edge record placement key includes the normalized edge")

# --- Layer coexistence ---

func _test_layer_coexistence() -> void:
	var manager := _make_manager()
	var inventory := _make_inventory({
		"wooden_floor": 4, "campfire": 2, "wooden_roof": 2, "wooden_foundation": 2,
	})
	manager.refund_inventory = inventory
	var placed := _make_placed_counter(manager)
	_check(manager.place_record("wooden_floor", Vector2i(5, 5), inventory, 0),
			"Floor places on the floor layer")
	_check(manager.place_record("campfire", Vector2i(5, 5), inventory, 0),
			"Object places on the same tile and story as the floor")
	_check(manager.place_record("wooden_roof", Vector2i(5, 5), inventory, 1),
			"Overhead roof places above the floor with support below")
	_check(manager.get_record_at(Vector2i(5, 5), 0, "floor") != null
			and manager.get_record_at(Vector2i(5, 5), 0, "object") != null
			and manager.get_record_at(Vector2i(5, 5), 1, "overhead") != null,
			"All three layers are independently queryable at one tile")
	_check(manager.get_building_at(Vector2i(5, 5), 0).building_id == "campfire",
			"The ambiguous tile query resolves by the deterministic layer priority")
	_check(placed[0] == 3, "Every successful placement emitted building_placed exactly once")
	var floor_count := _count(inventory, "wooden_floor")
	_check(not manager.place_record("wooden_floor", Vector2i(5, 5), inventory, 0),
			"A second floor on the identical slot is rejected")
	_check(_count(inventory, "wooden_floor") == floor_count
			and manager.get_building_count() == 3,
			"The rejected duplicate changed neither inventory nor occupancy")
	manager.queue_free()

# --- Edge identity and replacement ---

func _test_edge_identity_and_replacement() -> void:
	var manager := _make_manager()
	var inventory := _make_inventory({
		"wooden_wall": 6, "wooden_door": 2, "wooden_window": 2,
	})
	manager.refund_inventory = inventory
	_check(manager.place_record("wooden_wall", Vector2i(5, 5), inventory, 0, "east"),
			"Wall places on the east edge via its orientation")
	var edge_key := BuildingRecord.canonical_edge_key(Vector2i(5, 5), 0, "east")
	_check(manager.get_record_for_key(edge_key).item_id == "wooden_wall",
			"The placed wall occupies the canonical edge key")
	var walls := _count(inventory, "wooden_wall")
	_check(not manager.place_record("wooden_wall", Vector2i(6, 5), inventory, 0, "west"),
			"Placing the same physical edge from the neighbour tile is rejected")
	_check(_count(inventory, "wooden_wall") == walls,
			"The doubled-edge rejection consumed nothing")
	_check(manager.place_record("wooden_wall", Vector2i(5, 5), inventory, 0, "north")
			and manager.place_record("wooden_wall", Vector2i(5, 5), inventory, 0, "south"),
			"The other edges of the same tile stay independently placeable")
	# Replacement: door (edge_fixture) takes over the wall's edge and refunds it.
	var walls_before := _count(inventory, "wooden_wall")
	var doors := _count(inventory, "wooden_door")
	_check(manager.place_record("wooden_door", Vector2i(6, 5), inventory, 0, "west"),
			"A door replaces the plain wall on the same edge")
	_check(_count(inventory, "wooden_door") == doors - 1
			and _count(inventory, "wooden_wall") == walls_before + 1,
			"Replacement consumed the door and refunded the wall exactly")
	_check(manager.get_record_for_key(edge_key).item_id == "wooden_door",
			"The canonical edge slot now belongs to the door")
	var windows := _count(inventory, "wooden_window")
	_check(not manager.place_record("wooden_window", Vector2i(6, 5), inventory, 0, "west"),
			"A window cannot replace a door (both are fixtures)")
	_check(_count(inventory, "wooden_window") == windows,
			"The refused fixture replacement changed nothing")
	manager.queue_free()

# --- Support validator ---

func _test_support_validator() -> void:
	var manager := _make_manager()
	var inventory := _make_inventory({
		"wooden_foundation": 8, "wooden_floor": 8, "wooden_roof": 2, "campfire": 1,
	})
	_check(not manager.place_record("wooden_floor", Vector2i(9, 9), inventory, 1),
			"An unsupported upper floor is rejected")
	_check(manager.place_record("wooden_foundation", Vector2i(9, 9), inventory, 0)
			and manager.place_record("wooden_floor", Vector2i(9, 9), inventory, 1),
			"A foundation below satisfies the direct-support rule")
	# A supported 2x2 upper room.
	for tile in [Vector2i(9, 10), Vector2i(10, 9), Vector2i(10, 10)]:
		_check(manager.place_record("wooden_foundation", tile, inventory, 0),
				"Ground foundation places at %s" % str(tile))
	for tile in [Vector2i(9, 10), Vector2i(10, 9), Vector2i(10, 10)]:
		_check(manager.place_record("wooden_floor", tile, inventory, 1),
				"Supported upper floor places at %s" % str(tile))
	# A campfire (no structure tags) cannot support an upper floor.
	_check(manager.place_record("campfire", Vector2i(11, 11), inventory, 0),
			"Object places for the support-veto probe")
	_check(not manager.place_record("wooden_floor", Vector2i(11, 11), inventory, 1),
			"An object without structure tags cannot support an upper floor")
	# Roof: overhead layer never collides.
	_check(manager.place_record("wooden_roof", Vector2i(9, 9), inventory, 2),
			"A roof places over the supported upper room")
	var roof := manager.get_record_at(Vector2i(9, 9), 2, "overhead")
	_check(roof != null and roof.node != null and roof.node.collision_layer == 0,
			"Roof collision never blocks the player")
	manager.queue_free()

# --- Transactional failures ---

func _test_transactional_failure() -> void:
	var manager := _make_manager()
	var inventory := _make_inventory({"wooden_floor": 3})
	var failures: Array[String] = []
	manager.placement_failed.connect(func(reason): failures.append(str(reason)))
	_check(not manager.place_record("wooden_floor", Vector2i(20, 20), inventory, 1),
			"Unsupported placement returns false")
	_check(failures.size() == 1 and not str(failures[0]).is_empty(),
			"The exact failure reason is published on placement_failed")
	_check(_count(inventory, "wooden_floor") == 3 and manager.get_building_count() == 0,
			"A failed placement changed neither inventory nor occupancy")
	var unknown := _make_inventory({"nonexistent_part": 1})
	_check(not manager.place_record("nonexistent_part", Vector2i(21, 21), unknown, 0),
			"Unknown items cannot place")
	# Non-orientable parts ignore orientations entirely.
	var ground_inv := _make_inventory({"wooden_foundation": 2})
	_check(manager.place_record("wooden_foundation", Vector2i(30, 30), ground_inv, 0, "east"),
			"A foundation places even when an orientation is requested")
	var foundation := manager.get_record_at(Vector2i(30, 30), 0, "ground")
	_check(foundation != null and foundation.orientation == "",
			"Non-orientable definitions ignore a requested orientation")
	_check(not manager.place_record("wooden_foundation", Vector2i(30, 30), ground_inv, 0, "west"),
			"The orientation-less slot still rejects duplicates")
	manager.queue_free()

# --- Demolition refund ---

func _test_demolition_refund() -> void:
	var manager := _make_manager()
	var inventory := _make_inventory({"campfire": 1})
	manager.refund_inventory = inventory
	manager.place_record("campfire", Vector2i(40, 40), inventory, 0)
	_check(manager.demolish_at(Vector2i(40, 40), 0),
			"Demolition removes the placed record")
	_check(_count(inventory, "campfire") == 1 and manager.get_building_count() == 0,
			"Demolition refunds exactly one item and clears occupancy")
	_check(not manager.demolish_at(Vector2i(40, 40), 0),
			"Demolishing an empty slot fails")

# --- Collision rules ---

func _test_collision_rules() -> void:
	var manager := _make_manager()
	var inventory := _make_inventory({"wooden_wall": 2, "wooden_door": 1, "wooden_floor": 1})
	manager.place_record("wooden_wall", Vector2i(50, 50), inventory, 0, "north")
	var wall := manager.get_record_at(Vector2i(50, 50), 0, "edge", "north")
	_check(wall != null and wall.node != null and wall.node.collision_layer == BuildingRecord.STORY_COLLISION_BASE,
			"An edge wall on the active story owns its story collision bit")
	var shape: CollisionShape2D = null
	for child in wall.node.get_children():
		if child is CollisionShape2D:
			shape = child
	_check(shape != null and absf(shape.shape.size.y - 8.0) < 0.01,
			"The edge wall's collision is a thin strip along the edge, not the tile")
	var name_label: Label = null
	var health_bar: ProgressBar = null
	for child in wall.node.get_children():
		if child is Label:
			name_label = child
		elif child is ProgressBar:
			health_bar = child
	_check(name_label != null and not name_label.visible and health_bar != null and not health_bar.visible,
			"Pristine buildings keep name and health UI out of the room view")
	wall.node.take_damage(1)
	_check(health_bar.visible, "Damaged buildings reveal health feedback")
	manager.place_record("wooden_door", Vector2i(50, 51), inventory, 0, "north")
	var door := manager.get_record_at(Vector2i(50, 51), 0, "edge", "north")
	_check(door != null and door.node != null and door.node.collision_layer == 0,
			"A door is the walkable opening (no collision)")
	manager.queue_free()

# --- Save round-trip ---

func _test_save_round_trip() -> void:
	var manager := _make_manager()
	var inventory := _make_inventory({
		"wooden_foundation": 2, "wooden_wall": 4, "campfire": 1,
	})
	manager.place_record("wooden_foundation", Vector2i(60, 60), inventory, 0)
	manager.place_record("wooden_wall", Vector2i(60, 60), inventory, 0, "west")
	manager.place_record("campfire", Vector2i(61, 60), inventory, 0)
	var fire := manager.get_record_at(Vector2i(61, 60), 0, "object")
	fire.capability_state = {"enabled": true, "container": {"slots": [null, {"item_id": "wood", "quantity": 5}]}}
	var payload: Array = manager.serialize()
	_check(payload.size() == 3, "Serialization emits one v8 record per placement")
	var wall_entry: Dictionary = {}
	for entry in payload:
		if str(entry.get("item_id")) == "wooden_wall":
			wall_entry = entry
	_check(str(wall_entry.get("layer")) == "edge" and str(wall_entry.get("orientation")) == "west"
			and wall_entry.has("state") == false,
			"Edge records save layer and orientation; empty state is omitted")
	# Reload into a fresh manager.
	var manager2 := _make_manager()
	manager2.deserialize(payload)
	_check(manager2.get_building_count() == 3,
			"v8 records round-trip into a fresh manager")
	var restored_fire := manager2.get_record_at(Vector2i(61, 60), 0, "object")
	_check(restored_fire != null and restored_fire.capability_state.get("enabled") == true
			and not restored_fire.capability_state.is_empty(),
			"Capability state round-trips through the save payload")
	var restored_wall := manager2.get_record_at(Vector2i(60, 60), 0, "edge", "west")
	_check(restored_wall != null,
			"The canonical edge slot is re-reserved identically after load")
	manager2.queue_free()
	# v7 migration: flat entries without layer/orientation/state.
	var manager3 := _make_manager()
	manager3.deserialize([
		{"item_id": "wooden_wall", "x": 70, "y": 70, "story": 0, "health": 100},
		{"item_id": "campfire", "x": 71, "y": 70, "story": 0, "health": 50},
	])
	_check(manager3.get_building_count() == 2, "v7 flat building entries still load")
	var migrated_wall := manager3.get_record_at(Vector2i(70, 70), 0, "edge", "north")
	_check(migrated_wall != null and migrated_wall.layer == "edge"
			and migrated_wall.capability_state.is_empty(),
			"v7 walls migrate to the edge layer with empty state (never invented)")
	var migrated_fire := manager3.get_record_at(Vector2i(71, 70), 0, "object")
	_check(migrated_fire != null and migrated_fire.layer == "object",
			"v7 objects migrate to the object layer")
	manager3.queue_free()
	manager.queue_free()

# --- M5 container state ---

func _test_container_persistence_and_safe_demolition() -> void:
	var manager := _make_manager()
	var inventory := _make_inventory({"chest": 1, "wood": 12})
	manager.refund_inventory = inventory
	_check(manager.place_record("chest", Vector2i(80, 80), inventory, 0),
			"A data-authored chest places through the normal record path")
	var record := manager.get_record_at(Vector2i(80, 80), 0, "object")
	var storage := record.get_container_storage()
	storage.stack_sizes = inventory.get_stack_sizes()
	storage.add_item("wood", 12)
	var payload := manager.serialize()
	var entry: Dictionary = payload[0]
	_check(entry.get("state", {}).get("container", {}).get("slots", []).size() == 27
			and not entry.get("state", {}).has("open"),
			"Non-empty indexed container state saves in v8 while UI-open state stays transient")

	var restored_manager := _make_manager()
	restored_manager.deserialize(payload)
	var restored := restored_manager.get_record_at(Vector2i(80, 80), 0, "object")
	_check(restored != null and restored.get_container_storage().quantity_of("wood") == 12
			and restored.get_container_storage().slot_count() == 27,
			"Chest contents and authored capacity survive a save/reload round trip")

	var blocked_reasons: Array[String] = []
	manager.placement_failed.connect(func(reason: String): blocked_reasons.append(reason))
	_check(not manager.demolish_at(Vector2i(80, 80), 0) and manager.get_building_count() == 1
			and not blocked_reasons.is_empty(),
			"Any non-empty authored container refuses demolition with a clear message")
	storage.remove_item("wood", 12)
	_check(manager.demolish_at(Vector2i(80, 80), 0) and _count(inventory, "chest") == 1,
			"An empty container demolishes normally and refunds exactly one item")

	var malformed_manager := _make_manager()
	malformed_manager.deserialize([{
		"item_id": "chest", "x": 81, "y": 80, "story": 0, "layer": "object",
		"state": {"container": {"slots": ["not-a-27-slot-container"]}}
	}])
	var malformed := malformed_manager.get_record_at(Vector2i(81, 80), 0, "object")
	_check(malformed != null and malformed.get_container_storage().occupied_count() == 0
			and not malformed.capability_state.has("container"),
			"Malformed saved container fields are rejected safely without reshaping storage")
	restored_manager.queue_free()
	malformed_manager.queue_free()
	manager.queue_free()

## --- M10 release gate: one mixed, stateful multi-story house survives a save ---

func _test_m10_mixed_house_round_trip() -> void:
	var manager := _make_manager()
	var inventory := _make_inventory({
		"wooden_foundation": 3, "stone_foundation": 1, "stone_floor": 1,
		"wooden_wall": 1, "stone_wall": 1, "wooden_stairs_down": 1,
		"chest": 1, "campfire": 1, "workbench": 1, "wood": 24,
		"plank": 4, "wooden_hammer": 1,
	})
	manager.refund_inventory = inventory
	# Story 0 supports a mixed-material upper floor. The down stair is placed
	# on story 1 and reserves its landing on story 0, exercising the negative
	# connector offset through serialization as well as normal placement.
	var base := Vector2i(90, 90)
	_check(manager.place_record("wooden_foundation", base, inventory, 0)
			and manager.place_record("stone_foundation", base + Vector2i(1, 0), inventory, 0)
			and manager.place_record("wooden_foundation", base + Vector2i(2, 0), inventory, 0),
			"M10 mixed house foundations place on the ground story")
	_check(manager.place_record("wooden_stairs_down", base, inventory, 1, "east")
			and manager.place_record("stone_floor", base + Vector2i(1, 0), inventory, 1)
			and manager.place_record("wooden_wall", base, inventory, 1, "east")
			and manager.place_record("stone_wall", base + Vector2i(1, 0), inventory, 1, "north"),
			"M10 mixed upper story places a descending connector, floor, and oriented walls")
	_check(manager.place_record("chest", base + Vector2i(1, 0), inventory, 1)
			and manager.place_record("campfire", base + Vector2i(2, 0), inventory, 0)
			and manager.place_record("workbench", base + Vector2i(3, 0), inventory, 0),
			"M10 mixed house places furnished container, fuelled station, and workbench")

	var wooden_wall := manager.get_record_at(base, 1, "edge", "east")
	wooden_wall.health = 37
	var chest := manager.get_record_at(base + Vector2i(1, 0), 1, "object")
	var chest_storage := chest.get_container_storage()
	chest_storage.stack_sizes = inventory.get_stack_sizes()
	chest_storage.add_item("wood", 12)
	var campfire := manager.get_record_at(base + Vector2i(2, 0), 0, "object")
	var fuel_storage := campfire.get_fuel_storage()
	fuel_storage.stack_sizes = inventory.get_stack_sizes()
	fuel_storage.add_item("wood", 3)
	campfire.capability_state["enabled"] = true
	campfire.capability_state["fuel_seconds_remaining"] = 41.5
	var workbench := manager.get_record_at(base + Vector2i(3, 0), 0, "object")
	var inputs := workbench.get_station_input_storage()
	var outputs := workbench.get_station_output_storage()
	inputs.stack_sizes = inventory.get_stack_sizes()
	outputs.stack_sizes = inventory.get_stack_sizes()
	inputs.add_item("plank", 4)
	outputs.add_item("wooden_hammer", 1)

	var payload := manager.serialize()
	var restored_manager := _make_manager()
	restored_manager.deserialize(payload)
	var restored_stairs := restored_manager.get_record_at(base, 1, "connector")
	var restored_wall := restored_manager.get_record_at(base, 1, "edge", "east")
	var restored_chest := restored_manager.get_record_at(base + Vector2i(1, 0), 1, "object")
	var restored_fire := restored_manager.get_record_at(base + Vector2i(2, 0), 0, "object")
	var restored_bench := restored_manager.get_record_at(base + Vector2i(3, 0), 0, "object")
	_check(restored_manager.get_building_count() == manager.get_building_count()
			and restored_wall != null and restored_wall.health == 37
			and restored_wall.orientation == "east",
			"M10 round-trip preserves every mixed-house record plus wall health and orientation")
	_check(restored_stairs != null and restored_stairs.definition.connector_profile.upper_story_offset == -1
			and restored_manager.get_record_for_key(BuildingRecord.tile_key(base, 0, "floor")) == restored_stairs,
			"M10 round-trip preserves the descending stair's paired landing reservation")
	_check(restored_chest != null and restored_chest.get_container_storage().quantity_of("wood") == 12,
			"M10 round-trip preserves furnished-container contents")
	_check(restored_fire != null and bool(restored_fire.capability_state.get("enabled", false))
			and is_equal_approx(float(restored_fire.capability_state.get("fuel_seconds_remaining", 0.0)), 41.5)
			and restored_fire.get_fuel_storage().quantity_of("wood") == 3,
			"M10 round-trip preserves active fuel state and indexed fuel")
	_check(restored_bench != null and restored_bench.get_station_input_storage().quantity_of("plank") == 4
			and restored_bench.get_station_output_storage().quantity_of("wooden_hammer") == 1,
			"M10 round-trip preserves visible station inputs and outputs")
	restored_manager.queue_free()
	manager.queue_free()

# --- Orientation rotation (M9 box 5) ---
#
# The manager here has no player, so the live mouse-edge fallback
# resolves deterministically to "west" (zero cursor offset). The
# key-driven end-to-end flow lives in the sandbox suite.

func _test_orientation_rotation() -> void:
	var manager := _make_manager()
	var inventory := _make_inventory({"wooden_wall": 4})
	manager.refund_inventory = inventory
	# A non-orientable part never takes a pending orientation.
	manager.set_build_mode(true)
	manager.selected_item_id = "wooden_floor"
	manager.rotate_build_orientation(1)
	manager.rotate_build_orientation(-1)
	_check(manager.pending_orientation == "", "Rotating a non-orientable part is a no-op")
	# The first R press seeds from the live mouse-edge default (deterministically
	# "west" with no player) and advances clockwise; further presses keep
	# cycling the definition's allowed list in both directions.
	manager.selected_item_id = "wooden_wall"
	manager.rotate_build_orientation(1)
	_check(manager.pending_orientation == "north", "First R press seeds from the mouse-edge default and advances clockwise")
	manager.rotate_build_orientation(1)
	_check(manager.pending_orientation == "east", "R keeps advancing through the allowed orientations")
	manager.rotate_build_orientation(3)
	_check(manager.pending_orientation == "north", "Rotation wraps around the allowed orientation list")
	manager.rotate_build_orientation(-1)
	_check(manager.pending_orientation == "west", "Q walks the pending orientation backwards")
	# Selection changes and build-mode re-entry reset the rotation context.
	manager.selected_item_id = "wooden_wall"
	manager.pending_orientation = "east"
	manager.cycle_selection(1)
	_check(manager.pending_orientation == "", "Changing the selection resets the rotation context")
	manager.selected_item_id = "wooden_wall"
	manager.pending_orientation = "east"
	manager.set_build_mode(false)
	manager.set_build_mode(true)
	manager.selected_item_id = "wooden_wall"
	_check(manager.pending_orientation == "", "Re-entering build mode resets the rotation context")
	# Live placement and the ghost consume the pending orientation instead of
	# the mouse edge; with no pending choice the mouse-edge default applies.
	manager.pending_orientation = "east"
	_check(manager._placement_orientation(Vector2i(10, 10)) == "east", "Live placement uses the pending orientation over the mouse edge")
	manager.pending_orientation = "north"
	_check(manager._placement_orientation(Vector2i(10, 10)) == "north", "A changed pending orientation takes effect immediately")
	manager.pending_orientation = ""
	_check(manager._placement_orientation(Vector2i(10, 10)) == "west", "With no pending orientation the mouse-edge default applies")
	manager.selected_item_id = "wooden_floor"
	manager.pending_orientation = "east"
	_check(manager._placement_orientation(Vector2i(10, 10)) == "",
			"A pending orientation a non-orientable part cannot use is ignored, not forced")
	# The ghost's occupancy check follows the pending orientation: the
	# occupied edge fails while a free edge of the same tile still passes.
	manager.selected_item_id = "wooden_wall"
	manager.pending_orientation = "east"
	_check(manager.place_record("wooden_wall", Vector2i(10, 10), inventory, 0, "east"), "An east-oriented wall places on the east edge")
	_check(not manager.can_place(Vector2i(10, 10)), "The pending orientation makes the occupied edge fail the ghost check")
	# The east edge of (10,10) IS the west edge of (11,10) (canonical edge
	# keys); the same physical edge must fail placement under either spelling.
	_check(not manager.place_record("wooden_wall", Vector2i(11, 10), inventory, 0, "west"),
			"The same edge spelled from the other tile fails placement")
	manager.pending_orientation = "west"
	_check(manager.can_place(Vector2i(10, 10)), "The same tile is still buildable on its free west edge")
	# Saved orientations are never reinterpreted: a later rotation choice
	# placed elsewhere leaves the first record's stored orientation intact.
	_check(manager.place_record("wooden_wall", Vector2i(9, 10), inventory, 0, "west"), "A second wall places west-oriented on a neighbouring tile")
	var first := manager.get_record_at(Vector2i(10, 10), 0, "edge", "east")
	var second := manager.get_record_at(Vector2i(9, 10), 0, "edge", "west")
	_check(first != null and first.orientation == "east" and second != null and second.orientation == "west",
			"Saved records keep the orientation they were placed with")
	manager.queue_free()
