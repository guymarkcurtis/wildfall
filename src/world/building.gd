## Placeable structure with health, collision, and a colored placeholder.
class_name Building
extends StaticBody2D

const TILE_SIZE: float = 32.0
const STATION_TEXTURE_PATH := "res://assets/tiles/wildfall-crafting-stations.png"
const STATION_CELL_INDEX := {"campfire": 0, "furnace": 1, "workbench": 2, "anvil": 3}
const PARTS_TEXTURE_PATH := "res://assets/tiles/wildfall-building-parts.png"
const UTILITIES_TEXTURE_PATH := "res://assets/tiles/wildfall-building-utilities.png"
## Row order of the parts atlas: 2 columns (wood, stone) x 9 rows of 32px cells.
const PARTS_ROW_ORDER := ["foundation", "floor", "wall", "window", "door", "roof", "stair", "ramp", "pillar"]
const PARTS_MATERIAL_COLUMN := {"wood": 0, "stone": 1}
## Cell order of the utilities sheet: 5 columns x 1 row of 32px cells.
const UTILITY_CELL_INDEX := {"torch": 0, "bed": 1, "chest": 2, "farm_soil": 3, "fence": 4}

var building_id: String = ""
var display_name: String = "Building"
var health: int = 50
var max_health: int = 50
var tile_coords: Vector2i = Vector2i.ZERO
var story: int = 0
var part_type: String = "utility"
var tier: String = ""
var blocks_movement: bool = true
var layer: String = "object"
var orientation: String = ""

## Stable identity derived from the placement. Owned by the BuildingRecord;
## kept here for UI ownership and save-keyed lookups. Never a NodePath,
## creation order, or random id.
var placement_key: String = ""

## Per-placed-object runtime state for the capabilities its definition
## declares (container contents, fuel remaining, enabled flag, ...). The
## authoritative copy lives on the BuildingRecord and is serialized inside
## the building's save entry as `state`. Generic by design.
var capability_state: Dictionary = {}

## How far an edge part's art nudges toward its oriented edge (cheap
## readability for the edge model until the dedicated edge art lands).
const EDGE_VISUAL_OFFSET: float = 6.0

var _body: Polygon2D = null
var _station_sprite: Sprite2D = null
var _part_sprite: Sprite2D = null
var _label: Label = null
var _health_bar: ProgressBar = null

signal building_destroyed
signal building_damaged(current_health: int, max_health: int)

func setup(item_id: String, item_name: String, tile: Vector2i, hp: int = 50, story_level: int = 0, definition: Variant = null, placement_layer: String = "", edge_orientation: String = "") -> void:
	building_id = item_id
	display_name = item_name
	tile_coords = tile
	story = story_level
	health = hp
	max_health = hp
	placement_key = "%d:%d:%d" % [tile.x, tile.y, story]
	layer = placement_layer if placement_layer != "" else (str(definition.effective_placement_layer()) if definition != null else "object")
	orientation = edge_orientation
	# Aligned top-down: every story sits on the same world X/Y (the floor-plan
	# model). Stories are told apart by render band and opacity, never by
	# shifting position up the screen.
	position = Vector2(tile) * TILE_SIZE
	part_type = str(definition.get("part_type")) if definition != null else "utility"
	tier = str(definition.get("tier")) if definition != null else ""
	blocks_movement = bool(definition.get("blocks_movement")) if definition != null else _id_blocks(item_id)
	z_index = _render_band()
	_setup_visuals()
	_setup_collision()

func _id_blocks(item_id: String) -> bool:
	return item_id.ends_with("wall") or item_id == "fence" or item_id == "wooden_door"

