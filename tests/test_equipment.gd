## Coverage for the character screen: tag-filtered equipment slots, the
## held-light toggle, panel equip/unequip transfers, and mouse-demolish
## always taking the topmost part at the pointed tile (walls included).
## Run: godot --headless --path . --script res://tests/test_equipment.gd
extends SceneTree

var _failures := 0
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_equipment_component()
	_test_player_held_light()
	_test_character_panel()
	_test_demolish_top()
	print("Equipment/character failures: %d (%d checks)" % [_failures, _checks])
	quit(_failures)

func _make_database() -> ItemDatabase:
	var database := ItemDatabase.new()
	database.initialize()
	return database

func _make_inventory(database: ItemDatabase) -> InventoryComponent:
	var inventory := InventoryComponent.new()
	var stack_sizes: Dictionary = {}
	for item_id in database.items:
		stack_sizes[item_id] = int(database.items[item_id].stack_size)
	inventory.set_stack_sizes(stack_sizes)
	return inventory

func _test_equipment_component() -> void:
	var database := _make_database()
	var equipment := EquipmentComponent.new()
	equipment.tag_checker = func(item_id: String, tag: String) -> bool:
		var item := database.get_item(item_id)
		return item != null and item.has_tag(tag)
	equipment.apply_filters()
	_check(equipment.light_item_id() == "" and not equipment.light_enabled,
			"Equipment starts with empty slots and an unlit light")
	var light_storage := equipment.get_slot_storage("light")
	_check(light_storage.add_item("torch", 1) == 0,
			"The light slot accepts an item tagged light_source")
	_check(equipment.light_item_id() == "torch",
			"Equipping a torch makes it the light source")
	var armor_storage := equipment.get_slot_storage("armor")
	_check(armor_storage.add_item("torch", 1) == 1 and armor_storage.occupied_count() == 0,
			"The armour slot refuses a light source (tag mismatch)")
	_check(armor_storage.add_item("stone", 1) == 1,
			"Untagged items are refused by every equipment slot")
	_check(equipment.toggle_light() and equipment.light_enabled,
			"L toggles the equipped light on")
	_check(equipment.toggle_light() == false and not equipment.light_enabled,
			"A second L press toggles the light back off")
	# Unequip via transfer: the whole stack returns to the player inventory.
	var player_storage := InventoryStorage.new(10, 0.0)
	var outcome := InventoryTransfer.transfer(light_storage, 0, player_storage,
			player_storage.find_receiving_slot_for("torch", 1), 1)
	_check(int(outcome[InventoryTransfer.RESULT_MOVED]) == 1
			and equipment.light_item_id() == "",
			"Unequipping moves the torch back out of the light slot")
	_check(not equipment.toggle_light(),
			"The light toggle is refused with no light equipped")
	# Save roundtrip: contents and the lit state persist.
	_check(light_storage.add_item("torch", 1) == 0, "The torch re-equips for the save")
	equipment.set_light_enabled(true)
	var payload := equipment.serialize()
	var restored := EquipmentComponent.new()
	restored.deserialize(payload)
	_check(restored.light_item_id() == "torch" and restored.light_enabled,
			"Equipment contents and lit state survive serialize/deserialize")

func _test_player_held_light() -> void:
	var world := Node.new()
	root.add_child(world)
	var database := _make_database()
	database.name = "ItemDatabase"
	world.add_child(database)
	var player := Player.new()
	player.name = "Player"
	world.add_child(player)
	var held_light: PointLight2D = player.get_node_or_null("HeldLight")
	_check(held_light != null and not held_light.visible,
			"The player carries a held light that starts hidden")
	_check(player.toggle_held_light() == "empty",
			"L with nothing equipped reports an empty light slot")
	player.equipment.get_slot_storage("light").add_item("torch", 1)
	_check(not held_light.visible,
			"Equipping a torch alone does not light it (L is the switch)")
	_check(player.toggle_held_light() == "lit" and held_light.visible,
			"L lights the equipped torch and the held light turns on")
	_check(is_equal_approx(held_light.energy, 1.25)
			and held_light.color == Color(1.0, 0.82, 0.55),
			"The held light reads its presentation from the item's data fields")
	player.equipment.get_slot_storage("light").clear()
	_check(not held_light.visible,
			"Unequipping the light hides the held light even while lit")
	world.queue_free()

