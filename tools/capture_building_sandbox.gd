## Captures the three Building Sandbox regression screenshots named in
## docs/ACTIVE_BUILD_PLAN.md (M0): the ground build with the default station
## fixtures, an upper-story build, and the post-save/load restoration.
## Run windowed (rendering is required): godot --path . --script tools/capture_building_sandbox.gd
extends SceneTree

const OUT_DIR := "/Volumes/Space-SSD/Guy/code/riftwake/docs/sandbox_baseline"

var _main: Node = null

func _initialize() -> void:
	GameSession.request_new_game(GameSession.MODE_BUILDING_SANDBOX)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	call_deferred("_run")

func _run() -> void:
	for _frame in range(12):
		await process_frame
	_main.flush_pending_chunk_visuals()
	var buildings: BuildingManager = _main.get_node("BuildingManager")
	var player: Player = _main.get_node("Player")

	# 1. Ground build: the default fixtures plus a small placed ground room.
	for part in ["wooden_foundation", "wooden_wall", "wooden_roof"]:
		player.inventory.add_item(part, 8)
	var tiles := [Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2)]
	for tile in tiles:
		buildings.place_building_item("wooden_foundation", tile, player.inventory, 0)
	for tile in [Vector2i(3, 1), Vector2i(5, 1), Vector2i(3, 3), Vector2i(5, 3)]:
		buildings.place_building_item("wooden_wall", tile, player.inventory, 0)
	for tile in tiles:
		buildings.place_building_item("wooden_roof", tile, player.inventory, 0)
	for _frame in range(8):
		await process_frame
	_capture("ground_build.png")

	# 2. Upper-story build: floor + walls on story 1 above the ground room,
	# with the construction plane on story 1 so the cutaway shows.
	for tile in tiles:
		buildings.place_building_item("wooden_floor", tile, player.inventory, 1)
	for tile in [Vector2i(3, 1), Vector2i(5, 1), Vector2i(3, 3), Vector2i(5, 3)]:
		buildings.place_building_item("wooden_wall", tile, player.inventory, 1)
	buildings.set_selected_story(1)
	for _frame in range(8):
		await process_frame
	_capture("upper_story_build.png")

	# 3. Save/load: persist, reload, and confirm every placed part survived.
	var save_system: SaveSystem = _main.get_node("SaveSystem")
	var placed_before: int = buildings.get_building_count()
	var path: String = "user://saves/manual_0_sandbox_baseline.json"
	if not save_system.save_game(path, "manual"):
		push_error("Could not write the baseline save.")
		quit(1)
		return
	save_system.load_game(path)
	for _frame in range(12):
		await process_frame
	_main.flush_pending_chunk_visuals()
	if buildings.get_building_count() != placed_before:
		push_error("Save/load lost buildings (%d -> %d)" % [placed_before, buildings.get_building_count()])
		quit(1)
		return
	_capture("save_load.png")

	print("Captured 3 Building Sandbox baseline screenshots (%d buildings round-tripped)." % placed_before)
	quit(0)

func _capture(file_name: String) -> void:
	RenderingServer.force_draw()
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Empty capture for %s" % file_name)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	image.save_png("%s/%s" % [OUT_DIR, file_name])
