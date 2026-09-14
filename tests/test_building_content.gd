## Focused Active Build Plan M1 coverage: building content registry, item
## tags, InventoryStorage, InventoryTransfer, and the player-inventory
## migration behind InventoryComponent.
## Run: godot --headless --path . --script tests/test_building_content.gd
extends SceneTree

const BUILDINGS := ["wooden_foundation", "wooden_floor", "wooden_wall", "wooden_window",
	"wooden_door", "wooden_roof", "wooden_stairs", "wooden_ramp", "wooden_pillar",
	"stone_foundation", "stone_floor", "stone_wall", "stone_window", "stone_door",
	"stone_roof", "stone_stairs", "stone_ramp", "stone_pillar",
	"torch", "campfire", "furnace", "workbench", "anvil", "chest", "bed", "farm_soil", "fence",
	"fence_gate", "wooden_railing", "wooden_porch", "wooden_deck", "wooden_path", "planter_box",
	"wooden_table", "yard_lantern", "stone_gate", "stone_railing", "stone_patio", "stone_path",
	"stone_planter"]

var _failures := 0
var _checks := 0

func _initialize() -> void:
	_test_registry_discovery()
	_test_pinned_definition_values()
	_test_capability_profiles()
	_test_placement_metadata()
	_test_registry_validation_failures()
	_test_item_tags()
	_test_inventory_storage()
	_test_inventory_transfer()
	_test_inventory_component()
	_test_building_identity()
	print("Building content failures: %d (%d checks)" % [_failures, _checks])
	quit(_failures)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures += 1
		push_error("[FAIL] %s" % label)

# --- Registry ---

func _test_registry_discovery() -> void:
	var registry := BuildingContentRegistry.new()
	registry.discover()
	_check(not registry.has_validation_errors(),
			"Shipped building content validates with zero errors" + _first_error(registry))
	_check(registry.definitions.size() == 40,
			"Registry discovers all 40 building definitions (got %d)" % registry.definitions.size())
	var ids := registry.definitions.keys()
	ids.sort()
	var expected := BUILDINGS.duplicate()
	expected.sort()
	_check(str(ids) == str(expected), "Discovered ids exactly match the shipped content set")
	# Deterministic repeated discovery.
	var registry2 := BuildingContentRegistry.new()
	registry2.discover()
	_check(str(registry2.definitions.keys()) == str(registry.definitions.keys()),
			"Repeated discovery yields the identical sorted definition set")

func _test_pinned_definition_values() -> void:
	var registry := BuildingContentRegistry.new()
	registry.discover()
	var wall := registry.get_definition("wooden_wall")
	_check(wall != null and wall.part_type == "wall" and wall.tier == "wood"
			and wall.technology_id == "wood_building" and wall.max_health == 100
			and wall.blocks_movement and wall.requires_lower_support,
			"wooden_wall keeps its exact prior gameplay values")
	_check(wall != null and wall.build_cost.size() == 1
			and str(wall.build_cost[0]["item_id"]) == "plank"
			and int(wall.build_cost[0]["quantity"]) == 3,
			"wooden_wall keeps its plank build cost")
	var campfire := registry.get_definition("campfire")
	_check(campfire != null and campfire.part_type == "utility" and campfire.tier == "primitive"
			and campfire.technology_id == "" and campfire.max_health == 50
			and not campfire.blocks_movement and not campfire.requires_lower_support,
			"campfire keeps its exact prior gameplay values")
	var fence := registry.get_definition("fence")
	_check(fence != null and fence.display_name == "Fence" and fence.blocks_movement
			and fence.effective_placement_layer() == "edge",
			"fence is an edge-boundary with its stable name and collision")

