## Renders chunk terrain using TileMapLayer with proper tile sprites.
class_name TerrainRenderer
extends TileMapLayer

const CHUNK_SIZE: int = 16
const TILE_SIZE: int = 32

# Tile IDs
const TILE_WATER: int = 0
const TILE_SAND: int = 1
const TILE_GRASS: int = 2
const TILE_FOREST: int = 3
const TILE_DIRT: int = 4
const TILE_STONE: int = 5
const TILE_SNOW: int = 6
const TILE_MUD: int = 7

var _chunk_data: Dictionary = {}
var _chunk_coords: Dictionary = {}
var _tile_set: TileSet = null
# Sibling under Main; provides per-tile biome ids for smooth biome borders.
var world_generator: Node = null
var _water_cells: Dictionary = {}
var _water_frame: int = 0
var _art_generator: TileSetGenerator = null
# The TileMap remains as the logical terrain grid. Visuals deliberately live
# in sibling layers so its legacy tiles can never peek through the new surface.
var _chunk_art_sprites: Dictionary = {}
var _chunk_tile_ids: Dictionary = {}
var _chunk_detail_sprites: Dictionary = {}
var _surface_layer: Node2D = null
var _detail_layer: Node2D = null

## Set up the tile set.
func _ready() -> void:
	_create_tile_set()
	collision_enabled = true
	world_generator = get_node_or_null("../WorldGenerator")
	_create_visual_layers()
	# Physics stays on this TileMapLayer, while the visual tile sheet is hidden.
	# This prevents a 32px grid from leaking through at material transitions.
	visible = false

func _create_visual_layers() -> void:
	var parent := get_parent()
	if parent == null:
		return
	_surface_layer = Node2D.new()
	_surface_layer.name = "TerrainSurfaceLayer"
	_surface_layer.z_index = -20
	parent.call_deferred("add_child", _surface_layer)
	_detail_layer = Node2D.new()
	_detail_layer.name = "TerrainDetailLayer"
	_detail_layer.z_index = -10
	parent.call_deferred("add_child", _detail_layer)

## True when the given world tile is currently drawn as water.
func is_water_cell(world_tile: Vector2i) -> bool:
	return _water_cells.has(world_tile)

## Create the tile set with proper sprites.
func _create_tile_set() -> void:
	_art_generator = TileSetGenerator.new()
	add_child(_art_generator)
	_tile_set = _art_generator.generate_tile_set()
	tile_set = _tile_set

## Update terrain for a chunk.
func update_chunk(chunk_coords: Vector2i, data: Dictionary) -> void:
	_chunk_data[str(chunk_coords)] = data
	_chunk_coords[str(chunk_coords)] = chunk_coords
	_render_chunk(chunk_coords, data)

## Rebuild visual and TileSet textures without changing generated terrain,
## tile IDs, collisions, or the player's world state. This preserves Godot's
## TileSet handling while allowing an active texture pack to change live.
func refresh_texture_pack() -> void:
	TileSetGenerator.clear_texture_caches()
	if is_instance_valid(_art_generator):
		_art_generator.queue_free()
	_art_generator = TileSetGenerator.new()
	add_child(_art_generator)
	_tile_set = _art_generator.generate_tile_set()
	tile_set = _tile_set
	for chunk_key in _chunk_data:
		var coords: Vector2i = _chunk_coords.get(chunk_key, Vector2i.ZERO)
		_render_chunk(coords, _chunk_data[chunk_key])

## Clear all terrain.
func clear_all() -> void:
	_chunk_data.clear()
	_chunk_coords.clear()
	_water_cells.clear()
	_chunk_tile_ids.clear()
	for sprite in _chunk_art_sprites.values():
		if is_instance_valid(sprite):
			sprite.queue_free()
	_chunk_art_sprites.clear()
	for sprites in _chunk_detail_sprites.values():
		for sprite in sprites:
			if is_instance_valid(sprite):
				sprite.queue_free()
	_chunk_detail_sprites.clear()
	clear()

