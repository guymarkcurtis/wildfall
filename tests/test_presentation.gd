## Location-aware presentation coverage (Task G), run in SURVIVAL mode —
## The building sandbox is exempt from the structure-scoped rules below, so the survival boot proves the full contract:
##
## 1. Outside a structure the view is the structure's EXTERIOR SHELL: every
##    roof on every story in full colour, every exterior-facing wall (a wall
##    whose face is not backed by built-up space) in full colour on every
##    story, and the mass beneath (floors, foundations) ghosted. An
##    unfinished house shows exactly what exists — a freestanding wall on an
##    empty lot reads as shell, an interior partition reads as ghost. The
##    pavilion's deck floor, having no roof, is mass and ghosts; it no longer
##    impersonates a roof.
## 2. Entering a structure opens its INTERIOR CUTAWAY, scoped to the structure
##    the player stands in: the level the player is on in full colour (its
##    own overhead faded), every other story of that structure HIDDEN — the
##    level below is not a semi-transparent ghost, it is simply not shown.
##    Every OTHER structure keeps its exterior shell: standing inside the
##    house still shows the pavilion's walls and roof, not its rooms.
## 3. Leaving a structure from an upper story returns the active story to the
##    ground — except while crossing a stair connector, where the traversal
##    owns the story and the outdoor reset must stand down.
## 4. An indoor spot without a roof (an open deck) reads as outdoors: the
##    roof shows again (it is shell), but the floor underfoot keeps the
##    player on their story instead of snapping them to the ground. The deck
##    floor itself is mass, so it ghosts rather than reading as a roof.
## 5. Wall fixtures (torches, exterior lanterns) mount on a wall, door, or
##    window edge that faces outside the built structure. A fixture on an
##    interior partition is rejected, and a fixture in open air is rejected.
##    Demolishing the wall a fixture is mounted on removes the fixture with
##    it (refunded).
##
## The fixture is placed on a land block found by a spiral search from the
## spawn point (the survival yard is a 2048x2048 tile world, so no fixed
## tile is guaranteed clear; foundations validate against an 8-tile
## neighbourhood, so the water mask must be dry one tile beyond the block
## in every direction), then the player is teleported between its spots.
## Physics-frame awaits let the manager's own traversal/reset/sync hooks do
## the work, exactly the way the live game runs them.
##
## Run: godot --headless --path . --script tests/test_presentation.gd
extends SceneTree

const NO_ORIGIN := Vector2i(-100000, -100000)

var _main: Node = null
var _failures := 0
var _checks := 0
var _place_failures := 0
var _last_place_reason := ""

var _world_generator: WorldGenerator = null
var _buildings: BuildingManager = null
var _player: Player = null
var _hud: HUD = null
var _day_night: DayNightCycle = null
var _weather: WeatherSystem = null

# Fixture geometry (filled by _run before any check runs).
var _origin := Vector2i.ZERO
# House: 2x2, three stories — foundations (0), stair + floor + walls (1),
# roof + floor + walls (2), roof (3). The stairwell opening is (0,0).
# Pavilion: a 1x1 enclosed room at (4,0) with a 1x1 open deck at (5,0) —
# one story, a roof over the room only. The pavilion is not adjacent to the
# house, so the two are separate connected structures (the G4 scoping proof).
var _outdoor := Vector2i(2, 3)

var _roof_top: BuildingRecord = null
var _roof_mid: BuildingRecord = null
var _floor_upper: BuildingRecord = null
var _floor_lower: BuildingRecord = null
var _foundation: BuildingRecord = null
var _pavilion_roof: BuildingRecord = null
var _pavilion_room_floor: BuildingRecord = null
var _pavilion_deck_floor: BuildingRecord = null
# Wall records the shell/partition distinction is asserted against.
var _house_south_wall_s1: BuildingRecord = null
var _house_south_wall_s2: BuildingRecord = null
var _pavilion_north_wall: BuildingRecord = null
var _pavilion_east_wall: BuildingRecord = null


