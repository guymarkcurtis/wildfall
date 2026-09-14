## Focused M6 coverage for profile-driven station groups, persistent input /
## output inventories, and transactional immediate crafting.
## Run: godot --headless --path . --script tests/test_station_crafting.gd
extends SceneTree

var _failures := 0
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_station_panel_interaction()
	_test_fuel_tick()
	var database := ItemDatabase.new()
	database.initialize()
	var inventory := InventoryComponent.new()
	var stack_sizes: Dictionary = {}
	for item_id in database.items:
		stack_sizes[item_id] = int(database.items[item_id].stack_size)
	inventory.set_stack_sizes(stack_sizes)
	inventory.add_item("workbench", 1)
	inventory.add_item("plank", 8)
	inventory.add_item("stone", 4)
	var manager := BuildingManager.new()
	root.add_child(manager)
	_check(manager.place_record("workbench", Vector2i(10, 10), inventory, 0),
			"A data-authored workbench places through the normal record path")
	var record := manager.get_record_at(Vector2i(10, 10), 0, "object")
	var recipe := database.get_recipe("wooden_hammer")
	_check(record != null and recipe != null and record.definition.station_profile.recipe_group == recipe.crafting_station,
			"Recipe eligibility matches the authored StationProfile group")
	var filled := StationCrafting.fill_inputs(record, inventory.get_storage(), recipe)
	_check(int(filled.moved) == 6 and record.get_station_input_storage().quantity_of("plank") == 4
			and record.get_station_input_storage().quantity_of("stone") == 2,
			"Required ingredients move visibly into persistent station input slots")
	var crafted := StationCrafting.craft(record, inventory.get_storage(), recipe)
	_check(bool(crafted.success) and record.get_station_input_storage().occupied_count() == 0
			and record.get_station_output_storage().quantity_of("wooden_hammer") == 1,
			"Craft consumes only station inputs and writes its result to station output")
	var payload := manager.serialize()
	var restored_manager := BuildingManager.new()
	root.add_child(restored_manager)
	restored_manager.deserialize(payload)
	var restored := restored_manager.get_record_at(Vector2i(10, 10), 0, "object")
	_check(restored != null and restored.get_station_output_storage().quantity_of("wooden_hammer") == 1,
			"Station output survives save/load in the building's v8 state payload")
	StationCrafting.fill_inputs(record, inventory.get_storage(), recipe)
	var full := StationCrafting.craft(record, inventory.get_storage(), recipe)
	_check(not bool(full.success) and str(full.reason) == "output_full"
			and record.get_station_input_storage().quantity_of("plank") == 4,
			"A full output rejects crafting without consuming visible inputs")
	var locked := StationCrafting.craft(record, inventory.get_storage(), recipe, false)
	_check(not bool(locked.success) and str(locked.reason) == "technology_locked",
			"Research gates are enforced before any station mutation")
	_check(manager.get_nearby_station_ids(Vector2(336, 336)).has("workbench"),
			"Nearby station discovery reads StationProfile recipe groups, not building ids")
	print("Station crafting failures: %d (%d checks)" % [_failures, _checks])
	restored_manager.queue_free()
	manager.queue_free()
	quit(_failures)

func _test_fuel_tick() -> void:
	var database := ItemDatabase.new()
	database.initialize()
	var record := BuildingRecord.new()
	record.definition = load("res://data/buildings/campfire.tres") as BuildingDefinition
	var storage := record.get_fuel_storage()
	storage.stack_sizes = {"wood": 64}
	storage.add_item("wood", 1)
	record.capability_state["enabled"] = true
	FuelConsumer.tick(record, 1.0, database)
	_check(record.capability_state.get("fuel_seconds_remaining", 0.0) > 0.0
			and storage.quantity_of("wood") == 0,
			"FuelConsumer consumes only an item accepted by the profile's fuel tags")
	var saved := record.serialize()
	var restored := BuildingRecord.new()
	restored.deserialize(saved, record.definition)
	_check(float(restored.capability_state.get("fuel_seconds_remaining", 0.0)) > 0.0
			and bool(restored.capability_state.get("enabled", false)),
			"Enabled state and remaining fuel persist in the v8 building state payload")
	FuelConsumer.tick(record, 301.0, database)
	_check(not bool(record.capability_state.get("enabled", true))
			and is_zero_approx(float(record.capability_state.get("fuel_seconds_remaining", -1.0))),
			"Fuel depletion disables the object without consuming time while off")

	var main := Node.new()
	main.name = "Main"
	root.add_child(main)
	var cycle := DayNightCycle.new()
	cycle.name = "DayNightCycle"
	main.add_child(cycle)
	cycle.set_time(22.0)
	var building_parent := Node2D.new()
	main.add_child(building_parent)
	var torch := Building.new()
	torch.setup("torch", "Torch", Vector2i.ZERO, 50, 0,
			load("res://data/buildings/torch.tres") as BuildingDefinition)
	torch.capability_state["enabled"] = true
	building_parent.add_child(torch)
	torch._update_light()
	_check(torch._light != null and torch._light.visible,
			"A powered LightProfile is visible at night through the shared radial mask")
	torch.capability_state["enabled"] = false
	torch._update_light()
	_check(not torch._light.visible,
			"Powering an authored light off hides it without an item-id branch")
	torch.capability_state["enabled"] = true
	var distant_player := Node2D.new()
	distant_player.name = "Player"
	distant_player.global_position = Vector2(2000, 2000)
	main.add_child(distant_player)
	torch._update_light()
	_check(not torch._light.visible,
			"Lights outside the player-radius budget are culled deterministically")
	main.queue_free()

func _test_station_panel_interaction() -> void:
	var world := Node.new()
	root.add_child(world)
	var database := ItemDatabase.new()
	database.name = "ItemDatabase"
	world.add_child(database)
	database.initialize()
	var buildings := BuildingManager.new()
	buildings.name = "BuildingManager"
	world.add_child(buildings)
	var player := Player.new()
	player.name = "Player"
	world.add_child(player)
	var manager := InteractionManager.new()
	manager.name = "InteractionManager"
	world.add_child(manager)
	var stack_sizes: Dictionary = {}
	for item_id in database.items:
		stack_sizes[item_id] = int(database.items[item_id].stack_size)
	player.inventory.set_stack_sizes(stack_sizes)
	player.inventory.add_item("workbench", 1)
	player.inventory.add_item("plank", 4)
	player.inventory.add_item("stone", 2)
	buildings.place_record("workbench", Vector2i(4, 4), player.inventory, 0)
	var bench := buildings.get_record_at(Vector2i(4, 4), 0, "object").node
	player.global_position = Vector2(144, 144)
	_check(manager.open(bench) and manager.open_panel != null and manager.open_panel.output_grid != null,
			"E-interaction opens a station panel with persistent input, output, and player surfaces")
	manager.open_panel.station_craft_requested.emit("wooden_hammer")
	_check(manager.open_record.get_station_output_storage().quantity_of("wooden_hammer") == 1,
			"Station panel recipe action fills inputs and crafts into visible output")
	manager.close("test")
	world.queue_free()

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures += 1
		push_error("[FAIL] %s" % label)