## Clear rendered tiles for one chunk (used when the chunk is unloaded).
## (Godot 4.6's TileMapLayer has no rectangle-erase method, and
## PackedVector2iArray is not nameable in GDScript annotations in this
## engine build, so the chunk's 16x16 cells are erased one by one.)
func clear_chunk(chunk_coords: Vector2i) -> void:
	var chunk_key := str(chunk_coords)
	_chunk_data.erase(chunk_key)
	_chunk_coords.erase(chunk_key)
	_chunk_tile_ids.erase(chunk_key)
	if _chunk_art_sprites.has(chunk_key):
		var sprite: Sprite2D = _chunk_art_sprites[chunk_key]
		if is_instance_valid(sprite):
			sprite.queue_free()
		_chunk_art_sprites.erase(chunk_key)
	_clear_chunk_details(chunk_key)
	var world_start: Vector2i = _chunk_coords_to_world_start(chunk_coords)
	for y in range(CHUNK_SIZE):
		for x in range(CHUNK_SIZE):
			var cell := world_start + Vector2i(x, y)
			erase_cell(cell)
			_water_cells.erase(cell)

## Render a single chunk.
func _render_chunk(chunk_coords: Vector2i, data: Dictionary) -> void:
	if not data.has("elevation") or not data.has("moisture") or not data.has("biome"):
		return

	var world_start: Vector2i = _chunk_coords_to_world_start(chunk_coords)
	var elevation: PackedFloat32Array = data["elevation"]
	var moisture: PackedFloat32Array = data["moisture"]
	var tile_ids := PackedInt32Array()

	for y in range(CHUNK_SIZE):
		for x in range(CHUNK_SIZE):
			var world_x: int = world_start.x + x
			var world_y: int = world_start.y + y
			var tile_index: int = y * CHUNK_SIZE + x
			var elev: float = elevation.get(tile_index) if tile_index < elevation.size() else 0.5
			var moist: float = moisture.get(tile_index) if tile_index < moisture.size() else 0.5
			# Per-tile biome where the generator is available (smooth biome
			# borders); otherwise the chunk's dominant biome.
			var biome_id: String = data["biome"]
			if world_generator != null and is_instance_valid(world_generator) \
					and world_generator.has_method("get_biome_at_world"):
				biome_id = world_generator.get_biome_at_world(world_x, world_y)
			var tile_id: int = _get_tile_id(elev, moist, biome_id)
			tile_ids.append(tile_id)
			var cell := world_start + Vector2i(x, y)
			# Water has four animated source textures; the other terrain source IDs
			# remain identical to their biome tile IDs.
			set_cell(cell, _get_source_id(tile_id), Vector2i(0, 0))
			if tile_id == TILE_WATER:
				_water_cells[cell] = true
			else:
				_water_cells.erase(cell)

	_chunk_tile_ids[str(chunk_coords)] = tile_ids
	_update_chunk_surface(chunk_coords, tile_ids)
	_update_chunk_details(chunk_coords, tile_ids)

func _get_source_id(tile_id: int) -> int:
	if tile_id != TILE_WATER:
		return tile_id
	return 100 + _water_frame

func _update_chunk_surface(chunk_coords: Vector2i, tile_ids: PackedInt32Array) -> void:
	if _art_generator == null:
		return
	var chunk_key := str(chunk_coords)
	var world_start := _chunk_coords_to_world_start(chunk_coords)
	var texture := ImageTexture.create_from_image(
		_art_generator.create_contiguous_chunk_image(world_start, tile_ids, CHUNK_SIZE, _water_frame)
	)
	var sprite: Sprite2D = _chunk_art_sprites.get(chunk_key)
	if sprite == null or not is_instance_valid(sprite):
		sprite = Sprite2D.new()
		sprite.centered = false
		sprite.position = Vector2(world_start * TILE_SIZE)
		if _surface_layer != null:
			_surface_layer.add_child(sprite)
		else:
			add_child(sprite)
		_chunk_art_sprites[chunk_key] = sprite
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.scale = Vector2.ONE * (float(TILE_SIZE) / float(TileSetGenerator.MATERIAL_PIXELS_PER_TILE))
	sprite.texture = texture

