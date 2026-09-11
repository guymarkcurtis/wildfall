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
const WATER_FRAME_SECONDS: float = 0.32

var _chunk_data: Dictionary = {}
var _tile_set: TileSet = null
# Sibling under Main; provides per-tile biome ids for smooth biome borders.
var world_generator: Node = null
var _water_cells: Dictionary = {}
var _water_frame: int = 0
var _water_frame_elapsed: float = 0.0
var _art_generator: TileSetGenerator = null
# The TileMap remains as the logical terrain grid. These sprites are its
# high-resolution visual surface, generated once per streamed chunk.
var _chunk_art_sprites: Dictionary = {}
var _chunk_tile_ids: Dictionary = {}

## Set up the tile set.
func _ready() -> void:
	_create_tile_set()
	world_generator = get_node_or_null("../WorldGenerator")

## Create the tile set with proper sprites.
func _create_tile_set() -> void:
	_art_generator = TileSetGenerator.new()
	add_child(_art_generator)
	_tile_set = _art_generator.generate_tile_set()
	tile_set = _tile_set

func _process(delta: float) -> void:
	_water_frame_elapsed += delta
	if _water_frame_elapsed < WATER_FRAME_SECONDS or _water_cells.is_empty():
		return
	_water_frame_elapsed = 0.0
	_water_frame = (_water_frame + 1) % 4
	_refresh_water_animation()

## Update terrain for a chunk.
func update_chunk(chunk_coords: Vector2i, data: Dictionary) -> void:
	_chunk_data[str(chunk_coords)] = data
	_render_chunk(chunk_coords, data)

## Clear all terrain.
func clear_all() -> void:
	_chunk_data.clear()
	_water_cells.clear()
	_chunk_tile_ids.clear()
	for sprite in _chunk_art_sprites.values():
		if is_instance_valid(sprite):
			sprite.queue_free()
	_chunk_art_sprites.clear()
	clear()

## Clear rendered tiles for one chunk (used when the chunk is unloaded).
## (Godot 4.6's TileMapLayer has no rectangle-erase method, and
## PackedVector2iArray is not nameable in GDScript annotations in this
## engine build, so the chunk's 16x16 cells are erased one by one.)
func clear_chunk(chunk_coords: Vector2i) -> void:
	var chunk_key := str(chunk_coords)
	_chunk_data.erase(chunk_key)
	_chunk_tile_ids.erase(chunk_key)
	if _chunk_art_sprites.has(chunk_key):
		var sprite: Sprite2D = _chunk_art_sprites[chunk_key]
		if is_instance_valid(sprite):
			sprite.queue_free()
		_chunk_art_sprites.erase(chunk_key)
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

func _get_source_id(tile_id: int) -> int:
	if tile_id != TILE_WATER:
		return tile_id
	return 100 + _water_frame

func _refresh_water_animation() -> void:
	for cell in _water_cells:
		set_cell(cell, _get_source_id(TILE_WATER), Vector2i(0, 0))
	for chunk_key in _chunk_tile_ids:
		var tile_ids: PackedInt32Array = _chunk_tile_ids[chunk_key]
		if tile_ids.has(TILE_WATER):
			_update_chunk_surface_from_key(chunk_key, tile_ids)

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
		add_child(sprite)
		_chunk_art_sprites[chunk_key] = sprite
	sprite.texture = texture

func _update_chunk_surface_from_key(chunk_key: String, tile_ids: PackedInt32Array) -> void:
	var coords_text := chunk_key.trim_prefix("(").trim_suffix(")").split(", ")
	if coords_text.size() != 2:
		return
	var chunk_coords := Vector2i(int(coords_text[0]), int(coords_text[1]))
	_update_chunk_surface(chunk_coords, tile_ids)

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
