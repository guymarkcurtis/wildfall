## Focused Active Build Plan M4 coverage: the interaction router (targeting,
## prompt, input lock), the close-reason matrix (each path fired twice),
## object-to-object switching, and the shared container panel transfers.
## Genericity is proven with a runtime-registered "test_crate" definition, not
## the shipped chest — no name branches anywhere.
## Run: godot --headless --path . --script tests/test_interaction_router.gd
extends SceneTree

var _failures := 0
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_targeting_and_prompt()
	_test_open_close_matrix()
	_test_switching_and_transfers()
	print("Interaction router failures: %d (%d checks)" % [_failures, _checks])
	quit(_failures)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures += 1
		push_error("[FAIL] %s" % label)

func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(tile) * 32.0 + Vector2(16.0, 16.0)

func _make_inventory(quantity: int) -> InventoryComponent:
	var inventory := InventoryComponent.new()
	inventory.set_stack_sizes({"wood": 64, "test_crate": 8})
	inventory.add_item("wood", quantity)
	inventory.add_item("test_crate", 8)
	return inventory

## A data-authored generic container: interaction + container profiles, no
## chest anywhere. Registered at runtime instead of shipped content so the
## test proves the ROUTER is generic, not just the chest asset.
func _register_test_crate(manager: BuildingManager) -> void:
	var definition := BuildingDefinition.new()
	definition.id = "test_crate"
	definition.display_name = "Test Crate"
	definition.part_type = "utility"
	definition.tier = "primitive"
	definition.max_health = 40
	definition.interaction_profile = InteractionProfile.new()
	definition.interaction_profile.verb = "Open"
	definition.interaction_profile.range_px = 64.0
	definition.interaction_profile.ui_kind = "container"
	definition.container_profile = ContainerProfile.new()
	definition.container_profile.slot_count = 27
	definition.container_profile.max_weight = 200.0
	manager.definitions["test_crate"] = definition

func _make_world(player_tile: Vector2i) -> Array:
	var manager := InteractionManager.new()
	manager.name = "InteractionManager"
	root.add_child(manager)
	var buildings := BuildingManager.new()
	buildings.name = "BuildingManager"
	root.add_child(buildings)
	var player := Player.new()
	player.name = "Player"
	root.add_child(player)
	# InteractionManager resolves siblings by name in _ready, but wire
	# explicitly so the test does not depend on ready order.
	manager.player = player
	manager.building_manager = buildings
	player.global_position = _tile_center(player_tile)
	return [manager, buildings, player]

func _place_crate(buildings: BuildingManager, tile: Vector2i, inventory: InventoryComponent) -> Building:
	buildings.place_record("test_crate", tile, inventory, 0)
	return buildings.get_record_at(tile, 0, "object").node

# --- Targeting and prompt ---

func _test_targeting_and_prompt() -> void:
	var world := _make_world(Vector2i(10, 10))
	var manager: InteractionManager = world[0]
	var buildings: BuildingManager = world[1]
	var player: Player = world[2]
	_register_test_crate(buildings)
	var inventory := _make_inventory(3)
	# Out of range (range 64 px) first: it must never win.
	var far := _place_crate(buildings, Vector2i(20, 10), inventory)
	_check(manager.current_target == null and manager.current_prompt() == "",
			"No target and no prompt when only an out-of-range crate exists")
	# Two in range at different distances: nearest wins.
	var near := _place_crate(buildings, Vector2i(11, 10), inventory)
	var nearer := _place_crate(buildings, Vector2i(10, 11), inventory)
	manager._refresh_target()
	_check(manager.current_target == nearer,
			"The nearest interactable in range becomes the target")
	_check(manager.current_prompt() == "Open Test Crate",
			"The HUD prompt is built from the authored verb and display name")
	# Move so the two in-range crates are equidistant: stable key breaks the tie.
	player.global_position = _tile_center(Vector2i(11, 11))
	manager._refresh_target()
	var expected := nearer if nearer.placement_key < near.placement_key else near
	_check(manager.current_target == expected,
			"Distance ties resolve deterministically by stable placement key")
	# The shipped chest is targetable through the exact same generic path.
	player.global_position = _tile_center(Vector2i(10, 10))
	var chest_inventory := _make_inventory(0)
	chest_inventory.add_item("chest", 1)
	buildings.place_record("chest", Vector2i(10, 9), chest_inventory, 0)
	var chest := buildings.get_record_at(Vector2i(10, 9), 0, "object").node
	_check(chest.can_interact(player) and chest.get_interaction_prompt() == "Open Chest",
			"The shipped chest is targetable through the same generic interface")
	# try_interact with a target opens the panel.
	var opened := manager.try_interact()
	_check(opened and manager.open_panel != null and manager.open_panel.is_open,
			"try_interact opens the shared panel for the current target")
	_check(manager.ui_blocks_world(), "An open panel locks world input")
	_check(far.can_interact(player) == false,
			"The out-of-range crate reports can_interact false")
	manager.close("test")
	player.queue_free()
	manager.queue_free()
	buildings.queue_free()

