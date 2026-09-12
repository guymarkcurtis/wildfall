## Selects a discoverable pack through the same runtime API as the Options UI.
## Usage: godot --headless --path . --script tools/set_texture_pack.gd -- <pack-id>
extends SceneTree

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not TexturePackManager.set_active_pack_id(args[0]):
		quit(1)
		return
	print("Active texture pack: ", TexturePackManager.get_active_pack_id())
	quit()
