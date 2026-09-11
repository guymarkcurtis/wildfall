## Headless test harness for the Wildfall core loop.
##
## Run:
##   Godot_v4.6-stable --headless --path <project> --script tests/test_game.gd
##
## The main scene is added to the root FIRST, so Main._ready (and the whole
## boot pipeline: seed -> world generation -> chunk loading -> terrain ->
## resources -> UI) actually runs and is covered by these checks. Checks are
## deferred a few frames so Main._process (camera follow, chunk sync) has run.
##
## Exit code: 0 = all checks passed, N = N checks failed.
extends SceneTree

var _main: Node
var _frames: int = 0
var _passed: int = 0
var _failed: int = 0
var _done: bool = false
# Dynamic phases after the static checks:
# 0 -> panel starts hidden, press C      1 -> wait for panel to open, press C
# 2 -> wait for panel to close, walk     3 -> walk until far enough, check
# 4 -> free the tree, then quit
var _phase: int = 0
var _phase_frame: int = 0
var _crafted_press_sent: bool = false
var _walk_start: Vector2 = Vector2.ZERO

func _init() -> void:
	# Instantiate and attach first: the _ready chain runs synchronously on
	# add_child, so any boot-time crash surfaces immediately.
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)

## SceneTree script: _process returns true to stop the loop.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5 and not _done:
		_run_checks()
		_done = true
	if not _done:
		return false
	match _phase:
		0:
			var panel: Node = _main.get_node("HUD/CraftingPanel")
			_check(panel.visible == false, "Crafting panel starts hidden (does not cover the game)")
			Input.action_press("toggle_crafting")
			_phase = 1
			_phase_frame = _frames
		1:
			# The first press was sent at frame 5; the per-frame input flush
			# raises the "just pressed" edge on the NEXT frame, so polling
			# (with a timeout) instead of assuming a frame edge.
			var panel: Node = _main.get_node("HUD/CraftingPanel")
			if panel.visible == true:
				_check(true, "C key opens the crafting panel")
				# Release here: a second action_press in the same frame
				# would net out to "no state change" at the next flush, so
				# the release and the closing press must be separate frames.
				Input.action_release("toggle_crafting")
				_phase = 2
				_phase_frame = _frames
				_crafted_press_sent = false
			elif _frames > _phase_frame + 20:
				_check(false, "C key opens the crafting panel")
				_phase = 4
				_phase_frame = _frames
		2:
			# One frame after the release, send the second press so the input
			# flush sees a fresh press edge; then wait for the close.
			if not _crafted_press_sent:
				_crafted_press_sent = true
				Input.action_press("toggle_crafting")
				return false
			var panel: Node = _main.get_node("HUD/CraftingPanel")
			if panel.visible == false:
				_check(true, "Second C press closes the crafting panel again")
				Input.action_release("toggle_crafting")
				_walk_start = _main.get_node("Player").global_position
				(_main.get_node("Player") as Player).set_aim_locked(Vector2.RIGHT)
				Input.action_press("move_up")
				_phase = 3
				_phase_frame = _frames
			elif _frames > _phase_frame + 20:
				_check(false, "Second C press closes the crafting panel again")
				_phase = 4
				_phase_frame = _frames
		3:
			var pos: Vector2 = _main.get_node("Player").global_position
			if pos.x > _walk_start.x + 1050.0 or _frames > _phase_frame + 3600:
				_run_walk_checks(pos)
				Input.action_release("move_up")
				(_main.get_node("Player") as Player).clear_aim_lock()
				# Free a couple of frames later: queued frees flush at the
				# end of the frame, so exiting immediately would report
				# leaked instances.
				_phase = 4
				_phase_frame = _frames
		4:
			if _frames == _phase_frame + 1 and is_instance_valid(_main):
				_main.queue_free()
			elif _frames > _phase_frame + 2:
				print("\n%d passed, %d failed" % [_passed, _failed])
				quit(_failed if _failed > 0 else 0)
				return true
	return false