func _test_character_panel() -> void:
	var world := Node.new()
	root.add_child(world)
	var database := _make_database()
	database.name = "ItemDatabase"
	world.add_child(database)
	var player := Player.new()
	player.name = "Player"
	world.add_child(player)
	player.inventory.add_item("torch", 3)
	player.inventory.add_item("stone", 5)
	var panel := CharacterPanel.new()
	panel.name = "CharacterPanel"
	world.add_child(panel)
	panel.configure(player, database)
	# Open and equip by click-click: select the torch, click the light slot.
	panel.open_panel()
	_check(panel.is_open, "K opens the character screen")
	var toasts: Array[String] = []
	panel.toast_requested.connect(func(text: String) -> void: toasts.append(text))
	var torch_slot := player.inventory.get_storage().first_index_of("torch")
	panel._on_grid_slot_pressed("player", torch_slot, MOUSE_BUTTON_LEFT)
	panel._on_grid_slot_pressed("light", 0, MOUSE_BUTTON_LEFT)
	_check(player.equipment.light_item_id() == "torch"
			and player.inventory.get_item_quantity("torch") == 0,
			"Click-click equips the torch stack into the light slot")
	# A stone can never land in an equipment slot: the filter names the slot.
	var stone_slot := player.inventory.get_storage().first_index_of("stone")
	panel._on_grid_slot_pressed("player", stone_slot, MOUSE_BUTTON_LEFT)
	panel._on_grid_slot_pressed("armor", 0, MOUSE_BUTTON_LEFT)
	_check(player.equipment.get_slot_storage("armor").occupied_count() == 0
			and toasts == ["That slot only accepts armour"],
			"A refused equip names the slot's tag requirement")
	# Shift-click unequips straight back into the inventory.
	panel._on_quick_transfer("light", 0)
	_check(player.equipment.light_item_id() == ""
			and player.inventory.get_item_quantity("torch") == 3,
			"Shift-click unequips the whole stack into the inventory")
	# Shift-click equip: the first slot whose tag accepts the item wins.
	var torch_slot_again := player.inventory.get_storage().first_index_of("torch")
	panel._on_quick_transfer("player", torch_slot_again)
	_check(player.equipment.light_item_id() == "torch",
			"Shift-click equips into the matching equipment slot")
	# The light button flips the equipped torch, exactly like the L key.
	var toggles: Array[String] = []
	panel.light_toggle_requested.connect(func() -> void:
		var outcome := player.toggle_held_light()
		if outcome != "empty":
			toggles.append(outcome))
	panel.light_toggle_requested.emit()
	_check(toggles == ["lit"] and player.equipment.light_enabled,
			"The panel's light switch mirrors the L toggle")
	panel.close_panel()
	_check(not panel.is_open, "Closing the character screen hides it")
	world.queue_free()

func _test_demolish_top() -> void:
	var database := _make_database()
	var inventory := _make_inventory(database)
	inventory.add_item("wooden_foundation", 4)
	inventory.add_item("wooden_floor", 4)
	inventory.add_item("wooden_wall", 8)
	var manager := BuildingManager.new()
	root.add_child(manager)
	var tile := Vector2i(30, 30)
	_check(manager.place_record("wooden_foundation", tile, inventory, 0),
			"A ground foundation places on solid land")
	_check(manager.place_record("wooden_floor", tile, inventory, 1),
			"An upper floor places over the foundation's structure")
	_check(manager._demolish_top_at_tile(tile)
			and manager.get_record_at(tile, 1, "floor") == null
			and manager.get_record_at(tile, 0, "ground") != null,
			"F removes the TOP level first: the floor goes, the foundation stays")
	_check(manager._demolish_top_at_tile(tile)
			and manager.get_record_at(tile, 0, "ground") == null,
			"A second press removes the now-top foundation")
	# Walls anchor to edges: a wall on the east side of (40,30) is found both
	# from its own anchor tile and from the tile it visually borders.
	_check(manager.place_record("wooden_wall", Vector2i(40, 30), inventory, 0, "east"),
			"A wall places on an edge")
	_check(manager._demolish_top_at_tile(Vector2i(40, 30)),
			"Pointing at the wall's anchor tile finds the wall")
	_check(manager.place_record("wooden_wall", Vector2i(40, 30), inventory, 0, "east"),
			"The wall re-places for the neighbour check")
	_check(manager._demolish_top_at_tile(Vector2i(41, 30)),
			"Pointing at the tile the wall visually borders finds it too")
	# A full column: wall (edge, story 0) + floor above it at story 1, over a
	# foundation. Pointing at the column clears floor -> wall -> foundation.
	_check(manager.place_record("wooden_foundation", Vector2i(50, 50), inventory, 0),
			"A second column's foundation places")
	_check(manager.place_record("wooden_wall", Vector2i(50, 50), inventory, 0, "north"),
			"A wall places on the column's north edge")
	_check(manager.place_record("wooden_floor", Vector2i(50, 50), inventory, 1),
			"The column's upper floor places")
	_check(manager._demolish_top_at_tile(Vector2i(50, 50))
			and manager.get_record_at(Vector2i(50, 50), 1, "floor") == null
			and manager.get_record_at(Vector2i(50, 50), 0, "ground") != null,
			"Pointing at the column removes its top level (the floor) first")
	_check(manager._demolish_top_at_tile(Vector2i(50, 49))
			and manager.get_record_at(Vector2i(50, 50), 0, "edge", "north") == null,
			"Pointing at the wall from the neighbouring tile removes the wall")
	_check(manager._demolish_top_at_tile(Vector2i(50, 50))
			and manager.get_record_at(Vector2i(50, 50), 0, "ground") == null,
			"The last press removes the foundation")
	_check(not manager._demolish_top_at_tile(Vector2i(50, 50)),
			"Demolishing an empty tile is a safe no-op")
	manager.queue_free()

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures += 1
		push_error("[FAIL] %s" % label)