func _test_capability_profiles() -> void:
	var registry := BuildingContentRegistry.new()
	registry.discover()
	var chest := registry.get_definition("chest")
	_check(chest != null and chest.container_profile != null
			and chest.interaction_profile != null
			and chest.interaction_profile.ui_kind == "container",
			"chest is data-defined with container + interaction profiles")
	_check(chest != null and chest.container_profile.slot_count == 27,
			"chest container profile carries the agreed 27-slot grid")
	_check(chest != null and chest.appearance_profile != null
			and chest.appearance_profile.interaction_open_state == "open"
			and chest.appearance_profile.interaction_closed_state == "closed",
			"chest open/close presentation is authored through an AppearanceProfile")
	var campfire := registry.get_definition("campfire")
	_check(campfire != null and campfire.station_profile != null
			and campfire.fuel_profile != null and campfire.light_profile != null,
			"campfire is data-defined with station + fuel + light profiles")
	_check(campfire != null and campfire.station_profile.requires_power,
			"campfire station requires power (fuel) by data")
	var torch := registry.get_definition("torch")
	_check(torch != null and torch.fuel_profile != null and torch.light_profile != null
			and torch.container_profile == null,
			"torch has fuel + light and no container, by data")
	var bench := registry.get_definition("workbench")
	_check(bench != null and bench.station_profile.recipe_group == "workbench"
			and not bench.station_profile.requires_power,
			"workbench station serves its recipe group without power")
	var fence := registry.get_definition("fence")
	_check(fence != null and not fence.has_capabilities(),
			"decorative parts carry no capability profiles")
	var lantern := registry.get_definition("yard_lantern")
	_check(lantern != null and lantern.fuel_profile != null and lantern.light_profile != null,
			"yard lantern reuses generic fuel and local-light capabilities through data")

func _test_placement_metadata() -> void:
	var registry := BuildingContentRegistry.new()
	registry.discover()
	var layers := {"wooden_wall": "edge", "wooden_door": "edge", "wooden_roof": "overhead",
			"wooden_stairs": "connector", "wooden_foundation": "ground",
			"wooden_floor": "floor", "chest": "object"}
	var layers_ok := true
	for id in layers:
		var definition := registry.get_definition(id)
		if definition == null or definition.effective_placement_layer() != layers[id]:
			layers_ok = false
	_check(layers_ok, "effective_placement_layer derives the six-layer model from part_type")
	var floor := registry.get_definition("wooden_floor")
	_check(floor != null and floor.support_tags.has("structure"),
			"structural parts provide the 'structure' support tag")
	var roof := registry.get_definition("wooden_roof")
	_check(roof != null and roof.support_tags.has("cover"),
			"roofs provide the 'cover' support tag")
	var gate := registry.get_definition("fence_gate")
	_check(gate != null and gate.effective_placement_layer() == "edge"
			and gate.occupancy_replacement == "edge_fixture",
			"fence gates use the generic edge-fixture replacement contract")
	var stone_gate := registry.get_definition("stone_gate")
	_check(stone_gate != null and stone_gate.tier == "stone"
			and stone_gate.effective_placement_layer() == "edge",
			"stone boundary additions preserve the generic edge-layer topology")

func _test_registry_validation_failures() -> void:
	var registry := BuildingContentRegistry.new()
	registry.discover("res://tests/fixtures/building_validation/buildings",
			"res://tests/fixtures/building_validation/interactables")
	var joined := "\n".join(registry.validation_errors)
	_check(registry.has_validation_errors(), "Invalid fixture content is rejected")
	for expected in ["missing 'id'", "footprint", "build_cost[0]", "slot_count",
			"duplicate id", "recipe_group"]:
		_check(joined.contains(expected),
				"Validation reports the '%s' problem with an asset path" % expected)
	_check(not registry.definitions.has("bad_footprint") and not registry.definitions.has("bad_profile"),
			"Errored definitions are excluded from placement")
	_check(registry.definitions.has("duplicate") and registry.errored_definitions.has("bad_footprint"),
			"Clean definitions still load alongside errored ones")

# --- Item tags ---