func _initialize() -> void:
	GameSession.request_new_game(GameSession.MODE_SURVIVAL)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	call_deferred("_run")


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("  [PASS] " + name)
	else:
		printerr("  [FAIL] " + name)
		_failures += 1


func _place(item_id: String, tile: Vector2i, story: int = 0, orientation: String = "") -> void:
	if not _buildings.place_record(item_id, tile, _player.inventory, story, orientation):
		_place_failures += 1
		printerr("  placement failed: %s at (%d, %d) story %d %s (%s)" %
				[item_id, tile.x, tile.y, story, orientation, _last_place_reason])


func _on_placement_failed(reason: String) -> void:
	_last_place_reason = reason


# Move within the current story (presentation updates ride the manager's
# physics sync, exactly as in live play).
func _move(tile: Vector2i) -> void:
	_player.global_position = Vector2(tile) * float(BuildingManager.TILE_SIZE) + Vector2(16.0, 16.0)


# Teleport to a tile on a specific story.
func _go(tile: Vector2i, story: int) -> void:
	_move(tile)
	_buildings.set_active_story(story)


func _settle(frames: int) -> void:
	for _frame in range(frames):
		await process_frame


func _run() -> void:
	# Let the survival boot pipeline (world gen, chunks, UI) settle.
	for _frame in range(10):
		await process_frame
	_main.flush_pending_chunk_visuals()
	_world_generator = _main.get_node("WorldGenerator") as WorldGenerator
	_buildings = _main.get_node("BuildingManager") as BuildingManager
	_weather = _main.get_node("WeatherSystem") as WeatherSystem
	_day_night = _main.get_node("DayNightCycle") as DayNightCycle
	_player = _main.get_node("Player") as Player
	_hud = _main.get_node("HUD") as HUD
	_check(_world_generator != null and _buildings != null and _weather != null
			and _day_night != null and _player != null and _hud != null,
			"The presentation test finds every node it needs")
	if _buildings == null or _player == null or _hud == null or _world_generator == null:
		_finish()
		return
	_buildings.placement_failed.connect(_on_placement_failed)
	# Fixed daytime clear-weather conditions: this test is about the cutaway
	# view, not about the weather systems it shares the presentation tick with.
	_day_night.set_time(9.0)
	_weather.set_weather(WeatherSystem.WeatherType.CLEAR)
	_player.inventory.set_max_weight(1000.0)
	_player.inventory.add_item("wooden_foundation", 6)
	_player.inventory.add_item("wooden_floor", 8)
	_player.inventory.add_item("wooden_stairs", 2)
	_player.inventory.add_item("wooden_wall", 20)
	_player.inventory.add_item("wooden_roof", 7)
	_player.inventory.add_item("wall_torch", 3)
	_player.inventory.add_item("wall_lantern", 1)

	_origin = _find_clear_origin()
	_check(_origin != NO_ORIGIN,
			"The spiral search found a 6x5 block whose tiles all pass the placement water predicate")
	if _origin == NO_ORIGIN:
		_finish()
		return

	var _baseline_records := _buildings.get_building_count()
	_place_fixture()
	_check(_place_failures == 0, "All 42 fixture parts place on their support chains")
	_check(_buildings.get_building_count() == _baseline_records + 42,
			"The occupancy index accounts for every placed record")

	_resolve_fixture_records()
	_check(_roof_top != null and _roof_mid != null and _floor_upper != null
			and _floor_lower != null and _foundation != null and _pavilion_roof != null
			and _pavilion_room_floor != null and _pavilion_deck_floor != null
			and _house_south_wall_s1 != null and _house_south_wall_s2 != null
			and _pavilion_north_wall != null and _pavilion_east_wall != null,
			"Every fixture record resolves through the occupancy index")
	if _roof_top == null or _pavilion_roof == null or _pavilion_deck_floor == null:
		_finish()
		return

	# Every scenario awaits its own settles; scenario 1 must be awaited too,
	# or its remaining checks would race scenario 2's player moves.
	await _test_outdoor_exterior_view()
	await _test_interior_cutaway()
	await _test_upper_story_exit()
	await _test_unroofed_deck()
	await _test_wall_fixtures()
	_finish()