## Dynamic regression: walk 1050+ px (two real 512-px chunk boundaries) and
## verify the world stays under the player. With the old pixels/16 chunk
## math, the ground was already unloaded after ~64 px of walking.
func _run_walk_checks(pos: Vector2) -> void:
	var chunk_system: Node = _main.get_node("ChunkSystem")
	var terrain_renderer: Node = _main.get_node("TerrainRenderer")
	_check(pos.x > _walk_start.x + 1000.0, \
			"Player actually walked right (%.0f -> %.0f px)" % [_walk_start.x, pos.x])
	var nominal: Vector2i = chunk_system.get_player_chunk()
	_check(ChunkSystem.world_to_chunk_coords(pos) == nominal, \
			"ChunkSystem tracks the player's real chunk after walking (pos %s, nominal %s)" % [str(pos), str(nominal)])
	var feet: Vector2i = Vector2i(int(floor(pos.x / 32.0)), int(floor(pos.y / 32.0)))
	var feet_chunk: Vector2i = Vector2i(int(floor(feet.x / 16.0)), int(floor(feet.y / 16.0)))
	_check(chunk_system.has_chunk(feet_chunk), \
			"Chunk under the player's feet %s is still loaded after walking" % str(feet_chunk))
	# TileMapLayer 4.6 exposes get_cell_source_id (source id == tile id in
	# the renderer; -1 means "no cell"). has_cell is not part of the API here.
	_check(terrain_renderer.get_cell_source_id(feet) != -1, \
			"Terrain still rendered under the player's feet %s after walking (no vanishing ground)" % str(feet))

func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("[PASS] ", label)
	else:
		_failed += 1
		print("[FAIL] ", label)