func _test_item_tags() -> void:
	var database := ItemDatabase.new()
	database.initialize()
	for fuel_id in ["wood", "coal", "charcoal"]:
		_check(database.get_item(fuel_id) != null and database.get_item(fuel_id).has_tag("fuel"),
				"%s carries the data-defined 'fuel' tag" % fuel_id)
	_check(not database.get_item("stone").has_tag("fuel"),
			"Non-burnables carry no fuel tag")
	var tagged := database.get_items_with_tag("fuel")
	_check(tagged.size() == 3 and tagged[0] == "charcoal" and tagged[1] == "coal"
			and tagged[2] == "wood",
			"get_items_with_tag is a sorted data query")
	for building_id in ["fence_gate", "wooden_railing", "wooden_porch", "wooden_deck",
			"wooden_path", "planter_box", "wooden_table", "yard_lantern"]:
		_check(database.get_item(building_id) != null and database.get_recipe(building_id) != null
				and database.get_recipe(building_id).technology_id == "wood_building",
				"%s has a placeable item, reachable recipe, and wood research gate" % building_id)
	for building_id in ["stone_gate", "stone_railing", "stone_patio", "stone_path", "stone_planter"]:
		_check(database.get_item(building_id) != null and database.get_recipe(building_id) != null
				and database.get_recipe(building_id).technology_id == "stone_building",
				"%s has a placeable item, reachable recipe, and stone research gate" % building_id)

# --- InventoryStorage ---

func _test_inventory_storage() -> void:
	var storage := InventoryStorage.new(4, 0.0)
	_check(storage.add_item("wood", 10) == 0 and storage.quantity_at(0) == 10,
			"Storage accepts into the first free slot")
	_check(storage.add_item("wood", 5) == 0 and storage.quantity_at(0) == 15,
			"Storage stacks into the same slot")
	_check(storage.add_item("wood", 70) == 0 and storage.quantity_at(0) == 64
			and storage.quantity_at(1) == 21,
			"Multi-slot storage opens a second slot when a stack fills")
	_check(storage.remove_from_slot(0, 4) == 4 and storage.quantity_at(0) == 60,
			"Slot removal returns the removed quantity")
	var capped := InventoryStorage.new(1, 0.0)
	capped.stack_sizes["wood"] = 16
	_check(capped.add_item("wood", 20) == 4 and capped.quantity_of("wood") == 16,
			"Stack-size caps split the request and return the remainder")
	var heavy := InventoryStorage.new(4, 10.0)
	_check(heavy.add_item("wood", 12) == 2 and is_equal_approx(heavy.total_weight(), 10.0),
			"Weight limits cap acceptance without rollback side effects")
	var unique := InventoryStorage.new(4, 0.0)
	unique.merge_to_single_slot_per_item = true
	unique.stack_sizes["wood"] = 10
	unique.add_item("wood", 3)
	unique.add_item("wood", 4)
	_check(unique.occupied_count() == 1 and unique.quantity_at(0) == 7,
			"Unique mode keeps one display slot per item type")
	_check(unique.add_item("wood", 8) == 5 and unique.quantity_at(0) == 10,
			"Unique mode reports the remainder once the display stack is full")
	var filtered := InventoryStorage.new(2, 0.0)
	filtered.set_slot_filter(0, func(item_id: String): return item_id == "stone")
	_check(filtered.add_item("wood", 5) == 0 and filtered.item_id_at(0) == "",
			"Filtered slot is skipped for placement")
	_check(filtered.add_item("stone", 2) == 0 and filtered.quantity_at(0) == 2,
			"Filtered slot accepts matching items")
	var one_slot := InventoryStorage.new(1, 0.0)
	one_slot.set_slot_filter(0, func(item_id: String): return item_id == "stone")
	_check(one_slot.add_item("wood", 5) == 5 and one_slot.quantity_of("wood") == 0,
			"Filter-refused items leave the source quantity untouched")
	var source := InventoryStorage.new(2, 0.0)
	source.add_item("wood", 9)
	var serialized := source.serialize()
	var restored := InventoryStorage.new(0, 0.0)
	restored.deserialize(serialized)
	_check(restored.quantity_of("wood") == 9 and restored.slot_count() == 2,
			"Indexed serialization round-trips")
	changed_signal_count = 0
	source.changed.connect(func(): changed_signal_count += 1)
	source.add_item("stone", 1)
	_check(changed_signal_count >= 1, "Storage emits changed on mutation")
	# Malformed payloads drop bad entries safely.
	var broken := InventoryStorage.new(3, 0.0)
	broken.deserialize({"slots": [null, {"item_id": "", "quantity": 5}, {"item_id": "wood", "quantity": 2}], "max_weight": 5.0})
	_check(broken.quantity_of("wood") == 2 and broken.max_weight == 5.0,
			"Malformed slot entries are dropped, valid ones kept")