## Add sparse, independently placed accents. They make the ground feel alive
## without turning every floor pixel into a repeated illustration.
func _update_chunk_details(chunk_coords: Vector2i, tile_ids: PackedInt32Array) -> void:
	if _art_generator == null or _detail_layer == null:
		return
	var chunk_key := str(chunk_coords)
	_clear_chunk_details(chunk_key)
	var random := RandomNumberGenerator.new()
	random.seed = int(chunk_coords.x * 92821 + chunk_coords.y * 68917 + 1729)
	var sprites: Array[Sprite2D] = []
	var world_start := _chunk_coords_to_world_start(chunk_coords)
	var count := random.randi_range(9, 15)
	for _i in range(count):
		var tile_x := random.randi_range(0, CHUNK_SIZE - 1)
		var tile_y := random.randi_range(0, CHUNK_SIZE - 1)
		var tile_id: int = tile_ids[tile_y * CHUNK_SIZE + tile_x]
		var detail_index := _detail_for_tile(tile_id, random)
		if detail_index < 0:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = _art_generator.get_ground_detail_texture(detail_index)
		sprite.position = Vector2(
			(world_start.x + tile_x) * TILE_SIZE + random.randf_range(5.0, 27.0),
			(world_start.y + tile_y) * TILE_SIZE + random.randf_range(5.0, 27.0)
		)
		sprite.rotation = random.randf_range(-0.35, 0.35)
		sprite.scale = Vector2.ONE * random.randf_range(0.55, 0.82)
		sprite.modulate.a = random.randf_range(0.72, 0.94)
		_detail_layer.add_child(sprite)
		sprites.append(sprite)
	_chunk_detail_sprites[chunk_key] = sprites

func _clear_chunk_details(chunk_key: String) -> void:
	if not _chunk_detail_sprites.has(chunk_key):
		return
	for sprite in _chunk_detail_sprites[chunk_key]:
		if is_instance_valid(sprite):
			sprite.queue_free()
	_chunk_detail_sprites.erase(chunk_key)

func _detail_for_tile(tile_id: int, random: RandomNumberGenerator) -> int:
	match tile_id:
		TILE_WATER: return -1
		TILE_SAND: return [0, 3, 4][random.randi_range(0, 2)]
		TILE_GRASS: return [1, 3, 4, 5][random.randi_range(0, 3)]
		TILE_FOREST: return [2, 3, 4, 5][random.randi_range(0, 3)]
		TILE_DIRT, TILE_MUD: return [0, 3, 4, 6][random.randi_range(0, 3)]
		TILE_STONE: return [0, 4, 7][random.randi_range(0, 2)]
		TILE_SNOW: return 7
		_: return -1

## Get tile ID based on elevation, moisture, and the tile's biome.
## Water and sand shoreline are shared by all biomes; the biome then picks
## the ground cover so each of the six biomes reads distinctly on the map.
func _get_tile_id(elevation: float, moisture: float, biome: String) -> int:
	if elevation < 0.3:
		return TILE_WATER
	if elevation < 0.35:
		return TILE_SAND  # shoreline
	match biome:
		"arctic":
			return TILE_SNOW
		"desert":
			if elevation > 0.7:
				return TILE_STONE  # rocky high desert
			return TILE_SAND
		"mountain":
			if elevation > 0.5:
				return TILE_STONE
			return TILE_GRASS  # foothills
		"swamp":
			if moisture > 0.3:
				return TILE_MUD
			return TILE_GRASS
		"temperate_forest":
			if elevation > 0.7:
				return TILE_STONE
			if moisture > 0.3:
				return TILE_FOREST
			return TILE_GRASS
		"grassland", _:
			if elevation > 0.7:
				return TILE_STONE
			if moisture > 0.6:
				return TILE_MUD  # wet meadow
			if elevation > 0.5:
				return TILE_DIRT
			return TILE_GRASS

## Convert chunk coords to world start position.
func _chunk_coords_to_world_start(chunk_coords: Vector2i) -> Vector2i:
	return Vector2i(chunk_coords.x * CHUNK_SIZE, chunk_coords.y * CHUNK_SIZE)