func _find_clear_origin() -> Vector2i:
	var seed_tile := Vector2i(
			int(floor(_player.global_position.x / float(BuildingManager.TILE_SIZE))),
			int(floor(_player.global_position.y / float(BuildingManager.TILE_SIZE))))
	for radius in range(0, 49):
		var corner := seed_tile - Vector2i(radius, radius)
		var candidates: Array[Vector2i] = []
		if radius == 0:
			candidates.append(corner)
		else:
			for dx in range(2 * radius + 1):
				candidates.append(corner + Vector2i(dx, 0))
				candidates.append(corner + Vector2i(dx, 2 * radius))
			for dy in range(1, 2 * radius):
				candidates.append(corner + Vector2i(0, dy))
				candidates.append(corner + Vector2i(2 * radius, dy))
		for candidate in candidates:
			if _block_is_clear(candidate):
				return candidate
	return NO_ORIGIN


func _block_is_clear(origin: Vector2i) -> bool:
	# Use the manager's own foundation predicate (pixel-centred water-class
	# query) for every tile the fixture claims, so the search and the
	# placement validator can never disagree.
	for dy in range(5):
		for dx in range(6):
			if not _buildings._terrain_is_buildable(origin + Vector2i(dx, dy)):
				return false
	for dy in range(5):
		for dx in range(6):
			var tile := origin + Vector2i(dx, dy)
			for story in range(BuildingRecord.MAX_STORIES):
				if _buildings.get_building_at(tile, story) != null:
					return false
	return true


func _place_fixture() -> void:
	# House: 2x2 footprint on stories 0..3, stairwell at the (0,0) corner.
	_place("wooden_foundation", _origin)
	_place("wooden_foundation", _origin + Vector2i(1, 0))
	_place("wooden_foundation", _origin + Vector2i(0, 1))
	_place("wooden_foundation", _origin + Vector2i(1, 1))
	# Story 1: the stair goes in first, then the three floored tiles, then
	# the perimeter walls (each story's parts rest on the one below).
	_place("wooden_stairs", _origin, 1)
	_place("wooden_floor", _origin + Vector2i(1, 0), 1)
	_place("wooden_floor", _origin + Vector2i(0, 1), 1)
	_place("wooden_floor", _origin + Vector2i(1, 1), 1)
	_place("wooden_wall", _origin, 1, "north")
	_place("wooden_wall", _origin + Vector2i(1, 0), 1, "north")
	_place("wooden_wall", _origin + Vector2i(0, 1), 1, "south")
	_place("wooden_wall", _origin + Vector2i(1, 1), 1, "south")
	_place("wooden_wall", _origin, 1, "west")
	_place("wooden_wall", _origin + Vector2i(0, 1), 1, "west")
	_place("wooden_wall", _origin + Vector2i(1, 0), 1, "east")
	_place("wooden_wall", _origin + Vector2i(1, 1), 1, "east")
	# Story 2: roof + floor + walls over the three floored tiles; the
	# stairwell at (0,0) stays open (its floor key is reserved by the stair,
	# so nothing else may claim it).
	_place("wooden_roof", _origin + Vector2i(1, 0), 2)
	_place("wooden_roof", _origin + Vector2i(0, 1), 2)
	_place("wooden_roof", _origin + Vector2i(1, 1), 2)
	_place("wooden_floor", _origin + Vector2i(1, 0), 2)
	_place("wooden_floor", _origin + Vector2i(0, 1), 2)
	_place("wooden_floor", _origin + Vector2i(1, 1), 2)
	_place("wooden_wall", _origin, 2, "north")
	_place("wooden_wall", _origin + Vector2i(1, 0), 2, "north")
	_place("wooden_wall", _origin + Vector2i(0, 1), 2, "south")
	_place("wooden_wall", _origin + Vector2i(1, 1), 2, "south")
	_place("wooden_wall", _origin, 2, "west")
	_place("wooden_wall", _origin + Vector2i(0, 1), 2, "west")
	_place("wooden_wall", _origin + Vector2i(1, 0), 2, "east")
	_place("wooden_wall", _origin + Vector2i(1, 1), 2, "east")
	# Story 3: the top roof.
	_place("wooden_roof", _origin + Vector2i(1, 0), 3)
	_place("wooden_roof", _origin + Vector2i(0, 1), 3)
	_place("wooden_roof", _origin + Vector2i(1, 1), 3)
	# Pavilion: a 1x1 enclosed room at (4,0) with a 1x1 open deck at (5,0).
	# The room is fully walled (its east wall is the room/deck divider) and
	# roofed; the deck has a floor but no roof and no west wall of its own.
	_place("wooden_foundation", _origin + Vector2i(4, 0))
	_place("wooden_foundation", _origin + Vector2i(5, 0))
	_place("wooden_floor", _origin + Vector2i(4, 0), 1)
	_place("wooden_floor", _origin + Vector2i(5, 0), 1)
	_place("wooden_wall", _origin + Vector2i(4, 0), 1, "north")
	_place("wooden_wall", _origin + Vector2i(4, 0), 1, "south")
	_place("wooden_wall", _origin + Vector2i(4, 0), 1, "west")
	_place("wooden_wall", _origin + Vector2i(4, 0), 1, "east")
	_place("wooden_roof", _origin + Vector2i(4, 0), 2)