var changed_signal_count := 0

func _test_inventory_transfer() -> void:
	var source := InventoryStorage.new(4, 0.0)
	var target := InventoryStorage.new(4, 0.0)
	source.add_item("wood", 30)
	target.add_item("wood", 50)
	var outcome := InventoryTransfer.transfer(source, 0, target, 0, 99)
	_check(int(outcome[InventoryTransfer.RESULT_MOVED]) == 14
			and source.quantity_of("wood") == 16 and target.quantity_of("wood") == 64,
			"Merge caps at the target stack and conserves every unit")
	outcome = InventoryTransfer.transfer(source, 0, target, 1, 10)
	_check(int(outcome[InventoryTransfer.RESULT_MOVED]) == 10
			and target.quantity_at(1) == 10,
			"Empty target slots receive a split quantity")
	outcome = InventoryTransfer.transfer(source, 0, target, 1, 10)
	_check(int(outcome[InventoryTransfer.RESULT_MOVED]) == 6
			and source.quantity_of("wood") == 0,
			"Partial acceptance leaves the exact remainder in the source")
	# Swap.
	var swapper_a := InventoryStorage.new(2, 0.0)
	var swapper_b := InventoryStorage.new(2, 0.0)
	swapper_a.add_item("wood", 10)
	swapper_b.add_item("stone", 5)
	outcome = InventoryTransfer.transfer(swapper_a, 0, swapper_b, 0, 10)
	_check(bool(outcome[InventoryTransfer.RESULT_SWAPPED])
			and swapper_b.quantity_of("wood") == 10 and swapper_a.quantity_of("stone") == 5,
			"Whole-stack swap exchanges both slots exactly")
	# Weight-blocked swap changes nothing.
	var full_a := InventoryStorage.new(2, 100.0)
	var full_b := InventoryStorage.new(2, 6.0)
	full_a.add_item("wood", 10)
	full_b.add_item("stone", 5)
	var before_a := full_a.total_weight()
	var before_b := full_b.total_weight()
	outcome = InventoryTransfer.transfer(full_a, 0, full_b, 0, 10)
	_check(str(outcome[InventoryTransfer.RESULT_REJECTED]) == "cannot_swap"
			and is_equal_approx(full_a.total_weight(), before_a)
			and is_equal_approx(full_b.total_weight(), before_b),
			"Weight-blocked swaps refuse transactionally")
	# Filter refusal: the gate is occupied by a non-matching item, so the
	# transfer resolves to a refused swap; either way nothing moves.
	var gate := InventoryStorage.new(1, 0.0)
	gate.set_slot_filter(0, func(item_id: String): return item_id == "stone")
	gate.add_item("stone", 3)
	var feeder := InventoryStorage.new(2, 0.0)
	feeder.add_item("wood", 4)
	outcome = InventoryTransfer.transfer(feeder, 0, gate, 0, 4)
	_check(int(outcome[InventoryTransfer.RESULT_MOVED]) == 0
			and feeder.quantity_of("wood") == 4 and gate.quantity_of("stone") == 3,
			"Filter refusals move nothing")
	# transfer_between fans across several target slots.
	var donor := InventoryStorage.new(2, 0.0)
	var spread := InventoryStorage.new(2, 0.0)
	donor.add_item("wood", 100)
	spread.add_item("wood", 60)
	outcome = InventoryTransfer.transfer_between(donor, spread, "wood", 100)
	_check(int(outcome[InventoryTransfer.RESULT_MOVED]) == 68
			and donor.quantity_of("wood") == 32,
			"transfer_between fans the remainder across free slots")
	# Invalid requests change nothing.
	outcome = InventoryTransfer.transfer(donor, 0, spread, 0, 0)
	_check(str(outcome[InventoryTransfer.RESULT_REJECTED]) == "invalid_request",
			"Zero-quantity transfers are refused")

# --- InventoryComponent (player compatibility + migration) ---

