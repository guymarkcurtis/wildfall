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
	_check(world_registry.validation_errors.is_empty(),
		"Shipped world content passes startup validation with no errors")
	# Invalid-fixture suites: each points a fresh registry at a fixture dir
	# and checks that the collected errors name the offending asset and the
	# specific problem, so content authors get actionable failure messages.
	var missing_id_registry := _fixture_registry("missing_id")
	_check(_registry_errors_mention(missing_id_registry.validation_errors, "missing 'id'")
			and _registry_errors_mention(missing_id_registry.validation_errors, "no_id_biome.tres"),
		"Content asset without an id is reported with its path at startup")
	var duplicate_registry := _fixture_registry("duplicate_id")
	_check(_registry_errors_mention(duplicate_registry.validation_errors, "duplicate id")
			and _registry_errors_mention(duplicate_registry.validation_errors, "shared_biome"),
		"Duplicate content ids are reported at startup")
	_check(_registry_errors_mention(duplicate_registry.validation_errors, "shared_alpha.tres")
			and _registry_errors_mention(duplicate_registry.validation_errors, "shared_beta.tres"),
		"Duplicate-id report names both assets that claim the id")
	_check(duplicate_registry.biomes.has("ok_biome"),
		"Valid assets still register when a sibling asset fails validation")
	var invalid_range_registry := _fixture_registry("invalid_range")
	_check(_registry_errors_mention(invalid_range_registry.validation_errors, "inverted")
			and _registry_errors_mention(invalid_range_registry.validation_errors, "elevation_range"),
		"Inverted biome environment ranges are rejected at startup")
	_check(_registry_errors_mention(invalid_range_registry.validation_errors, "moisture_range")
			and _registry_errors_mention(invalid_range_registry.validation_errors, "outside the normalized"),
		"Environment ranges outside the 0..1 field are rejected at startup")
	var unknown_terrain_registry := _fixture_registry("unknown_terrain")
	_check(_registry_errors_mention(unknown_terrain_registry.validation_errors, "'crystal'"),
		"Unknown terrain tile ids are rejected at startup")
	_check(_registry_errors_mention(unknown_terrain_registry.validation_errors, "'void'"),
		"Unknown high-elevation terrain ids are rejected at startup")
	_check(_registry_errors_mention(unknown_terrain_registry.validation_errors, "water is a physical world system"),
		"Water posing as a biome terrain is rejected at startup")
	var dangling_registry := _fixture_registry("dangling_references")
	_check(_registry_errors_mention(dangling_registry.validation_errors, "ghost_neighbor"),
		"Dangling preferred-neighbor biome references are reported")
	_check(_registry_errors_mention(dangling_registry.validation_errors, "ghost_transition"),
		"Dangling transition biome references are reported")
	_check(_registry_errors_mention(dangling_registry.validation_errors, "ghost_resource"),
		"Dangling resource references from biomes are reported")
	var distribution_registry := _fixture_registry("unknown_distribution")
	_check(_registry_errors_mention(distribution_registry.validation_errors, "galactic")
			and _registry_errors_mention(distribution_registry.validation_errors, "distribution_mode"),
		"Unknown distribution modes are rejected at startup")
	var cave_links_registry := _fixture_registry("broken_cave_links")
	_check(_registry_errors_mention(cave_links_registry.validation_errors, "missing_poi"),
		"Cave entrance links to missing POIs are reported")
	_check(_registry_errors_mention(cave_links_registry.validation_errors, "allowed_biomes references unknown biome 'ghost_biome'"),
		"Cave biome links to missing biomes are reported")
	_check(_registry_errors_mention(cave_links_registry.validation_errors, "missing_ore"),
		"Cave resource links to missing resources are reported")
	_check(_registry_errors_mention(cave_links_registry.validation_errors, "ghost_poi"),
		"Cave interior POI links to missing POIs are reported")
	var combinations_registry := _fixture_registry("unspawnable_combinations")
	_check(_registry_errors_mention(combinations_registry.validation_errors, "ghost_ore")
			and _registry_errors_mention(combinations_registry.validation_errors, "can never spawn"),
		"Resources disabled on both surface and underground are reported")
	_check(_registry_errors_mention(combinations_registry.validation_errors, "deep_ore")
			and _registry_errors_mention(combinations_registry.validation_errors, "not surface_spawnable"),
		"Biomes listing underground-only resources are reported")
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
	# --- 2b. Generic POI layer: a POI no cave links to (WG-02) ------------
	# "survey_marker" is a minimal fixture that no cave definition references,
	# so it exercises the plain-POI path end to end: discovered from data,
	# generated with its own spacing grid, and loaded as a runtime node.
	var marker_poi: POIDefinition = world_registry.get_poi("survey_marker")
	var marker_cave_linked := false
	for cave_id_variant in world_gen.get_cave_definitions():
		var linked_cave: CaveDefinition = world_gen.get_cave(str(cave_id_variant))
		if linked_cave != null and linked_cave.entrance_poi_id == "survey_marker":
			marker_cave_linked = true
	_check(marker_poi != null and not marker_cave_linked,
			"POI with no cave definition is discovered from data alone")
	var poi_region_chunks: Array[Vector2i] = []
	for rx in range(-4, 5):
		for ry in range(-4, 5):
			poi_region_chunks.append(Vector2i(rx, ry))
	var region_candidates_first: Dictionary = {}
	var region_candidates_second: Dictionary = {}
	for poi_chunk_coords in poi_region_chunks:
		region_candidates_first[poi_chunk_coords] = (world_gen.generate_chunk(poi_chunk_coords) as Dictionary).get("poi_candidates", [])
		region_candidates_second[poi_chunk_coords] = (world_gen.generate_chunk(poi_chunk_coords) as Dictionary).get("poi_candidates", [])
	var marker_candidates: Array = []
	var entrance_candidates: Array = []
	for poi_chunk_coords in poi_region_chunks:
		for candidate in region_candidates_first[poi_chunk_coords]:
			if str(candidate.get("poi_id", "")) == "survey_marker":
				marker_candidates.append(candidate)
			elif str(candidate.get("poi_id", "")) == "cave_entrance":
				entrance_candidates.append(candidate)
	_check(not marker_candidates.is_empty(),
			"POI with no cave definition generates candidates across the region (%d found)" % marker_candidates.size())
	_check(str(region_candidates_first) == str(region_candidates_second),
			"POI candidates including the non-cave POI are stable across regeneration")
	# The live world's seed decides which biomes appear near the origin, so a
	# presence assertion for cave-linked POIs there would flake on seeds whose
	# origin region holds no eligible biome. A small fixture world (a
	# disposable generator whose registry points at
	# tests/fixtures/world_validation/poi_consumers) guarantees one cave-linked
	# POI and one plain POI running through the same generic candidate stage,
	# so the cave consumer is verified directly instead of by luck.
	var fixture_gen := WorldGenerator.new()
	fixture_gen.initialize(0, world_config)
	fixture_gen.content_registry = _fixture_registry("poi_consumers")
	var fixture_region_first: Dictionary = {}
	var fixture_region_second: Dictionary = {}
	for fx in range(-2, 3):
		for fy in range(-2, 3):
			var fixture_chunk_coords := Vector2i(fx, fy)
			fixture_region_first[fixture_chunk_coords] = (fixture_gen.generate_chunk(fixture_chunk_coords) as Dictionary).get("poi_candidates", [])
			fixture_region_second[fixture_chunk_coords] = (fixture_gen.generate_chunk(fixture_chunk_coords) as Dictionary).get("poi_candidates", [])
	var fixture_cave_candidates: Array = []
	var fixture_plain_candidates: Array = []
	for fixture_chunk_coords in fixture_region_first:
		for candidate in fixture_region_first[fixture_chunk_coords]:
			if str(candidate.get("poi_id", "")) == "fixture_cave_entrance":
				fixture_cave_candidates.append(candidate)
			elif str(candidate.get("poi_id", "")) == "fixture_plain_marker":
				fixture_plain_candidates.append(candidate)
	var fixture_cave_identity_ok := not fixture_cave_candidates.is_empty()
	for candidate in fixture_cave_candidates:
		var fixture_cave_type := str(candidate.get("cave_type_id", ""))
		if fixture_gen.get_cave(fixture_cave_type) == null \
				or str(candidate.get("cave_id", "")) != fixture_gen.generation_context.cave_identity(
					Vector2i(int(candidate.get("x", 0)), int(candidate.get("y", 0))), fixture_cave_type):
			fixture_cave_identity_ok = false
	_check(fixture_cave_identity_ok,
			"Cave-linked POIs are one consumer of the generic candidate stage (%d cave candidates, stable identities)" % fixture_cave_candidates.size())
	var fixture_plain_routing_ok := not fixture_plain_candidates.is_empty()
	for candidate in fixture_plain_candidates:
		if str(candidate.get("cave_type_id", "")) != "" or str(candidate.get("cave_id", "")) != "":
			fixture_plain_routing_ok = false
	_check(fixture_plain_routing_ok,
			"Non-cave POIs are the other consumer of the same stage (%d candidates, no cave identity)" % fixture_plain_candidates.size())
	_check(str(fixture_region_first) == str(fixture_region_second),
			"Cave-linked and generic POI candidates are both deterministic across regeneration")
	fixture_gen.free()
	var poi_boundary_clash := false
	var poi_claim_owner: Dictionary = {}
	for poi_chunk_coords in poi_region_chunks:
		for candidate in region_candidates_first[poi_chunk_coords]:
			var claim_key := "%s@%d,%d" % [str(candidate.get("poi_id", "")), int(candidate.get("x", 0)), int(candidate.get("y", 0))]
			if poi_claim_owner.has(claim_key) and poi_claim_owner[claim_key] != poi_chunk_coords:
				poi_boundary_clash = true
			elif not poi_claim_owner.has(claim_key):
				poi_claim_owner[claim_key] = poi_chunk_coords
	_check(not poi_boundary_clash, "No POI position is claimed by two different chunks across a chunk boundary")
	var marker_spacing_ok := marker_poi != null
	for first_index in range(marker_candidates.size()):
		for second_index in range(first_index):
			var first_tile := Vector2i(int(marker_candidates[first_index].get("x", 0)), int(marker_candidates[first_index].get("y", 0)))
			var second_tile := Vector2i(int(marker_candidates[second_index].get("x", 0)), int(marker_candidates[second_index].get("y", 0)))
			if maxi(absi(first_tile.x - second_tile.x), absi(first_tile.y - second_tile.y)) < marker_poi.min_spacing_tiles:
				marker_spacing_ok = false
	_check(marker_spacing_ok, "Non-cave POI candidates respect the asset's min_spacing_tiles across chunk boundaries")
	# Live scene: deliberately drain the pending chunk visuals, then verify
	# the generic POI consumer loaded the deterministic payload as nodes.
	main.call("flush_pending_chunk_visuals")
	var loaded_marker_nodes: Array = []
	for child in main.get_children():
		var marker_node: PoiMarker = child as PoiMarker
		if marker_node != null:
			loaded_marker_nodes.append(marker_node)
	_check(not loaded_marker_nodes.is_empty(),
			"Non-cave POIs load as runtime nodes in the live scene (%d markers)" % loaded_marker_nodes.size())
	var marker_loads_match_payload := not loaded_marker_nodes.is_empty()
	for marker_child in loaded_marker_nodes:
		var loaded_chunk: Dictionary = chunk_system.get_chunk(marker_child.get_meta("chunk_coords"))
		var payload_match := false
		for candidate in loaded_chunk.get("poi_candidates", []):
			if str(candidate.get("poi_id", "")) == "survey_marker" \
					and int(candidate.get("x", 0)) == marker_child.marker_tile.x \
					and int(candidate.get("y", 0)) == marker_child.marker_tile.y:
				payload_match = true
				break
		if not payload_match:
			marker_loads_match_payload = false
	_check(marker_loads_match_payload, "Every loaded POI node matches the deterministic payload of its chunk")
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

	# --- 2c. Coherent regions: minimum_region_size becomes geography (WG-03) --
	# The fixture world opts fx_meadow and fx_shrub into the coherent-region
	# stage (minimum_region_size = 256 tiles = 4 region cells); fx_bare keeps
	# the 0 default and stays out of it. The fixture's reduced biome weights
	# leave raw shrub fragments below that floor, so the stage has raw
	# islands to fold into neighbouring cells following the raw biome's
	# adjacency metadata. Every check below is world-coordinate based, so it
	# holds for any seed and any chunk box the world is grown in.
	var region_config: WorldGenerationConfig = world_config.duplicate() as WorldGenerationConfig
	region_config.regional_biome_weight = 0.25
	region_config.transition_biome_weight = 0.1
	region_config.preferred_neighbor_weight = 0.1
	var region_gen := WorldGenerator.new()
	region_gen.initialize(42, region_config)
	region_gen.content_registry = _fixture_registry("region_coherence")
	_check(region_gen.get_biomes().size() == 3 and region_gen.content_registry.validation_errors.is_empty(),
		"Coherent-region fixture discovers three biomes with no validation errors")
	_check(int(region_gen.get_biome("fx_meadow").minimum_region_size) == 256 \
			and int(region_gen.get_biome("fx_shrub").minimum_region_size) == 256 \
			and int(region_gen.get_biome("fx_bare").minimum_region_size) == 0,
		"Minimum region sizes are read from biome data, not hard-coded")
	var region_box: Dictionary = {}
	for rx in range(-4, 5):
		for ry in range(-4, 5):
			region_box[Vector2i(rx, ry)] = region_gen.generate_chunk(Vector2i(rx, ry))
	var region_box_complete := 0
	for region_coords_key in region_box:
		if not (region_box[region_coords_key] as Dictionary).is_empty():
			region_box_complete += 1
	_check(region_box_complete == 81, "Coherent-region fixture generates the full 9x9-chunk box")
	var region_cell_size: int = region_config.region_cell_size_tiles
	var cell_grid_ok := true
	for region_coords_key in region_box:
		var region_chunk_coords: Vector2i = region_coords_key
		var region_entries: Array = (region_box[region_coords_key] as Dictionary).get("region_cells", [])
		var region_cell_set: Dictionary = {}
		for region_entry in region_entries:
			region_cell_set[region_entry.get("cell")] = true
		if region_cell_set.size() != 4:
			cell_grid_ok = false
			break
		for region_dx in range(2):
			for region_dy in range(2):
				if not region_cell_set.has(Vector2i(region_chunk_coords.x * 2 + region_dx,
						region_chunk_coords.y * 2 + region_dy)):
					cell_grid_ok = false
	_check(cell_grid_ok, "Region cells are world-aligned 8-tile squares: exactly 2x2 per chunk, none straddling a boundary")
	# No raw fragment the data says is too small may survive the stage. The
	# per-cell window is re-measured here against the same shared raw map the
	# stage used (the generator's memo), so a kept cell is verified against
	# the exact fragment it was decided on.
	var region_min_sizes: Dictionary = {}
	for region_biome_id in region_gen.get_biomes().keys():
		var region_biome_definition := region_gen.get_biome(str(region_biome_id))
		if region_biome_definition != null and region_biome_definition.minimum_region_size > 0:
			region_min_sizes[str(region_biome_id)] = int(region_biome_definition.minimum_region_size)
	var raw_island_violations := 0
	var region_merged_count := 0
	var region_kept_count := 0
	for region_coords_key in region_box:
		for region_entry in (region_box[region_coords_key] as Dictionary).get("region_cells", []):
			var region_source := str(region_entry.get("source", ""))
			if region_source == "merged":
				region_merged_count += 1
			if region_source != "kept":
				continue
			region_kept_count += 1
			var region_raw_biome := str(region_entry.get("raw", ""))
			if not region_min_sizes.has(region_raw_biome):
				continue
			var region_cell: Vector2i = region_entry.get("cell")
			var region_cells_needed: int = ceili(float(region_min_sizes[region_raw_biome]) / float(region_cell_size * region_cell_size))
			var region_window: int = maxi(1, ceili(sqrt(float(maxi(region_cells_needed, 1))) / 2.0))
			var region_fragment_seen: Dictionary = {region_cell: true}
			var region_fragment_stack: Array[Vector2i] = [region_cell]
			while not region_fragment_stack.is_empty():
				var region_current: Vector2i = region_fragment_stack.pop_back()
				for region_fx in range(-1, 2):
					for region_fy in range(-1, 2):
						if region_fx == 0 and region_fy == 0:
							continue
						var region_neighbour_cell: Vector2i = region_current + Vector2i(region_fx, region_fy)
						if region_fragment_seen.has(region_neighbour_cell):
							continue
						if absi(region_neighbour_cell.x - region_cell.x) > region_window or absi(region_neighbour_cell.y - region_cell.y) > region_window:
							continue
						if str(region_gen._cell_dominant_biome(region_neighbour_cell)) == region_raw_biome:
							region_fragment_seen[region_neighbour_cell] = true
							region_fragment_stack.append(region_neighbour_cell)
			if region_fragment_seen.size() * region_cell_size * region_cell_size < int(region_min_sizes[region_raw_biome]):
				raw_island_violations += 1
	_check(raw_island_violations == 0, "No kept region cell leaves a raw fragment below its biome's minimum region size (%d/%d kept cells)" % [raw_island_violations, region_kept_count])
	_check(region_merged_count > 0, "Raw fragments below the data floor are folded into neighbouring cells (%d merged in the box)" % region_merged_count)
	# The receiver a merged cell joins follows the raw biome's authored
	# adjacency: a preferred neighbour always wins (score 2.0 beats any
	# 0.1-per-adjacency score), then a transition neighbour (1.0), then
	# plain adjacency count, then id order.
	var region_receiver_ok := true
	for region_coords_key in region_box:
		for region_entry in (region_box[region_coords_key] as Dictionary).get("region_cells", []):
			if str(region_entry.get("source", "")) != "merged":
				continue
			var region_cell: Vector2i = region_entry.get("cell")
			var region_raw_biome := str(region_entry.get("raw", ""))
			var region_receiver := str(region_entry.get("biome", ""))
			var region_raw_definition := region_gen.get_biome(region_raw_biome)
			if region_raw_definition == null:
				region_receiver_ok = false
				continue
			var region_neighbour_biomes: Dictionary = {}
			for region_nx in range(-1, 2):
				for region_ny in range(-1, 2):
					if absi(region_nx) + absi(region_ny) != 1:
						continue
					var region_neighbour_biome := str(region_gen._cell_dominant_biome(region_cell + Vector2i(region_nx, region_ny)))
					if region_neighbour_biome != "":
						region_neighbour_biomes[region_neighbour_biome] = true
			var region_has_preferred := false
			var region_has_transition := false
			for region_candidate_id in region_neighbour_biomes:
				if region_raw_definition.preferred_neighbors.has(str(region_candidate_id)):
					region_has_preferred = true
				elif region_raw_definition.transition_biome_ids.has(str(region_candidate_id)):
					region_has_transition = true
			if region_has_preferred:
				if not region_raw_definition.preferred_neighbors.has(region_receiver):
					region_receiver_ok = false
			elif region_has_transition:
				if not region_raw_definition.transition_biome_ids.has(region_receiver):
					region_receiver_ok = false
			elif not region_neighbour_biomes.has(region_receiver):
				region_receiver_ok = false
	_check(region_receiver_ok, "Merged cells join a neighbouring cell's biome, preferring the raw biome's authored adjacency metadata")
	# Payload and on-demand query are the same stage result, tile for tile,
	# including water tiles (the stage rewrites land tiles only, and the
	# query path keeps the raw biome under water).
	var region_tile_disagreements := 0
	var region_tiles_checked := 0
	for region_coords_key in region_box:
		var region_chunk_payload: Dictionary = region_box[region_coords_key]
		var region_biomes: PackedStringArray = region_chunk_payload["biomes"]
		var region_world_start: Vector2i = (region_coords_key as Vector2i) * region_config.chunk_size_tiles
		for region_ty in range(region_config.chunk_size_tiles):
			for region_tx in range(region_config.chunk_size_tiles):
				region_tiles_checked += 1
				if str(region_gen.get_biome_at_world(region_world_start.x + region_tx,
						region_world_start.y + region_ty)) != str(region_biomes[region_ty * region_config.chunk_size_tiles + region_tx]):
					region_tile_disagreements += 1
	_check(region_tile_disagreements == 0, "Payload and on-demand biome queries agree at every tile of the region box, water included (%d tiles)" % region_tiles_checked)
	# Seam stability: the same chunk generated alone (only its own halo) or
	# inside the box (its neighbours' halos cached first) must produce the
	# same payload — adjacent chunks therefore always match at boundaries.
	var region_seam_alone_gen := WorldGenerator.new()
	region_seam_alone_gen.initialize(42, region_config.duplicate() as WorldGenerationConfig)
	region_seam_alone_gen.content_registry = _fixture_registry("region_coherence")
	var region_seam_alone: Dictionary = region_seam_alone_gen.generate_chunk(Vector2i(0, 0))
	region_seam_alone_gen.free()
	var region_seam_in_box: Dictionary = region_box[Vector2i(0, 0)]
	_check(str(region_seam_in_box.get("biomes", [])) == str(region_seam_alone.get("biomes", [])) \
			and str(region_seam_in_box.get("region_cells", [])) == str(region_seam_alone.get("region_cells", [])),
		"Seam chunk payload is identical whether generated alone or inside the region box")
	var region_gen_reversed := WorldGenerator.new()
	region_gen_reversed.initialize(42, region_config.duplicate() as WorldGenerationConfig)
	region_gen_reversed.content_registry = _fixture_registry("region_coherence")
	var region_box_reversed: Dictionary = {}
	for rx in range(4, -5, -1):
		for ry in range(4, -5, -1):
			region_box_reversed[Vector2i(rx, ry)] = region_gen_reversed.generate_chunk(Vector2i(rx, ry))
	region_gen_reversed.free()
	region_gen.free()
	# Compare per-chunk, not by stringifying the whole box: a Dictionary's
	# string form follows insertion order, and the reversed run inserts its
	# chunks in a different order. Per-chunk payloads are built by one code
	# path, so their key order matches and the string comparison is a
	# faithful content comparison.
	var region_box_key_set: Dictionary = {}
	for region_coords_key in region_box:
		region_box_key_set[region_coords_key] = true
	var region_reversed_key_set: Dictionary = {}
	for region_coords_key in region_box_reversed:
		region_reversed_key_set[region_coords_key] = true
	var region_order_same := region_box_key_set == region_reversed_key_set
	for region_coords_key in region_box:
		if not region_order_same:
			break
		if str(region_box[region_coords_key]) != str(region_box_reversed[region_coords_key]):
			region_order_same = false
	_check(region_order_same,
		"Region decisions and full chunk payloads are identical in reversed generation order")
	# The shipped world's biomes all keep the 0 default, so the stage must
	# stay dormant there: no region_cells records and byte-identical biomes
	# versus the on-demand query, on the live seed.
	var region_dormant_gen := WorldGenerator.new()
	region_dormant_gen.initialize(world_gen.get_seed(), world_config)
	region_dormant_gen.content_registry = world_gen.get_content_registry()
	var region_dormant_chunk: Dictionary = region_dormant_gen.generate_chunk(Vector2i(3, 3))
	var region_dormant_mismatches := 0
	var region_dormant_noop := region_dormant_chunk.has("region_cells") \
			and (region_dormant_chunk["region_cells"] as Array).is_empty()
	if region_dormant_noop:
		var region_dormant_start: Vector2i = Vector2i(3, 3) * world_config.chunk_size_tiles
		var region_dormant_biomes: PackedStringArray = region_dormant_chunk["biomes"]
		for region_dy in range(world_config.chunk_size_tiles):
			for region_dx in range(world_config.chunk_size_tiles):
				if str(region_dormant_gen.get_biome_at_world(region_dormant_start.x + region_dx,
						region_dormant_start.y + region_dy)) != str(region_dormant_biomes[region_dy * world_config.chunk_size_tiles + region_dx]):
					region_dormant_mismatches += 1
	region_dormant_gen.free()
	_check(region_dormant_noop and region_dormant_mismatches == 0,
		"Shipped world keeps byte-identical biome maps with the stage dormant (all minimum region sizes 0)")

	# --- 2d. Terrain-feature candidate layer: the seam for structure (WG-04)
	# Terrain features (cliffs, clearings, scree, ...) become generic mask
	# layers between biome selection and the placement stages: each feature
	# definition discovered from data emits deterministic candidates through
	# the same anchor-grid machinery as POIs, and the payload's
	# feature_candidates array feeds both the runtime marker and the
	# resource spawner's spawn veto. The shipped world carries no feature
	# assets, so the stage is dormant there. The fixture world below adds
	# two feature assets with zero generator code changes — that is the
	# done-when witness for this card.
	var feature_registry := _fixture_registry("terrain_features")
	var fixture_scree: TerrainFeatureDefinition = feature_registry.get_terrain_feature("fixture_scree")
	var fixture_clearing: TerrainFeatureDefinition = feature_registry.get_terrain_feature("fixture_clearing")
	_check(fixture_scree != null and fixture_clearing != null and feature_registry.validation_errors.is_empty(),
			"Terrain-feature definitions are discovered from data and pass startup validation (2 assets, 0 errors)")
	_check(world_registry.terrain_features.is_empty(),
			"Shipped world carries no terrain-feature assets, so the stage is dormant there")
	_check(fixture_scree != null and fixture_scree.min_spacing_tiles == 16 and fixture_scree.footprint_radius_tiles == 1
			and (fixture_scree.influence_tags as PackedStringArray).has("no_spawn")
			and fixture_clearing != null and fixture_clearing.min_spacing_tiles == 24 and fixture_clearing.footprint_radius_tiles == 2
			and (fixture_clearing.influence_tags as PackedStringArray).has("open_ground"),
			"Feature spacing, footprint, and influence tags are data, not code")
	var feature_gen := WorldGenerator.new()
	feature_gen.initialize(42, world_config.duplicate() as WorldGenerationConfig)
	feature_gen.content_registry = feature_registry
	var feature_box_first: Dictionary = {}
	var feature_box_second: Dictionary = {}
	for ftx in range(-2, 3):
		for fty in range(-2, 3):
			var feature_chunk_coords := Vector2i(ftx, fty)
			feature_box_first[feature_chunk_coords] = feature_gen.generate_chunk(feature_chunk_coords)
			feature_box_second[feature_chunk_coords] = feature_gen.generate_chunk(feature_chunk_coords)
	var feature_scree_candidates: Array = []
	var feature_clearing_candidates: Array = []
	for feature_chunk_coords in feature_box_first:
		for candidate in feature_box_first[feature_chunk_coords].get("feature_candidates", []):
			if str(candidate.get("feature_id", "")) == "fixture_scree":
				feature_scree_candidates.append(candidate)
			elif str(candidate.get("feature_id", "")) == "fixture_clearing":
				feature_clearing_candidates.append(candidate)
	_check(not feature_scree_candidates.is_empty() and not feature_clearing_candidates.is_empty(),
			"Both feature assets emit candidates with no generator code change (%d scree, %d clearing) — the done-when seam" % [feature_scree_candidates.size(), feature_clearing_candidates.size()])
	_check(str(feature_box_first) == str(feature_box_second),
			"Feature candidates (including halo entries from neighbouring chunks) are stable across regeneration")
	var feature_seam_gen := WorldGenerator.new()
	feature_seam_gen.initialize(42, world_config.duplicate() as WorldGenerationConfig)
	feature_seam_gen.content_registry = _fixture_registry("terrain_features")
	var feature_seam_alone: Dictionary = feature_seam_gen.generate_chunk(Vector2i(0, 0))
	feature_seam_gen.free()
	_check(str(feature_box_first[Vector2i(0, 0)]) == str(feature_seam_alone),
			"Seam chunk payload (biomes, region cells, feature mask) is identical generated alone vs inside the box")
	var feature_gen_reversed := WorldGenerator.new()
	feature_gen_reversed.initialize(42, world_config.duplicate() as WorldGenerationConfig)
	feature_gen_reversed.content_registry = _fixture_registry("terrain_features")
	var feature_box_reversed: Dictionary = {}
	for rtx in range(2, -3, -1):
		for rty in range(2, -3, -1):
			feature_box_reversed[Vector2i(rtx, rty)] = feature_gen_reversed.generate_chunk(Vector2i(rtx, rty))
	feature_gen_reversed.free()
	var feature_order_same := (feature_box_first as Dictionary).size() == (feature_box_reversed as Dictionary).size()
	for feature_coords_key in feature_box_first:
		if not feature_order_same:
			break
		if not feature_box_reversed.has(feature_coords_key) \
				or str(feature_box_first[feature_coords_key]) != str(feature_box_reversed[feature_coords_key]):
			feature_order_same = false
	_check(feature_order_same,
			"Feature masks and complete chunk payloads are identical in reversed generation order")
	var feature_owner_clash := false
	for feature_chunk_coords in feature_box_first:
		var feature_candidates_list: Array = feature_box_first[feature_chunk_coords].get("feature_candidates", [])
		for candidate in feature_candidates_list:
			var feature_anchor := Vector2i(int(candidate.get("x", 0)), int(candidate.get("y", 0)))
			var feature_owner := Vector2i(floori(float(feature_anchor.x) / float(world_config.chunk_size_tiles)),
					floori(float(feature_anchor.y) / float(world_config.chunk_size_tiles)))
			if bool(candidate.get("in_chunk", false)) != (feature_chunk_coords == feature_owner):
				feature_owner_clash = true
	_check(not feature_owner_clash,
			"Halo candidates always report their anchor's own chunk, and in_chunk marks exactly the owners")
	var feature_spacing_ok := true
	for first_index in range(feature_scree_candidates.size()):
		for second_index in range(first_index):
			var first_tile := Vector2i(int(feature_scree_candidates[first_index].get("x", 0)), int(feature_scree_candidates[first_index].get("y", 0)))
			var second_tile := Vector2i(int(feature_scree_candidates[second_index].get("x", 0)), int(feature_scree_candidates[second_index].get("y", 0)))
			if maxi(absi(first_tile.x - second_tile.x), absi(first_tile.y - second_tile.y)) < fixture_scree.min_spacing_tiles:
				feature_spacing_ok = false
	_check(fixture_scree != null and feature_spacing_ok,
			"Feature candidates respect the asset's min_spacing_tiles across chunk boundaries")
	var feature_block_probe := false
	var feature_block_probe_found := false
	for feature_chunk_coords in feature_box_first:
		var probe_candidates: Array = feature_box_first[feature_chunk_coords].get("feature_candidates", [])
		for candidate in probe_candidates:
			if str(candidate.get("feature_id", "")) != "fixture_scree" or not bool(candidate.get("in_chunk", false)):
				continue
			var probe_tile := Vector2i(int(candidate.get("x", 0)), int(candidate.get("y", 0)))
			var probe_radius := int(candidate.get("footprint_radius_tiles", 0))
			feature_block_probe = ResourceSpawner.is_feature_blocked_tile(probe_tile, probe_candidates) \
					and ResourceSpawner.is_feature_blocked_tile(Vector2i(probe_tile.x + probe_radius, probe_tile.y), probe_candidates) \
					and not ResourceSpawner.is_feature_blocked_tile(Vector2i(probe_tile.x + probe_radius + 1, probe_tile.y), probe_candidates)
			feature_block_probe_found = true
			break
		if feature_block_probe_found:
			break
	_check(feature_block_probe_found and feature_block_probe,
			"The spawner's mask helper vetoes exactly the tiles a no_spawn feature's footprint covers")
	var fixture_spawner := ResourceSpawner.new()
	fixture_spawner.world_generator = feature_gen
	fixture_spawner.initialize(42)
	var fixture_spawned_total := 0
	var fixture_spawned_blocked := 0
	for feature_chunk_coords in feature_box_first:
		var spawned: Array = fixture_spawner.generate_chunk_resources(feature_chunk_coords, 42,
				feature_box_first[feature_chunk_coords].get("feature_candidates", []))
		fixture_spawned_total += spawned.size()
		var blocked_tiles: Dictionary = {}
		for candidate in feature_box_first[feature_chunk_coords].get("feature_candidates", []):
			var candidate_tags = candidate.get("influence_tags", PackedStringArray())
			if not (candidate_tags is PackedStringArray and (candidate_tags as PackedStringArray).has(ResourceSpawner.NO_SPAWN_FEATURE_TAG)):
				continue
			var candidate_anchor_x := int(candidate.get("x", 0))
			var candidate_anchor_y := int(candidate.get("y", 0))
			var candidate_radius := int(candidate.get("footprint_radius_tiles", 0))
			for dy in range(-candidate_radius, candidate_radius + 1):
				for dx in range(-candidate_radius, candidate_radius + 1):
					blocked_tiles[Vector2i(candidate_anchor_x + dx, candidate_anchor_y + dy)] = true
		for record in spawned:
			var tile := Vector2i(int(record.get("x", 0)), int(record.get("y", 0)))
			if blocked_tiles.has(tile):
				fixture_spawned_blocked += 1
	_check(fixture_spawned_total > 0 and fixture_spawned_blocked == 0,
			"Resources spawn in the fixture world and none on tiles vetoed by the no_spawn feature mask (%d placed, %d vetoed)" % [fixture_spawned_total, fixture_spawned_blocked])
	fixture_spawner.free()
	feature_gen.free()
	var live_feature_markers := 0
	for child in main.get_children():
		if child is TerrainFeatureMarker:
			live_feature_markers += 1
	_check(live_feature_markers == 0,
			"Live scene spawns no feature markers while the shipped world carries no feature assets")
	var live_feature_payload: Dictionary = chunk_system.get_chunk(Vector2i(0, 0))
	_check((live_feature_payload.get("feature_candidates", []) as Array).is_empty(),
			"Live chunk payloads carry an empty feature layer while the stage is dormant")
	var feature_marker_probe := TerrainFeatureMarker.new()
	main.add_child(feature_marker_probe)
	var feature_marker_setup_ok := false
	if not feature_clearing_candidates.is_empty():
		feature_marker_probe.setup(feature_clearing_candidates[0])
		feature_marker_setup_ok = feature_marker_probe.marker_tile == Vector2i(int(feature_clearing_candidates[0].get("x", 0)),
				int(feature_clearing_candidates[0].get("y", 0))) \
				and feature_marker_probe.footprint_radius_tiles == int(feature_clearing_candidates[0].get("footprint_radius_tiles", 0)) \
				and feature_marker_probe.feature_id == "fixture_clearing" \
				and feature_marker_probe.feature_identity == "%s@%d,%d" % [str(feature_marker_probe.feature_id), feature_marker_probe.marker_tile.x, feature_marker_probe.marker_tile.y]
	feature_marker_probe.queue_free()
	_check(feature_marker_setup_ok,
			"TerrainFeatureMarker nodes carry stable identity and footprint from the payload")
	var invalid_feature_registry := _fixture_registry("invalid_feature")
	_check(invalid_feature_registry.has_validation_errors() \
			and _registry_errors_mention(invalid_feature_registry.validation_errors, "missing_biome"),
			"Feature assets with dangling biome references fail startup validation like other content")

	# --- 2e. WG-05: water classes + shore distance field -------------------
	# Water is a physical world system, not an ordinary biome: chunk
	# payloads additionally carry water_class ("land" / "shore" / "coast" /
	# "deep_water"), water_origin ("ocean" for water below the water level,
	# "lake" for water at or above it, "" on land) and a Chebyshev
	# distance_to_water field: 0 on water tiles, 1..cap - 1 exact, and the
	# cap value meaning "no water within cap - 1 tiles". Biomes, POIs,
	# terrain features and resources may each opt into min/max distance
	# values, and the generator, spawner and public queries branch only on
	# those fields - never on water-body names.

	# 2e.1 A small 6x6-chunk fixture world (seed 42) whose lake thresholds
	# sit above the water level, so both water origins occur. All of its
	# content is constrained purely by the distance field.
	var water_fixture_registry := _fixture_registry("water_classification")
	_check(water_fixture_registry.validation_errors.is_empty(),
			"WG-05 fixture world (distance-constrained water content) passes registry validation")
	_check(water_fixture_registry.biomes.size() == 2 and water_fixture_registry.pois.size() == 1 \
			and water_fixture_registry.terrain_features.size() == 1 and water_fixture_registry.resources.size() == 1,
			"WG-05 fixture world registers exactly 2 distance-constrained biomes, 1 POI, 1 terrain feature and 1 resource")

	# 2e.2 Every live definition keeps -1/-1, so the new field vetoes
	# nothing in the live world the game actually ships. This is the same
	# scan the generator's on-demand distance gate performs.
	var live_content_unconstrained: bool = true
	for biome_id in world_registry.biomes.keys():
		var biome := world_registry.get_biome(str(biome_id))
		if biome != null and (biome.min_distance_to_water != -1 or biome.max_distance_to_water != -1):
			live_content_unconstrained = false
	for poi_id in world_registry.pois.keys():
		var poi := world_registry.get_poi(str(poi_id))
		if poi != null and (poi.min_distance_to_water != -1 or poi.max_distance_to_water != -1):
			live_content_unconstrained = false
	for feature_id in world_registry.terrain_features.keys():
		var feature := world_registry.get_terrain_feature(str(feature_id))
		if feature != null and (feature.min_distance_to_water != -1 or feature.max_distance_to_water != -1):
			live_content_unconstrained = false
	for resource_id in world_registry.resources.keys():
		var resource := world_registry.get_resource(str(resource_id))
		if resource != null and (resource.min_distance_to_water != -1 or resource.max_distance_to_water != -1):
			live_content_unconstrained = false
	_check(live_content_unconstrained,
			"WG-05 leaves every live biome, POI, terrain feature and resource distance-unconstrained (-1/-1)")

	# 2e.3 Generate the fixture world once, chunk by chunk, and check the
	# three new payload keys arrive at full chunk size.
	var water_fixture_config := _fixture_config("water_classification")
	var water_fixture_gen := WorldGenerator.new()
	water_fixture_gen.initialize(42, water_fixture_config)
	water_fixture_gen.content_registry = water_fixture_registry
	var fixture_chunk_size: int = water_fixture_config.chunk_size_tiles
	var fixture_chunk_coords: Array[Vector2i] = []
	for fx in range(water_fixture_config.world_dimensions_chunks.x):
		for fy in range(water_fixture_config.world_dimensions_chunks.y):
			fixture_chunk_coords.append(water_fixture_config.world_origin_chunk + Vector2i(int(fx), int(fy)))
	var water_first: Dictionary = {}
	for chunk_coords in fixture_chunk_coords:
		water_first[chunk_coords] = water_fixture_gen.generate_chunk(chunk_coords)
	var water_payloads_ok: bool = water_first.size() == fixture_chunk_coords.size()
	for chunk_coords in fixture_chunk_coords:
		var fixture_payload: Dictionary = water_first[chunk_coords]
		if not (fixture_payload.has("water_class") and fixture_payload.has("water_origin") \
				and fixture_payload.has("distance_to_water")):
			water_payloads_ok = false
		elif (fixture_payload["water_class"] as PackedStringArray).size() != fixture_chunk_size * fixture_chunk_size \
				or (fixture_payload["water_origin"] as PackedStringArray).size() != fixture_chunk_size * fixture_chunk_size \
				or (fixture_payload["distance_to_water"] as PackedInt32Array).size() != fixture_chunk_size * fixture_chunk_size:
			water_payloads_ok = false
	_check(water_payloads_ok,
			"WG-05 fixture world: every chunk payload carries water_class, water_origin and distance_to_water at full chunk size")

	# The generator samples each chunk from its own rect grown by the cap on
	# every side (UNCLAMPED: noise and water continue past the finite
	# world). Every water tile within the cap of a core tile lies inside
	# that rect, distances up to the cap are exact, and everything at the
	# cap or beyond saturates to the cap - so one world-wide reference rect
	# (which contains every per-chunk rect) computes the identical value for
	# every tile. The field is a pure function of world coordinates + seed +
	# config, and the reference below is that function computed by an
	# independent copy of the BFS.
	var water_cap: int = water_fixture_config.distance_to_water_cap_tiles
	var fixture_tile_start: Vector2i = water_fixture_config.world_origin_chunk * fixture_chunk_size
	var ref_side_x: int = int(water_fixture_config.world_dimensions_chunks.x) * fixture_chunk_size + 2 * water_cap
	var ref_side_y: int = int(water_fixture_config.world_dimensions_chunks.y) * fixture_chunk_size + 2 * water_cap
	var ref_start: Vector2i = fixture_tile_start - Vector2i(water_cap, water_cap)
	var ref_water := PackedInt32Array()
	ref_water.resize(ref_side_x * ref_side_y)
	var ref_elevations := PackedFloat32Array()
	ref_elevations.resize(ref_side_x * ref_side_y)
	for w_y in range(ref_side_y):
		for w_x in range(ref_side_x):
			var tile_x: int = int(ref_start.x) + int(w_x)
			var tile_y: int = int(ref_start.y) + int(w_y)
			var tile_values: Dictionary = water_fixture_gen.get_noise_values(float(tile_x), float(tile_y))
			var is_reference_water: bool = water_fixture_gen._is_water(
					float(tile_values["elevation"]), float(tile_values["moisture"]), float(tile_values["water"]))
			ref_water[int(w_y) * ref_side_x + int(w_x)] = 1 if is_reference_water else 0
			ref_elevations[int(w_y) * ref_side_x + int(w_x)] = float(tile_values["elevation"])
	var ref_dist := _wg05_bfs_reference(ref_side_x, ref_side_y, water_cap, ref_water)
	var fixture_distance_matches: bool = true
	var fixture_class_matches: bool = true
	var fixture_origin_matches: bool = true
	var on_demand_sample_indices: Array[int] = [0, 7, 8, 15, 105, 127, 128, 130, 152, 200, 240, 255]
	for chunk_coords in fixture_chunk_coords:
		var fixture_payload: Dictionary = water_first[chunk_coords]
		var chunk_mask: PackedByteArray = fixture_payload["water_mask"]
		var chunk_dist: PackedInt32Array = fixture_payload["distance_to_water"]
		var chunk_class: PackedStringArray = fixture_payload["water_class"]
		var chunk_origin: PackedStringArray = fixture_payload["water_origin"]
		var world_start: Vector2i = chunk_coords * fixture_chunk_size
		for index in range(fixture_chunk_size * fixture_chunk_size):
			var wx: int = int(world_start.x) + (index % fixture_chunk_size)
			var wy: int = int(world_start.y) + (index / fixture_chunk_size)
			var ref_index: int = (wy - int(ref_start.y)) * ref_side_x + (wx - int(ref_start.x))
			var raw_dist: int = int(ref_dist[ref_index])
			var expected_dist: int = water_cap if raw_dist < 0 or raw_dist >= water_cap else raw_dist
			if int(chunk_dist[index]) != expected_dist:
				fixture_distance_matches = false
			var adjacent_water: int = 0
			var ry: int = wy - int(ref_start.y)
			var rx: int = wx - int(ref_start.x)
			for d_y in range(-1, 2):
				for d_x in range(-1, 2):
					if int(d_x) == 0 and int(d_y) == 0:
						continue
					var n_y: int = ry + int(d_y)
					var n_x: int = rx + int(d_x)
					if n_y < 0 or n_y >= ref_side_y or n_x < 0 or n_x >= ref_side_x:
						continue
					if ref_water[n_y * ref_side_x + n_x] == 1:
						adjacent_water += 1
			var is_water_tile: bool = int(chunk_mask[index]) == 1
			var expected_class: String = "coast" if is_water_tile and adjacent_water < 8 \
					else ("deep_water" if is_water_tile else ("shore" if adjacent_water > 0 else "land"))
			if str(chunk_class[index]) != expected_class:
				fixture_class_matches = false
			var expected_origin: String = ""
			if is_water_tile:
				expected_origin = "ocean" if float(ref_elevations[ref_index]) < water_fixture_config.water_level else "lake"
			if str(chunk_origin[index]) != expected_origin:
				fixture_origin_matches = false
	_check(fixture_distance_matches,
			"WG-05 fixture world: the payload distance field matches an independent world-wide BFS with cap saturation on all 12,544 tiles")
	_check(fixture_class_matches,
			"WG-05 fixture world: water classes (land/shore/coast/deep_water) match an independent 8-neighbour recount on all 12,544 tiles")
	_check(fixture_origin_matches,
			"WG-05 fixture world: water origins match the water-level rule (ocean below, lake at or above) on all 12,544 tiles")
	var seen_classes: Dictionary = {}
	var seen_origins: Dictionary = {}
	for chunk_coords in fixture_chunk_coords:
		var fixture_payload: Dictionary = water_first[chunk_coords]
		for class_entry in fixture_payload["water_class"]:
			seen_classes[str(class_entry)] = int(seen_classes.get(str(class_entry), 0)) + 1
		for origin_entry in fixture_payload["water_origin"]:
			if str(origin_entry) != "":
				seen_origins[str(origin_entry)] = int(seen_origins.get(str(origin_entry), 0)) + 1
	_check(seen_classes.has("land") and seen_classes.has("shore") and seen_classes.has("coast") and seen_classes.has("deep_water"),
			"WG-05 fixture world produces all four water classes (land, shore, coast, deep_water) - water is a physical system, not a biome")
	_check(seen_origins.has("ocean") and seen_origins.has("lake"),
			"WG-05 fixture world produces both water origins (ocean below the level, lake above it)")

	# The fixture biomes consume the field through their own min/max
	# constraints alone: distance <= 1 selects fixture_shore, distance >= 2
	# selects fixture_grassland - an exact partition of the land tiles that
	# no water-body name appears in.
	var fixture_biome_consumption_ok: bool = true
	for chunk_coords in fixture_chunk_coords:
		var fixture_payload: Dictionary = water_first[chunk_coords]
		var chunk_mask: PackedByteArray = fixture_payload["water_mask"]
		var chunk_dist: PackedInt32Array = fixture_payload["distance_to_water"]
		var chunk_biomes: PackedStringArray = fixture_payload["biomes"]
		for index in range(fixture_chunk_size * fixture_chunk_size):
			if int(chunk_mask[index]) != 0:
				continue
			var expected_biome: String = "fixture_grassland" if int(chunk_dist[index]) >= 2 else "fixture_shore"
			if str(chunk_biomes[index]) != expected_biome:
				fixture_biome_consumption_ok = false
	_check(fixture_biome_consumption_ok,
			"WG-05: distance constraints alone pick the fixture biomes (distance <= 1 selects fixture_shore, >= 2 selects fixture_grassland) with no water-body names in code")
	var water_legacy_biome_matches: bool = true
	for chunk_coords in fixture_chunk_coords:
		var fixture_payload: Dictionary = water_first[chunk_coords]
		var chunk_mask: PackedByteArray = fixture_payload["water_mask"]
		var chunk_biomes: PackedStringArray = fixture_payload["biomes"]
		var world_start: Vector2i = chunk_coords * fixture_chunk_size
		for index in range(fixture_chunk_size * fixture_chunk_size):
			if int(chunk_mask[index]) == 0:
				continue
			var wx: int = int(world_start.x) + (index % fixture_chunk_size)
			var wy: int = int(world_start.y) + (index / fixture_chunk_size)
			var expected_biome: String = _legacy_select_biome_at(water_fixture_gen,
					float(fixture_payload["elevation"][index]),
					float(fixture_payload["moisture"][index]),
					float(fixture_payload["temperature"][index]),
					water_fixture_gen.get_regional_noise_values(wx, wy))
			if str(chunk_biomes[index]) != expected_biome:
				water_legacy_biome_matches = false
	_check(water_legacy_biome_matches,
			"WG-05: water tiles keep the exact pre-WG-05 (unconstrained, region-weighted) biome - the distance field vetoes, it never re-selects water")

	var water_fixture_gen_second := WorldGenerator.new()
	water_fixture_gen_second.initialize(42, water_fixture_config)
	water_fixture_gen_second.content_registry = water_fixture_registry
	var second_payloads_ok: bool = true
	for chunk_coords in fixture_chunk_coords:
		var first_payload: Dictionary = water_first[chunk_coords]
		var second_payload: Dictionary = water_fixture_gen_second.generate_chunk(chunk_coords)
		for payload_key in ["biomes", "water_mask", "distance_to_water", "water_class", "water_origin"]:
			if str(second_payload.get(payload_key, "%%missing%%")) != str(first_payload.get(payload_key, "%%missing%%")):
				second_payloads_ok = false
	_check(second_payloads_ok,
			"WG-05 fixture world regenerates byte-identical biome maps and water fields from the same seed (deterministic)")

	var lone_chunk_coords: Vector2i = water_fixture_config.world_origin_chunk + Vector2i(
			int(water_fixture_config.world_dimensions_chunks.x) - 1,
			int(water_fixture_config.world_dimensions_chunks.y) - 1)
	var water_fixture_gen_lone := WorldGenerator.new()
	water_fixture_gen_lone.initialize(42, water_fixture_config)
	water_fixture_gen_lone.content_registry = water_fixture_registry
	var lone_payload: Dictionary = water_fixture_gen_lone.generate_chunk(lone_chunk_coords)
	var in_box_payload: Dictionary = water_first[lone_chunk_coords]
	var lone_matches_in_box: bool = true
	for payload_key in ["biomes", "water_mask", "distance_to_water", "water_class",
			"water_origin", "poi_candidates", "feature_candidates"]:
		if str(lone_payload.get(payload_key, "%%missing%%")) != str(in_box_payload.get(payload_key, "%%missing%%")):
			lone_matches_in_box = false
	_check(lone_matches_in_box,
			"WG-05: a single corner chunk generated in isolation matches its in-box twin (water fields, biomes and candidates are coordinate-pure)")

	var water_fixture_gen_reversed := WorldGenerator.new()
	water_fixture_gen_reversed.initialize(42, water_fixture_config)
	water_fixture_gen_reversed.content_registry = water_fixture_registry
	var reversed_order_ok: bool = true
	for step in range(fixture_chunk_coords.size()):
		var chunk_coords: Vector2i = fixture_chunk_coords[fixture_chunk_coords.size() - 1 - int(step)]
		var first_payload: Dictionary = water_first[chunk_coords]
		var reversed_payload: Dictionary = water_fixture_gen_reversed.generate_chunk(chunk_coords)
		for payload_key in ["biomes", "water_mask", "distance_to_water", "water_class",
				"water_origin", "poi_candidates", "feature_candidates"]:
			if str(reversed_payload.get(payload_key, "%%missing%%")) != str(first_payload.get(payload_key, "%%missing%%")):
				reversed_order_ok = false
	_check(reversed_order_ok,
			"WG-05: chunk generation order does not change water fields, biomes or candidates (no cross-chunk state)")

	var fixture_poi_count: int = 0
	var fixture_poi_constraints_ok: bool = true
	var fixture_poi_anchor_set: Dictionary = {}
	for chunk_coords in fixture_chunk_coords:
		var fixture_payload: Dictionary = water_first[chunk_coords]
		var chunk_start: Vector2i = chunk_coords * fixture_chunk_size
		var chunk_dist: PackedInt32Array = fixture_payload["distance_to_water"]
		for candidate in fixture_payload.get("poi_candidates", []):
			if str(candidate.get("poi_id", "")) != "fixture_waystation":
				continue
			fixture_poi_count += 1
			var poi_x: int = int(candidate.get("x", 0))
			var poi_y: int = int(candidate.get("y", 0))
			fixture_poi_anchor_set["%d,%d" % [poi_x, poi_y]] = true
			var in_own_chunk: bool = poi_x >= int(chunk_start.x) \
					and poi_x < int(chunk_start.x) + fixture_chunk_size \
					and poi_y >= int(chunk_start.y) \
					and poi_y < int(chunk_start.y) + fixture_chunk_size
			var local_index: int = (poi_y - int(chunk_start.y)) * fixture_chunk_size + (poi_x - int(chunk_start.x))
			if not in_own_chunk or int(chunk_dist[local_index]) < 3:
				fixture_poi_constraints_ok = false
	var fixture_poi_known_anchors: bool = fixture_poi_anchor_set.has("22,-43") \
			and fixture_poi_anchor_set.has("-42,-11") and fixture_poi_anchor_set.has("22,-11") \
			and fixture_poi_anchor_set.has("-26,5")
	_check(fixture_poi_count == 23 and fixture_poi_known_anchors and fixture_poi_constraints_ok,
			"WG-05: the min_distance_to_water POI places exactly 23 candidates (including the 4 probe-verified anchor positions; the 13 of its 36 spacing-grid anchors within distance < 3 are correctly excluded), each inside its own chunk at distance >= 3")
	var fixture_feature_anchors: Dictionary = {}
	var fixture_feature_in_chunk_count: int = 0
	var fixture_feature_constraint_ok: bool = true
	var fixture_feature_halo_ok: bool = true
	for chunk_coords in fixture_chunk_coords:
		var fixture_payload: Dictionary = water_first[chunk_coords]
		var chunk_start: Vector2i = chunk_coords * fixture_chunk_size
		for candidate in fixture_payload.get("feature_candidates", []):
			if str(candidate.get("feature_id", "")) != "fixture_shore_boulders":
				continue
			var anchor_x: int = int(candidate.get("x", 0))
			var anchor_y: int = int(candidate.get("y", 0))
			if bool(candidate.get("in_chunk", false)) == false:
				var halo_outside: bool = anchor_x < int(chunk_start.x) \
						or anchor_x >= int(chunk_start.x) + fixture_chunk_size \
						or anchor_y < int(chunk_start.y) \
						or anchor_y >= int(chunk_start.y) + fixture_chunk_size
				if not halo_outside:
					fixture_feature_halo_ok = false
				continue
			fixture_feature_in_chunk_count += 1
			fixture_feature_anchors["%d,%d" % [anchor_x, anchor_y]] = true
			var owner_chunk: Vector2i = Vector2i(
					floori(float(anchor_x) / float(fixture_chunk_size)),
					floori(float(anchor_y) / float(fixture_chunk_size)))
			var owner_start: Vector2i = owner_chunk * fixture_chunk_size
			var owner_local: int = (anchor_y - int(owner_start.y)) * fixture_chunk_size + (anchor_x - int(owner_start.x))
			if anchor_x < int(owner_start.x) or anchor_x >= int(owner_start.x) + fixture_chunk_size \
					or anchor_y < int(owner_start.y) or anchor_y >= int(owner_start.y) + fixture_chunk_size \
					or int((water_first[owner_chunk] as Dictionary)["distance_to_water"][owner_local]) != 1:
				fixture_feature_constraint_ok = false
	var expected_feature_anchors: bool = fixture_feature_anchors.has("21,-19") \
			and fixture_feature_anchors.has("-35,-11") and fixture_feature_anchors.has("-11,-3") \
			and fixture_feature_anchors.has("-3,-3")
	_check(fixture_feature_anchors.size() == 4 and expected_feature_anchors \
			and fixture_feature_in_chunk_count == fixture_feature_anchors.size(),
			"WG-05: the max_distance_to_water feature yields exactly the 4 probe-verified anchors (21,-19 / -35,-11 / -11,-3 / -3,-3), each once, in-chunk")
	_check(fixture_feature_constraint_ok and fixture_feature_halo_ok,
			"WG-05: every feature anchor sits in its owner chunk at distance == 1, and halo copies only ride in chunks whose core excludes the anchor")

	var wg05_spawner := ResourceSpawner.new()
	wg05_spawner.world_generator = water_fixture_gen
	wg05_spawner.initialize(42)
	for chunk_coords in fixture_chunk_coords:
		wg05_spawner.generate_chunk_resources(chunk_coords, 42,
				water_first[chunk_coords].get("feature_candidates", []),
				(water_first[chunk_coords] as Dictionary)["biomes"] as PackedStringArray,
				(water_first[chunk_coords] as Dictionary)["water_mask"] as PackedByteArray,
				(water_first[chunk_coords] as Dictionary)["distance_to_water"] as PackedInt32Array)
	var fixture_placements: Dictionary = wg05_spawner.get_all_resources()
	var fixture_placement_constraints_ok: bool = true
	for resource_tile_key in fixture_placements:
		var resource_tile: Vector2i = resource_tile_key
		var owner_chunk: Vector2i = Vector2i(
				floori(float(resource_tile.x) / float(fixture_chunk_size)),
				floori(float(resource_tile.y) / float(fixture_chunk_size)))
		var owner_start: Vector2i = owner_chunk * fixture_chunk_size
		var local_index: int = (int(resource_tile.y) - int(owner_start.y)) * fixture_chunk_size \
				+ (int(resource_tile.x) - int(owner_start.x))
		var owner_payload: Dictionary = water_first[owner_chunk]
		if int(owner_payload["water_mask"][local_index]) != 0 \
				or int(owner_payload["distance_to_water"][local_index]) > 1:
			fixture_placement_constraints_ok = false
	_check(fixture_placements.size() > 0 and fixture_placement_constraints_ok,
			"WG-05: the resource spawner honors the distance constraint end to end - every placed fixture resource sits on land within distance <= 1 of water")
	var wg05_spawner_second := ResourceSpawner.new()
	wg05_spawner_second.world_generator = water_fixture_gen
	wg05_spawner_second.initialize(42)
	for chunk_coords in fixture_chunk_coords:
		wg05_spawner_second.generate_chunk_resources(chunk_coords, 42,
				water_first[chunk_coords].get("feature_candidates", []),
				(water_first[chunk_coords] as Dictionary)["biomes"] as PackedStringArray,
				(water_first[chunk_coords] as Dictionary)["water_mask"] as PackedByteArray,
				(water_first[chunk_coords] as Dictionary)["distance_to_water"] as PackedInt32Array)
	var second_placements: Dictionary = wg05_spawner_second.get_all_resources()
	_check(fixture_placements.size() == second_placements.size() \
			and str(fixture_placements) == str(second_placements),
			"WG-05: fixture resource placement is identical across spawner instances (distance vetoes consume no random rolls)")

	# In the fixture world the field is in use, so the public on-demand
	# queries (which run their own tile +/- cap BFS) must agree with the
	# payload: both rects are square, both unclamped, and both saturate at
	# the cap, so they compute the same value for every tile of the chunk.
	var fixture_chunk_zero_payload: Dictionary = water_first[Vector2i(0, 0)]
	var fixture_on_demand_queries_ok: bool = true
	for index in on_demand_sample_indices:
		var wx: int = index % fixture_chunk_size
		var wy: int = index / fixture_chunk_size
		if water_fixture_gen.get_water_class_at_world(wx, wy) != str(fixture_chunk_zero_payload["water_class"][index]) \
				or water_fixture_gen.get_water_origin_at_world(wx, wy) != str(fixture_chunk_zero_payload["water_origin"][index]) \
				or water_fixture_gen.get_distance_to_water_at_world(wx, wy) != int(fixture_chunk_zero_payload["distance_to_water"][index]):
			fixture_on_demand_queries_ok = false
	_check(fixture_on_demand_queries_ok,
			"WG-05: with the field in use (fixture world), the on-demand public queries agree with the chunk payload at sampled tiles")

	# 2e.4 The live world: unconstrained content means the new field changes
	# nothing about what the live world generates. Chunk (0, 0) is the world
	# centre, inside the streamed box, so its live payload is auditable
	# directly.
	var live_generator := world_gen as WorldGenerator
	var live_chunk_data: Dictionary = chunk_system.get_chunk(Vector2i(0, 0))
	var live_chunk_size: int = world_config.chunk_size_tiles
	var live_field_present: bool = live_chunk_data.has("water_class") \
			and live_chunk_data.has("water_origin") and live_chunk_data.has("distance_to_water")
	var live_field_sizes_ok: bool = live_field_present \
			and (live_chunk_data["water_class"] as PackedStringArray).size() == live_chunk_size * live_chunk_size \
			and (live_chunk_data["water_origin"] as PackedStringArray).size() == live_chunk_size * live_chunk_size \
			and (live_chunk_data["distance_to_water"] as PackedInt32Array).size() == live_chunk_size * live_chunk_size
	_check(live_field_present and live_field_sizes_ok,
			"WG-05: the live chunk payload gains the three water-field keys at full chunk size")
	var live_water_cap: int = world_config.distance_to_water_cap_tiles
	var live_ref_side: int = live_chunk_size + 2 * live_water_cap
	var live_ref_start: Vector2i = Vector2i.ZERO - Vector2i(live_water_cap, live_water_cap)
	var live_ref_water := PackedInt32Array()
	live_ref_water.resize(live_ref_side * live_ref_side)
	var live_ref_elevations := PackedFloat32Array()
	live_ref_elevations.resize(live_ref_side * live_ref_side)
	for w_y in range(live_ref_side):
		for w_x in range(live_ref_side):
			var tile_x: int = int(live_ref_start.x) + int(w_x)
			var tile_y: int = int(live_ref_start.y) + int(w_y)
			var tile_values: Dictionary = live_generator.get_noise_values(float(tile_x), float(tile_y))
			var is_live_water: bool = live_generator._is_water(
					float(tile_values["elevation"]), float(tile_values["moisture"]), float(tile_values["water"]))
			live_ref_water[int(w_y) * live_ref_side + int(w_x)] = 1 if is_live_water else 0
			live_ref_elevations[int(w_y) * live_ref_side + int(w_x)] = float(tile_values["elevation"])
	var live_ref_dist := _wg05_bfs_reference(live_ref_side, live_ref_side, live_water_cap, live_ref_water)
	var live_mask: PackedByteArray = live_chunk_data["water_mask"]
	var live_dist: PackedInt32Array = live_chunk_data["distance_to_water"]
	var live_class: PackedStringArray = live_chunk_data["water_class"]
	var live_origin: PackedStringArray = live_chunk_data["water_origin"]
	var live_distance_matches: bool = true
	var live_class_matches: bool = true
	var live_origin_matches: bool = true
	for index in range(live_chunk_size * live_chunk_size):
		var wx: int = index % live_chunk_size
		var wy: int = index / live_chunk_size
		var ref_index: int = (wy + live_water_cap) * live_ref_side + (wx + live_water_cap)
		var raw_dist: int = int(live_ref_dist[ref_index])
		var expected_dist: int = live_water_cap if raw_dist < 0 or raw_dist >= live_water_cap else raw_dist
		if int(live_dist[index]) != expected_dist or (int(live_dist[index]) == 0) != (int(live_mask[index]) == 1):
			live_distance_matches = false
		var adjacent_water: int = 0
		var ry: int = wy - int(live_ref_start.y)
		var rx: int = wx - int(live_ref_start.x)
		for d_y in range(-1, 2):
			for d_x in range(-1, 2):
				if int(d_x) == 0 and int(d_y) == 0:
					continue
				var n_y: int = ry + int(d_y)
				var n_x: int = rx + int(d_x)
				if n_y < 0 or n_y >= live_ref_side or n_x < 0 or n_x >= live_ref_side:
					continue
				if live_ref_water[n_y * live_ref_side + n_x] == 1:
					adjacent_water += 1
		var is_water_tile: bool = int(live_mask[index]) == 1
		var expected_class: String = "coast" if is_water_tile and adjacent_water < 8 \
				else ("deep_water" if is_water_tile else ("shore" if adjacent_water > 0 else "land"))
		if str(live_class[index]) != expected_class:
			live_class_matches = false
		var expected_origin: String = ""
		if is_water_tile:
			expected_origin = "ocean" if float(live_ref_elevations[ref_index]) < world_config.water_level else "lake"
		if str(live_origin[index]) != expected_origin:
			live_origin_matches = false
	_check(live_distance_matches,
			"WG-05 live world: the streamed chunk's distance field matches an independent BFS over its own expanded rect, with distance 0 exactly on water tiles")
	_check(live_class_matches,
			"WG-05 live world: the streamed chunk's water classes match an independent 8-neighbour recount")
	_check(live_origin_matches,
			"WG-05 live world: the streamed chunk's water origins follow the water-level rule (the live lake level sits below the water level, so every live water tile is ocean-origin)")
	var live_on_demand_queries_ok: bool = true
	var live_legacy_biome_matches: bool = true
	for index in on_demand_sample_indices:
		var wx: int = index % live_chunk_size
		var wy: int = index / live_chunk_size
		if live_generator.get_water_class_at_world(wx, wy) != str(live_class[index]) \
				or live_generator.get_water_origin_at_world(wx, wy) != str(live_origin[index]) \
				or live_generator.get_distance_to_water_at_world(wx, wy) != -1:
			live_on_demand_queries_ok = false
		var expected_biome: String = _legacy_select_biome_at(live_generator,
				float(live_chunk_data["elevation"][index]),
				float(live_chunk_data["moisture"][index]),
				float(live_chunk_data["temperature"][index]),
				live_generator.get_regional_noise_values(wx, wy))
		if str(live_chunk_data["biomes"][index]) != expected_biome:
			live_legacy_biome_matches = false
	_check(live_on_demand_queries_ok,
			"WG-05 live world: on-demand class/origin queries agree with the payload, and the distance query stays closed at the -1 sentinel while no content uses the field (zero cost for unconstrained worlds)")
	_check(live_legacy_biome_matches,
			"WG-05 live world: sampled tile biomes are byte-identical to the pre-WG-05 selector's output - the distance gate is a no-op while every definition stays unconstrained")

	# 2e.5 The invalid fixture: min > max, and a surface resource pinned to
	# distance 0 (which is water) must fail registry validation.
	var inverted_registry := _fixture_registry("inverted_shore_distance")
	_check(inverted_registry.has_validation_errors(),
			"WG-05 invalid fixture (inverted min/max, surface resource at distance 0) fails registry validation")
	_check(_registry_errors_mention(inverted_registry.validation_errors, "exceeds max_distance_to_water") \
			and _registry_errors_mention(inverted_registry.validation_errors, "can never spawn"),
			"WG-05 invalid fixture: validation names the distance-to-water rules it breaks (min > max; surface resource with max distance 0)")

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
	main.call("_spawn_resources_for_chunk", destroyed_resource_chunk, chunk_system.get_chunk(destroyed_resource_chunk))
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

