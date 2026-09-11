## Placeable structure with health, collision, and a colored placeholder.
class_name Building
extends StaticBody2D

const TILE_SIZE: float = 32.0
const STORY_RISE: float = 12.0

var building_id: String = ""
var display_name: String = "Building"
var health: int = 50
var max_health: int = 50
var tile_coords: Vector2i = Vector2i.ZERO
var story: int = 0
var part_type: String = "utility"
var blocks_movement: bool = true

var _body: Polygon2D = null
var _label: Label = null
var _health_bar: ProgressBar = null

signal building_destroyed
signal building_damaged(current_health: int, max_health: int)

func setup(item_id: String, item_name: String, tile: Vector2i, hp: int = 50, story_level: int = 0, definition: Variant = null) -> void:
	building_id = item_id
	display_name = item_name
	tile_coords = tile
	story = story_level
	health = hp
	max_health = hp
	position = Vector2(tile) * TILE_SIZE + Vector2(0.0, -story * STORY_RISE)
	part_type = str(definition.get("part_type")) if definition != null else "utility"
	blocks_movement = bool(definition.get("blocks_movement")) if definition != null else _id_blocks(item_id)
	z_index = story * 2
	_setup_visuals()
	_setup_collision()

func _id_blocks(item_id: String) -> bool:
	return item_id.ends_with("wall") or item_id == "fence" or item_id == "wooden_door"

func _setup_visuals() -> void:
	_body = Polygon2D.new()
	var inset: float = 2.0
	_body.polygon = PackedVector2Array([
		Vector2(inset, inset),
		Vector2(TILE_SIZE - inset, inset),
		Vector2(TILE_SIZE - inset, TILE_SIZE - inset),
		Vector2(inset, TILE_SIZE - inset)
	])
	_body.color = _color_for(building_id)
	add_child(_body)

	_label = Label.new()
	_label.text = "%s  L%d" % [display_name, story + 1]
	_label.position = Vector2(0.0, -16.0)
	_label.add_theme_font_size_override("font_size", 10)
	add_child(_label)

	_health_bar = ProgressBar.new()
	_health_bar.min_value = 0
	_health_bar.max_value = max_health
	_health_bar.value = health
	_health_bar.custom_minimum_size = Vector2(TILE_SIZE, 4)
	_health_bar.position = Vector2(0.0, -6.0)
	_health_bar.show_percentage = false
	add_child(_health_bar)

func _color_for(item_id: String) -> Color:
	match item_id:
		"wooden_wall", "wooden_door", "fence":
			return Color(0.55, 0.35, 0.18, 0.95)
		"stone_wall", "stone_floor":
			return Color(0.55, 0.55, 0.58, 0.95)
		"campfire":
			return Color(0.85, 0.35, 0.1, 0.95)
		"furnace", "anvil":
			return Color(0.4, 0.4, 0.45, 0.95)
		"workbench":
			return Color(0.6, 0.45, 0.25, 0.95)
		"chest":
			return Color(0.7, 0.5, 0.2, 0.95)
		"bed":
			return Color(0.45, 0.35, 0.7, 0.95)
		"torch":
			return Color(1.0, 0.8, 0.3, 0.95)
		_:
			return Color(0.5, 0.55, 0.4, 0.95)

func _setup_collision() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE_SIZE - 4.0, TILE_SIZE - 4.0)
	shape.shape = rect
	shape.position = Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	add_child(shape)
	collision_layer = 1
	collision_mask = 0
	if not blocks_movement or story > 0:
		# Upper stories are a cutaway construction plane; they should not block
		# the player moving on the ground layer.
		collision_layer = 0

## Top-down cutaway: keep the current construction story crisp, fade the
## stories beneath it, and hide the stories above it.
func set_cutaway_story(active_story: int) -> void:
	visible = story <= active_story
	modulate = Color(1.0, 1.0, 1.0, 1.0 if story == active_story else 0.48)

func take_damage(amount: float) -> bool:
	if amount <= 0 or health <= 0:
		return false
	health = maxi(0, health - int(amount))
	if _health_bar:
		_health_bar.value = health
	building_damaged.emit(health, max_health)
	if health <= 0:
		building_destroyed.emit()
		return true
	return false

func get_building_id() -> String:
	return building_id