func _resolve_fixture_records() -> void:
	_roof_top = _buildings.get_record_at(_origin + Vector2i(1, 0), 3, "overhead")
	_roof_mid = _buildings.get_record_at(_origin + Vector2i(1, 0), 2, "overhead")
	_floor_upper = _buildings.get_record_at(_origin + Vector2i(1, 1), 2, "floor")
	_floor_lower = _buildings.get_record_at(_origin + Vector2i(1, 1), 1, "floor")
	_foundation = _buildings.get_record_at(_origin, 0, "ground")
	_pavilion_roof = _buildings.get_record_at(_origin + Vector2i(4, 0), 2, "overhead")
	_pavilion_room_floor = _buildings.get_record_at(_origin + Vector2i(4, 0), 1, "floor")
	_pavilion_deck_floor = _buildings.get_record_at(_origin + Vector2i(5, 0), 1, "floor")
	# Resolved with the same tile + orientation the wall was placed with; the
	# canonical key normalises either side of a shared edge to the same key.
	_house_south_wall_s1 = _buildings.get_record_at(_origin + Vector2i(0, 1), 1, "edge", "south")
	_house_south_wall_s2 = _buildings.get_record_at(_origin + Vector2i(0, 1), 2, "edge", "south")
	_pavilion_north_wall = _buildings.get_record_at(_origin + Vector2i(4, 0), 1, "edge", "north")
	_pavilion_east_wall = _buildings.get_record_at(_origin + Vector2i(4, 0), 1, "edge", "east")


