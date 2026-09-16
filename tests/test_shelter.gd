## M11 shelter coverage: a room with a floor underfoot, a perimeter
## (walls, doors, or windows) sealing all four directions, and a roof one
## story up is indoors. Indoors, every cold source is cancelled — snow
## weather's chill and the arctic-night biome chill — and any slow/frozen
## status the weather already applied is cleared, so the player warms up.
## The options "Ignore environmental effects" toggle is covered too: it
## grants the same immunity everywhere (and clears what the weather
## already applied) without a room, and it is restored before the arctic
## leg so that leg still tests the option-off behaviour.
##
## The arctic-night leg swaps main's WorldGenerator member for a data-shaped
## stand-in: the sandbox yard's seed is random per boot, and the sandbox
## biome data never yields arctic tiles in the compact yard, so a real arctic
## world cannot be requested. The stand-in is a WorldGenerator subclass whose
## data answers "arctic" everywhere — exactly the data condition main's night
## branch reads. Only that per-frame branch consumes the swapped member: the
## generator has no _ready or _process, and the chunk/weather/building
## systems hold their own references taken at startup.
##
## The test drives main's own presentation tick directly for determinism
## instead of sleeping for the 0.2 s cadence, and counts failures on class
## members (GDScript 4 lambdas capture locals by value, so a lambda-local
## counter could never trip a check).
##
## Run: godot --headless --path . --script tests/test_shelter.gd
extends SceneTree

## Godot 4.7 exposes most KEY_* punctuation constants to GDScript but not
## the bracket pair, so the physical key codes (the same values the input
## map binds) are named here instead.
const KEY_BRACKET_LEFT := 91
const KEY_BRACKET_RIGHT := 93

