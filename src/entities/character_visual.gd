## Presentation-only player character sprite system.
## Gameplay owns movement; this component turns that movement into a walk loop
## and exposes gender/outfit selection without changing player mechanics.
class_name CharacterVisual
extends Node2D

const BASE_SHEET: Texture2D = preload("res://assets/characters/explorer-base-walk.png")
const STORM_SHEET: Texture2D = preload("res://assets/characters/explorer-storm-walk.png")
const COLUMNS := 4
const ROWS := 2
const FRAME_SIZE := Vector2i(72, 96)
const WALK_FRAME_SECONDS := 0.13

var _sprite: Sprite2D
var _gender: String = "female"
var _outfit: String = "base"
var _frame: int = 0
var _walk_time: float = 0.0
var _frame_textures: Array[Texture2D] = []

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
	var source: Texture2D = STORM_SHEET if _outfit == "storm" else BASE_SHEET
	var sheet := source.get_image()
	var cell_width: int = sheet.get_width() / COLUMNS
	var cell_height: int = sheet.get_height() / ROWS
	var row: int = 0 if _gender == "male" else 1
	for column in range(COLUMNS):
		var frame := sheet.get_region(Rect2i(column * cell_width, row * cell_height,
				cell_width, cell_height))
		_clear_baked_checkerboard(frame)
		frame.resize(FRAME_SIZE.x, FRAME_SIZE.y, Image.INTERPOLATE_LANCZOS)
		_frame_textures.append(ImageTexture.create_from_image(frame))
	_frame = 0
	_apply_frame()

func set_outfit(outfit: String) -> void:
	set_appearance(_gender, outfit)

## `facing` is the aim direction (mouse). The sprite always turns to that,
## independent of travel. Walk frames still follow `motion`.
func update_animation(motion: Vector2, delta: float, facing: Vector2 = Vector2.ZERO) -> void:
	if motion.length() < 1.0:
		_walk_time = 0.0
		_frame = 0
		_apply_frame()
	else:
		_walk_time += delta
		if _walk_time >= WALK_FRAME_SECONDS:
			_walk_time = 0.0
			_frame = (_frame + 1) % COLUMNS
			_apply_frame()
	# Sheets face +Y (down the screen). Aim/mouse is the orientation.
	var look: Vector2 = facing if facing != Vector2.ZERO else motion
	if look != Vector2.ZERO:
		if _sprite != null:
			_sprite.flip_h = false
		rotation = look.angle() - PI * 0.5

func _apply_frame() -> void:
	if _sprite != null and _frame < _frame_textures.size():
		_sprite.texture = _frame_textures[_frame]

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
