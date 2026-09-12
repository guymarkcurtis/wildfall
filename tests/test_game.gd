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
# 2 -> wait for panel to close, walk east 3 -> walk until far enough, check
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
				var recipe_scroll: ScrollContainer = panel.get_node_or_null("MarginContainer/VBox/RecipeScroll") as ScrollContainer
				_check(recipe_scroll != null and recipe_scroll.get_v_scroll_bar().max_value > 0.0,
					"Crafting recipe list scrolls instead of overflowing the panel")
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
	var inventory_panel: InventoryPanel = main.get_node_or_null("HUD/InventoryPanel")
	var build_palette: Node = main.get_node_or_null("HUD/BuildPalette")
	var technology_panel: Node = main.get_node_or_null("HUD/TechnologyPanel")
	var technology_system: TechnologySystem = main.get_node_or_null("TechnologySystem") as TechnologySystem
	var texture_pack_manager: TexturePackManager = main.get_node_or_null("TexturePackManager") as TexturePackManager

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
	_check((hud.get_node("Overlay") as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Passive HUD lets world clicks reach building placement")
	_check(inventory_panel != null, "Inventory panel node present")
	_check(build_palette != null, "Build palette node present")
	_check(technology_panel != null, "Technology panel node present")
	_check(technology_system != null, "TechnologySystem node present")
	_check(texture_pack_manager != null, "TexturePackManager node present")
	if _failed > 0:
		return

	# --- 1b. Persistent quick bar + expandable inventory -------------------
	_check(not inventory_panel.is_open(), "Inventory starts collapsed to its quick bar")
	_check(player.get_hotbar_items().size() == 9, "Player owns nine saved quick-bar assignments")
	player.select_hotbar_slot(0)
	_check(player.active_hotbar_slot == 0, "Numbered quick-bar slot can be selected")
	_check(player.equipped_tool == player.get_hotbar_items()[0], "Selecting a quick-bar slot equips its assigned item")
	player.inventory.add_item("wood", 3)
	inventory_panel.open()
	_check(inventory_panel.is_open(), "Inventory expands above the quick bar")
	var backpack_bottom := inventory_panel._backpack_grid.position.y + InventoryPanel.SLOT_SIZE * 3.0 + InventoryPanel.GRID_GAP * 2.0
	_check(is_equal_approx(inventory_panel._hotbar_grid.position.y - backpack_bottom, InventoryPanel.GRID_GAP),
		"Expanded quick bar uses the same gap as backpack rows")
	# Wood is not in the initial quick bar. Select it in the backpack, then
	# assign it to slot 9 — the same two-click move used by the player UI.
	inventory_panel._on_slot_pressed(false, 0)
	inventory_panel._on_slot_pressed(true, 8)
	_check(player.get_hotbar_items()[8] == "wood", "Backpack item can be assigned to a quick-bar slot")
	var first_hotbar_item: String = player.get_hotbar_items()[0]
	var second_hotbar_item: String = player.get_hotbar_items()[1]
	inventory_panel._on_slot_dropped(true, 0, true, 1)
	_check(player.get_hotbar_items()[0] == second_hotbar_item and player.get_hotbar_items()[1] == first_hotbar_item,
		"Dragging between quick-bar slots swaps their assignments")
	inventory_panel.close()
	_check(not inventory_panel.is_open(), "Closing inventory leaves the quick bar visible")

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
	var world_config: WorldGenerationConfig = world_gen.get_configuration()
	_check(world_config.world_dimensions_chunks.x >= 64 and world_config.world_dimensions_chunks.y >= 64,
		"World bounds are configured as a large finite world")
	_check(world_config.streaming_radius >= 1 and world_config.chunk_size_tiles == 16,
		"Chunk size and streaming radius come from world configuration")
	var world_registry: WorldContentRegistry = world_gen.get_content_registry()
	_check(world_registry.biomes.size() >= 6 and world_registry.resources.size() >= 8,
		"Biome and resource content is discovered from data assets")
	var regional_a: Dictionary = world_gen.get_regional_noise_values(137, -91)
	var regional_b: Dictionary = world_gen.get_regional_noise_values(137, -91)
	var adjacency_authored := false
	for biome_definition in world_registry.biomes.values():
		if not biome_definition.preferred_neighbors.is_empty() or not biome_definition.transition_biome_ids.is_empty():
			adjacency_authored = true
			break
	_check(regional_a == regional_b and adjacency_authored and world_config.regional_biome_weight > 0.0,
		"Regional biome fields and adjacency metadata are deterministic and data-defined")
	var poi_ids := world_registry.pois.keys()
	poi_ids.sort()
	var poi_definition: POIDefinition = world_registry.get_poi(str(poi_ids[0])) if not poi_ids.is_empty() else null
	var poi_anchors: Array = []
	if poi_definition != null:
		for chunk_x in range(-8, 9):
			for chunk_y in range(-8, 9):
				var anchors: Array = world_gen.call("_poi_anchor_tiles_in_chunk", poi_definition,
						Vector2i(chunk_x * 16, chunk_y * 16), 16)
				poi_anchors.append_array(anchors)
	var poi_spacing_ok := poi_definition != null and not poi_anchors.is_empty()
	for first_index in range(poi_anchors.size()):
		var first: Vector2i = poi_anchors[first_index]
		for second_index in range(first_index):
			var second: Vector2i = poi_anchors[second_index]
			if maxi(abs(first.x - second.x), abs(first.y - second.y)) < poi_definition.min_spacing_tiles:
				poi_spacing_ok = false
	_check(poi_spacing_ok, "POI asset spacing is deterministic across chunk boundaries")
	var poi_chunk_a: Dictionary = world_gen.generate_chunk(Vector2i(0, 0))
	var poi_chunk_b: Dictionary = world_gen.generate_chunk(Vector2i(0, 0))
	_check(str(poi_chunk_a.get("poi_candidates", [])) == str(poi_chunk_b.get("poi_candidates", [])),
		"POI candidates are stable regardless of generation order")
	var surface_ore_found := false
	for resource_record in resource_spawner.get_all_resources().values():
		var resource_type := str(resource_record.get("type", ""))
		if resource_type in ["iron_ore", "coal", "gold_ore"]:
			surface_ore_found = true
	_check(not surface_ore_found, "Underground-only mineral definitions do not spawn on the surface")
	var cave_definition: CaveDefinition = world_gen.get_cave("mountain_cave")
	var cave_generator := CaveSpaceGenerator.new()
	var cave_a: Dictionary = cave_generator.generate_cave(world_gen.get_seed(), "mountain_cave@4,4", Vector2i(4, 4), cave_definition, world_registry.resources)
	var cave_b: Dictionary = cave_generator.generate_cave(world_gen.get_seed(), "mountain_cave@4,4", Vector2i(4, 4), cave_definition, world_registry.resources)
	_check(cave_definition != null and cave_a.get("cave_id", "") == cave_b.get("cave_id", "") and cave_a.get("seed", -1) == cave_b.get("seed", -2),
		"Cave spaces have stable deterministic identities and seeds")
	var cave_deposits: Array = cave_a.get("resource_candidates", [])
	var cave_deposits_are_underground := not cave_deposits.is_empty() and str(cave_deposits) == str(cave_b.get("resource_candidates", []))
	for deposit in cave_deposits:
		var deposit_definition: ResourceDefinition = world_registry.get_resource(str(deposit.get("resource_id", "")))
		if deposit_definition == null or not deposit_definition.underground_spawnable:
			cave_deposits_are_underground = false
			break
	_check(cave_deposits_are_underground, "Cave deposits are deterministic and use only underground resource data")
	var cave_rooms: Array = cave_a.get("rooms", [])
	_check(not cave_rooms.is_empty() and cave_rooms[0].get("center", Vector2i.ONE) == Vector2i.ZERO,
		"Cave entrance chamber is anchored at the runtime exit")
	var runtime_entrance := CaveEntrance.new()
	runtime_entrance.setup({
		"cave_id": "mountain_cave@4,4",
		"cave_type_id": "mountain_cave",
		"x": 4,
		"y": 4,
		"biome": "test"
	})
	main.add_child(runtime_entrance)
	runtime_entrance.entered.connect(Callable(main, "_on_cave_entrance_entered"))
	runtime_entrance.interact()
	_check(bool(main.call("is_in_cave")) and main.get_node_or_null("ActiveCaveSpace") is CaveSpace,
		"Surface cave entrance opens a separate generated cave space")
	var active_cave: CaveSpace = main.get_node_or_null("ActiveCaveSpace") as CaveSpace
	_check(active_cave != null and not (active_cave.cave_data.get("resource_candidates", []) as Array).is_empty(),
		"Entering a cave carries its deterministic underground deposit candidates")
	var cave_state: Dictionary = main.call("_collect_world_state") as Dictionary
	_check((cave_state.get("discovered_caves", []) as Array).has("mountain_cave@4,4"),
		"Entering a cave records only its stable discovery identity")
	main.call("interact_with_active_cave")
	_check(not bool(main.call("is_in_cave")) and terrain_renderer.collision_enabled,
		"Cave exit restores the surface space and terrain collision")
	runtime_entrance.queue_free()

	# --- 3. Terrain + resources --------------------------------------------
	_check(terrain_renderer.get_used_cells().size() > 0, "Terrain rendered for initial chunks (%d tiles)" % terrain_renderer.get_used_cells().size())
	_check(TileSetGenerator.MATERIAL_PIXELS_PER_TILE == 4, "Stock terrain keeps its lightweight streaming resolution")
	_check(resource_spawner.get_all_resources().size() > 0, "Resources spawned in initial chunks")
	var reachable_resources := true
	for resource_tile in resource_spawner.get_all_resources().keys():
		if not resource_spawner.is_walkable_spawn_tile(resource_tile):
			reachable_resources = false
			break
	_check(reachable_resources, "Every spawned resource is on reachable terrain")

	# --- 3b. Texture pack export + live selection --------------------------
	var original_pack := TexturePackManager.get_active_pack_id()
	var stock_texture := TexturePackManager.get_texture("res://assets/tiles/wildfall-terrain-atlas.png")
	_check(stock_texture != null and stock_texture.get_width() > 0, "Stock terrain texture resolves through TexturePackManager")
	var reference_export := TexturePackManager.export_stock_reference()
	_check(FileAccess.file_exists(TexturePackManager.CARD_PATH), "Stock texture contact card exports for external editing")
	_check(FileAccess.file_exists("user://texture_packs/stock_reference/manifest.json"), "Stock reference pack includes its manifest")
	_check(FileAccess.file_exists("user://texture_packs/stock_reference/assets/tiles/wildfall-crafting-stations.png"),
		"Stock reference pack includes the crafting-station texture atlas")
	var station_texture := TexturePackManager.get_texture("res://assets/tiles/wildfall-crafting-stations.png")
	_check(station_texture != null and station_texture.get_width() == 128 and station_texture.get_height() == 32, "Crafting-station atlas has four 32px cells")
	# --- Generated art sheets (external image pipeline) ----------------------
	# Inspect the built-in source sheet so a user's active texture-pack choice
	# cannot make this asset-contract check fail.
	var artreq_roster_img: Image = TexturePackManager.get_stock_image("res://assets/creatures/alien-creature-roster.png")
	_check(artreq_roster_img != null and artreq_roster_img.get_size() == Vector2i(2688, 1024), "Creature roster atlas is the full 7x2 sheet")
	_check(CreatureVisual.COLUMNS == 7, "CreatureVisual samples the roster as seven columns")
	var artreq_species_columns: Dictionary = CreatureVisual.SPECIES_COLUMNS
	var artreq_columns_seen: Array = []
	var artreq_columns_unique := true
	for artreq_species in artreq_species_columns:
		var artreq_species_col = artreq_species_columns[artreq_species]
		if artreq_columns_seen.has(artreq_species_col):
			artreq_columns_unique = false
		artreq_columns_seen.append(artreq_species_col)
	_check(artreq_species_columns.size() == 7, "All seven creature species have roster columns")
	_check(artreq_columns_unique, "No two creature species share a roster column")
	var artreq_parts_img: Image = TexturePackManager.get_image("res://assets/tiles/wildfall-building-parts.png")
	_check(artreq_parts_img != null and artreq_parts_img.get_size() == Vector2i(64, 288), "Building parts atlas is the 2x9 wood/stone grid")
	var artreq_parts_full := true
	if artreq_parts_img != null:
		for artreq_row in range(9):
			for artreq_col in range(2):
				if not _atlas_cell_has_art(artreq_parts_img, artreq_col * 32, artreq_row * 32):
					artreq_parts_full = false
	_check(artreq_parts_img != null and artreq_parts_full, "Every building parts atlas cell contains artwork")
	var artreq_utils_img: Image = TexturePackManager.get_image("res://assets/tiles/wildfall-building-utilities.png")
	_check(artreq_utils_img != null and artreq_utils_img.get_size() == Vector2i(160, 32), "Building utilities atlas is the 5x1 grid")
	var artreq_utils_full := true
	if artreq_utils_img != null:
		for artreq_util_col in range(5):
			if not _atlas_cell_has_art(artreq_utils_img, artreq_util_col * 32, 0):
				artreq_utils_full = false
	_check(artreq_utils_img != null and artreq_utils_full, "Every building utilities atlas cell contains artwork")
	var artreq_stations_full := true
	if station_texture != null:
		for artreq_station_col in range(4):
			if not _atlas_cell_has_art(station_texture.get_image(), artreq_station_col * 32, 0):
				artreq_stations_full = false
	_check(artreq_stations_full, "Every crafting-station atlas cell contains artwork")
	var refinement_export := TexturePackManager.create_refinement_pack()
	_check(FileAccess.file_exists("user://texture_packs/refinement/manifest.json"), "Editable refinement pack is created with its manifest")
	_check(TexturePackManager.get_available_pack_ids().has(TexturePackManager.REFINEMENT_PACK), "Editable refinement pack appears in the selector")
	_check(TexturePackManager.set_active_pack_id(TexturePackManager.REFINEMENT_PACK), "Refinement texture pack can be selected live")
	_check(TexturePackManager.get_active_pack_id() == TexturePackManager.REFINEMENT_PACK, "Selected texture pack is persisted as active")
	var packed_tile_ids := PackedInt32Array()
	packed_tile_ids.append(TerrainRenderer.TILE_GRASS)
	var pack_generator := TileSetGenerator.new()
	var packed_ground := pack_generator.create_contiguous_chunk_image(Vector2i.ZERO, packed_tile_ids, 1, 0)
	var pack_grass := TexturePackManager.get_image("res://assets/ground/grass.png")
	_check(packed_ground.get_size() == Vector2i(32, 32), "Active texture pack renders terrain at native tile resolution")
	_check(packed_ground.get_pixel(7, 11).is_equal_approx(pack_grass.get_pixel(7, 11)), "Active texture-pack pixels reach the world without downsampling")
	pack_generator.free()
	_check(TexturePackManager.set_active_pack_id(original_pack), "Texture pack can switch back to the previous selection")
	var options := OptionsPanel.new()
	root.add_child(options)
	options.open()
	var refinement_index := -1
	for index in range(options._pack_picker.item_count):
		if str(options._pack_picker.get_item_metadata(index)) == TexturePackManager.REFINEMENT_PACK:
			refinement_index = index
			break
	options._on_texture_pack_selected(refinement_index)
	_check(options._pending_pack_id == TexturePackManager.REFINEMENT_PACK and TexturePackManager.get_active_pack_id() == original_pack,
		"Texture picker stages a selection until Apply is pressed")
	options._on_apply_texture_pack()
	_check(TexturePackManager.get_active_pack_id() == TexturePackManager.REFINEMENT_PACK and not options._preview_tiles.is_empty() and options._preview_tiles[0].texture != null,
		"Texture Apply button changes the active pack and refreshes its preview")
	TexturePackManager.set_active_pack_id(original_pack)
	options.queue_free()

	# --- 4. Item database + crafting panel (B10/B13) -----------------------
	_check(item_database.items.size() > 0, "Item database populated (%d items)" % item_database.items.size())
	_check(item_database.recipes.size() > 0, "Recipe database populated (%d recipes)" % item_database.recipes.size())
	var panel_recipes: Array = crafting_panel.recipes
	_check(panel_recipes.size() > 0, "Crafting panel shows recipes (%d)" % panel_recipes.size())
	var recipe_scroll: ScrollContainer = crafting_panel.get_node_or_null("MarginContainer/VBox/RecipeScroll") as ScrollContainer
	var recipe_list: VBoxContainer = crafting_panel.get_node_or_null("MarginContainer/VBox/RecipeScroll/RecipeList") as VBoxContainer
	_check(recipe_scroll != null and recipe_list != null and recipe_list.get_child_count() - 1 == panel_recipes.size(),
		"Crafting panel renders every available recipe in its scroll list")
	_check(recipe_list != null and recipe_list.custom_minimum_size.y >= float(panel_recipes.size()) * 48.0,
		"Crafting recipe list reserves content height for every recipe")
	var recipe_ids: Array = []
	for r in panel_recipes:
		recipe_ids.append(str(r.get("id", "")))
	_check("plank" in recipe_ids, "Live recipe 'plank' visible in crafting panel")
	_check("wooden_axe" in recipe_ids, "Live recipe 'wooden_axe' visible in crafting panel")
	# --- 4b. Technology tree gates higher tiers, then unlocks them ---------
	_check(InputMap.has_action("toggle_technology"), "toggle_technology input action exists (U key)")
	_check(technology_system.is_unlocked("wood_building"), "Wood construction is available from the start")
	_check(not technology_system.is_unlocked("stone_building"), "Stone construction starts research-locked")
	_check("wooden_foundation" in recipe_ids, "Starting wood building recipe is visible")
	_check(not ("stone_foundation" in recipe_ids), "Stone building recipe stays hidden before research")
	var technology_buildings: BuildingManager = main.get_node_or_null("BuildingManager") as BuildingManager
	player.inventory.add_item("stone_foundation", 1)
	_check(not technology_buildings.place_building_item("stone_foundation", Vector2i(12, 12), player.inventory),
		"Owned stone parts cannot be placed before their technology is researched")
	technology_panel.call("toggle")
	_check(technology_panel.visible, "Technology panel opens")
	technology_panel.call("toggle")
	_check(not technology_panel.visible, "Technology panel closes")
	var stone_cost: int = 30
	var wood_cost: int = 20
	player.inventory.add_item("stone", stone_cost)
	player.inventory.add_item("wood", wood_cost)
	var stone_before: int = player.inventory.get_item_quantity("stone")
	var wood_before_research: int = player.inventory.get_item_quantity("wood")
	_check(technology_system.try_unlock("stone_building", player.inventory), "Stone construction can be researched with its resource cost")
	_check(technology_system.is_unlocked("stone_building"), "Stone construction becomes unlocked")
	_check(player.inventory.get_item_quantity("stone") == stone_before - stone_cost and player.inventory.get_item_quantity("wood") == wood_before_research - wood_cost,
		"Research consumes the configured wood and stone cost")
	panel_recipes = crafting_panel.recipes
	recipe_ids.clear()
	for r in panel_recipes:
		recipe_ids.append(str(r.get("id", "")))
	_check("stone_foundation" in recipe_ids, "Stone building recipe appears after research")
	var technology_save: Dictionary = technology_system.serialize()
	technology_system.deserialize({})
	_check(not technology_system.is_unlocked("stone_building"), "Missing save technology data falls back to starting research")
	technology_system.deserialize(technology_save)
	_check(technology_system.is_unlocked("stone_building"), "Saved technology unlock is restored")
	main.call("_refresh_ui")

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

	# --- 7. Save / load roundtrip + persistent world mutations ---------------
	# Ensure a few real chunk visuals have been constructed without forcing the
	# complete 7×7 ring in one test frame.
	var coverage_chunk_loads := 0
	while (main.get("_resource_nodes") as Array).is_empty() or (main.get("_creature_nodes") as Array).is_empty():
		if coverage_chunk_loads >= 12:
			break
		main.call("_process_one_chunk_visual")
		coverage_chunk_loads += 1
	var tracked_resources: Array = main.get("_resource_nodes")
	var resource_to_destroy: HarvestableResource = tracked_resources[0] as HarvestableResource if not tracked_resources.is_empty() else null
	_check(resource_to_destroy != null, "A spawned resource is available for persistence coverage")
	var destroyed_resource_tile := Vector2i.ZERO
	if resource_to_destroy != null:
		destroyed_resource_tile = resource_to_destroy.get_meta("spawn_tile", Vector2i.ZERO)
		resource_to_destroy.destroy()
		_check((main.get("_destroyed_resource_tiles") as Dictionary).has(destroyed_resource_tile),
			"Depleting a resource records its deterministic spawn tile")

	var tracked_creatures: Array = main.get("_creature_nodes")
	var creature_to_kill: Creature = tracked_creatures[0] as Creature if not tracked_creatures.is_empty() else null
	_check(creature_to_kill != null, "A spawned creature is available for persistence coverage")
	var destroyed_creature_tile := Vector2i.ZERO
	if creature_to_kill != null:
		destroyed_creature_tile = creature_to_kill.get_meta("spawn_tile", Vector2i.ZERO)
		creature_to_kill.take_damage(creature_to_kill.health)
		_check((main.get("_destroyed_creature_tiles") as Dictionary).has(destroyed_creature_tile),
			"Killing a creature records its deterministic spawn tile")

	var saved_building_tile := Vector2i(14, 14)
	player.inventory.add_item("wooden_wall", 1)
	_check(technology_buildings.place_building_item("wooden_wall", saved_building_tile, player.inventory),
		"Placed building is ready for save/load coverage")
	player.global_position = Vector2(123.0, -77.0)
	var ok_save: bool = main.call("save_game")
	_check(ok_save, "save_game() succeeds (player at %s)" % str(player.global_position))
	player.global_position = Vector2(50.0, 50.0)  # simulate drift away from saved position
	var ok_load: bool = main.call("load_game")
	_check(ok_load, "load_game() succeeds")
	# Reconstruct exactly the affected chunks. This verifies the saved ledger
	# participates in deterministic spawning without eagerly building every
	# queued visual chunk during this synchronous test step.
	var destroyed_resource_chunk := Vector2i(
		int(floor(float(destroyed_resource_tile.x) / 16.0)),
		int(floor(float(destroyed_resource_tile.y) / 16.0))
	)
	var destroyed_creature_chunk := Vector2i(
		int(floor(float(destroyed_creature_tile.x) / 16.0)),
		int(floor(float(destroyed_creature_tile.y) / 16.0))
	)
	main.call("_spawn_resources_for_chunk", destroyed_resource_chunk)
	main.call("_spawn_creatures_for_chunk", destroyed_creature_chunk)
	_check(player.global_position.distance_to(Vector2(123.0, -77.0)) < 1.0, \
		"Player position restored from save (%s)" % str(player.global_position))
	_check(player.get_hotbar_items()[8] == "wood", "Saved quick-bar assignment is restored on load")
	_check(technology_system.is_unlocked("stone_building"), "Saved technology research is restored on load")
	_check(not resource_spawner.has_resource(destroyed_resource_tile),
		"Destroyed resource stays absent after loading the same seed")
	var resource_respawned := false
	for candidate in main.get("_resource_nodes"):
		if is_instance_valid(candidate) and not candidate.is_queued_for_deletion() \
				and candidate.get_meta("spawn_tile", Vector2i.ZERO) == destroyed_resource_tile:
			resource_respawned = true
			break
	_check(not resource_respawned, "Destroyed resource node is not recreated after load")
	var save_creature_spawner: CreatureSpawner = main.get_node_or_null("CreatureSpawner") as CreatureSpawner
	_check(save_creature_spawner != null and save_creature_spawner.get_creature(destroyed_creature_tile).is_empty(),
		"Killed creature stays absent after loading the same seed")
	var creature_respawned := false
	for candidate in main.get("_creature_nodes"):
		if is_instance_valid(candidate) and not candidate.is_queued_for_deletion() \
				and candidate.get_meta("spawn_tile", Vector2i.ZERO) == destroyed_creature_tile:
			creature_respawned = true
			break
	_check(not creature_respawned, "Killed creature node is not recreated after load")
	_check(technology_buildings.get_building_at(saved_building_tile) != null,
		"Placed building is restored after loading")

	# --- 8. Chunk unload / re-enter cycle (B3) --------------------------------
	# Full signal path: ChunkSystem.generate_chunk/unload_chunk -> Main handlers
	# -> ResourceSpawner (records) + TerrainRenderer (cells) + resource nodes.
	var far: Vector2i = Vector2i(10, 0)
	main.call("flush_pending_chunk_visuals")
	var res_before: int = resource_spawner.get_all_resources().size()
	chunk_system.generate_chunk(far)
	main.call("flush_pending_chunk_visuals")
	var res_after_gen: int = resource_spawner.get_all_resources().size()
	_check(res_after_gen > res_before, "Far chunk generates resources when loaded (+%d)" % (res_after_gen - res_before))
	var nodes_before: int = int(main.get("_resource_nodes").size())
	chunk_system.unload_chunk(far)
	var nodes_after: int = int(main.get("_resource_nodes").size())
	_check(nodes_after < nodes_before, "Unloading a chunk frees its resource nodes (%d -> %d)" % [nodes_before, nodes_after])
	_check(resource_spawner.get_all_resources().size() == res_before, "Spawner records cleared on chunk unload")
	chunk_system.generate_chunk(far)
	main.call("flush_pending_chunk_visuals")
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
	_check(InputMap.has_action("jump"), "jump input action exists (Space)")
	_check(InputMap.has_action("toggle_build"), "toggle_build input action exists")
	var camera: CameraController = camera_controller as CameraController
	var player_ent: Player = player as Player
	camera.rotate_view(PI * 0.5)
	_check(abs(camera.rotation - PI * 0.5) < 0.01, "Camera rotate_view applies radians")
	camera.reset_view()
	_check(is_zero_approx(camera.rotation), "reset_view returns north-up")
	var player_visual: CharacterVisual = player_ent.character_visual
	player_visual.update_animation(Vector2.ZERO, 0.0, Vector2.RIGHT)
	var east_texture := player_visual.get_active_texture()
	_check(player_visual.get_facing_direction() == "east" and player_visual.get_facing_direction_slot() == 0,
			"Player visual selects the east authored directional frame")
	_check(is_zero_approx(player_visual.rotation), "Player body does not rotate its sprite node when aiming")
	player_visual.update_animation(Vector2.ZERO, 0.0, Vector2.DOWN)
	_check(player_visual.get_facing_direction() == "south" and player_visual.get_active_texture() != east_texture,
			"Player visual swaps to a distinct south authored directional frame")
	player_visual.update_animation(Vector2.ZERO, 0.0, Vector2.UP)
	_check(player_visual.get_facing_direction() == "north" and is_zero_approx(player_visual.rotation),
			"Player visual retains a non-rotated north facing frame")
	for appearance_gender in ["female", "male"]:
		player_visual.set_appearance(appearance_gender, "base")
		for animation_type in ["axe", "pickaxe", "sword", "bow", "jump"]:
			_check(player_visual.has_complete_directional_animation(animation_type),
					"%s player visual has a complete eight-way %s animation" % [appearance_gender.capitalize(), animation_type])
	player_visual.set_appearance(player_ent.character_gender, player_ent.character_outfit)
	player_ent.set_aim_locked(Vector2.RIGHT)
	_check(player_ent.try_jump() and player_ent.is_jumping(), "Player can start an aimed jump")
	player_ent._physics_process(Player.JUMP_DURATION + 0.01)
	_check(not player_ent.is_jumping(), "Player jump finishes after its configured duration")
	player_ent.set_aim_locked(Vector2.RIGHT)
	Input.action_press("move_up")
	var north: Vector2 = player_ent.get_move_vector()
	Input.action_release("move_up")
	_check(north.y < -0.5, "W always moves north (%s)" % str(north))
	Input.action_press("move_down")
	var south: Vector2 = player_ent.get_move_vector()
	Input.action_release("move_down")
	_check(south.y > 0.5, "S always moves south (%s)" % str(south))
	Input.action_press("move_left")
	var west: Vector2 = player_ent.get_move_vector()
	Input.action_release("move_left")
	_check(west.x < -0.5, "A always moves west (%s)" % str(west))
	Input.action_press("move_right")
	var east: Vector2 = player_ent.get_move_vector()
	Input.action_release("move_right")
	_check(east.x > 0.5, "D always moves east (%s)" % str(east))
	_check(_player_has_shape(player_ent), "Player has a collision shape for terrain")
	var tileset: TileSet = (terrain_renderer as TerrainRenderer).tile_set
	_check(tileset != null and tileset.get_physics_layers_count() > 0,
			"Terrain TileSet keeps a physics layer for water")
	var stone_source: TileSetAtlasSource = tileset.get_source(TerrainRenderer.TILE_STONE) as TileSetAtlasSource
	var stone_data: TileData = stone_source.get_tile_data(Vector2i.ZERO, 0) if stone_source != null else null
	_check(stone_data != null and stone_data.get_collision_polygons_count(0) == 0,
			"Rocky terrain is walkable so mineable nodes remain reachable")
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
		buildings.set_build_mode(true)
		_check(build_palette.visible, "Build mode opens the selectable build palette")
		_check(buildings.selected_item_id != "", "Build palette has an owned structural part selected")
		buildings.set_build_mode(false)
		player_ent.inventory.add_item("wooden_wall", 1)
		var placed: bool = buildings.place_building_item("wooden_wall", Vector2i(3, 3), player_ent.inventory)
		_check(placed, "BuildingManager places a wooden wall")
		_check(buildings.get_building_count() >= 1, "BuildingManager tracks placed buildings")
		buildings.demolish_at(Vector2i(3, 3))
		var structure_tile := Vector2i(7, 7)
		player_ent.inventory.add_item("wooden_foundation", 1)
		player_ent.inventory.add_item("wooden_floor", 2)
		_check(buildings.place_building_item("wooden_foundation", structure_tile, player_ent.inventory, 0),
			"Foundation can be placed on the ground story")
		_check(buildings.place_building_item("wooden_floor", structure_tile, player_ent.inventory, 1),
			"Supported floor can be placed on the story above")
		_check(buildings.get_building_at(structure_tile, 0) != null and buildings.get_building_at(structure_tile, 1) != null,
			"One map tile can hold structural parts on separate stories")
		_check(not buildings.place_building_item("wooden_floor", Vector2i(9, 9), player_ent.inventory, 1),
			"Upper-story placement needs structure directly below it")
		buildings.set_selected_story(1)
		_check(buildings.get_building_at(structure_tile, 1).visible and buildings.get_building_at(structure_tile, 0).visible,
			"Cutaway keeps the selected story and its support visible")
		buildings.set_selected_story(0)
		player_ent.global_position = Vector2.ZERO
		var cooked_meat: RecipeDefinition = item_database.get_recipe("cooked_meat")
		_check(cooked_meat != null and not main._has_required_crafting_station(cooked_meat),
			"Station recipe cannot be crafted away from its station")
		player_ent.inventory.add_item("meat", 1)
		var raw_meat_before := player_ent.inventory.get_item_quantity("meat")
		var cooked_before := player_ent.inventory.get_item_quantity("cooked_meat")
		var crafting_defs: Array = main.get("_recipe_defs")
		var cooked_recipe_index := crafting_defs.find(cooked_meat)
		main._on_craft_requested(cooked_recipe_index)
		_check(player_ent.inventory.get_item_quantity("meat") == raw_meat_before and player_ent.inventory.get_item_quantity("cooked_meat") == cooked_before,
			"Crafting rejects a station recipe without a nearby station")
		player_ent.inventory.add_item("campfire", 1)
		var campfire_tile := Vector2i(1, 0)
		_check(buildings.place_building_item("campfire", campfire_tile, player_ent.inventory, 0), "Crafted campfire can be placed in the world")
		var campfire: Building = buildings.get_building_at(campfire_tile, 0)
		_check(campfire != null and campfire._station_sprite != null and campfire._station_sprite.texture != null,
			"Placed campfire uses the exported texture-pack atlas")
		_check(buildings.has_station_near("campfire", player_ent.global_position) and main._has_required_crafting_station(cooked_meat),
			"Nearby campfire satisfies the cooking requirement")
		main._on_craft_requested(cooked_recipe_index)
		_check(player_ent.inventory.get_item_quantity("meat") == raw_meat_before - 1 and player_ent.inventory.get_item_quantity("cooked_meat") == cooked_before + 1,
			"Nearby campfire enables its recipe and consumes ingredients")
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
	_check(SaveSystem.SAVE_VERSION >= 4, "Save format includes world mutation persistence (v4+)")
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

	# ------------------------------------------------- tool durability
	_check(SaveSystem.SAVE_VERSION == 5, "Save format v5 persists tool durability")
	var all_durations: Dictionary = item_database.get_all_durations()
	_check(all_durations.size() > 0, "Item database knows which items are durable")
	_check(int(all_durations.get("wooden_axe", 0)) == 50, "Wooden axe is defined at 50 durability")
	_check(int(player.inventory.get_tool_durability("wooden_axe")["max"]) == 50, "Starting axe carries full durability")
	_check(int(player.inventory.get_tool_durability("wooden_axe")["current"]) == 50, "Starting axe has unused durability")
	_check(player.inventory.damage_tool("wooden_axe", 25) == false, "Partly worn tool does not break")
	_check(int(player.inventory.get_tool_durability("wooden_axe")["current"]) == 25, "Tool durability is consumed by use")
	var axe_slot: int = player.get_hotbar_items().find("wooden_axe")
	player.select_hotbar_slot(axe_slot)
	_check(axe_slot >= 0 and player.equipped_tool == "wooden_axe", "Quick-bar slot equips the tool")
	var bus = main.get_node_or_null("GameEventBus")
	_check(bus != null, "Main scene owns the event bus")
	var broken_ids: Array[String] = []
	bus.tool_broken.connect(func(item_id: String) -> void: broken_ids.append(str(item_id)))
	_check(player.inventory.damage_tool("wooden_axe", 25) == true, "Fully worn tool breaks")
	_check(player.inventory.has_item("wooden_axe") == false, "Broken tool is removed from the inventory")
	_check(broken_ids == ["wooden_axe"], "Tool break is announced on the event bus")
	_check(player.equipped_tool == "hand", "Broken equipped tool falls back to bare hands")
	player.inventory.add_item("wooden_axe", 1)
	player.populate_hotbar_from_inventory()  # same refresh the crafting flow triggers
	var re_axe_slot: int = player.get_hotbar_items().find("wooden_axe")
	player.select_hotbar_slot(re_axe_slot)
	_check(re_axe_slot >= 0 and player.equipped_tool == "wooden_axe", "Re-crafting restores the tool")
	_check(int(player.inventory.get_tool_durability("wooden_axe")["current"]) == 50, "A re-crafted tool starts at full durability")
	_check(int(player.inventory.get_tool_durability("wood")["max"]) == 0, "Non-durable items have no durability")
	player.inventory.damage_tool("wooden_axe", 12)
	_check(int(player.inventory.get_tool_durability("wooden_axe")["current"]) == 38, "Wear accumulates across uses")
	_check(main.call("save_game"), "Worn tool durability can be saved")
	var durability_save_path: String = ss.last_save_path
	_check(main.call("load_game", durability_save_path), "Worn tool durability can be loaded")
	_check(int(player.inventory.get_tool_durability("wooden_axe")["current"]) == 38, "Worn durability survives a save/load round trip")
	player.inventory.add_item("wood", 1)

	# ------------------------------------------------- missions
	_check(InputMap.has_action("toggle_missions"), "M is registered to toggle the mission journal")
	_check(bus.has_signal("mission_accepted") and bus.has_signal("mission_completed") and bus.has_signal("missions_changed"), "Event bus relays mission lifecycle signals")
	var mm = main.get_node_or_null("MissionManager")
	_check(mm != null, "Main scene owns the mission manager")
	var mission_panel = main.get_node_or_null("HUD/MissionPanel")
	_check(mission_panel != null, "HUD hosts the mission journal")
	var main_1 = mm.get_mission("main_1")
	# main_1 was auto-accepted at world start and already completed from
	# the wood the research refuel picked up earlier in this run.
	_check(main_1 != null and main_1.state == Mission.MissionState.COMPLETED, "Auto-accepted mission completes from real play pickups")
	_check(main_1.progress == 15, "Completed mission progress caps at the objective")
	bus.entity_died.emit("fish")
	_check(mm.get_mission("side_fish").progress == 0, "Progress only counts while a mission is active")
	player.inventory.add_item("wood", 20)
	player.inventory.set_max_weight(1000.0)  # room for every reward granted in this section
	_check(main_1.state == Mission.MissionState.COMPLETED and main_1.progress == 15, "Completed missions stop counting further pickups")
	_check(mm.accept_mission("main_2") == true, "Completed prerequisite unlocks the next main mission")
	var clay_before: int = player.inventory.get_item_quantity("clay")
	player.inventory.add_item("stone", 25)
	_check(mm.get_mission("main_2").state == Mission.MissionState.COMPLETED, "Second main mission completes")
	_check(player.inventory.get_item_quantity("clay") == clay_before + 15, "Second mission reward is granted")
	_check(technology_system.is_unlocked("stone_building"), "Research reward leaves the tech line available")
	mm.accept_mission("main_3")
	var hide_before: int = player.inventory.get_item_quantity("hide")
	bus.entity_died.emit("rabbit")
	bus.entity_died.emit("rabbit")
	bus.entity_died.emit("rabbit")
	_check(mm.get_mission("main_3").state == Mission.MissionState.COMPLETED, "Kill missions track creature deaths on the bus")
	_check(player.inventory.get_item_quantity("hide") == hide_before + 5, "Hunt reward (hide) is granted")
	mm.accept_mission("main_4")
	var metal_before: bool = technology_system.is_unlocked("metalworking")
	bus.building_placed.emit("campfire", Vector2i(3, 4))
	_check(mm.get_mission("main_4").state == Mission.MissionState.COMPLETED, "Build mission completes when the player places the building")
	_check(metal_before == false and technology_system.is_unlocked("metalworking"), "Research reward unlocks the technology for free")
	mm.accept_mission("side_forage")
	player.inventory.add_item("fibre", 12)
	_check(mm.get_mission("side_forage").state == Mission.MissionState.COMPLETED, "Side missions are completable from real play")
	mm.accept_mission("side_ore")
	player.inventory.add_item("copper_ore", 5)
	_check(mm.get_mission("side_ore").state == Mission.MissionState.COMPLETED, "Ore prospecting completes")
	mm.accept_mission("side_fish")
	bus.entity_died.emit("fish")
	bus.entity_died.emit("fish")
	bus.entity_died.emit("fish")
	_check(mm.get_mission("side_fish").state == Mission.MissionState.COMPLETED, "Fishing mission completes from kills")
	_check((mm.get_completed_missions() as Array).size() == 7, "All seven missions can complete in one run")
	_check(main.call("save_game"), "Mission progress can be saved")
	mm.start_new_world()
	_check(mm.get_mission("main_1").state == Mission.MissionState.IN_PROGRESS, "start_new_world() resets mission state for a new world")
	_check(mm.accept_mission("main_2") == false, "Second mission stays locked until the first completes")
	_check("First Steps" in mm.get_unmet_prerequisites("main_2"), "Locked mission names its unmet prerequisite")
	_check(main.call("load_game"), "Mission progress can be loaded")
	_check(mm.get_mission("main_1").state == Mission.MissionState.COMPLETED, "Mission state is restored from the save")
	_check((mm.get_completed_missions() as Array).size() == 7, "Completed missions persist across a save/load cycle")
	_check(mission_panel.get_node_or_null("MissionWindow") != null, "Mission journal builds its window UI")
	bus.toggle_missions_ui.emit()
	_check(mission_panel.visible == true, "M (bus toggle) opens the mission journal")
	bus.toggle_missions_ui.emit()
	_check(mission_panel.visible == false, "M again closes the mission journal")
	var v2_save: Dictionary = {"version": 2, "modules": {"world": {"seed": 77}, "player": {"position": {"x": 9.0, "y": 4.0}, "inventory": {"slots": {"wooden_axe": {"quantity": 1, "max_stack": 1}}}, "max_weight": 100.0, "max_slots": 50}}}
	var v2_migrated: Dictionary = ss.migrate(v2_save)
	_check(int(v2_migrated.get("version", 0)) == SaveSystem.SAVE_VERSION, "Legacy v2 save migrates to the current version")
	var v2_axe: Dictionary = v2_migrated["modules"]["player"]["inventory"]["slots"]["wooden_axe"]
	_check(int(v2_axe.get("durability", -1)) == 50, "Legacy v2 save backfills tool durability at full")

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

## True when the 32x32 atlas cell at (x, y) holds at least one opaque pixel.
func _atlas_cell_has_art(atlas: Image, x: int, y: int) -> bool:
	for py in range(32):
		for px in range(32):
			if atlas.get_pixel(x + px, y + py).a > 0.0:
				return true
	return false