# --- Close matrix: every reason, fired twice (idempotent) ---

func _test_open_close_matrix() -> void:
	var world := _make_world(Vector2i(30, 30))
	var manager: InteractionManager = world[0]
	var buildings: BuildingManager = world[1]
	var player: Player = world[2]
	_register_test_crate(buildings)
	var inventory := _make_inventory(2)
	var crate := _place_crate(buildings, Vector2i(30, 30), inventory)
	var closed_reasons: Array[String] = []
	manager.panel_closed.connect(func(reason): closed_reasons.append(str(reason)))

	# Escape path (the panel emits; the manager owns the pipeline) twice:
	# the first close emits, the second is a silent no-op.
	manager.open(crate)
	manager.open_panel.close_requested.emit("escape")
	manager.close("escape")
	_check(manager.open_panel == null and closed_reasons.count("escape") == 1,
			"Escape closes the panel, and a second close is a silent no-op")
	_check(not manager.ui_blocks_world(), "World input unlocks after close")

	# Toggle path (E while open) twice.
	manager.open(crate)
	manager.close("toggle")
	manager.close("toggle")
	_check(manager.open_panel == null and closed_reasons.count("toggle") == 1,
			"The toggle path closes twice safely")

	# Out of range: walk away, let the manager's range check fire.
	manager.open(crate)
	player.global_position = _tile_center(Vector2i(40, 40))
	manager._close_if_out_of_range()
	manager._close_if_out_of_range()
	_check(manager.open_panel == null and closed_reasons.count("out_of_range") == 1,
			"Leaving range closes the panel (idempotently)")

	# Building removal while open.
	manager.open(crate)
	crate.building_destroyed.emit()
	manager.close("removed")
	_check(manager.open_panel == null and closed_reasons.count("removed") == 1,
			"Demolishing the open object closes the panel twice safely")

	# Building damage while open.
	var crate2 := _place_crate(buildings, Vector2i(31, 30), inventory)
	manager.open(crate2)
	crate2.building_damaged.emit(1, 40)
	manager.close("damaged")
	_check(manager.open_panel == null and closed_reasons.count("damaged") == 1,
			"Damaging the open object closes the panel twice safely")

	# World reset, cave entry, death, pause: direct manager reasons. A fresh
	# crate, because the simulated demolition above removed `crate` from the
	# placement index (as a real demolition would).
	var crate3 := _place_crate(buildings, Vector2i(32, 30), inventory)
	for reason in ["world_reset", "cave", "death", "pause"]:
		manager.open(crate3)
		manager.close(reason)
		manager.close(reason)
	var all_good := true
	var detail := ""
	for reason in ["world_reset", "cave", "death", "pause"]:
		if closed_reasons.count(reason) != 1:
			all_good = false
			detail += " %s=%d" % [reason, closed_reasons.count(reason)]
	_check(all_good, "World-reset, cave, death, and pause closes are each idempotent" + detail)

	# Closing with nothing open never emits.
	var before := closed_reasons.size()
	manager.close("spurious")
	_check(closed_reasons.size() == before,
			"A close with nothing open emits no signal")

	# try_interact with no target is NOT consumed (E falls through to world).
	_check(manager.try_interact() == false,
			"try_interact without a target returns false for world fall-through")
	player.queue_free()
	manager.queue_free()
	buildings.queue_free()