func _test_outdoor_exterior_view() -> void:
	# G1: standing in the open yard, every structure presents its exterior
	# shell — roofs and exterior-facing walls in full colour on ALL stories,
	# the mass (floors, foundations) ghosted. A freestanding wall is shell;
	# an interior partition (both sides built up) is not.
	_go(_origin + _outdoor, 0)
	# A fresh teleport can transiently report the previous position before the
	# manager's outdoor reset + presentation sync converge; two frames is
	# enough for that to settle on every seed observed.
	await _settle(2)
	_main._update_world_presentation(0.2)
	_check(not _buildings.is_player_sheltered(), "Baseline: the player in the open yard is not sheltered")
	_check(_buildings.active_story == 0, "Baseline: the active story is the ground level outdoors")
	_check(_roof_top.node.visible and _roof_top.node.modulate.a == 1.0,
			"Outside, the house's top roof (story 3) renders in full colour")
	_check(_roof_mid.node.visible and _roof_mid.node.modulate.a == 1.0,
			"Outside, the house's story-2 roof ALSO renders in full colour — the shell shows every story, not just the topmost")
	_check(absf(_floor_upper.node.modulate.a - 0.25) < 0.001,
			"Outside, the house's interior floor ghosts — mass, not skin")
	_check(absf(_floor_lower.node.modulate.a - 0.25) < 0.001,
			"Outside, the house's lower floor ghosts")
	_check(absf(_foundation.node.modulate.a - 0.25) < 0.001,
			"Outside, the house's ground foundations ghost")
	_check(_house_south_wall_s1.node.visible and _house_south_wall_s1.node.modulate.a == 1.0,
			"Outside, the house's story-1 exterior wall renders in full colour")
	_check(_house_south_wall_s2.node.visible and _house_south_wall_s2.node.modulate.a == 1.0,
			"Outside, the house's story-2 exterior wall renders in full colour — a 3-story house reads as 3 stories")
	_check(_pavilion_roof.node.visible and _pavilion_roof.node.modulate.a == 1.0,
			"Outside, the pavilion's roof renders in full colour")
	_check(_pavilion_north_wall.node.visible and _pavilion_north_wall.node.modulate.a == 1.0,
			"Outside, the pavilion's exterior-facing wall renders in full colour (shell)")
	_check(absf(_pavilion_east_wall.node.modulate.a - 0.25) < 0.001,
			"Outside, the pavilion's interior partition (the room/deck divider) ghosts — both sides are built up")
	_check(absf(_pavilion_room_floor.node.modulate.a - 0.25) < 0.001,
			"Outside, the pavilion's room floor ghosts")
	_check(absf(_pavilion_deck_floor.node.modulate.a - 0.25) < 0.001,
			"Outside, the roofless deck's floor ghosts — mass never impersonates a roof")
	# Per-story visual offset: each story's visuals are shifted up-left by one
	# EXTERIOR_STORY_OFFSET step per story, so the facade reads as stacked.
	_check(_roof_top.node.visual_offset == Building.EXTERIOR_STORY_OFFSET * 3,
			"Outside, the story-3 roof is visually offset by three EXTERIOR_STORY_OFFSET steps")
	_check(_floor_lower.node.visual_offset == Building.EXTERIOR_STORY_OFFSET * 1,
			"Outside, the story-1 floor is visually offset by one EXTERIOR_STORY_OFFSET step")
	_check(_foundation.node.visual_offset == Vector2.ZERO,
			"Outside, the ground story has no visual offset")
	var info_label: Label = _hud.get("_info_label")
	_check(info_label != null and not str(info_label.text).contains("Sheltered"),
			"Outside, the HUD does not claim the player is sheltered")


