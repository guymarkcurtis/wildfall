## Focused M6+ coverage for profile-driven station groups, persistent input /
## output inventories, transactional crafting, timed craft jobs, and the
## overhauled interaction panel (recipe fill, take-only output).
## Run: godot --headless --path . --script tests/test_station_crafting.gd
extends SceneTree

var _failures := 0
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_station_panel_interaction()
	_test_fuel_tick()
	_test_timed_crafting()
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
	var paused_record := BuildingRecord.new()
	paused_record.definition = record.definition
	var paused_storage := paused_record.get_fuel_storage()
	paused_storage.stack_sizes = {"wood": 64}
	paused_storage.add_item("wood", 1)
	FuelConsumer.tick(paused_record, 60.0, database)
	_check(paused_storage.quantity_of("wood") == 1
			and is_zero_approx(float(paused_record.capability_state.get("fuel_seconds_remaining", 0.0))),
			"Disabled fuel consumers do not burn while the game supplies no active state")
	var invalid_record := BuildingRecord.new()
	invalid_record.definition = record.definition
	var invalid_storage := invalid_record.get_fuel_storage()
	invalid_storage.stack_sizes = {"stone": 64}
	invalid_storage.add_item("stone", 1)
	invalid_record.capability_state["enabled"] = true
	FuelConsumer.tick(invalid_record, 1.0, database)
	_check(invalid_storage.quantity_of("stone") == 1 and not bool(invalid_record.capability_state.get("enabled", true)),
			"Invalid untagged fuel is never consumed and leaves the emitter out of fuel")

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
	# The torch owns a dedicated appearance profile (M9 6.6) whose powered
	# state name is authored on the profile, so read it from there rather than
	# assuming the shared fuelled profile's "lit" vocabulary.
	var expected_powered := str(torch.definition.appearance_profile.powered_state)
	var lit_state := torch._appearance_state
	torch.reload_visual_texture()
	_check(lit_state == expected_powered and torch._appearance_state == lit_state,
			"Texture refresh keeps the authored fuelled appearance state without resetting power")
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

	var budget_manager := BuildingManager.new()
	root.add_child(budget_manager)
	var budget_player := Player.new()
	budget_player.global_position = Vector2(2000, 2000)
	root.add_child(budget_player)
	budget_manager.player = budget_player
	for index in range(BuildingManager.MAX_VISIBLE_LOCAL_LIGHTS + 1):
		var budget_record := BuildingRecord.new()
		budget_record.definition = load("res://data/buildings/torch.tres") as BuildingDefinition
		budget_record.tile = Vector2i(index, 0)
		budget_record.node = Building.new()
		budget_record.node.setup("torch", "Torch", budget_record.tile, 50, 0, budget_record.definition)
		budget_record.node.global_position = budget_player.global_position + Vector2(float(index), 0.0)
		budget_manager._record_list.append(budget_record)
	budget_manager._refresh_local_light_budget()
	_check(budget_manager._record_list[0].node._light_budget_allowed
			and not budget_manager._record_list[BuildingManager.MAX_VISIBLE_LOCAL_LIGHTS].node._light_budget_allowed,
			"Dense local lights use a deterministic nearest-first shared budget cap")
	for budget_record in budget_manager._record_list:
		budget_record.node.free()
	budget_manager.free()
	budget_player.free()

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
	player.inventory.add_item("torch", 1)
	player.inventory.add_item("plank", 4)
	player.inventory.add_item("stone", 2)
	player.inventory.add_item("wood", 1)
	buildings.place_record("workbench", Vector2i(4, 4), player.inventory, 0)
	var bench := buildings.get_record_at(Vector2i(4, 4), 0, "object").node
	player.global_position = Vector2(144, 144)
	_check(manager.open(bench) and manager.open_panel != null and manager.open_panel.output_grid != null,
			"E-interaction opens a station panel with persistent input, output, and player surfaces")
	var toasts: Array[String] = []
	manager.open_panel.toast_requested.connect(func(text: String) -> void: toasts.append(text))
	manager.open_panel.station_fill_requested.emit("wooden_hammer")
	_check(manager.open_record.get_station_input_storage().quantity_of("plank") == 4
			and manager.open_record.get_station_input_storage().quantity_of("stone") == 2,
			"The panel fill action pulls the recipe's ingredients onto the station surface")
	_check(toasts == ["Filled 6 ingredients from your inventory"],
			"Filling announces how many ingredients moved")
	manager.open_panel.station_craft_requested.emit("wooden_hammer")
	_check(StationCrafting.job_of(manager.open_record).get("recipe_id", "") == "wooden_hammer"
			and manager.open_record.get_station_input_storage().occupied_count() == 0,
			"Crafting consumes the input slots and starts a timed job on the record")
	_check(toasts.size() == 2 and toasts[1] == "Crafting 1x Wooden Hammer — 5s",
			"A started craft announces itself with its craft time")
	StationCrafting.tick(manager.open_record, 2.0, database)
	_check(float(StationCrafting.job_of(manager.open_record).get("remaining", -1.0)) > 0.0
			and manager.open_record.get_station_output_storage().occupied_count() == 0,
			"A timed job is not finished before its craft time elapses")
	StationCrafting.tick(manager.open_record, 3.0, database)
	_check(StationCrafting.job_of(manager.open_record).is_empty()
			and manager.open_record.get_station_output_storage().quantity_of("wooden_hammer") == 1,
			"The finished job writes its result to the visible output slot")
	var held_hammers := player.inventory.get_item_quantity("wooden_hammer")
	manager.open_panel._on_grid_slot_pressed("output", 0, MOUSE_BUTTON_LEFT)
	_check(player.inventory.get_item_quantity("wooden_hammer") == held_hammers + 1
			and manager.open_record.get_station_output_storage().occupied_count() == 0,
			"Output slots are take-only: a click picks the result up into the player inventory")
	# The first craft consumed the player's planks and stone, so this repeat
	# has nothing to start from: the failure names the missing inputs.
	manager.open_panel.station_craft_requested.emit("wooden_hammer")
	_check(toasts.size() == 3 and toasts[2] == "Missing ingredients — fill the input slots",
			"A starved repeat craft names the missing ingredients")
	manager.close("test")
	buildings.place_record("torch", Vector2i(7, 4), player.inventory, 0)
	var torch_record := buildings.get_record_at(Vector2i(7, 4), 0, "object")
	player.global_position = Vector2(240, 144)
	_check(manager.open(torch_record.node) and manager.open_panel.fuel_grid != null,
			"A fuel-only interactable opens the shared panel with its filtered fuel slot")
	var torch_toasts: Array[String] = []
	manager.open_panel.toast_requested.connect(func(text: String) -> void: torch_toasts.append(text))
	# The craft above left the player with wood but no planks; hand them one
	# so the filter has something to refuse.
	player.inventory.add_item("plank", 1)
	var plank_slot := player.inventory.get_storage().first_index_of("plank")
	manager.open_panel._on_grid_slot_pressed("player", plank_slot, MOUSE_BUTTON_LEFT)
	manager.open_panel._on_grid_slot_pressed("fuel", 0, MOUSE_BUTTON_LEFT)
	_check(torch_toasts == ["That fuel slot only accepts: fuel"],
			"A non-fuel item refused by the fuel slot names the accepted tags")
	# A failed transfer keeps the selection, so re-click the plank to deselect,
	# then select the wood (an accepted fuel) and move it in.
	manager.open_panel._on_grid_slot_pressed("player", plank_slot, MOUSE_BUTTON_LEFT)
	var wood_slot := player.inventory.get_storage().first_index_of("wood")
	manager.open_panel._on_grid_slot_pressed("player", wood_slot, MOUSE_BUTTON_LEFT)
	manager.open_panel._on_grid_slot_pressed("fuel", 0, MOUSE_BUTTON_LEFT)
	_check(torch_toasts.size() == 1, "An accepted fuel enters the slot silently")
	_check(torch_record.get_fuel_storage().quantity_of("wood") == 1,
			"The accepted fuel actually landed in the fuel storage")
	var enabled_before := bool(torch_record.capability_state.get("enabled", false))
	manager.open_panel.fuel_toggle_requested.emit()
	_check(bool(torch_record.capability_state.get("enabled", false)) != enabled_before,
			"Fuel-panel on/off controls mutate only the record's generic enabled state")
	manager.close("test")
	world.queue_free()