func _run_checks() -> void:
	GameSession.set_game_mode(GameSession.MODE_SURVIVAL)
	var main: Node = _main
	var world_gen: Node = main.get_node_or_null("WorldGenerator")
	var chunk_system: Node = main.get_node_or_null("ChunkSystem")
	var terrain_renderer: Node = main.get_node_or_null("TerrainRenderer")
	var resource_spawner: Node = main.get_node_or_null("ResourceSpawner")
	var item_database: Node = main.get_node_or_null("ItemDatabase")
	var player: Node = main.get_node_or_null("Player")
	var camera_controller: Node = main.get_node_or_null("CameraController")
	var seed_input: Node = main.get_node_or_null("SeedInput")
	var hud: Node = main.get_node_or_null("HUD")
	var crafting_panel: Node = main.get_node_or_null("HUD/CraftingPanel")

	# --- 1. Required scene nodes -------------------------------------------
	_check(world_gen != null, "WorldGenerator node present")
	_check(chunk_system != null, "ChunkSystem node present")
	_check(terrain_renderer != null, "TerrainRenderer node present")
	_check(resource_spawner != null, "ResourceSpawner node present")
	_check(item_database != null, "ItemDatabase node present")
	_check(player != null, "Player node present")
	_check(camera_controller != null, "CameraController node present")
	_check(seed_input != null, "SeedInput node present")
	_check(hud != null, "HUD node present")
	if _failed > 0:
		return

	# --- 2. World generation -----------------------------------------------
	var chunk0: Dictionary = chunk_system.get_chunk(Vector2i(0, 0))
	_check(chunk0.size() > 0, "Chunk (0,0) generated with terrain data")
	# Chunk coordinates come from PIXEL positions (one chunk = 512 px) with
	# floor semantics: the pixel just left/above the origin belongs to
	# chunk (-1,0)/(0,-1) — exactly where the terrain renderer draws that
	# tile. (Regression guard: dividing pixels by 16 treated every 16 px as
	# a chunk boundary and unloaded the ground under the player while
	# walking — "the terrain disappears when I move".)
	_check(ChunkSystem.world_to_chunk_coords(Vector2(0, 0)) == Vector2i(0, 0), "chunk math: origin -> (0,0)")
	_check(ChunkSystem.world_to_chunk_coords(Vector2(511, 511)) == Vector2i(0, 0), "chunk math: last pixel of chunk (0,0) stays (0,0)")
	_check(ChunkSystem.world_to_chunk_coords(Vector2(512, 512)) == Vector2i(1, 1), "chunk math: first pixel of chunk (1,1) -> (1,1)")
	_check(ChunkSystem.world_to_chunk_coords(Vector2(-1, -1)) == Vector2i(-1, -1), "chunk math: negative pixels floor, never truncate")
	_check(ChunkSystem.chunk_coords_to_world_start(Vector2i(1, 0)) == Vector2i(16, 0), "chunk_coords_to_world_start(1,0) == (16,0)")
	var seen_biomes: Dictionary = {}
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			seen_biomes[world_gen.get_biome_at_world(dx * 16, dy * 16)] = true
	_check(seen_biomes.size() > 1, "Biome map is varied across the region (%d distinct biomes)" % seen_biomes.size())

	# --- 3. Terrain + resources --------------------------------------------
	_check(terrain_renderer.get_used_cells().size() > 0, "Terrain rendered for initial chunks (%d tiles)" % terrain_renderer.get_used_cells().size())
	_check(resource_spawner.get_all_resources().size() > 0, "Resources spawned in initial chunks")

	# --- 4. Item database + crafting panel (B10/B13) -----------------------
	_check(item_database.items.size() > 0, "Item database populated (%d items)" % item_database.items.size())
	_check(item_database.recipes.size() > 0, "Recipe database populated (%d recipes)" % item_database.recipes.size())
	var panel_recipes: Array = crafting_panel.recipes
	_check(panel_recipes.size() > 0, "Crafting panel shows recipes (%d)" % panel_recipes.size())
	var recipe_ids: Array = []
	for r in panel_recipes:
		recipe_ids.append(str(r.get("id", "")))
	_check("plank" in recipe_ids, "Live recipe 'plank' visible in crafting panel")
	_check("wooden_axe" in recipe_ids, "Live recipe 'wooden_axe' visible in crafting panel")
	# Phase 3 (creatures & hunting): creature drops (meat/fish/hide/feather/
	# bone) and plant drops (wheat/herb/mushroom), plus the new stone_brick
	# and flour recipes, close every obtainability gap — the panel must now
	# show the ENTIRE recipe database. Any recipe hidden from here on is a
	# new ghost (Main's obtainability filter is a safety net only).
	var total_recipes: int = item_database.recipes.size()
	_check(panel_recipes.size() == total_recipes,
		"Panel shows all %d recipes (no ghost recipes left in Phase 3)" % total_recipes)

	# --- 5. Camera follows the player (B2) ----------------------------------
	var cam_target: Vector2 = camera_controller.get_target()
	_check(cam_target != Vector2.ZERO, "Camera target set from player position")
	_check(camera_controller.position.distance_to(cam_target) < 60.0, \
			"Camera lerps toward the player over frames (pos %s, target %s)" % \
			[str(camera_controller.position), str(cam_target)])

	# --- 6. Seed editing (B1) ------------------------------------------------
	_check(InputMap.has_action("change_seed"), "change_seed input action exists (T key)")
	_check(seed_input.is_editing() == false, "Seed editor starts closed")
	var boot_seed: int = seed_input.get_seed()
	seed_input.start_editing()
	_check(seed_input.is_editing() == true, "start_editing() opens the editor")
	_check(seed_input.get_input_buffer() == str(boot_seed), "Editor buffer pre-filled with current seed")
	seed_input.cancel_editing()
	_check(seed_input.is_editing() == false, "cancel_editing() closes the editor")
	_check(seed_input.get_seed() == boot_seed, "Cancel keeps the original seed")

	# --- 7. Save / load roundtrip --------------------------------------------
	player.global_position = Vector2(123.0, -77.0)
	var ok_save: bool = main.call("save_game")
	_check(ok_save, "save_game() succeeds (player at %s)" % str(player.global_position))
	player.global_position = Vector2(50.0, 50.0)  # simulate drift away from saved position
	var ok_load: bool = main.call("load_game")
	_check(ok_load, "load_game() succeeds")
	_check(player.global_position.distance_to(Vector2(123.0, -77.0)) < 1.0, \
			"Player position restored from save (%s)" % str(player.global_position))

	# --- 8. Chunk unload / re-enter cycle (B3) --------------------------------
	# Full signal path: ChunkSystem.generate_chunk/unload_chunk -> Main handlers
	# -> ResourceSpawner (records) + TerrainRenderer (cells) + resource nodes.
	var far: Vector2i = Vector2i(10, 0)
	var res_before: int = resource_spawner.get_all_resources().size()
	chunk_system.generate_chunk(far)
	var res_after_gen: int = resource_spawner.get_all_resources().size()
	_check(res_after_gen > res_before, "Far chunk generates resources when loaded (+%d)" % (res_after_gen - res_before))
	var nodes_before: int = int(main.get("_resource_nodes").size())
	chunk_system.unload_chunk(far)
	var nodes_after: int = int(main.get("_resource_nodes").size())
	_check(nodes_after < nodes_before, "Unloading a chunk frees its resource nodes (%d -> %d)" % [nodes_before, nodes_after])
	_check(resource_spawner.get_all_resources().size() == res_before, "Spawner records cleared on chunk unload")
	chunk_system.generate_chunk(far)
	var res_reentered: int = resource_spawner.get_all_resources().size()
	_check(res_reentered == res_after_gen, \
			"Re-entering an unloaded chunk re-spawns the same resources (%d -> %d) (B3)" % [res_before, res_reentered])
	var nodes_reentered: int = int(main.get("_resource_nodes").size())
	_check(nodes_reentered > nodes_after, \
			"Re-entering an unloaded chunk recreates its resource nodes (%d -> %d)" % [nodes_after, nodes_reentered])

	# --- 9. Seed change regenerates the world (full loop) --------------------
	seed_input.set_seed(42)
	_check(int(main.get("_world_seed")) == 42, "set_seed(42) updates the world seed")
	_check(chunk_system.get_chunk(Vector2i(0, 0)).size() > 0, "World regenerated for new seed")
	var seed_label: String = str(hud.get_node("Overlay/SeedLabel").text)
	_check(seed_label.find("42") >= 0, "HUD seed label shows the new seed (%s)" % seed_label)

	# --- 10. Phase 3 remainder: camera, combat, world systems ---------------
	_check(InputMap.has_action("rotate_ccw"), "rotate_ccw input action exists")
	_check(InputMap.has_action("rotate_cw"), "rotate_cw input action exists")
	_check(InputMap.has_action("reset_view"), "reset_view input action exists")
	_check(InputMap.has_action("fire"), "fire input action exists")
	_check(InputMap.has_action("toggle_build"), "toggle_build input action exists")
	var camera: CameraController = camera_controller as CameraController
	var player_ent: Player = player as Player
	camera.rotate_view(PI * 0.5)
	_check(abs(camera.rotation - PI * 0.5) < 0.01, "Camera rotate_view applies radians")
	camera.reset_view()
	_check(is_zero_approx(camera.rotation), "reset_view returns north-up")
	player_ent.set_aim_locked(Vector2.RIGHT)
	Input.action_press("move_up")
	var toward: Vector2 = player_ent.get_move_vector()
	Input.action_release("move_up")
	_check(toward.x > 0.5, "W moves toward the aim/mouse (%s)" % str(toward))
	Input.action_press("move_down")
	var away: Vector2 = player_ent.get_move_vector()
	Input.action_release("move_down")
	_check(away.x < -0.5, "S moves away from the aim/mouse (%s)" % str(away))
	Input.action_press("move_right")
	var orbit: Vector2 = player_ent.get_move_vector()
	Input.action_release("move_right")
	_check(orbit.y > 0.5, "D strafes around the pointer (%s)" % str(orbit))
	_check(_player_has_shape(player_ent), "Player has a collision shape for terrain")
	var tileset: TileSet = (terrain_renderer as TerrainRenderer).tile_set
	_check(tileset != null and tileset.get_physics_layers_count() > 0,
			"Terrain TileSet has a physics layer (stone collision)")
	var creature_spawner: Node = main.get_node_or_null("CreatureSpawner")
	_check(creature_spawner != null, "CreatureSpawner node present")
	if creature_spawner != null:
		var wolf: CreatureDefinition = creature_spawner.get_definition("wolf")
		_check(wolf != null and wolf.hostile, "Wolf is a hostile predator")
		var rabbit: CreatureDefinition = creature_spawner.get_definition("rabbit")
		_check(rabbit != null and not rabbit.hostile, "Rabbit stays passive")
	var day_night: DayNightCycle = main.get_node_or_null("DayNightCycle") as DayNightCycle
	_check(day_night != null, "DayNightCycle node present")
	if day_night != null:
		_check(day_night.is_daytime() == true, "DayNightCycle starts in daytime")
		day_night.set_time(22.0, 1)
		_check(day_night.is_nighttime() == true, "DayNightCycle set_time reaches night")
		day_night.set_time(8.0, 1)
	var weather: WeatherSystem = main.get_node_or_null("WeatherSystem") as WeatherSystem
	_check(weather != null, "WeatherSystem node present")
	if weather != null:
		weather.set_weather(WeatherSystem.WeatherType.RAIN, 0.8, 10.0)
		_check(weather.get_weather_name() == "Rain", "WeatherSystem can switch to rain")
		weather.set_weather(WeatherSystem.WeatherType.CLEAR, 0.0, 40.0)
	var statuses: StatusEffectSystem = main.get_node_or_null("StatusEffectSystem") as StatusEffectSystem
	_check(statuses != null, "StatusEffectSystem node present")
	if statuses != null:
		statuses.apply_effect("poison")
		_check(statuses.has_effect("poison"), "StatusEffectSystem applies poison")
		statuses.remove_effect("poison")
		_check(not statuses.has_effect("poison"), "StatusEffectSystem removes poison")
	var buildings: BuildingManager = main.get_node_or_null("BuildingManager") as BuildingManager
	_check(buildings != null, "BuildingManager node present")
	if buildings != null and player_ent.inventory != null:
		player_ent.inventory.add_item("wooden_wall", 1)
		var placed: bool = buildings.place_building_item("wooden_wall", Vector2i(3, 3), player_ent.inventory)
		_check(placed, "BuildingManager places a wooden wall")
		_check(buildings.get_building_count() >= 1, "BuildingManager tracks placed buildings")
		buildings.demolish_at(Vector2i(3, 3))
	_check(item_database.has_item("wooden_bow"), "Wooden bow exists for ranged combat")
	_check(item_database.has_item("arrow"), "Arrows exist for ranged combat")

	# --- 11. Title screen + versioned saves ----------------------------------
	var title: Node = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	_check(title != null, "Title scene instantiates")
	var title_buttons: PackedStringArray = PackedStringArray()
	_collect_button_labels(title, title_buttons)
	_check("New Game" in title_buttons, "Title has New Game")
	_check("Load Game" in title_buttons, "Title has Load Game")
	_check("Options" in title_buttons, "Title has Options placeholder")
	_check("Quit Game" in title_buttons, "Title has Quit Game")
	(title as TitleScreen)._on_new_game()
	var mode_buttons: PackedStringArray = PackedStringArray()
	_collect_button_labels(title, mode_buttons)
	_check("Survival" in mode_buttons, "New Game offers Survival mode")
	_check("Creative" in mode_buttons, "New Game offers Creative mode")
	title.queue_free()
	var ss: SaveSystem = main.get_node("SaveSystem") as SaveSystem
	_check(SaveSystem.SAVE_VERSION >= 2, "Save format is versioned (v2+)")
	var v1: Dictionary = {
		"version": 1,
		"player": {"position": {"x": 9.0, "y": 4.0}},
		"world": {"seed": 77}
	}
	var migrated: Dictionary = ss.migrate(v1)
	_check(int(migrated.get("version", 0)) == SaveSystem.SAVE_VERSION, "v1 saves migrate to current version")
	var modules: Dictionary = migrated.get("modules", {})
	_check(modules.has("player") and modules.has("world"), "Migrated save has required modules")
	_check(int(modules.get("world", {}).get("seed", 0)) == 77, "Migrated world seed is preserved")
	GameSession.set_game_mode(GameSession.MODE_CREATIVE)
	_check(GameSession.is_creative(), "Creative mode can be selected")
	var plank_idx: int = -1
	var defs: Array = main.get("_recipe_defs")
	for i in range(defs.size()):
		if str(defs[i].recipe_id) == "plank":
			plank_idx = i
			break
	var wood_before: int = player_ent.inventory.get_item_quantity("wood")
	var plank_before: int = player_ent.inventory.get_item_quantity("plank")
	main.call("_on_craft_requested", plank_idx)
	_check(player_ent.inventory.get_item_quantity("plank") > plank_before, "Creative mode crafts without ingredients")
	_check(player_ent.inventory.get_item_quantity("wood") == wood_before, "Creative mode does not consume materials")
	ss.save_manual()
	var creative_seen: bool = false
	for entry in SaveSystem.list_save_entries():
		if str(entry.get("game_mode", "")) == GameSession.MODE_CREATIVE:
			creative_seen = true
			break
	_check(creative_seen, "Save list records Creative mode")
	GameSession.set_game_mode(GameSession.MODE_SURVIVAL)
	_check(GameSession.is_survival(), "Survival is the default locked mode")
	_check(ss.has_any_save(), "A save exists after save_game()")
	var before_manual: int = 0
	var before_auto: int = 0
	for entry in SaveSystem.list_save_entries():
		if str(entry.get("kind", "")) == "autosave":
			before_auto += 1
		else:
			before_manual += 1
	_check(ss.save_manual(), "save_manual() creates another slot")
	_check(ss.save_manual(), "save_manual() can create multiple slots")
	var after_manual: int = 0
	for entry in SaveSystem.list_save_entries():
		if str(entry.get("kind", "")) != "autosave":
			after_manual += 1
	_check(after_manual >= before_manual + 2, "Multiple manual saves are kept (%d)" % after_manual)
	_check(ss.save_autosave(), "save_autosave() writes an autosave")
	_check(ss.save_autosave(), "save_autosave() can rotate")
	_check(ss.save_autosave(), "save_autosave() third write")
	var autos: int = 0
	var kinds_ok: bool = false
	for entry in SaveSystem.list_save_entries():
		if str(entry.get("kind", "")) == "autosave":
			autos += 1
		else:
			kinds_ok = true
	_check(autos <= SaveSystem.AUTOSAVE_KEEP, "Only the last %d autosaves are kept (%d found)" % [SaveSystem.AUTOSAVE_KEEP, autos])
	_check(kinds_ok and autos >= 1, "Load list includes both manual and autosave files")
	var prev_auto: bool = SaveSystem.is_autosave_enabled()
	SaveSystem.set_autosave_enabled(false)
	_check(SaveSystem.is_autosave_enabled() == false, "Options can disable autosave")
	SaveSystem.set_autosave_enabled(true)
	_check(SaveSystem.is_autosave_enabled() == true, "Options can enable autosave")
	SaveSystem.set_autosave_enabled(prev_auto)

func _collect_button_labels(node: Node, into: PackedStringArray) -> void:
	if node is Button:
		into.append((node as Button).text)
	for child in node.get_children():
		_collect_button_labels(child, into)

func _player_has_shape(player: Node) -> bool:
	for child in player.get_children():
		if child is CollisionShape2D:
			return true
	return false
