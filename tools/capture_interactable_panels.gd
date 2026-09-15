## Captures the overhauled interactable-panel screenshots: workbench station,
## furnace mid-craft (fuel + progress), chest container, and the fuel-only
## torch. Run windowed (rendering is required):
## godot --path . --script tools/capture_interactable_panels.gd
extends SceneTree

const OUT_DIR := "/Volumes/Space-SSD/Guy/code/riftwake/docs/ui_baseline"

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
	var interaction: InteractionManager = _main.get_node("InteractionManager")
	var hud: HUD = _main.get_node("HUD")
	hud.toggle_debug(false) # keep the panel, not the perf overlay, in the shot
	var perf_overlay := _main.get_node_or_null("PerformanceOverlay")
	if perf_overlay != null:
		perf_overlay.visible = false

	for item in ["plank", "stone", "sand", "coal", "wood", "iron_ore", "fibre", "berry", "herb"]:
		player.inventory.add_item(item, 24)
	for item in ["workbench", "furnace", "chest", "torch"]:
		player.inventory.add_item(item, 1)
	var placed := {}
	for entry in [["workbench", Vector2i(6, 4)], ["furnace", Vector2i(8, 4)],
			["chest", Vector2i(10, 4)], ["torch", Vector2i(12, 4)]]:
		if not buildings.place_building_item(entry[0], entry[1], player.inventory, 0):
			push_error("Could not place %s for capture" % entry[0])
			quit(1)
			return
		placed[entry[0]] = buildings.get_record_at(entry[1], 0, "object")
	for _frame in range(4):
		await process_frame

	# 1. Workbench: recipe card, filled ingredient slots, ready craft button.
	player.global_position = Vector2(6, 5) * 32.0
	interaction.open(placed["workbench"].node)
	interaction.open_panel.station_fill_requested.emit("wooden_hammer")
	for _frame in range(3):
		await process_frame
	_capture("interactable_workbench.png")
	interaction.close("capture")

	# 2. Furnace: fuel slot burning, ingredients filled, craft in progress.
	player.global_position = Vector2(8, 5) * 32.0
	interaction.open(placed["furnace"].node)
	var furnace_record: BuildingRecord = placed["furnace"]
	furnace_record.get_fuel_storage().add_item("wood", 6)
	furnace_record.capability_state["enabled"] = true
	var furnace_panel: InteractablePanel = interaction.open_panel
	furnace_panel.station_fill_requested.emit("glass")
	furnace_panel.station_craft_requested.emit("glass")
	for _frame in range(3):
		await process_frame
	_capture("interactable_furnace.png")
	interaction.close("capture")

	# 3. Chest container: two grids of icon slots.
	player.global_position = Vector2(10, 5) * 32.0
	interaction.open(placed["chest"].node)
	(placed["chest"] as BuildingRecord).get_container_storage().add_item("wood", 40)
	(placed["chest"] as BuildingRecord).get_container_storage().add_item("stone", 18)
	for _frame in range(3):
		await process_frame
	_capture("interactable_chest.png")
	interaction.close("capture")

	# 4. Fuel-only device: single filtered fuel slot with status + toggle.
	player.global_position = Vector2(12, 5) * 32.0
	interaction.open(placed["torch"].node)
	(placed["torch"] as BuildingRecord).get_fuel_storage().add_item("wood", 3)
	for _frame in range(3):
		await process_frame
	_capture("interactable_torch.png")
	interaction.close("capture")

	# 5. Character screen (K): torch equipped in the light slot and lit.
	var item_database: ItemDatabase = _main.get_node("ItemDatabase")
	var character_panel: CharacterPanel = _main.get_node("HUD/CharacterPanel")
	character_panel.configure(player, item_database)
	player.inventory.add_item("torch", 1)
	player.equipment.get_slot_storage("light").add_item("torch", 1)
	player.equipment.set_light_enabled(true)
	character_panel.open_panel()
	for _frame in range(3):
		await process_frame
	_capture("interactable_character.png")
	character_panel.close_panel()

	print("Captured 5 interactable-panel screenshots to %s" % OUT_DIR)
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
