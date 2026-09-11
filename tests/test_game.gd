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
	# Free the game tree a couple of frames later: queued frees flush at the
	# end of the frame, so exiting immediately would report leaked instances.
	if _frames == 8 and _done and is_instance_valid(_main):
		_main.queue_free()
	if _frames == 10 and _done:
		print("\n%d passed, %d failed" % [_passed, _failed])
		quit(_failed if _failed > 0 else 0)
		return true
	return false

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
	_check(ChunkSystem.world_to_chunk_coords(Vector2i(16, 0)) == Vector2i(1, 0), "world_to_chunk_coords(16,0) == (1,0)")
	_check(ChunkSystem.world_to_chunk_coords(Vector2i(31, 31)) == Vector2i(1, 1), "world_to_chunk_coords(31,31) == (1,1)")
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
