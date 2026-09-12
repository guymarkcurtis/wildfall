## Starts a clean Survival game with the PixelLab comparison pack and captures
## the rendered viewport without relying on desktop capture permissions.
extends SceneTree

func _initialize() -> void:
	TexturePackManager.set_active_pack_id("pixellab_comparison")
	GameSession.request_new_game(GameSession.MODE_SURVIVAL)
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	var seed_input := root.get_node_or_null("Main/SeedInput")
	if seed_input != null and seed_input.has_method("set_seed"):
		seed_input.set_seed(41158)
	for frame in range(20):
		await process_frame
	RenderingServer.force_draw()
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png("/tmp/riftwake-pixellab-in-game.png") != OK:
		push_error("Could not capture the in-game PixelLab frame.")
		quit(1)
		return
	print("Captured PixelLab new-game frame.")
	quit()
