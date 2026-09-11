extends SceneTree

func _initialize() -> void:
	var exported := TexturePackManager.export_stock_reference()
	TexturePackManager.create_refinement_pack()
	var failures := 0
	var manifest_file := FileAccess.open("user://texture_packs/stock_reference/manifest.json", FileAccess.READ)
	var manifest: Dictionary = JSON.parse_string(manifest_file.get_as_text()) if manifest_file != null else {}
	if manifest_file != null:
		manifest_file.close()
	var asset_metadata: Array = manifest.get("assets", [])
	if manifest.get("schema") != "riftwake.texture-pack" or manifest.get("schema_version") != 2 or asset_metadata.size() != TexturePackManager.PACK_ASSETS.size():
		failures += 1
	for asset in asset_metadata:
		if not asset is Dictionary or not asset.has_all(["path", "name", "purpose", "used_for", "layout", "editor_note"]):
			failures += 1
	for surface in TexturePackManager.GROUND_NAMES:
		var image := Image.new()
		if image.load("user://texture_packs/refinement/assets/ground/%s.png" % surface) != OK or image.get_size() != Vector2i(256, 256):
			failures += 1
	var previous := TexturePackManager.get_active_pack_id()
	TexturePackManager.set_active_pack_id("refinement")
	TileSetGenerator.clear_texture_caches()
	var generator := TileSetGenerator.new()
	var ground := TexturePackManager.get_image("res://assets/ground/grass.png")
	if not generator._material_colour(2, 17, 23, 0).is_equal_approx(ground.get_pixel(17, 23)):
		failures += 1
	TexturePackManager.set_active_pack_id(previous)
	TileSetGenerator.clear_texture_caches()
	generator.free()
	print("Ground pack checks: ", failures, " failures. Export: ", exported)
	quit(failures)
