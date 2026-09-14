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