func _test_interior_cutaway() -> void:
	# G3 + G4: entering the house opens its interior cutaway scoped to the
	# structure the player stands in — the level they are on in full colour,
	# EVERY other story of that structure hidden (the level below is not a
	# ghost, it is gone) — while the separate pavilion keeps its exterior
	# shell.
	_go(_origin + Vector2i(1, 1), 2)
	await _settle(1)
	_main._update_world_presentation(0.2)
	_check(_buildings.is_player_sheltered(), "Inside the upper room the player is sheltered")
	_check(not _roof_top.node.visible,
			"Inside, the roof above the room (story 3) is hidden — not a ghost")
	_check(_roof_mid.node.visible and absf(_roof_mid.node.modulate.a - 0.4) < 0.001,
			"Inside, the room's own overhead (story 2) stays as the cutaway fade")
	_check(_floor_upper.node.modulate.a == 1.0,
			"Inside, the level the player is on (story 2) renders in full colour")
	_check(not _floor_lower.node.visible,
			"Inside, the story below the player is HIDDEN — the level below is not a semi-transparent ghost")
	var info_label: Label = _hud.get("_info_label")
	_check(info_label != null and str(info_label.text).contains("Sheltered"),
			"Inside, the HUD info line shows Sheltered")
	_check(info_label != null and str(info_label.text).contains("Floor L3"),
			"Inside the upper room, the HUD names the level the player is on (Floor L3)")
	# G4: the pavilion is a separate connected structure, so it keeps its
	# exterior shell — its roof and exterior walls show, its partition ghosts.
	_check(_pavilion_roof.node.visible and _pavilion_roof.node.modulate.a == 1.0,
			"Inside the house, the separate pavilion keeps its exterior shell (roof in full colour)")
	_check(_pavilion_north_wall.node.visible and _pavilion_north_wall.node.modulate.a == 1.0,
			"Inside the house, the pavilion's exterior wall still renders in full colour (its own shell)")
	_check(absf(_pavilion_east_wall.node.modulate.a - 0.25) < 0.001,
			"Inside the house, the pavilion's interior partition still ghosts")
	_check(absf(_pavilion_deck_floor.node.modulate.a - 0.25) < 0.001,
			"Inside the house, the pavilion's deck floor still ghosts (mass, exterior)")
	# The same cutaway holds on the lower room: its ceiling is the story-2 roof.
	_go(_origin + Vector2i(1, 1), 1)
	await _settle(1)
	_main._update_world_presentation(0.2)
	_check(_buildings.is_player_sheltered(), "Inside the lower room the player is sheltered too")
	_check(not _roof_mid.node.visible,
			"Standing on the lower level, the roof above it (the upper room) is hidden")
	_check(_floor_lower.node.modulate.a == 1.0,
			"Standing on the lower level, that level renders in full colour")
	_check(_pavilion_roof.node.visible and _pavilion_roof.node.modulate.a == 1.0,
			"On the lower level the separate pavilion still keeps its exterior shell")
	_check(info_label != null and str(info_label.text).contains("Floor L2"),
			"On the lower level, the HUD names Floor L2")


func _test_upper_story_exit() -> void:
	# G1/G3 return path: leaving the house from an upper story returns to the
	# ground level and the exterior shell — except while crossing a stair
	# connector, where the traversal owns the story and the outdoor reset
	# stands down.
	_go(_origin + Vector2i(1, 1), 2)
	await _settle(1)
	_check(_buildings.active_story == 2, "Setup: the player is on the upper story")
	# Walk out into the yard from the upper story (no floor underfoot there).
	_move(_origin + _outdoor)
	await _settle(3)
	_check(_buildings.active_story == 0,
			"Leaving the house from the upper story returns the active story to the ground level")
	_check(_player.collision_mask == 1 | BuildingRecord.STORY_COLLISION_BASE,
			"The player's collision filtering follows the ground story back")
	_main._update_world_presentation(0.2)
	var info_label: Label = _hud.get("_info_label")
	_check(info_label != null and not str(info_label.text).contains("Sheltered")
			and not str(info_label.text).contains("Floor L"),
			"Back in the yard, the HUD drops both the floor label and Sheltered")
	_check(_roof_top.node.visible and _roof_top.node.modulate.a == 1.0,
			"Back in the yard, the exterior shell is restored — the top roof in full colour")
	_check(_roof_mid.node.visible and _roof_mid.node.modulate.a == 1.0,
			"Back in the yard, the story-2 roof is part of the shell and shows too")
	await _settle(2)
	_check(_buildings.active_story == 0, "The ground level holds (no story flip-flop)")

	# Crossing a stair is the exception: the traversal owns the story while
	# the player is in the stairwell, so the outdoor reset must not fire
	# mid-crossing. The stairwell tile has no floor of its own, which makes
	# the connector exemption the only thing keeping the story at 1.
	_go(_origin + Vector2i(1, 1), 2)
	await _settle(1)
	_check(_buildings.is_player_sheltered(), "Setup: the player is sheltered in the upper room again")
	_check(not _buildings.has_layer_covering(_origin, 2, "floor"),
			"Setup: the stairwell opening really has no floor over it (the reset would fire without the exemption)")
	_move(_origin)
	await _settle(3)
	_check(_buildings.active_story == 1,
			"Crossing the stair between the levels, the traversal story holds - the outdoor reset stands down")
	_check(_buildings.get("_connector_under_player") != null,
			"The connector record is tracked while the player stands in the stairwell")
	await _settle(2)
	_check(_buildings.active_story == 1,
			"The stairwell does not drop to the ground while the player stands on the stair")
	# Step off the stair back into the room on the lower story.
	_go(_origin + Vector2i(1, 1), 1)
	await _settle(3)
	_check(_buildings.active_story == 1 and _buildings.is_player_sheltered(),
			"Stepping off the stair into the lower room lands on that level, sheltered")
	_check(_buildings.get("_connector_under_player") == null,
			"Leaving the stair clears the connector state for the next crossing")


