## Presentation-only animated creature sprite driven by Creature movement.
class_name CreatureVisual
extends Node2D

const ROSTER_SHEET: Texture2D = preload("res://assets/creatures/alien-creature-roster.png")
const COLUMNS := 4
const ROWS := 2
const FRAME_SECONDS := 0.22

const SPECIES_COLUMNS := {
	"rabbit": 2,       # quick bone-shell scavenger
	"deer": 1,         # moss-backed grazer
	"boar": 0,         # plated dusk stalker
	"wolf": 0,
	"polar_bear": 1,
	"vulture": 3,      # hovering spore predator
	"fish": 3
}

# Creature instances stream in and out with chunks. Build the two presentation
# frames once per species/size pair instead of resampling a large source image
# every time a creature enters view.
static var _texture_cache: Dictionary = {}

var _sprite: Sprite2D
var _species: String = "rabbit"
var _frame: int = 0
var _elapsed: float = 0.0
var _idle_texture: Texture2D
var _move_texture: Texture2D

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.z_index = 1
	add_child(_sprite)
	_apply_texture()

func configure(species: String, visual_size: float) -> void:
	_species = species
	var cache_key := "%s_%.1f" % [_species, visual_size]
	if _texture_cache.has(cache_key):
		var frames: Array = _texture_cache[cache_key]
		_idle_texture = frames[0]
		_move_texture = frames[1]
		_apply_texture()
		return
	var sheet := ROSTER_SHEET.get_image()
	var cell_width: int = sheet.get_width() / COLUMNS
	var cell_height: int = sheet.get_height() / ROWS
	var column: int = int(SPECIES_COLUMNS.get(_species, 0))
	_idle_texture = _make_texture(sheet, Rect2i(column * cell_width, 0, cell_width, cell_height), visual_size)
	_move_texture = _make_texture(sheet, Rect2i(column * cell_width, cell_height, cell_width, cell_height), visual_size)
	_texture_cache[cache_key] = [_idle_texture, _move_texture]
	_apply_texture()

func update_animation(motion: Vector2, delta: float) -> void:
	if motion.length() < 1.0:
		_frame = 0
		_apply_texture()
		return
	_elapsed += delta
	if _elapsed >= FRAME_SECONDS:
		_elapsed = 0.0
		_frame = 1 - _frame
		_apply_texture()
	# Roster art faces +Y (head toward the bottom of the cell).
	if _sprite != null:
		_sprite.flip_h = false
	rotation = motion.angle() - PI * 0.5

func _make_texture(sheet: Image, region: Rect2i, visual_size: float) -> Texture2D:
	var frame := sheet.get_region(region)
	var used := frame.get_used_rect()
	if used.size.x > 0 and used.size.y > 0:
		frame = frame.get_region(used)
	var height: int = clampi(int(visual_size * 5.0), 42, 96)
	var width: int = maxi(24, int(float(frame.get_width()) / float(frame.get_height()) * float(height)))
	frame.resize(width, height, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(frame)

func _apply_texture() -> void:
	if _sprite == null:
		return
	_sprite.texture = _move_texture if _frame == 1 and _move_texture != null else _idle_texture
