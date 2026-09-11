extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var player: Player = main.get_node("Player")
	player.global_position = Vector2(20000, 20000)
	player.set_aim_locked(Vector2.RIGHT)
	var assignments: Array[String] = ["wooden_axe", "stone_pickaxe"]
	player.set_hotbar_items(assignments)
	var failures := 0
	for entry in [{"type": "tree", "item": "wood", "slot": 0}, {"type": "rock", "item": "stone", "slot": 1}]:
		var resource := HarvestableResource.new()
		resource.position = player.global_position + Vector2(24, -16)
		resource.setup(entry.type, 60.0, [{"item_id": entry.item, "min_qty": 4, "max_qty": 4, "chance": 1.0}])
		resource.resource_destroyed.connect(func(id: String, quantity: int): main._on_resource_destroyed(resource, id, quantity))
		main.add_child(resource)
		var before := player.inventory.get_item_quantity(entry.item)
		player.select_hotbar_slot(entry.slot)
		for hit in range(4):
			player.set("_fire_cooldown", 0.0)
			player._handle_interaction()
		if not resource.is_destroyed or player.inventory.get_item_quantity(entry.item) != before + 4:
			failures += 1
			push_error("Harvest failed: " + entry.type)
		await process_frame
	var wood_before := player.inventory.get_item_quantity("wood")
	var planks_before := player.inventory.get_item_quantity("plank")
	var recipes: Array = main.get("_recipe_defs")
	for index in range(recipes.size()):
		if recipes[index].recipe_id == "plank":
			main._on_craft_requested(index)
			break
	if player.inventory.get_item_quantity("wood") != wood_before - 1 or player.inventory.get_item_quantity("plank") != planks_before + 4:
		failures += 1
		push_error("Harvested materials did not craft into planks")
	main.queue_free()
	await process_frame
	print("Harvesting and crafting failures: ", failures)
	quit(failures)
