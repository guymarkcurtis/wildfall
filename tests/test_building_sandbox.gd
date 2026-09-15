## Focused Building Sandbox boot coverage.
## Run: godot --headless --path . --script tests/test_building_sandbox.gd
extends SceneTree

var _main: Node = null
var _failures := 0

func _initialize() -> void:
	GameSession.request_new_game(GameSession.MODE_BUILDING_SANDBOX)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	call_deferred("_run")

func _run() -> void:
	# Let deferred fixture placement and queued chunk presentation settle.
	for _frame in range(8):
		await process_frame
	_main.flush_pending_chunk_visuals()
	var world_generator: WorldGenerator = _main.get_node("WorldGenerator") as WorldGenerator
	var config: WorldGenerationConfig = world_generator.get_configuration()
	_check(GameSession.is_building_sandbox(), "Building Sandbox mode is active")
	_check(config.config_id == "building_sandbox" and config.world_dimensions_chunks == Vector2i(5, 3),
		"Sandbox uses the compact five-by-three chunk test yard")
	_check((_main.get("_resource_nodes") as Array).is_empty(), "Sandbox spawns no generated resources")
	_check((_main.get("_creature_nodes") as Array).is_empty(), "Sandbox spawns no creatures")
	_check((_main.get("_poi_marker_nodes") as Array).is_empty() and (_main.get("_cave_entrance_nodes") as Array).is_empty(),
		"Sandbox keeps the yard free of generated POIs")
	var buildings: BuildingManager = _main.get_node("BuildingManager") as BuildingManager
	# Station membership is content, not code: the set comes from the
	# definitions that ship a station profile, so a new station needs no
	# test or manager edit.
	var station_ids: PackedStringArray = PackedStringArray()
	for key in buildings.content_registry.definitions:
		var station_def: BuildingDefinition = buildings.content_registry.definitions[key]
		if station_def.station_profile != null:
			station_ids.append(str(key))
	_check(station_ids.size() > 0, "Sandbox discovers station buildings from building content")
	for station_id in station_ids:
		var found := false
		for building in buildings.get_all_buildings():
			if is_instance_valid(building) and building.building_id == station_id:
				found = true
				break
		_check(found, "Sandbox places %s by default" % station_id)
	var technology: TechnologySystem = _main.get_node("TechnologySystem") as TechnologySystem
	_check(technology.get_unlocked_ids().size() == technology.technology_order.size(), "Sandbox keeps every technology unlocked")
	var day_night: DayNightCycle = _main.get_node("DayNightCycle") as DayNightCycle
	var initial_hour := day_night.get_current_hour()
	for _frame in range(4):
		await process_frame
	_check(is_equal_approx(day_night.get_current_hour(), initial_hour), "Sandbox time stays fixed instead of progressing")
	_main.set_sandbox_time(22.0)
	_check(is_equal_approx(day_night.get_current_hour(), 22.0) and day_night.is_nighttime(),
		"Sandbox time selector can set a fixed night lighting state")
	var recipes: Array = _main.get("_recipe_defs") as Array
	var item_database: ItemDatabase = _main.get_node("ItemDatabase") as ItemDatabase
	# M6 made the C-key panel hand-crafting only: station recipes are
	# exposed through the E-interaction station panel, never the C panel,
	# so the contract here is "every hand-crafted recipe is exposed".
	var hand_recipe_count := 0
	for recipe_id in item_database.recipes:
		var recipe_def: RecipeDefinition = item_database.get_recipe(recipe_id)
		if recipe_def != null and recipe_def.crafting_station.is_empty():
			hand_recipe_count += 1
	_check(recipes.size() == hand_recipe_count, "Sandbox exposes every hand-crafted recipe")
	var store: SandboxSupplyStore = _main.get("_sandbox_store") as SandboxSupplyStore
	var store_panel: SandboxStorePanel = _main.get_node("HUD/SandboxStorePanel") as SandboxStorePanel
	_check(store != null and store_panel != null, "Sandbox has a clickable supply store and its catalog panel")
	store_panel._grant("wood", 64)
	var player: Player = _main.get_node("Player") as Player
	_check(player.inventory.get_item_quantity("wood") >= 64, "Supply store grants stackable crafting materials")
	var hunger_before := player.hunger_component.current_hunger
	for _frame in range(4):
		await process_frame
	_check(is_equal_approx(player.hunger_component.current_hunger, hunger_before), "Sandbox pauses hunger drain for long build tests")
	# M9 box 4: the palette's group filter is presentation state on the
	# manager. The starter kit already owns wooden walls and a campfire,
	# so the working set below is those plus the granted doors and window.
	var palette: BuildPalette = _main.get_node("HUD/BuildPalette") as BuildPalette
	_check(palette != null, "Sandbox exposes a build palette")
	player.inventory.add_item("wooden_wall", 3)
	player.inventory.add_item("wooden_door", 2)
	player.inventory.add_item("wooden_window", 1)
	buildings.set_build_mode(true)
	_check(buildings.get_visible_building_items().size() == 4,
		"An empty filter exposes every owned building part (starter walls + campfire + granted doors and window)")
	_check(buildings.select_item("wooden_wall"), "Wall selection is possible in the full list")
	buildings.set_build_filter("doors_windows")
	_check(buildings.build_filter == "doors_windows", "Filtering narrows the working list to one group")
	var visible_items := buildings.get_visible_building_items()
	_check(visible_items.size() == 2 and visible_items.has("wooden_door") and visible_items.has("wooden_window")
			and not visible_items.has("wooden_wall") and not visible_items.has("campfire"),
		"doors_windows shows both openings and hides the wall and the campfire")
	_check(str(palette.get("_active_group")) == "doors_windows",
		"The palette mirrors the manager's active filter")
	_check(buildings.selected_item_id != "wooden_wall"
			and visible_items.has(buildings.selected_item_id),
		"Filtering out the selected part re-points the selection into the visible list")
	var cycle_stayed_visible := true
	for _cycle in range(6):
		buildings.cycle_selection(1)
		if not visible_items.has(buildings.selected_item_id):
			cycle_stayed_visible = false
	_check(cycle_stayed_visible, "Wheel cycling stays inside the filtered list")
	buildings.set_build_filter("boundaries")
	_check(buildings.build_filter.is_empty(),
		"Filtering into a group the player owns no parts of falls back to the full list")
	_check(str(palette.get("_active_group")) == "" if palette != null else false,
		"The palette mirrors the fallback back to the full list")
	_check(buildings.get_visible_building_items().size() == 4,
		"The fallback re-exposes the full owned list")
	buildings.set_build_mode(false)
	var toolbar: SandboxSaveToolbar = _main.get_node("HUD/SandboxSaveToolbar") as SandboxSaveToolbar
	_check(toolbar.visible and not bool(toolbar.get("_expanded")), "Sandbox keeps its save controls collapsed by default")
	toolbar.call("_toggle_drawer")
	_check(bool(toolbar.get("_expanded")) and (toolbar.get("_drawer") as Control).visible,
		"Sandbox save button expands to reveal save controls and time selection")
	_main.queue_free()
	await process_frame
	GameSession.set_game_mode(GameSession.MODE_SURVIVAL)
	print("Building Sandbox failures: %d" % _failures)
	quit(_failures)

func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures += 1
		push_error("[FAIL] %s" % label)
