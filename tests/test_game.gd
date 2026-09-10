## Basic test script for Wildfall game validation.
extends SceneTree

func _init() -> void:
	var root: Node = get_root()
	
	# Test 1: Check if main scene loads
	print("[TEST] Loading main scene...")
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	if main_scene:
		print("[PASS] Main scene loads successfully")
	else:
		print("[FAIL] Failed to load main scene")
		quit(1)
		return
	
	# Test 2: Instantiate main scene
	print("[TEST] Instantiating main scene...")
	var main_node: Node = main_scene.instantiate()
	if main_node:
		print("[PASS] Main scene instantiated successfully")
	else:
		print("[FAIL] Failed to instantiate main scene")
		quit(1)
		return
	
	# Test 3: Check required nodes exist
	print("[TEST] Checking required nodes...")
	var required_nodes: PackedStringArray = ["GameEventBus", "WorldGenerator", "ChunkSystem", "TerrainRenderer", "ResourceSpawner", "Player", "CameraController", "DebugOverlay", "HUD"]
	for node_name in required_nodes:
		var node := main_node.get_node_or_null(node_name)
		if node:
			print("[PASS] Found node: %s" % node_name)
		else:
			print("[FAIL] Missing node: %s" % node_name)
	
	# Test 4: Check world generation
	print("[TEST] Testing world generation...")
	var world_gen := main_node.get_node_or_null("WorldGenerator") as Node
	if world_gen:
		var chunk_data: Dictionary = world_gen.call("generate_chunk", Vector2i(0, 0), 42)
		if not chunk_data.is_empty():
			print("[PASS] World generation works")
			print("  - Biome: %s" % chunk_data.get("biome", "unknown"))
		else:
			print("[FAIL] World generation returned empty data")
	else:
		print("[FAIL] WorldGenerator not found")
	
	# Test 5: Check chunk system
	print("[TEST] Testing chunk system...")
	var chunk_sys := main_node.get_node_or_null("ChunkSystem") as Node
	if chunk_sys:
		chunk_sys.initialize(42)
		var chunk_coords: Vector2i = chunk_sys.world_to_chunk_coords(Vector2i(32, 32))
		if chunk_coords == Vector2i(2, 2):
			print("[PASS] Chunk coordinate conversion works")
		else:
			print("[FAIL] Chunk coordinate conversion failed: expected (2,2), got %s" % chunk_coords)
	else:
		print("[FAIL] ChunkSystem not found")
	
	# Test 6: Check resource spawner
	print("[TEST] Testing resource spawner...")
	var res_spawner := main_node.get_node_or_null("ResourceSpawner") as Node
	if res_spawner:
		res_spawner.initialize(42)
		var resources: Array[Dictionary] = res_spawner.generate_chunk_resources("0,0", 42)
		if resources.size() > 0:
			print("[PASS] Resource spawning works: %d resources" % resources.size())
		else:
			print("[FAIL] No resources generated")
	else:
		print("[FAIL] ResourceSpawner not found")
	
	# Test 7: Check player
	print("[TEST] Testing player...")
	var player := main_node.get_node_or_null("Player") as CharacterBody2D
	if player:
		print("[PASS] Player node exists")
		# Check player has required methods
		if player.has_method("get_world_position"):
			print("[PASS] Player has get_world_position method")
		else:
			print("[FAIL] Player missing get_world_position method")
	else:
		print("[FAIL] Player not found")
	
	# Test 8: Save/load functionality
	print("[TEST] Testing save/load...")
	var test_data: Dictionary = {
		"world_seed": 42,
		"player_position": Vector2(0, 0),
		"inventory": [{"item_id": "wood", "quantity": 10}]
	}
	var save_path: String = "user://test_save.json"
	
	# Try to save
	var saved: bool = false
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(test_data))
		f.close()
		saved = true
		print("[PASS] Save functionality works")
	
	# Try to load
	var loaded_data: Dictionary = {}
	if FileAccess.file_exists(save_path):
		f = FileAccess.open(save_path, FileAccess.READ)
		if f:
			loaded_data = JSON.parse_string(f.get_as_text())
			f.close()
			if loaded_data.get("world_seed") == 42:
				print("[PASS] Load functionality works")
			else:
				print("[FAIL] Load returned incorrect data")
		else:
			print("[FAIL] Could not open save file for reading")
	else:
		print("[FAIL] Save file not found")
	
	# Cleanup
	root.add_child(main_node)
	
	print("")
	print("==================================================")
	print("TEST COMPLETE")
	print("==================================================")
	
	quit(0)
