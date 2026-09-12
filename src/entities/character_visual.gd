## Presentation-only player character sprite system.
## Gameplay owns movement; this component turns that movement into a walk loop
## and exposes gender/outfit selection without changing player mechanics.
class_name CharacterVisual
extends Node2D

const BASE_SHEET_PATH := "res://assets/characters/explorer-base-walk.png"
const STORM_SHEET_PATH := "res://assets/characters/explorer-storm-walk.png"
const ACTION_SHEET_PATH := "res://assets/characters/actions/%s-%s.png"
const TRAILBLAZER_ROOT := "res://assets/characters/trailblazer/%s/Idle"
const COLUMNS := 4
const ROWS := 2
const FRAME_SIZE := Vector2i(72, 96)
const DIRECTIONAL_FRAME_SIZE := Vector2i(88, 88)
const WALK_FRAME_SECONDS := 0.13
const ACTION_FRAME_SECONDS := 0.11
## Player aim remains continuous, but the visual reserves 16 facing slots so
## higher-density authored rotations can be added later. PixelLab's current
## Trailblazer art supplies the eight cardinal/intercardinal frames below.
const FACING_SLOT_COUNT := 16
const ART_DIRECTIONS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
# `pickaxe` must precede `axe`, because "pickaxe" also ends in "axe".
const ACTION_TOOL_TYPES := ["pickaxe", "axe", "sword", "bow", "hoe", "hammer"]
const ACTION_ANIMATION_TYPES := ["pickaxe", "axe", "sword", "bow", "hoe", "hammer", "jump"]

var _sprite: Sprite2D
var _gender: String = "female"
var _outfit: String = "base"
var _frame: int = 0
var _walk_time: float = 0.0
var _frame_textures: Array[Texture2D] = []
var _action_frame_textures: Dictionary = {}
var _directional_walk_textures: Dictionary = {}
var _directional_action_frame_textures: Dictionary = {}
var _uses_directional_art := false
var _facing_slot := 0
var _facing_direction := "east"
var _look_direction := Vector2.RIGHT
var _tool_id := "hand"
var _action_type := ""
var _action_elapsed := -1.0

func set_equipped_tool(tool_id: String) -> void:
	_tool_id = tool_id
	queue_redraw()

func play_tool_swing() -> void:
	_action_type = _tool_type_for_id(_tool_id)
	if _action_type.is_empty():
		return
	_action_elapsed = 0.0
	queue_redraw()

## A jump is a full authored body animation, separate from tool-use logic.
func play_jump() -> void:
	_action_type = "jump"
	_action_elapsed = 0.0
	queue_redraw()

func _draw() -> void:
	if _action_elapsed < 0.0 or _action_type == "jump" or not _current_action_frames().is_empty():
		return
	var progress := clampf(_action_elapsed / (ACTION_FRAME_SECONDS * COLUMNS), 0.0, 1.0)
	# Only the held tool rotates in this fallback. The body always comes from
	# an authored directional frame, never from rotating its sprite node.
	var angle := _look_direction.angle() + lerpf(-1.2, 1.0, progress)
	var grip := _look_direction * 12.0
	var tip := grip + Vector2(0, 28).rotated(angle)
	draw_line(grip, tip, Color("98683e"), 4.0, true)
	var cross := Vector2(10, 0).rotated(angle)
	if _action_type == "pickaxe":
		draw_line(tip - cross, tip + cross, Color("c0c9d1"), 5.0, true)
	elif _action_type == "axe":
		draw_colored_polygon(PackedVector2Array([tip - cross * 0.3, tip + cross, tip + cross + Vector2(0, 10).rotated(angle), tip + Vector2(0, 6).rotated(angle)]), Color("bbc5cf"))
	elif _action_type == "sword":
		draw_line(grip, tip, Color("c0c9d1"), 5.0, true)

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.position = Vector2(0, -20)
	_sprite.z_index = 1
	add_child(_sprite)
	set_appearance(_gender, _outfit)