func _setup_visuals() -> void:
	var edge_offset := _edge_visual_offset()
	_body = Polygon2D.new()
	var inset: float = 2.0
	_body.polygon = PackedVector2Array([
		Vector2(inset, inset),
		Vector2(TILE_SIZE - inset, inset),
		Vector2(TILE_SIZE - inset, TILE_SIZE - inset),
		Vector2(inset, TILE_SIZE - inset)
	])
	_body.color = _color_for(building_id)
	_body.position = edge_offset
	add_child(_body)
	if STATION_CELL_INDEX.has(building_id):
		# Station artwork always comes through the texture-pack manager. The
		# matching 4x1 sheet is exported with every reference/refinement pack.
		_body.color = Color(0.0, 0.0, 0.0, 0.0)
		_station_sprite = Sprite2D.new()
		_station_sprite.position = Vector2(TILE_SIZE, TILE_SIZE) * 0.5 + edge_offset
		_station_sprite.region_enabled = true
		_station_sprite.region_rect = Rect2(float(STATION_CELL_INDEX[building_id]) * TILE_SIZE, 0.0, TILE_SIZE, TILE_SIZE)
		_station_sprite.texture = TexturePackManager.get_texture(STATION_TEXTURE_PATH)
		add_child(_station_sprite)
	var atlas_cell := _atlas_cell(building_id)
	if atlas_cell.x >= 0:
		# Structural parts and the small utilities render from their atlas
		# cell; the flat color placeholder stays as a fallback when the art
		# sheet is missing or the part has no atlas cell.
		_body.color = Color(0.0, 0.0, 0.0, 0.0)
		_part_sprite = Sprite2D.new()
		_part_sprite.position = Vector2(TILE_SIZE, TILE_SIZE) * 0.5 + edge_offset
		_part_sprite.region_enabled = true
		_part_sprite.region_rect = Rect2(float(atlas_cell.x) * TILE_SIZE, float(atlas_cell.y) * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		_part_sprite.texture = TexturePackManager.get_texture(UTILITIES_TEXTURE_PATH if UTILITY_CELL_INDEX.has(building_id) else PARTS_TEXTURE_PATH)
		add_child(_part_sprite)

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

func reload_visual_texture() -> void:
	if _station_sprite != null:
		_station_sprite.texture = TexturePackManager.get_texture(STATION_TEXTURE_PATH)
	if _part_sprite != null:
		_part_sprite.texture = TexturePackManager.get_texture(UTILITIES_TEXTURE_PATH if UTILITY_CELL_INDEX.has(building_id) else PARTS_TEXTURE_PATH)

## Nudge direction for edge parts so their oriented side reads from above.
func _edge_visual_offset() -> Vector2:
	if layer != "edge":
		return Vector2.ZERO
	match orientation:
		"north":
			return Vector2(0.0, -EDGE_VISUAL_OFFSET)
		"south":
			return Vector2(0.0, EDGE_VISUAL_OFFSET)
		"west":
			return Vector2(-EDGE_VISUAL_OFFSET, 0.0)
		"east":
			return Vector2(EDGE_VISUAL_OFFSET, 0.0)
		_:
			return Vector2.ZERO

## [column, row] of this building's atlas cell, or (-1, -1) when it keeps the
## colored placeholder (no atlas cell, or the art sheet is not present yet).
func _atlas_cell(item_id: String) -> Vector2i:
	if UTILITY_CELL_INDEX.has(item_id) and not FileAccess.file_exists(UTILITIES_TEXTURE_PATH):
		return Vector2i(-1, -1)
	if UTILITY_CELL_INDEX.has(item_id):
		return Vector2i(int(UTILITY_CELL_INDEX[item_id]), 0)
	var row := PARTS_ROW_ORDER.find(part_type)
	if row < 0 or not PARTS_MATERIAL_COLUMN.has(tier):
		return Vector2i(-1, -1)
	if not FileAccess.file_exists(PARTS_TEXTURE_PATH):
		return Vector2i(-1, -1)
	return Vector2i(int(PARTS_MATERIAL_COLUMN[tier]), row)

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
	var center := Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	if layer == "edge" and blocks_movement:
		# Edge walls occupy a strip along their oriented edge, so a room's
		# own floor tile stays walkable and the same edge can't double-book.
		var horizontal := orientation == "north" or orientation == "south" or orientation == ""
		rect.size = Vector2(TILE_SIZE - 4.0, 8.0) if horizontal else Vector2(8.0, TILE_SIZE - 4.0)
		match orientation:
			"north", "":
				center = Vector2(TILE_SIZE * 0.5, 4.0)
			"south":
				center = Vector2(TILE_SIZE * 0.5, TILE_SIZE - 4.0)
			"west":
				center = Vector2(4.0, TILE_SIZE * 0.5)
			"east":
				center = Vector2(TILE_SIZE - 4.0, TILE_SIZE * 0.5)
	else:
		rect.size = Vector2(TILE_SIZE - 4.0, TILE_SIZE - 4.0)
	shape.shape = rect
	shape.position = center
	add_child(shape)
	# Stories own dedicated collision bits, so the player's mask (owned by
	# the active-story state) only ever sees the active story's bodies.
	collision_layer = BuildingRecord.STORY_COLLISION_BASE << clampi(story, 0, BuildingRecord.MAX_STORIES - 1)
	collision_mask = 0
	if not blocks_movement or layer == "overhead":
		# Walkable parts and roofs never block anyone.
		collision_layer = 0

## Within-band z for this part's placement layer.
func _render_band() -> int:
	var story_band := clampi(story, 0, BuildingRecord.MAX_STORIES - 1) * BuildingRecord.STORY_Z_STRIDE
	return story_band + int(BuildingRecord.LAYER_Z.get(layer, 2))

## Top-down cutaway policy. The focus story is the player's active story in
## normal play and the selected construction story in build mode.
##   focus story: full colour (roofs/overheads fade so interiors read; the
##                sandbox roof toggle can hide them completely)
##   below focus: ~25% ghost — orientation only, never a second floor
##   above focus: hidden while moving; a faint blueprint in build mode
## All stories stay aligned in X/Y — no screen-position skew.
func set_presentation(focus_story: int, build_mode: bool, roofs_visible: bool = true) -> void:
	var delta := story - focus_story
	if delta > 0:
		if build_mode:
			visible = true
			modulate = Color(0.75, 0.85, 1.0, 0.14) # blueprint hint
		else:
			visible = false
		return
	visible = true
	if delta < 0:
		modulate = Color(1.0, 1.0, 1.0, 0.25)
		return
	if layer == "overhead":
		modulate = Color(1.0, 1.0, 1.0, 0.4 if roofs_visible else 0.0)
		visible = roofs_visible
		return
	modulate = Color(1.0, 1.0, 1.0, 1.0)

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
