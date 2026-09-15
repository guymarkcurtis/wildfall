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
	# M9 box 5: R rotates the pending orientation clockwise and Q
	# counter-clockwise; the first press seeds it from the live mouse-edge
	# default, and the choice sticks until the selection changes or build
	# mode is (re)entered. F5 (formerly R) toggles roof visibility.
	var allowed_edges := ["north", "east", "south", "west"]
	_check(_action_keycode("build_rotate_cw") == KEY_R, "R is bound to clockwise building rotation")
	_check(_action_keycode("build_rotate_ccw") == KEY_Q, "Q is bound to counter-clockwise building rotation")
	_check(_action_keycode("toggle_roofs") == KEY_F5, "F5 (not R) toggles roof visibility")
	buildings.set_build_mode(true)
	_check(buildings.select_item("wooden_wall"), "The orientable starter wall is selectable for rotation")
	await process_frame
	_check(bool(buildings.get("_orientation_label").visible), "The ghost shows a compass letter for an orientable part")
	_check(String(buildings.get("_orientation_label").text) in ["N", "E", "S", "W"], "The compass letter names the resolved edge")
	_press_key("build_rotate_cw")
	var seeded := ""
	for _frame in range(20):
		await process_frame
		if not buildings.pending_orientation.is_empty():
			seeded = str(buildings.pending_orientation)
			break
	_release_key("build_rotate_cw")
	await process_frame
	_check(not seeded.is_empty() and allowed_edges.has(seeded),
			"First R press seeds the pending orientation from the live mouse edge")
	_press_key("build_rotate_cw")
	for _frame in range(20):
		await process_frame
		if not buildings.pending_orientation.is_empty() and buildings.pending_orientation != seeded:
			break
	_release_key("build_rotate_cw")
	await process_frame
	var advanced := str(buildings.pending_orientation)
	_check(advanced != seeded and allowed_edges.has(advanced), "Second R press advances the pending orientation")
	_press_key("build_rotate_ccw")
	for _frame in range(20):
		await process_frame
		if str(buildings.pending_orientation) == seeded:
			break
	_release_key("build_rotate_ccw")
	await process_frame
	_check(str(buildings.pending_orientation) == seeded, "Q walks the pending orientation back to the seeded edge")
	# The key-rotated choice is what the live placement consumes.
	_check(buildings.get_record_at(Vector2i(5, 2), 0, "edge", seeded) == null,
			"The test tile is free on the rotated edge before placement")
	_check(buildings.try_place_at(Vector2i(5, 2)), "The key-rotated pending orientation places successfully")
	var placed_wall := buildings.get_record_at(Vector2i(5, 2), 0, "edge", seeded)
	_check(placed_wall != null and str(placed_wall.orientation) == seeded,
			"The placed record keeps exactly the orientation the player rotated to")
	# Later rotations never reinterpret an already-saved orientation.
	var other_edge := "north"
	for edge in allowed_edges:
		if str(edge) != seeded:
			other_edge = str(edge)
			break
	buildings.pending_orientation = other_edge
	_check(buildings.try_place_at(Vector2i(7, 2)), "A second wall places with the new rotation choice")
	_check(placed_wall != null and is_instance_valid(placed_wall) and str(placed_wall.orientation) == seeded,
			"Rotating a later placement never reinterprets an already-saved orientation")
	# A non-orientable part is a rotation no-op and shows no compass.
	_check(buildings.select_item("campfire"), "The non-orientable campfire is selectable")
	_press_key("build_rotate_cw")
	for _frame in range(4):
		await process_frame
	_release_key("build_rotate_cw")
	await process_frame
	_check(buildings.pending_orientation.is_empty(), "Rotating a non-orientable part is a no-op")
	_check(not bool(buildings.get("_orientation_label").visible), "A non-orientable part shows no compass letter")
	# F5 (repointed from R) still toggles the sandbox roof layer.
	_press_key("toggle_roofs")
	for _frame in range(20):
		await process_frame
		if not buildings.roofs_visible:
			break
	_release_key("toggle_roofs")
	await process_frame
	_check(not buildings.roofs_visible, "F5 hides the roof layer in the sandbox")
	_press_key("toggle_roofs")
	for _frame in range(20):
		await process_frame
		if buildings.roofs_visible:
			break
	_release_key("toggle_roofs")
	await process_frame
	_check(buildings.roofs_visible, "F5 shows the roof layer again")
	buildings.set_build_mode(false)
	# M10 release playtest: construct each promised sandbox layout through the
	# same data-driven placement API used by the player. This is deliberately a
	# compact structural smoke rather than a second catalogue list: it proves
	# the authored tiers, layers, connectors, and furniture compose together.
	_test_m10_layout_smoke(buildings, player)
	# M9 box 6: the ghost shows the full placement contract — one marker per
	# reserved key (each footprint cell, the exact edge an edge part occupies,
	# the stairwell landing a connector reserves) — and per-marker colour
	# names the specific failure.
	buildings.set_build_mode(true)
	player.inventory.add_item("awning", 1)
	player.inventory.add_item("wooden_stairs", 1)
	player.inventory.add_item("wooden_roof", 1)
	player.inventory.add_item("wooden_wall", 2)
	for _frame in range(3):
		await process_frame
	var ghost: Node2D = buildings.get("_ghost")
	_check(ghost != null and ghost.visible, "The ghost is visible while build mode is active")
	# Edge part: one strip on the pending side of the anchor tile.
	_check(buildings.select_item("wooden_wall"), "The wall is selectable for the ghost checks")
	buildings.pending_orientation = "east"
	for _frame in range(3):
		await process_frame
	_check(ghost.get_child_count() == 1, "A wall reserves exactly one key, so the ghost has one marker")
	var wall_marker := ghost.get_child(0) as Polygon2D
	_check(str(wall_marker.get_meta("ghost_kind")) == "edge"
			and str(wall_marker.get_meta("ghost_side")) == "east",
			"The wall's marker sits on the pending (east) side of the tile")
	_check(int(wall_marker.z_index) == 5, "The edge marker floats in the story-0 edge band")
	# Multi-tile footprint: one marker per reserved cell.
	var awning_def := buildings.get_definition("awning") as BuildingDefinition
	_check(awning_def != null, "The awning definition loads for the white-box width probe")
	awning_def.width = 2
	buildings.select_item("awning")
	for _frame in range(3):
		await process_frame
	_check(ghost.get_child_count() == 2, "A two-tile awning reserves two ghost cells")
	var awning_cells := PackedVector2Array()
	for _index in range(ghost.get_child_count()):
		var cell_marker := ghost.get_child(_index) as Polygon2D
		awning_cells.append(Vector2(int(cell_marker.position.x / 32.0), int(cell_marker.position.y / 32.0)))
	_check(awning_cells.has(Vector2.ZERO) and awning_cells.has(Vector2(1, 0)),
			"The awning's markers cover the anchor cell and its east neighbour")
	_check(str(ghost.get_child(0).get_meta("ghost_layer")) == "overhead",
			"Awning cells are overhead-layer markers")
	awning_def.width = 1
	# Stairwell: the connector's base plus the floor slot it reserves above.
	buildings.select_item("wooden_stairs")
	for _frame in range(3):
		await process_frame
	_check(ghost.get_child_count() == 2, "The stair ghost marks its base and its reserved landing")
	var landing_marker := ghost.get_child(1) as Polygon2D
	_check(str(landing_marker.get_meta("ghost_kind")) == "landing"
			and int(landing_marker.get_meta("ghost_story")) == 1,
			"The landing marker reserves the floor slot one story up")
	_check(int(landing_marker.z_index) == 22
			and landing_marker.position == (ghost.get_child(0) as Polygon2D).position,
			"The landing marker sits in the story-1 band above the stair's own tile")
	# Ghost colour mirrors the exact placement decision: an upper-story part
	# with nothing supporting it is red.
	var ghost_tile := buildings._mouse_tile()
	buildings.set_selected_story(1)
	buildings.select_item("wooden_roof")
	for _frame in range(3):
		await process_frame
	var roof_marker := ghost.get_child(0) as Polygon2D
	_check(buildings.can_place(ghost_tile, 1) == false, "A roof finds no support over an empty upper story")
	_check(roof_marker.color == Color(0.85, 0.25, 0.2, 0.4),
			"The roof ghost is red over an unsupported upper story")
	buildings.set_selected_story(0)
	# An occupied reserved key is red — and the ghost names that specific key.
	_check(buildings.select_item("wooden_wall"), "Back to the wall for the occupancy colour check")
	var free_side := ""
	for candidate in ["north", "east", "south", "west"]:
		if buildings.get_record_for_key(BuildingRecord.canonical_edge_key(ghost_tile, 0, str(candidate))) == null:
			free_side = str(candidate)
			break
	_check(free_side != "", "At least one edge around the ghost tile is free")
	buildings.pending_orientation = free_side
	for _frame in range(3):
		await process_frame
	var wall_marker2 := ghost.get_child(0) as Polygon2D
	_check(wall_marker2.color == Color(0.3, 0.85, 0.35, 0.4), "A free reserved edge shows a green marker")
	_check(buildings.try_place_at(ghost_tile), "The wall places on the edge the ghost reserved")
	for _frame in range(3):
		await process_frame
	_check(wall_marker2.color == Color(0.85, 0.25, 0.2, 0.4),
			"The ghost marker turns red once its reserved edge is occupied")
	buildings.set_build_mode(false)
	_check(ghost != null and not ghost.visible, "Leaving build mode hides the ghost")
	var toolbar: SandboxSaveToolbar = _main.get_node("HUD/SandboxSaveToolbar") as SandboxSaveToolbar
	_check(toolbar.visible and not bool(toolbar.get("_expanded")), "Sandbox keeps its save controls collapsed by default")
	toolbar.call("_toggle_drawer")
	_check(bool(toolbar.get("_expanded")) and (toolbar.get("_drawer") as Control).visible,
		"Sandbox save button expands to reveal save controls and time selection")
	# M9 box 7: the sandbox ships a data-authored tutorial card, visible at
	# start, dismissible with X, re-openable from the drawer's ? button.
	var card: SandboxTutorialCardPanel = _main.get_node("HUD/SandboxTutorialCard") as SandboxTutorialCardPanel
	_check(card != null, "The sandbox scene carries the tutorial card")
	_check(card != null and card.visible, "The tutorial card is visible when the sandbox starts")
	var card_data := load("res://data/sandbox/sandbox_tutorial_card.tres") as SandboxTutorialCard
	_check(card_data != null and card_data.validate().is_empty(),
		"The tutorial card data resource is valid")
	var expected_headings: Array[String] = []
	for heading in card_data.lines:
		expected_headings.append(str(heading))
	_check(card.heading_labels() == expected_headings,
		"Every data-authored line renders, in authored order")
	card._close_button.pressed.emit()
	_check(not card.visible, "The X button dismisses the tutorial card")
	toolbar._help_button.pressed.emit()
	_check(card.visible, "The drawer's ? button reopens the tutorial card")
	_main.queue_free()
	await process_frame
	GameSession.set_game_mode(GameSession.MODE_SURVIVAL)
	print("Building Sandbox failures: %d" % _failures)
	quit(_failures)

