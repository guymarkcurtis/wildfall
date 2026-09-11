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
				Input.action_press("move_right")
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
				Input.action_release("move_right")
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
