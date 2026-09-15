## Verifies that a named user texture pack fully overrides every stock asset.
## Usage: godot --headless --path . --script tools/verify_texture_pack.gd -- <pack-id>
extends SceneTree

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(1)
		return
	var pack_id := args[0]
	if not TexturePackManager.get_available_pack_ids().has(pack_id):
		push_error("Texture pack is not discoverable: %s" % pack_id)
		quit(1)
		return
	var previous := TexturePackManager.get_active_pack_id()
	var failures := 0
	if not TexturePackManager.set_active_pack_id(pack_id):
		push_error("Could not activate texture pack: %s" % pack_id)
		quit(1)
		return
	for relative_path in TexturePackManager.get_pack_override_paths():
		var override_path := "user://texture_packs/%s/%s" % [pack_id, relative_path]
		var image := TexturePackManager.get_image("res://%s" % relative_path)
		if not FileAccess.file_exists(override_path) or image == null or image.is_empty():
			failures += 1
			push_error("Missing or unreadable override: %s" % relative_path)
	TexturePackManager.set_active_pack_id(previous)
	print("Texture-pack verification: %d failure(s)." % failures)
	quit(failures)