## Point a fresh registry at one validation fixture directory and return it.
## Each fixture dir contains the standard content subdirectories, so the
## unrelated kinds simply find nothing there.
func _fixture_registry(fixture_name: String) -> WorldContentRegistry:
	var registry := WorldContentRegistry.new()
	registry.discover("res://tests/fixtures/world_validation/%s" % fixture_name)
	return registry

## True when at least one collected validation error contains the fragment.
func _registry_errors_mention(errors: Array[String], fragment: String) -> bool:
	for error in errors:
		if error.contains(fragment):
			return true
	return false

## Load a fixture world config: the fixture's own .tres when present,
## otherwise a duplicate of the live config (the invalid fixture ships
## content only and is validated against the live config).
func _fixture_config(fixture_name: String) -> WorldGenerationConfig:
	var path := "res://tests/fixtures/world_validation/%s/world_generation_config.tres" % fixture_name
	if FileAccess.file_exists(path):
		return load(path) as WorldGenerationConfig
	var live_config := load("res://data/world/world_generation_config.tres") as WorldGenerationConfig
	return live_config.duplicate() as WorldGenerationConfig

## Frozen copy of the pre-WG-05 biome selection: the pure region-weighted
## score loop with no distance gate. While every definition stays
## distance-unconstrained the live and fixture payloads must agree with
## this - which is what keeps the live world byte-identical.
func _legacy_select_biome_at(gen: WorldGenerator, elevation: float, moisture: float, temperature: float,
		regional_values: Dictionary = {}) -> String:
	var regional_biome_id := ""
	if not regional_values.is_empty():
		regional_biome_id = gen._select_biome_from_fields(
			float(regional_values.get("elevation", elevation)),
			float(regional_values.get("moisture", moisture)),
			float(regional_values.get("temperature", temperature))
		)
	var regional_biome := gen.get_biome(regional_biome_id)
	var config := gen.get_configuration()
	var best_biome := ""
	var best_score := -INF
	var ids := gen.get_biomes().keys()
	ids.sort()
	for biome_id in ids:
		var biome := gen.get_biome(str(biome_id))
		if biome == null:
			continue
		var score := gen._biome_match_score(biome, elevation, moisture, temperature) * maxf(0.01, biome.rarity_weight)
		if regional_biome != null:
			if biome.id == regional_biome.id:
				score += config.regional_biome_weight
			elif regional_biome.transition_biome_ids.has(biome.id):
				score += config.transition_biome_weight
			elif regional_biome.preferred_neighbors.has(biome.id):
				score += config.preferred_neighbor_weight
		if score > best_score:
			best_score = score
			best_biome = biome.id
	if best_biome.is_empty() and not ids.is_empty():
		best_biome = str(ids[0])
	return best_biome

## Independent copy of the generator's multi-source Chebyshev BFS over a
## water rect: every water tile starts at 0, the wavefront expands to the
## 8 neighbours and is written but not expanded once it reaches the cap,
## so the result is -1 beyond the cap, exact within it, and the cap itself
## on the frontier.
func _wg05_bfs_reference(side_x: int, side_y: int, cap: int, water_rect: PackedInt32Array) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(side_x * side_y)
	dist.fill(-1)
	var queue: Array[int] = []
	for i in range(side_x * side_y):
		if water_rect[i] == 1:
			dist[i] = 0
			queue.append(int(i))
	var head: int = 0
	while head < queue.size():
		var qi: int = queue[head]
		head += 1
		var qy: int = qi / side_y
		var qx: int = qi % side_x
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if int(dx) == 0 and int(dy) == 0:
					continue
				var ny: int = qy + int(dy)
				var nx: int = qx + int(dx)
				if ny < 0 or ny >= side_y or nx < 0 or nx >= side_x:
					continue
				var j: int = ny * side_x + nx
				if dist[j] == -1:
					dist[j] = dist[qi] + 1
					if dist[j] < cap:
						queue.append(j)
	return dist