var _main: Node = null
var _failures := 0
var _place_failures := 0

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
	var buildings: BuildingManager = _main.get_node("BuildingManager") as BuildingManager
	var weather_system: WeatherSystem = _main.get_node("WeatherSystem") as WeatherSystem
	var day_night: DayNightCycle = _main.get_node("DayNightCycle") as DayNightCycle
	var status_effects: StatusEffectSystem = _main.get_node("StatusEffectSystem") as StatusEffectSystem
	var player: Player = _main.get_node("Player") as Player
	var hud: HUD = _main.get_node("HUD") as HUD
	_check(world_generator != null and buildings != null and weather_system != null
			and day_night != null and status_effects != null and player != null and hud != null,
			"The shelter test finds every node it needs")
	if buildings == null or weather_system == null or status_effects == null \
			or player == null or hud == null or world_generator == null:
		_finish()
		return
	# Fix the sandbox clock at day for the weather legs; night is set
	# explicitly for the arctic leg.
	_main.set_sandbox_time(9.0)
	weather_system.set_weather(WeatherSystem.WeatherType.CLEAR)

	# --- Key bindings: the help text now says [ and ], and those really are
	# the bound keys. The old "[ / ]" text pointed at a slash that no action
	# uses, which is why editing a different level looked broken.
	_check(_action_keycode("build_level_down") == KEY_BRACKET_LEFT,
			"The story-down help key [ is actually bound to build_level_down")
	_check(_action_keycode("build_level_up") == KEY_BRACKET_RIGHT,
			"The story-up help key ] is actually bound to build_level_up")
	var slash_bound := ""
	for action in InputMap.get_actions():
		for event in InputMap.action_get_events(str(action)):
			if event is InputEventKey and (event as InputEventKey).keycode == KEY_SLASH:
				slash_bound = str(action)
	_check(slash_bound.is_empty(), "No input action is bound to the slash key the old help text promised")

	# --- Enclosure rules. Six rooms on the all-land row y=0, four tiles
	# apart so no seal walk ever crosses a room boundary:
	#   A: a fully enclosed 2x2 room                        -> sheltered
	#   B: a walled 1x1 room without a roof                 -> not, until the roof is built
	#   C: a walled 1x1 room with the north side open       -> not
	#   D: a 1x1 room sealed by four doors                  -> sheltered
	#   E: stacked foundations (no floor part) and a roof   -> sheltered (a foundation is a built floor surface)
	#   F: a GROUND-LEVEL foundation house walked at story 0 -> sheltered
	#   G: a two-story house; on the stair landing (the reserved floor
	#      opening) the stair underfoot is the surface      -> sheltered
	var room_a := Vector2i(6, 0)
	var room_b := Vector2i(12, 0)
	var room_c := Vector2i(16, 0)
	var room_d := Vector2i(20, 0)
	var room_e := Vector2i(24, 0)
	var room_f := Vector2i(28, 0)
	var room_g := Vector2i(32, 0)
	player.inventory.add_item("wooden_foundation", 16)
	player.inventory.add_item("wooden_floor", 12)
	player.inventory.add_item("wooden_wall", 40)
	player.inventory.add_item("wooden_door", 8)
	player.inventory.add_item("wooden_roof", 16)
	player.inventory.add_item("wooden_stairs", 4)
	player.inventory.add_item("wooden_door", 6)
	player.inventory.add_item("wooden_roof", 10)
	# Room A: the full enclosure on two stories.
	for offset in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		_place(buildings, player, "wooden_foundation", room_a + offset)
		_place(buildings, player, "wooden_floor", room_a + offset, 1)
		_place(buildings, player, "wooden_roof", room_a + offset, 2)
	_place(buildings, player, "wooden_wall", room_a, 1, "north")
	_place(buildings, player, "wooden_wall", room_a + Vector2i(1, 0), 1, "north")
	_place(buildings, player, "wooden_wall", room_a + Vector2i(0, 1), 1, "south")
	_place(buildings, player, "wooden_wall", room_a + Vector2i(1, 1), 1, "south")
	_place(buildings, player, "wooden_wall", room_a, 1, "west")
	_place(buildings, player, "wooden_wall", room_a + Vector2i(0, 1), 1, "west")
	_place(buildings, player, "wooden_wall", room_a + Vector2i(1, 0), 1, "east")
	_place(buildings, player, "wooden_wall", room_a + Vector2i(1, 1), 1, "east")
	# Room B: walled, floor, no roof (the roof is the second leg's subject).
	_place(buildings, player, "wooden_foundation", room_b)
	_place(buildings, player, "wooden_floor", room_b, 1)
	_place(buildings, player, "wooden_wall", room_b, 1, "north")
	_place(buildings, player, "wooden_wall", room_b, 1, "east")
	_place(buildings, player, "wooden_wall", room_b, 1, "south")
	_place(buildings, player, "wooden_wall", room_b, 1, "west")
	# Room C: west, south, and east walled; the north side stays open.
	_place(buildings, player, "wooden_foundation", room_c)
	_place(buildings, player, "wooden_floor", room_c, 1)
	_place(buildings, player, "wooden_wall", room_c, 1, "west")
	_place(buildings, player, "wooden_wall", room_c, 1, "south")
	_place(buildings, player, "wooden_wall", room_c, 1, "east")
	_place(buildings, player, "wooden_roof", room_c, 2)
	# Room D: the whole perimeter is doors.
	_place(buildings, player, "wooden_foundation", room_d)
	_place(buildings, player, "wooden_floor", room_d, 1)
	_place(buildings, player, "wooden_door", room_d, 1, "north")
	_place(buildings, player, "wooden_door", room_d, 1, "east")
	_place(buildings, player, "wooden_door", room_d, 1, "south")
	_place(buildings, player, "wooden_door", room_d, 1, "west")
	_place(buildings, player, "wooden_roof", room_d, 2)
	# Room E: a stacked foundation and a roof, but no floor part — the
	# foundation IS the built floor surface.
	_place(buildings, player, "wooden_foundation", room_e)
	_place(buildings, player, "wooden_foundation", room_e, 1)
	_place(buildings, player, "wooden_wall", room_e, 1, "north")
	_place(buildings, player, "wooden_wall", room_e, 1, "east")
	_place(buildings, player, "wooden_wall", room_e, 1, "south")
	_place(buildings, player, "wooden_wall", room_e, 1, "west")
	_place(buildings, player, "wooden_roof", room_e, 2)
	# Room F: the ground-level foundation house — foundation at story 0, a
	# door in the south wall, and a roof at story 1 (the shape a player's
	# first house takes; the roof must cut away when they walk in).
	_place(buildings, player, "wooden_foundation", room_f)
	_place(buildings, player, "wooden_wall", room_f, 0, "north")
	_place(buildings, player, "wooden_wall", room_f, 0, "east")
	_place(buildings, player, "wooden_wall", room_f, 0, "west")
	_place(buildings, player, "wooden_door", room_f, 0, "south")
	_place(buildings, player, "wooden_roof", room_f, 1)
	# Room G: the two-story house — the stairwell's landing story holds the
	# reserved floor OPENING instead of a floor part, so standing at the top
	# of the stairs must read the stair connector itself as the surface.
	var stair_tile := room_g + Vector2i(1, 0)
	for offset in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		_place(buildings, player, "wooden_foundation", room_g + offset)
	for offset in [Vector2i.ZERO, Vector2i(1, 0)]:
		_place(buildings, player, "wooden_wall", room_g + offset, 0, "north")
	for offset in [Vector2i.ZERO, Vector2i(0, 1)]:
		_place(buildings, player, "wooden_wall", room_g + offset, 0, "west")
	_place(buildings, player, "wooden_wall", room_g + Vector2i(1, 0), 0, "east")
	_place(buildings, player, "wooden_wall", room_g + Vector2i(1, 1), 0, "east")
	_place(buildings, player, "wooden_door", room_g + Vector2i(0, 1), 0, "south")
	_place(buildings, player, "wooden_wall", room_g + Vector2i(1, 1), 0, "south")
	_place(buildings, player, "wooden_stairs", stair_tile, 0)
	for offset in [Vector2i.ZERO, Vector2i(0, 1), Vector2i(1, 1)]:
		_place(buildings, player, "wooden_floor", room_g + offset, 1)
	for offset in [Vector2i.ZERO, Vector2i(1, 0)]:
		_place(buildings, player, "wooden_wall", room_g + offset, 1, "north")
	for offset in [Vector2i.ZERO, Vector2i(0, 1)]:
		_place(buildings, player, "wooden_wall", room_g + offset, 1, "west")
	_place(buildings, player, "wooden_wall", room_g + Vector2i(1, 0), 1, "east")
	_place(buildings, player, "wooden_wall", room_g + Vector2i(1, 1), 1, "east")
	_place(buildings, player, "wooden_wall", room_g + Vector2i(0, 1), 1, "south")
	_place(buildings, player, "wooden_wall", room_g + Vector2i(1, 1), 1, "south")
	for offset in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		_place(buildings, player, "wooden_roof", room_g + offset, 2)
	_check(_place_failures == 0, "Every room piece places on its support chain (foundations, floors, edges, roofs)")

	_teleport(player, room_a, 1, buildings)
	_check(buildings.is_player_sheltered(), "The enclosed 2x2 room shelters the player at its west corner")
	_teleport(player, room_a + Vector2i(1, 0), 1, buildings)
	_check(buildings.is_player_sheltered(), "The 2x2 room shelters the east corner too (the seal walk spans the footprint)")
	_teleport(player, room_a, 0, buildings)
	_check(not buildings.is_player_sheltered(),
			"Standing under the elevated room on its ground-story foundation is not indoors (story 0 has no walls or roof)")
	_teleport(player, room_b, 1, buildings)
	_check(not buildings.is_player_sheltered(),
			"A walled room without a roof does not shelter (the ceiling is part of the enclosure)")
	_place(buildings, player, "wooden_roof", room_b, 2)
	_check(_place_failures == 0, "The missing roof places on the walled story-1 floor")
	_check(buildings.is_player_sheltered(),
			"Placing the roof while the player stands inside flips shelter on (the cache invalidates on placement)")
	_teleport(player, room_c, 1, buildings)
	_check(not buildings.is_player_sheltered(),
			"A room with one open side does not shelter (the seal walk leaves through the gap)")
	_teleport(player, room_d, 1, buildings)
	_check(buildings.is_player_sheltered(), "Doors count as perimeter fixtures: four doors seal the room")
	_teleport(player, room_e, 1, buildings)
	_check(buildings.is_player_sheltered(),
			"A foundation is a built floor surface: the stacked-foundation room shelters like a floor-built one")
	_teleport(player, room_f, 0, buildings)
	_check(buildings.is_player_sheltered(),
			"The ground-level foundation house shelters the player walking on its foundation at story 0")
	var roof_f_record: BuildingRecord = buildings.get_record_at(room_f, 1, "overhead")
	_check(roof_f_record != null, "The foundation house's roof resolves for the cutaway check")
	if roof_f_record != null:
		_check(not roof_f_record.node.visible,
				"Inside the foundation house the roof cuts away instead of staying as an exterior shell")
	_teleport(player, stair_tile, 1, buildings)
	_check(buildings.is_player_sheltered(),
			"Standing on the stairwell landing (the reserved floor opening) shelters: the stair is the surface underfoot")
	var roof_g_record: BuildingRecord = buildings.get_record_at(stair_tile, 2, "overhead")
	_check(roof_g_record != null, "The two-story house's roof resolves for the landing cutaway check")
	if roof_g_record != null:
		_check(not roof_g_record.node.visible,
				"On the level-2 stair landing the roof cuts away instead of blocking the view")
	_teleport(player, room_g + Vector2i(0, 1), 1, buildings)
	_check(buildings.is_player_sheltered(),
			"Away from the stairs, the level-2 floor tiles shelter as usual")
	# Demolishing a wall while standing inside must break the shelter.
	_teleport(player, room_a, 1, buildings)
	_check(buildings.is_player_sheltered(), "Room A is still enclosed before the demolition check")
	var demo_wall := buildings.get_record_at(room_a, 1, "edge", "north")
	_check(demo_wall != null, "Room A's north wall resolves for demolition")
	if demo_wall != null:
		buildings.call("_remove_record", demo_wall, false)
	_check(not buildings.is_player_sheltered(),
			"Demolishing the north wall while standing inside breaks the shelter (the cache invalidates on removal)")

	# --- Snow weather: the cold source is live on the presentation tick.
	var outdoor := Vector2i(3, 2)
	weather_system.set_weather(WeatherSystem.WeatherType.SNOW)
	_teleport(player, outdoor, 0, buildings)
	_main._update_world_presentation(0.2)
	_check(status_effects.has_effect("frozen"), "Snow weather chills the player outdoors on the presentation tick")
	_teleport(player, room_b, 1, buildings)
	_check(buildings.is_player_sheltered(), "The roofed room is still a valid shelter for the weather leg")
	_main._update_world_presentation(0.2)
	_check(not status_effects.has_effect("frozen"), "Walking indoors clears the snow chill")
	_main._update_world_presentation(0.2)
	_check(not status_effects.has_effect("frozen"), "The chill does not re-apply while the player stays indoors")
	_teleport(player, outdoor, 0, buildings)
	_main._update_world_presentation(0.2)
	_check(status_effects.has_effect("frozen"), "Leaving the shelter re-applies the snow chill outdoors")

	# --- Storm: the wet-weather slow source, plus the warm-up clearing the
	# cold the previous weather left behind.
	weather_system.set_weather(WeatherSystem.WeatherType.STORM)
	_main._update_world_presentation(0.2)
	_check(status_effects.has_effect("slow"), "Storm weather slows the player outdoors")
	_check(status_effects.has_effect("frozen"), "The snow chill persists into the storm outdoors (a storm does not thaw)")
	_teleport(player, room_b, 1, buildings)
	_main._update_world_presentation(0.2)
	_check(not status_effects.has_effect("slow") and not status_effects.has_effect("frozen"),
			"Indoors the room warms the player: the slow and the leftover freeze are both cleared")
	_teleport(player, outdoor, 0, buildings)
	_main._update_world_presentation(0.2)
	_check(status_effects.has_effect("slow") and not status_effects.has_effect("frozen"),
			"Back outdoors the storm slows again, and only the storm's own effect is applied")

	# --- Options: "Ignore environmental effects" — the character always
	# moves normally. Cold sources stop applying, the chill the weather
	# already applied is cleared, and the weather's speed penalty drops.
	# The setting is restored before the arctic leg so that leg tests the
	# option-off behaviour it was written for.
	weather_system.set_weather(WeatherSystem.WeatherType.SNOW)
	_teleport(player, outdoor, 0, buildings)
	_main._update_world_presentation(0.2)
	_check(status_effects.has_effect("frozen"),
			"Baseline: with the option off, snow chills the outdoor player")
	var chilled_mult: float = player.call("_speed_multiplier")
	_check(chilled_mult < 1.0,
			"Baseline: with the option off, the snow speed penalty slows the player")
	SaveSystem.set_ignore_environment_effects(true)
	_main._update_world_presentation(0.2)
	_check(not status_effects.has_effect("frozen"),
			"Ignore environmental effects clears the chill in the middle of a snowfall")
	_main._update_world_presentation(0.2)
	_check(not status_effects.has_effect("frozen"),
			"The immunity persists on further ticks (no re-freeze while the option is on)")
	var immune_mult: float = player.call("_speed_multiplier")
	_check(immune_mult == 1.0,
			"Ignore environmental effects drops the weather speed penalty (normal movement)")
	SaveSystem.set_ignore_environment_effects(false)
	_main._update_world_presentation(0.2)
	_check(status_effects.has_effect("frozen"),
			"Switching the option back off re-applies the chill")
	weather_system.set_weather(WeatherSystem.WeatherType.CLEAR)

	# --- Arctic night: the biome chill source, via the data stand-in.
	# `world_generator` (fetched from the scene above) is the member's
	# current value, so it doubles as the restore target.
	weather_system.set_weather(WeatherSystem.WeatherType.CLEAR)
	var arctic_stub: WorldGenerator = _make_arctic_stub(world_generator, _main)
	_check(arctic_stub != null, "The arctic stand-in generator compiles and initialises from the sandbox seed")
	if arctic_stub == null:
		_finish()
		return
	_main.set("world_generator", arctic_stub)
	_main.set_sandbox_time(22.0)
	_check(day_night.is_nighttime(), "The sandbox clock is set to night for the arctic leg")
	_teleport(player, outdoor, 0, buildings)
	_main._update_world_presentation(0.2)
	_check(status_effects.has_effect("frozen"), "An arctic biome at night chills the player outdoors")
	_teleport(player, room_b, 1, buildings)
	_main._update_world_presentation(0.2)
	_check(not status_effects.has_effect("frozen"), "Indoors the arctic-night chill is cancelled too")
	_main._update_world_presentation(0.2)
	_check(not status_effects.has_effect("frozen"),
			"The arctic-night chill does not re-apply while the player stays indoors")
	_teleport(player, outdoor, 0, buildings)
	_main._update_world_presentation(0.2)
	_check(status_effects.has_effect("frozen"), "Back outdoors the arctic-night chill re-applies")
	# Restore the real generator and the day clock.
	_main.set("world_generator", world_generator)
	_main.set_sandbox_time(9.0)
	_check(_main.get("world_generator") == world_generator and not day_night.is_nighttime(),
			"The real generator and the day clock are restored after the arctic leg")
	_check(world_generator.get_biome_at_world(outdoor.x, outdoor.y) != "arctic",
			"The sandbox yard data yields no arctic at the outdoor tile (the leg above needed the stand-in)")

	# --- HUD: the info line names the sheltered state. The player walks
	# back indoors first: that is what clears the freeze the arctic leg left
	# behind (the outdoor branch only ever applies, never clears), and it is
	# the state the label must show.
	_teleport(player, room_b, 1, buildings)
	_main._update_world_presentation(0.2)
	var info_label: Label = hud.get("_info_label")
	_check(not status_effects.has_effect("frozen") and not status_effects.has_effect("slow"),
			"Back indoors under the real yard, the arctic leg's freeze is cleared")
	_check(info_label != null and str(info_label.text).contains("Sheltered"),
			"The HUD info line shows Sheltered while the player is indoors")
	_teleport(player, outdoor, 0, buildings)
	_main._update_world_presentation(0.2)
	_check(not status_effects.has_effect("frozen") and not status_effects.has_effect("slow"),
			"No cold source in the real yard re-chills the outdoor player by day")
	_check(not str(info_label.text).contains("Sheltered"),
			"The HUD info line drops Sheltered once the player is outdoors")

	# --- Sandbox parity: the sandbox exists to rehearse the real world, so
	# it shares survival's rules: an upper story without a floor underfoot
	# snaps the active story back to the ground, and the outdoor view shows
	# each structure's full exterior shell rather than an active-story
	# cutaway. The player is on the outdoor tile from the HUD leg (no floor
	# underfoot upstairs).
	var roof_b_record: BuildingRecord = buildings.get_record_at(room_b, 2, "overhead")
	var floor_b_record: BuildingRecord = buildings.get_record_at(room_b, 1, "floor")
	_check(roof_b_record != null and floor_b_record != null,
			"The sandbox-parity leg resolves room B's roof and floor")
	if roof_b_record != null and floor_b_record != null:
		var roof_b := roof_b_record.node
		var floor_b := floor_b_record.node
		_check(not buildings.has_layer_covering(outdoor, 2, "floor"),
				"Sandbox-parity precondition: the outdoor tile has no story-2 floor")
		buildings.set_active_story(2)
		buildings._update_outdoor_story_reset()
		_check(buildings.active_story == 0,
				"Sandbox parity: an upper story without a floor underfoot resets to the ground, like survival")
		_check(roof_b.visible and absf(roof_b.modulate.a - 1.0) < 0.001,
				"Sandbox parity: the outdoor view is the exterior shell (roof at full colour), not a cutaway")
		_check(floor_b.visible and absf(floor_b.modulate.a - 0.25) < 0.001,
				"Sandbox parity: interior mass ghosts at 25% under the exterior shell, like survival")
		# Back inside room B, the cutaway matches survival's interior view:
		# the story above hides outright, the level underfoot shows in full.
		_teleport(player, room_b, 1, buildings)
		_check(not roof_b.visible,
				"Sandbox parity: indoors, the ceiling above the player hides for the cutaway")
		_check(floor_b.visible and absf(floor_b.modulate.a - 1.0) < 0.001,
				"Sandbox parity: indoors, the level underfoot renders in full colour")
	_finish()