func _test_unroofed_deck() -> void:
	# G1 + the outdoor reset: an indoor spot without a roof (the open deck)
	# reads as outdoors — the roof shows again (it is shell) — but the floor
	# underfoot keeps the player's story. The deck floor itself is mass, so
	# it ghosts rather than impersonating a roof.
	_go(_origin + Vector2i(4, 0), 1)
	await _settle(1)
	_main._update_world_presentation(0.2)
	_check(_buildings.is_player_sheltered(), "Inside the pavilion's roofed room the player is sheltered")
	_check(not _pavilion_roof.node.visible,
			"Inside the room, its roof is hidden the way the interior cutaway works")
	# Step out of the room onto the open deck: same story, no roof overhead.
	_move(_origin + Vector2i(5, 0))
	await _settle(3)
	_check(not _buildings.is_player_sheltered(),
			"On the open deck the enclosure is broken (the sky is open) - not sheltered")
	_check(_pavilion_roof.node.visible and _pavilion_roof.node.modulate.a == 1.0,
			"The roof shows again the moment the player steps onto the unroofed deck (it is shell)")
	_check(_buildings.active_story == 1,
			"The deck has a floor underfoot, so the player keeps their story - no snap back to the ground")
	_check(absf(_pavilion_deck_floor.node.modulate.a - 0.25) < 0.001,
			"On the deck, its floor ghosts — from outside, mass is not skin and never impersonates a roof")
	_check(absf(_pavilion_room_floor.node.modulate.a - 0.25) < 0.001,
			"From the deck, the roofed room's floor ghosts (mass, exterior)")
	_check(_pavilion_north_wall.node.visible and _pavilion_north_wall.node.modulate.a == 1.0,
			"From the deck, the pavilion's exterior wall renders in full colour")
	_check(absf(_pavilion_east_wall.node.modulate.a - 0.25) < 0.001,
			"From the deck, the pavilion's interior partition ghosts")
	_main._update_world_presentation(0.2)
	var info_label: Label = _hud.get("_info_label")
	_check(info_label != null and not str(info_label.text).contains("Sheltered"),
			"On the open deck the HUD drops Sheltered (the deck reads as outdoors)")
	_check(info_label != null and str(info_label.text).contains("Floor L2"),
			"On the deck the HUD still names the level the player stands on (Floor L2)")