## Timed crafting: multi-ingredient fills on the widened surface, job
## progression, power pauses, already-crafting refusal, mid-craft save/load,
## and the shorter-array input migration.
func _test_timed_crafting() -> void:
	var database := ItemDatabase.new()
	database.initialize()
	var inventory := InventoryComponent.new()
	var stack_sizes: Dictionary = {}
	for item_id in database.items:
		stack_sizes[item_id] = int(database.items[item_id].stack_size)
	inventory.set_stack_sizes(stack_sizes)
	inventory.add_item("furnace", 1)
	inventory.add_item("sand", 8)
	inventory.add_item("coal", 8)
	var manager := BuildingManager.new()
	root.add_child(manager)
	_check(manager.place_record("furnace", Vector2i(20, 20), inventory, 0),
			"A data-authored furnace places through the normal record path")
	var record := manager.get_record_at(Vector2i(20, 20), 0, "object")
	_check(record.get_station_input_storage().slot_count() == 3,
			"The furnace's authored input surface provides three ingredient slots")
	var glass_recipe := database.get_recipe("glass")
	var filled := StationCrafting.fill_inputs(record, inventory.get_storage(), glass_recipe)
	_check(int(filled.moved) == 3 and record.get_station_input_storage().quantity_of("sand") == 2
			and record.get_station_input_storage().quantity_of("coal") == 1,
			"Two distinct ingredients fill separate input slots for one recipe")
	var refused := StationCrafting.start_craft(record, inventory.get_storage(), glass_recipe)
	_check(not bool(refused.success) and str(refused.reason) == "unpowered",
			"An unpowered station refuses to start a craft without consuming inputs")
	record.capability_state["enabled"] = true
	var started := StationCrafting.start_craft(record, inventory.get_storage(), glass_recipe)
	_check(bool(started.success) and record.get_station_input_storage().occupied_count() == 0
			and not StationCrafting.job_of(record).is_empty(),
			"Starting a timed craft consumes the inputs and opens a job")
	var again := StationCrafting.start_craft(record, inventory.get_storage(), glass_recipe)
	_check(not bool(again.success) and str(again.reason) == "already_crafting",
			"A second start while a job runs is refused as already crafting")
	StationCrafting.tick(record, 2.0, database)
	record.capability_state["enabled"] = false
	var before_pause := float(StationCrafting.job_of(record).get("remaining", -1.0))
	StationCrafting.tick(record, 60.0, database)
	_check(is_equal_approx(float(StationCrafting.job_of(record).get("remaining", -1.0)), before_pause),
			"Losing power pauses the job without progress or loss")
	record.capability_state["enabled"] = true
	var payload := manager.serialize()
	var restored_manager := BuildingManager.new()
	root.add_child(restored_manager)
	restored_manager.deserialize(payload)
	var restored := restored_manager.get_record_at(Vector2i(20, 20), 0, "object")
	_check(float(StationCrafting.job_of(restored).get("remaining", -1.0)) > 0.0,
			"A mid-craft job persists in the building's v8 state payload")
	StationCrafting.tick(restored, 5.0, database)
	_check(StationCrafting.job_of(restored).is_empty()
			and restored.get_station_output_storage().quantity_of("glass") == 1,
			"The resumed job finishes into the output slot after reload")
	# Old saves carried a one-slot input surface: the shorter array restores,
	# then pads up to the authored count instead of being dropped.
	var legacy := BuildingRecord.new()
	legacy.definition = record.definition
	legacy.capability_state["station"] = {"inputs": {"slots": [
			{"item_id": "iron_ore", "quantity": 2}]}}
	var legacy_inputs := legacy.get_station_input_storage()
	_check(legacy_inputs.slot_count() == 3 and legacy_inputs.quantity_of("iron_ore") == 2,
			"Station inputs saved with fewer slots restore and pad to the authored count")
	restored_manager.queue_free()
	manager.queue_free()

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures += 1
		push_error("[FAIL] %s" % label)