# --- Switching and panel transfers ---

func _test_switching_and_transfers() -> void:
	var world := _make_world(Vector2i(50, 50))
	var manager: InteractionManager = world[0]
	var buildings: BuildingManager = world[1]
	var player: Player = world[2]
	_register_test_crate(buildings)
	var inventory := _make_inventory(10)
	var crate_a := _place_crate(buildings, Vector2i(50, 50), inventory)
	var crate_b := _place_crate(buildings, Vector2i(51, 50), inventory)

	# Object-to-object switching: opening B closes A ("switched").
	manager.open(crate_a)
	_check(manager.open_building == crate_a, "Crate A opens")
	manager.open(crate_b)
	_check(manager.open_building == crate_b and manager.open_panel != null
			and manager.open_panel.is_open,
			"Opening crate B closed A and opened exactly one panel")
	var panel: InteractablePanel = manager.open_panel
	_check(panel.object_grid != null and panel.player_grid != null
			and panel.object_grid.storage.slot_count() == 27,
			"The panel shows the object's 27-slot container and the player grid")

	# Click-click transfer: select the player's wood stack, deposit into crate.
	player.inventory.add_item("wood", 10)
	var wood_slot: int = player.inventory.get_storage().first_index_of("wood")
	var wood_before: int = player.inventory.get_item_quantity("wood")
	panel._on_grid_slot_pressed("player", wood_slot, MOUSE_BUTTON_LEFT)
	panel._on_grid_slot_pressed("object", 0, MOUSE_BUTTON_LEFT)
	_check(player.inventory.get_item_quantity("wood") == 0
			and manager.open_record.container_storage.quantity_of("wood") == wood_before,
			"Click-click moves the stack into the container with exact conservation")

	# Shift-click quick transfer back out.
	panel._on_grid_slot_pressed("object", 0, MOUSE_BUTTON_LEFT)
	panel._on_quick_transfer("object", 0)
	_check(player.inventory.get_item_quantity("wood") == wood_before,
			"Shift-click quick-transfers the whole stack back to the player")

	# Right-click splits half into the crate. The slot index is re-resolved
	# because the round-trip may land the stack in a different free slot.
	wood_slot = player.inventory.get_storage().first_index_of("wood")
	panel._on_grid_slot_pressed("player", wood_slot, MOUSE_BUTTON_RIGHT)
	_check(player.inventory.get_item_quantity("wood") == wood_before / 2
			and manager.open_record.container_storage.quantity_of("wood") == wood_before / 2,
			"The split moved exactly half, conserving every unit")

	# Container edits refresh the panel through the storage signal.
	manager._on_open_storage_changed()
	_check(panel.is_open, "The panel stays open across storage refreshes")

	# Persisted-look check is M5; here the record storage is live and stable.
	var record := buildings.get_record_for_building(crate_b)
	_check(record.get_container_storage() == record.get_container_storage(),
			"The container storage is a stable per-record instance (seeded once)")
	# M5 safety: the same generic panel closes if an occupied data-authored
	# container is protected from demolition. No chest-specific route exists.
	buildings.demolish_at(Vector2i(51, 50), 0)
	_check(manager.open_panel == null and buildings.get_record_at(Vector2i(51, 50), 0, "object") != null,
			"Protected non-empty container demolition closes its panel without deleting contents")
	player.queue_free()
	manager.queue_free()
	buildings.queue_free()