func _test_wall_fixtures() -> void:
	# G2: wall fixtures (torches, exterior lanterns) mount on a wall, door,
	# or window edge that faces OUTSIDE the built structure. A fixture on an
	# interior partition is rejected; a fixture in open air is rejected; and
	# demolishing the wall a fixture is mounted on removes the fixture too.
	# The player stands in the open yard so the whole scene is in exterior
	# mode and a freshly mounted fixture reads at full colour.
	_go(_origin + _outdoor, 0)
	await _settle(2)
	_main._update_world_presentation(0.2)
	_check(not _buildings.is_player_sheltered(), "Baseline: the player is in the open yard (exterior mode)")

	# (a) A torch on the house's story-1 south exterior wall — the edge faces
	# the open yard, so it mounts.
	_last_place_reason = ""
	var mounted_s1 := _buildings.place_record("wall_torch", _origin + Vector2i(0, 1), _player.inventory, 1, "south")
	_check(mounted_s1, "A wall torch mounts on the house's story-1 south exterior wall (%s)" % _last_place_reason)
	var torch_s1 := _buildings.get_record_at(_origin + Vector2i(0, 1), 1, "fixture", "south")
	_check(torch_s1 != null and torch_s1.node != null,
			"The mounted torch resolves through the fixture key namespace (separate from the wall)")
	_check(torch_s1 != null and torch_s1.node.visible and torch_s1.node.modulate.a == 1.0,
			"Outside, a mounted torch on the exterior wall renders in full colour (it is shell)")
	_check(torch_s1 != null and torch_s1.node.has_local_light(),
			"A mounted torch carries its own local light")

	# (b) A torch on an UPPER story (story 2) — upper-story fixtures work.
	_last_place_reason = ""
	var mounted_s2 := _buildings.place_record("wall_torch", _origin, _player.inventory, 2, "north")
	_check(mounted_s2, "A wall torch mounts on the house's story-2 north exterior wall (%s)" % _last_place_reason)
	var torch_s2 := _buildings.get_record_at(_origin, 2, "fixture", "north")
	_check(torch_s2 != null and torch_s2.node != null and torch_s2.node.modulate.a == 1.0,
			"An upper-story torch mounts and renders in full colour from outside")

	# (c) A lantern on the pavilion's EAST wall — that wall is an interior
	# partition (the room/deck divider, both sides built up), so it is
	# rejected: fixtures mount on the OUTSIDE only.
	_last_place_reason = ""
	var mounted_partition := _buildings.place_record("wall_lantern", _origin + Vector2i(4, 0), _player.inventory, 1, "east")
	_check(not mounted_partition, "A lantern is REJECTED on the pavilion's interior partition")
	_check(_last_place_reason == "That wall faces inside the building — fixtures mount on its outside",
			"The partition rejection names the inside-facing wall exactly")
	_check(_buildings.get_record_at(_origin + Vector2i(4, 0), 1, "fixture", "east") == null,
			"No fixture record exists on the partition after the rejection")

	# (d) A torch in open air (no wall on that edge) — rejected: fixtures
	# mount on a wall, door, or window edge.
	_last_place_reason = ""
	var mounted_open := _buildings.place_record("wall_torch", _origin + _outdoor, _player.inventory, 0, "south")
	_check(not mounted_open, "A torch is REJECTED in open air (no wall on that edge)")
	_check(_last_place_reason == "Wall fixtures mount on a wall, door, or window edge",
			"The open-air rejection names the missing wall edge")

	# (e) Demolishing the wall the story-1 torch is mounted on removes the
	# torch with it (refunded): the edge key is freed, so the mounted fixture
	# cascades.
	_check(torch_s1 != null and _buildings.get_record_at(_origin + Vector2i(0, 1), 1, "edge", "south") != null,
			"Setup: the story-1 torch is mounted on a wall that still exists")
	_buildings._remove_record(_house_south_wall_s1, true)
	await _settle(1)
	_check(_buildings.get_record_at(_origin + Vector2i(0, 1), 1, "edge", "south") == null,
			"Demolishing the wall removes the wall")
	_check(_buildings.get_record_at(_origin + Vector2i(0, 1), 1, "fixture", "south") == null,
			"Demolishing the wall cascades: the torch mounted on it is removed with it")
	_check(_buildings.get_record_at(_origin, 2, "fixture", "north") != null,
			"The unrelated upper-story torch on the house's north wall survives the story-1 demolition")


func _finish() -> void:
	if _main != null:
		_main.queue_free()
	await process_frame
	GameSession.set_game_mode(GameSession.MODE_SURVIVAL)
	print("Presentation failures: %d (%d checks)" % [_failures, _checks])
	quit(_failures)
