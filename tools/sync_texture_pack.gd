## Fills missing assets in one or more existing texture packs without
## overwriting their custom art. Use whenever PACK_ASSETS gains new content.
##
## Usage:
## godot --headless --path . --script tools/sync_texture_pack.gd -- <pack-id> [<pack-id> ...]
extends SceneTree

func _init() -> void:
	var pack_ids := OS.get_cmdline_user_args()
	if pack_ids.is_empty():
		push_error("Expected at least one texture-pack id.")
		quit(1)
		return
	var failures := 0
	for pack_id in pack_ids:
		var result := TexturePackManager.sync_missing_pack_assets(pack_id)
		if not bool(result.get("ok", false)):
			failures += 1
			push_error("Could not synchronize texture pack '%s': %s" % [pack_id, str(result.get("reason", "unknown_error"))])
			continue
		print("Synchronized %s: added %d missing assets (%d total)." % [
			pack_id, int(result.get("added", 0)), int(result.get("total_assets", 0))
		])
	quit(failures)