func _test_m10_layout_smoke(buildings: BuildingManager, player: Player) -> void:
	var supplies := {
		"wooden_foundation": 40, "wooden_floor": 40, "wooden_wall": 40,
		"wooden_roof": 12, "wooden_stairs": 3, "fence": 12, "fence_gate": 3,
		"planter_box": 4, "wooden_table": 2, "chair": 4,
		"stone_foundation": 12, "stone_floor": 12, "stone_wall": 12,
		"furnace": 2, "workbench": 2,
	}
	for item_id in supplies:
		player.inventory.add_item(str(item_id), int(supplies[item_id]))
	var failures := 0
	var place := func(item_id: String, tile: Vector2i, story: int = 0, orientation: String = "") -> void:
		if not buildings.place_record(item_id, tile, player.inventory, story, orientation):
			failures += 1
	# Cabin: timber foundation, edges, roof, and furniture.
	var cabin := Vector2i(10, 6)
	for offset in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		place.call("wooden_foundation", cabin + offset)
		place.call("wooden_roof", cabin + offset, 1)
	place.call("wooden_wall", cabin, 0, "north")
	place.call("wooden_wall", cabin, 0, "west")
	place.call("wooden_table", cabin + Vector2i(1, 1))
	place.call("chair", cabin + Vector2i(1, 0))
	# Two-storey cottage: the stair reserves its opening; the other upper
	# tiles form the usable floor.
	var cottage := Vector2i(14, 6)
	for offset in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		place.call("wooden_foundation", cottage + offset)
	place.call("wooden_stairs", cottage)
	for offset in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		place.call("wooden_floor", cottage + offset, 1)
	place.call("wooden_wall", cottage + Vector2i(1, 0), 1, "north")
	# Fenced farmyard: boundary pieces and exterior objects coexist with ground.
	var yard := Vector2i(19, 6)
	for offset in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)]:
		place.call("fence", yard + offset, 0, "north")
	place.call("fence_gate", yard + Vector2i(1, 0), 0, "south")
	place.call("planter_box", yard + Vector2i(1, 1))
	# Stone workshop: a second material tier carries floor, edges, and stations.
	var workshop := Vector2i(24, 6)
	for offset in [Vector2i.ZERO, Vector2i(1, 0)]:
		place.call("stone_foundation", workshop + offset)
		place.call("stone_floor", workshop + offset)
	place.call("stone_wall", workshop, 0, "north")
	place.call("furnace", workshop)
	place.call("workbench", workshop + Vector2i(1, 0))
	# Three-story stress layout: two supported floors above the ground story.
	var tower := Vector2i(29, 6)
	for offset in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		place.call("wooden_foundation", tower + offset)
		place.call("wooden_floor", tower + offset, 1)
		place.call("wooden_floor", tower + offset, 2)
	place.call("wooden_wall", tower, 2, "north")
	_check(failures == 0, "M10 sandbox playtest builds cabin, cottage, yard, workshop, and three-story layout")

func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures += 1
		push_error("[FAIL] %s" % label)

## The first keycode bound to an input action (KEY_* value; -1 when the
## action is missing or carries no key event).
func _action_keycode(action: String) -> int:
	if not InputMap.has_action(action):
		return -1
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			if key.keycode != 0:
				return int(key.keycode)
	return -1

## Inject a real key event for the first InputEventKey bound to `action`
## so the manager's _unhandled_input path runs exactly as it would for a
## physical key.
func _press_key(action: String, pressed: bool = true) -> void:
	if not InputMap.has_action(action):
		return
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var source := event as InputEventKey
			var injected := InputEventKey.new()
			injected.keycode = source.keycode
			injected.unicode = source.unicode
			injected.pressed = pressed
			Input.parse_input_event(injected)
			return

func _release_key(action: String) -> void:
	_press_key(action, false)
