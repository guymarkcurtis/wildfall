## Packs downloaded Pixel Lab character frames into Wildfall's runtime layout.
##
## Usage:
## godot --headless --path . --script tools/build_character_pack.gd -- <input-dir> <pack-dir>
##
## Input layout:
##   <input-dir>/<gender>/idle.png
##   <input-dir>/<gender>/<tool>/0.png ... 3.png
## where gender is male/female and tool is axe, pickaxe, sword, bow, hoe, or hammer.
extends SceneTree

const GENDERS := ["male", "female"]
const TOOLS := ["axe", "pickaxe", "sword", "bow", "hoe", "hammer"]

func _init() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 2:
		_fail("Expected <input-dir> and <pack-dir> arguments.")
		return
	var input_root := arguments[0]
	var pack_root := arguments[1]
	for gender in GENDERS:
		for tool in TOOLS:
			var frames: Array[String] = []
			for index in range(4):
				frames.append("%s/%s/%s/%d.png" % [input_root, gender, tool, index])
			_pack_strip(frames, "%s/assets/characters/actions/%s-%s.png" % [pack_root, gender, tool])
	_pack_walk_sheet(input_root, "%s/assets/characters/explorer-base-walk.png" % pack_root)
	_pack_walk_sheet(input_root, "%s/assets/characters/explorer-storm-walk.png" % pack_root)
	print("Character texture pack written to ", pack_root)
	quit(0)

func _pack_walk_sheet(input_root: String, destination: String) -> void:
	var generated_male_path := "%s/male/walk.png" % input_root
	var generated_female_path := "%s/female/walk.png" % input_root
	if FileAccess.file_exists(generated_male_path) and FileAccess.file_exists(generated_female_path):
		_pack_generated_walk_rows(generated_male_path, generated_female_path, destination)
		return
	var male_frames := _load_animation_frames(input_root, "male", "walk")
	var female_frames := _load_animation_frames(input_root, "female", "walk")
	if male_frames.size() == 4 and female_frames.size() == 4:
		_pack_walk_frames(male_frames, female_frames, destination)
		return
	var male := _load_required("%s/male/idle.png" % input_root)
	var female := _load_required("%s/female/idle.png" % input_root)
	if male == null or female == null:
		return
	var width := maxi(male.get_width(), female.get_width())
	var height := maxi(male.get_height(), female.get_height())
	var sheet := Image.create_empty(width * 4, height * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	for column in range(4):
		sheet.blit_rect(male, Rect2i(Vector2i.ZERO, male.get_size()), Vector2i(column * width + (width - male.get_width()) / 2, (height - male.get_height()) / 2))
		sheet.blit_rect(female, Rect2i(Vector2i.ZERO, female.get_size()), Vector2i(column * width + (width - female.get_width()) / 2, height + (height - female.get_height()) / 2))
	_save(sheet, destination)

func _load_animation_frames(input_root: String, gender: String, animation: String) -> Array[Image]:
	var frames: Array[Image] = []
	for index in range(4):
		var path := "%s/%s/%s/%d.png" % [input_root, gender, animation, index]
		if not FileAccess.file_exists(path):
			return []
		var frame := _load_required(path)
		if frame == null:
			return []
		frames.append(frame)
	return frames

func _pack_walk_frames(male_frames: Array[Image], female_frames: Array[Image], destination: String) -> void:
	var width := 0
	var height := 0
	for frame in male_frames + female_frames:
		width = maxi(width, frame.get_width())
		height = maxi(height, frame.get_height())
	var sheet := Image.create_empty(width * 4, height * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	for column in range(4):
		var male := male_frames[column]
		var female := female_frames[column]
		sheet.blit_rect(male, Rect2i(Vector2i.ZERO, male.get_size()), Vector2i(column * width + (width - male.get_width()) / 2, (height - male.get_height()) / 2))
		sheet.blit_rect(female, Rect2i(Vector2i.ZERO, female.get_size()), Vector2i(column * width + (width - female.get_width()) / 2, height + (height - female.get_height()) / 2))
	_save(sheet, destination)

## Image generators can author the entire four-column walk row in one pass.
## Keeping those rows intact avoids a brittle attempt to detect subject bounds.
func _pack_generated_walk_rows(male_path: String, female_path: String, destination: String) -> void:
	var male := _load_required(male_path)
	var female := _load_required(female_path)
	if male == null or female == null:
		return
	var width := maxi(male.get_width(), female.get_width())
	var height := maxi(male.get_height(), female.get_height())
	var sheet := Image.create_empty(width, height * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)
	sheet.blit_rect(male, Rect2i(Vector2i.ZERO, male.get_size()), Vector2i((width - male.get_width()) / 2, (height - male.get_height()) / 2))
	sheet.blit_rect(female, Rect2i(Vector2i.ZERO, female.get_size()), Vector2i((width - female.get_width()) / 2, height + (height - female.get_height()) / 2))
	_save(sheet, destination)

func _pack_strip(paths: Array[String], destination: String) -> void:
	var generated_strip_path := paths[0].get_base_dir().path_join("strip.png")
	if FileAccess.file_exists(generated_strip_path):
		var generated_strip := _load_required(generated_strip_path)
		if generated_strip != null:
			_save(generated_strip, destination)
		return
	var frames: Array[Image] = []
	for path in paths:
		var frame := _load_required(path)
		if frame == null:
			return
		frames.append(frame)
	var width := 0
	var height := 0
	for frame in frames:
		width = maxi(width, frame.get_width())
		height = maxi(height, frame.get_height())
	var strip := Image.create_empty(width * frames.size(), height, false, Image.FORMAT_RGBA8)
	strip.fill(Color.TRANSPARENT)
	for index in range(frames.size()):
		var frame := frames[index]
		strip.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(index * width + (width - frame.get_width()) / 2, (height - frame.get_height()) / 2))
	_save(strip, destination)

func _load_required(path: String) -> Image:
	var image := Image.new()
	if image.load(path) != OK or image.is_empty():
		_fail("Could not read generated frame: %s" % path)
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _save(image: Image, destination: String) -> void:
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	if image.save_png(destination) != OK:
		_fail("Could not write %s" % destination)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