## Place one part, counting failures on the class member (see the header:
## lambda-captured locals cannot fail a check).
func _place(buildings: BuildingManager, player: Player, item_id: String, tile: Vector2i,
		story: int = 0, orientation: String = "") -> void:
	if not buildings.place_record(item_id, tile, player.inventory, story, orientation):
		_place_failures += 1
		printerr("  placement failed: %s at (%d, %d) story %d %s" % [item_id, tile.x, tile.y, story, orientation])

## Move the player to the centre of a tile and switch the active story
## (set_active_story preserves x/y, so the tile holds).
func _teleport(player: Player, tile: Vector2i, story: int, buildings: BuildingManager) -> void:
	player.global_position = Vector2(tile) * float(BuildingManager.TILE_SIZE) + Vector2(16.0, 16.0)
	buildings.set_active_story(story)

## Build the data stand-in: a WorldGenerator subclass whose biome data
## answers "arctic" everywhere, initialised from the sandbox's own seed and
## config so everything else behaves exactly like the real yard.
func _make_arctic_stub(source: WorldGenerator, main: Node) -> WorldGenerator:
	var stub_script := GDScript.new()
	stub_script.source_code = (
			"extends WorldGenerator\n"
			+ "func get_biome_at_world(world_x: int, world_y: int) -> String:\n"
			+ "\treturn \"arctic\"\n")
	stub_script.reload()
	if not stub_script.can_instantiate():
		return null
	var stub: WorldGenerator = stub_script.new()
	var seed := int(main.get("_world_seed"))
	stub.initialize(seed, source.get_configuration())
	return stub

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

func _finish() -> void:
	if _main != null:
		_main.queue_free()
	await process_frame
	GameSession.set_game_mode(GameSession.MODE_SURVIVAL)
	print("Shelter failures: %d" % _failures)
	quit(_failures)