func _test_inventory_component() -> void:
	var inventory := InventoryComponent.new()
	var database := ItemDatabase.new()
	database.initialize()
	var stack_sizes: Dictionary = {}
	for item_id in database.items:
		stack_sizes[item_id] = int(database.items[item_id].stack_size)
	inventory.set_stack_sizes(stack_sizes)
	inventory.set_item_durations(database.get_all_durations())

	_check(inventory.add_item("wood", 12) == 0 and inventory.get_item_quantity("wood") == 12,
			"Player inventory API accepts and reports quantities")
	_check(inventory.get_slots().has("wood")
			and int(inventory.get_slots()["wood"]["quantity"]) == 12,
			"get_slots keeps the compact projection shape for the UI")
	_check(inventory.has_item("wood", 12) and not inventory.has_item("wood", 13),
			"has_item semantics unchanged")
	_check(inventory.add_item("wooden_axe", 1) == 0
			and inventory.get_tool_durability("wooden_axe")["current"] == 50,
			"Durable tools keep their durability through the storage refactor")
	var damaged := inventory.damage_tool("wooden_axe", 20)
	_check(not damaged and inventory.get_tool_durability("wooden_axe")["current"] == 30,
			"damage_tool reduces durability through the storage")
	damaged = inventory.damage_tool("wooden_axe", 30)
	_check(damaged and inventory.get_item_quantity("wooden_axe") == 0,
			"Breaking a tool removes it and reports the break")
	# Full-inventory behaviour: 50 distinct types.
	var bulk := InventoryComponent.new()
	bulk.set_stack_sizes({"wood": 64})
	for type_index in range(50):
		bulk.add_item("item_%02d" % type_index, 1)
	_check(bulk.is_full and bulk.add_item("another", 1) == 1,
			"The 50-type player limit and full-inventory remainder are preserved")
	# Legacy compact save migration.
	var legacy := InventoryComponent.new()
	legacy.set_stack_sizes(stack_sizes)
	legacy.set_item_durations(database.get_all_durations())
	legacy.deserialize({
		"slots": {
			"wood": {"quantity": 12, "max_stack": 64},
			"wooden_axe": {"quantity": 1, "max_stack": 1},
		},
		"max_weight": 100.0,
		"max_slots": 50,
	})
	_check(legacy.get_item_quantity("wood") == 12 and legacy.get_item_quantity("wooden_axe") == 1,
			"Legacy compact save payload migrates into indexed slots")
	_check(legacy.get_tool_durability("wooden_axe")["current"] == 50,
			"Pre-v5 durable tools backfill to full durability on migration")
	var round_trip := legacy.serialize()
	_check(typeof(round_trip["slots"]) == TYPE_DICTIONARY
			and int(round_trip["max_slots"]) == 50,
			"serialize keeps the compact save format (unchanged until v8)")
	var again := InventoryComponent.new()
	again.set_stack_sizes(stack_sizes)
	again.set_item_durations(database.get_all_durations())
	again.deserialize(round_trip)
	_check(again.get_all_items() == legacy.get_all_items(),
			"Serialize/deserialize round-trips the migrated inventory")
	# Transactional transfer_to: a full target can no longer destroy overflow.
	var sender := InventoryComponent.new()
	var receiver := InventoryComponent.new()
	sender.set_stack_sizes({"wood": 64})
	receiver.set_stack_sizes({"wood": 64})
	receiver.set_max_weight(5.0)
	sender.add_item("wood", 20)
	var moved := sender.transfer_to(receiver, "wood", 20)
	_check(moved == 5 and sender.get_item_quantity("wood") == 15
			and receiver.get_item_quantity("wood") == 5,
			"transfer_to is transactional: overflow stays in the source")

# --- Building identity ---

func _test_building_identity() -> void:
	var building := Building.new()
	building.setup("chest", "Chest", Vector2i(3, 4), 50, 2, null)
	_check(building.placement_key == "3:4:2",
			"Placement key is the stable x:y:story identity")
	_check(building.capability_state.is_empty(),
			"Capability state starts empty until a capability system seeds it")
	var building2 := Building.new()
	building2.setup("chest", "Chest", Vector2i(3, 4), 50, 2, null)
	_check(building2.placement_key == building.placement_key,
			"Identical placements share one stable key (save/UI ownership)")
	building.free()
	building2.free()

func _first_error(registry: BuildingContentRegistry) -> String:
	if registry.validation_errors.is_empty():
		return ""
	return " (first: %s)" % registry.validation_errors[0]