## `gender` selects the authored male/female row; `outfit` selects a whole
## visual layer today, while retaining a stable API for future equipment slots.
func set_appearance(gender: String, outfit: String) -> void:
	_gender = gender if gender in ["male", "female"] else "female"
	_outfit = outfit if outfit in ["base", "storm"] else "base"
	_frame_textures.clear()
	_directional_walk_textures.clear()
	_directional_action_frame_textures.clear()
	_load_directional_frames()
	var source: Texture2D = TexturePackManager.get_texture(STORM_SHEET_PATH if _outfit == "storm" else BASE_SHEET_PATH)
	if source != null:
		var sheet := source.get_image()
		var cell_width: int = sheet.get_width() / COLUMNS
		var cell_height: int = sheet.get_height() / ROWS
		var row: int = 0 if _gender == "male" else 1
		for column in range(COLUMNS):
			var frame := sheet.get_region(Rect2i(column * cell_width, row * cell_height,
					cell_width, cell_height))
			_frame_textures.append(_make_frame_texture(frame))
	_load_action_frames()
	_frame = 0
	_action_elapsed = -1.0
	_apply_frame()

func set_outfit(outfit: String) -> void:
	set_appearance(_gender, outfit)

func reload_texture_pack() -> void:
	set_appearance(_gender, _outfit)

## `facing` is the aim direction (mouse). The body selects an authored
## directional frame independently of travel; it must never rotate as a node.
func update_animation(motion: Vector2, delta: float, facing: Vector2 = Vector2.ZERO) -> void:
	var look: Vector2 = facing if facing != Vector2.ZERO else motion
	if look != Vector2.ZERO:
		_look_direction = look.normalized()
		_facing_slot = _direction_slot_for_vector(_look_direction)
		_facing_direction = _art_direction_for_slot(_facing_slot)
	rotation = 0.0
	if _action_elapsed >= 0.0:
		_action_elapsed += delta
		var action_frames := _current_action_frames()
		var action_duration := ACTION_FRAME_SECONDS * (action_frames.size() if not action_frames.is_empty() else COLUMNS)
		if _action_elapsed >= action_duration:
			_action_elapsed = -1.0
			_action_type = ""
			_apply_frame()
		else:
			_apply_frame()
		queue_redraw()
	elif motion.length() < 1.0:
		_walk_time = 0.0
		_frame = 0
		_apply_frame()
	else:
		_walk_time += delta
		if _walk_time >= WALK_FRAME_SECONDS:
			_walk_time = 0.0
			_frame = (_frame + 1) % _walk_frame_count()
			_apply_frame()

func _apply_frame() -> void:
	if _sprite == null:
		return
	if _action_elapsed >= 0.0:
		var action_frames := _current_action_frames()
		if not action_frames.is_empty():
			var action_frame := mini(int(_action_elapsed / ACTION_FRAME_SECONDS), action_frames.size() - 1)
			_sprite.texture = action_frames[action_frame] as Texture2D
			return
	if _uses_directional_art:
		var directional_frames: Array = _directional_walk_textures.get(_facing_direction, [])
		if not directional_frames.is_empty():
			_sprite.texture = directional_frames[_frame % directional_frames.size()] as Texture2D
			return
	if _frame < _frame_textures.size():
		_sprite.texture = _frame_textures[_frame]

func get_facing_direction_slot() -> int:
	return _facing_slot

func get_facing_direction() -> String:
	return _facing_direction

func get_active_texture() -> Texture2D:
	return _sprite.texture if _sprite != null else null

func has_complete_directional_animation(animation_type: String) -> bool:
	var by_direction: Dictionary = _directional_action_frame_textures.get(animation_type, {})
	if by_direction.size() != ART_DIRECTIONS.size():
		return false
	for direction in ART_DIRECTIONS:
		var frames: Array = by_direction.get(direction, [])
		if frames.size() != COLUMNS:
			return false
	return true

