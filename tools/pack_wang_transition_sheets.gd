## Normalizes PixelLab's metadata-defined Wang sheet order into the runtime
## order used by TileSetGenerator: NW=1, NE=2, SW=4, SE=8.
##
## Usage:
## godot --headless --path . --script tools/pack_wang_transition_sheets.gd -- <input-dir> <pack-dir>
## Input must contain <pair>-sheet.png and <pair>-meta.json for every pair.
extends SceneTree

const PAIRS := ["water-sand", "sand-grass", "sand-forest", "grass-forest", "grass-stone", "forest-stone", "stone-snow", "grass-mud"]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		_fail("Expected <input-dir> and <pack-dir> arguments.")
		return
	for pair in PAIRS:
		_pack_pair(args[0], args[1], pair)
	print("PixelLab Wang transition sheets written.")
	quit(0)

func _pack_pair(input_root: String, pack_root: String, pair: String) -> void:
	var sheet := Image.new()
	var image_path := input_root.path_join("%s-sheet.png" % pair)
	if sheet.load(image_path) != OK or sheet.is_empty():
		_fail("Could not load PixelLab Wang sheet: %s" % image_path)
		return
	var metadata_path := input_root.path_join("%s-meta.json" % pair)
	var file := FileAccess.open(metadata_path, FileAccess.READ)
	if file == null:
		_fail("Could not load PixelLab Wang metadata: %s" % metadata_path)
		return
	var metadata: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	var tiles: Array = metadata.get("tileset_data", {}).get("tiles", [])
	if tiles.size() != 16:
		_fail("Expected 16 Wang tiles in %s." % metadata_path)
		return
	var atlas := Image.create_empty(128, 128, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	for raw_tile in tiles:
		var tile: Dictionary = raw_tile
		var corners: Dictionary = tile.get("corners", {})
		var mask := 0
		if corners.get("NW", "lower") == "upper": mask |= 1
		if corners.get("NE", "lower") == "upper": mask |= 2
		if corners.get("SW", "lower") == "upper": mask |= 4
		if corners.get("SE", "lower") == "upper": mask |= 8
		var box: Dictionary = tile.get("bounding_box", {})
		var source := Rect2i(int(box.get("x", 0)), int(box.get("y", 0)), int(box.get("width", 0)), int(box.get("height", 0)))
		if source.size != Vector2i(32, 32):
			_fail("Unexpected PixelLab tile bounds in %s." % pair)
			return
		atlas.blit_rect(sheet, source, Vector2i(posmod(mask, 4) * 32, (mask / 4) * 32))
	var destination := pack_root.path_join("assets/tiles/transitions/%s.png" % pair)
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	if atlas.save_png(destination) != OK:
		_fail("Could not save Wang transition atlas: %s" % destination)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