func _direction_slot_for_vector(direction: Vector2) -> int:
	var step := TAU / float(FACING_SLOT_COUNT)
	return posmod(int(floor((wrapf(direction.angle(), 0.0, TAU) + step * 0.5) / step)), FACING_SLOT_COUNT)

func _art_direction_for_slot(slot: int) -> String:
	# Nearest of the eight supplied rotations. When 16-direction art is added,
	# this lookup is the only part that needs expanded content data.
	return ART_DIRECTIONS[posmod(int(round(float(slot) * 0.5)), ART_DIRECTIONS.size())]

func _walk_frame_count() -> int:
	if _uses_directional_art:
		var frames: Array = _directional_walk_textures.get(_facing_direction, [])
		if not frames.is_empty():
			return frames.size()
	return COLUMNS

func _current_action_frames() -> Array:
	var directional_actions: Dictionary = _directional_action_frame_textures.get(_action_type, {})
	var directional_frames: Array = directional_actions.get(_facing_direction, [])
	if not directional_frames.is_empty():
		return directional_frames
	return _action_frame_textures.get(_action_type, []) if not _uses_directional_art else []

func _load_directional_frames() -> void:
	for direction in ART_DIRECTIONS:
		var frames: Array[Texture2D] = []
		for frame_index in range(5):
			var texture := _load_directional_texture("animations/walk/%s/frame_%03d.png" % [direction, frame_index])
			if texture != null:
				frames.append(texture)
		if not frames.is_empty():
			_directional_walk_textures[direction] = frames
	_uses_directional_art = _directional_walk_textures.size() == ART_DIRECTIONS.size()
	for tool_type in ACTION_ANIMATION_TYPES:
		var by_direction := {}
		for direction in ART_DIRECTIONS:
			var action_frames: Array[Texture2D] = []
			for frame_index in range(COLUMNS):
				var texture := _load_directional_texture("animations/%s/%s/frame_%03d.png" % [tool_type, direction, frame_index])
				if texture != null:
					action_frames.append(texture)
			if not action_frames.is_empty():
				by_direction[direction] = action_frames
		if not by_direction.is_empty():
			_directional_action_frame_textures[tool_type] = by_direction

func _load_directional_texture(relative_path: String) -> Texture2D:
	var image := TexturePackManager.get_image(TRAILBLAZER_ROOT % _gender + "/" + relative_path)
	if image == null or image.is_empty():
		return null
	return _make_frame_texture(image, DIRECTIONAL_FRAME_SIZE, false)

func _load_action_frames() -> void:
	_action_frame_textures.clear()
	for tool_type in ACTION_TOOL_TYPES:
		var source := TexturePackManager.get_texture(ACTION_SHEET_PATH % [_gender, tool_type])
		if source == null:
			continue
		var sheet := source.get_image()
		if sheet == null or sheet.is_empty():
			continue
		var frame_width := sheet.get_width() / COLUMNS
		if frame_width <= 0:
			continue
		var frames: Array[Texture2D] = []
		for column in range(COLUMNS):
			frames.append(_make_frame_texture(sheet.get_region(Rect2i(column * frame_width, 0, frame_width, sheet.get_height()))))
		_action_frame_textures[tool_type] = frames

func _make_frame_texture(frame: Image, display_size: Vector2i = FRAME_SIZE, clear_checkerboard := true) -> Texture2D:
	if clear_checkerboard:
		_clear_baked_checkerboard(frame)
	frame.resize(display_size.x, display_size.y, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(frame)

func _tool_type_for_id(tool_id: String) -> String:
	for tool_type in ACTION_TOOL_TYPES:
		if tool_id.ends_with(tool_type):
			return tool_type
	return ""

## Image generation currently returns a light checkerboard baked into these
## sheets. It is removed at load time, leaving the dark line work untouched.
func _clear_baked_checkerboard(image: Image) -> void:
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			var channel_spread := maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b))
			if channel_spread < 0.055 and color.get_luminance() > 0.67:
				color.a = 0.0
				image.set_pixel(x, y, color)
