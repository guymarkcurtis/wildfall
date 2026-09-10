## Renders chunk terrain using TileMapLayer with proper tile set.
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
var _tile_set: TileSet = null

## Set up the tile set.
func _ready() -> void:
	_create_placeholder_tile_set()

## Create a placeholder tile set for testing.
func _create_placeholder_tile_set() -> void:
	_tile_set = TileSet.new()

	# Create simple colored tiles for each terrain type
	var tiles: Dictionary = {
		TILE_WATER: Color(0.2, 0.4, 0.8),
		TILE_SAND: Color(0.8, 0.7, 0.4),
		TILE_GRASS: Color(0.2, 0.6, 0.2),
		TILE_FOREST: Color(0.15, 0.45, 0.15),
		TILE_DIRT: Color(0.5, 0.4, 0.3),
		TILE_STONE: Color(0.5, 0.5, 0.5),
		TILE_SNOW: Color(0.9, 0.9, 0.95),
		TILE_MUD: Color(0.4, 0.35, 0.25)
	}

	# Create a simple 1x1 tile set for each terrain type
	for tile_id in tiles:
		var tile_data := TileSetAtlasSource.new()
		var texture := Image.new()
		texture.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		var color: Color = tiles[tile_id]
		for y in range(TILE_SIZE):
			for x in range(TILE_SIZE):
				texture.set_pixel(x, y, color)
		var image_texture := ImageTexture.create_from_image(texture)
		tile_data.texture = image_texture
		tile_data.add_texture_rect(Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(0, 0))
		_tile_set.add_texture_source(tile_data, -1)

	tile_set = _tile_set

## Update terrain for a chunk.
func update_chunk(chunk_coords: Vector2i, data: Dictionary) -> void:
	_chunk_data[str(chunk_coords)] = data
	_render_chunk(chunk_coords, data)

## Clear all terrain.
func clear_all() -> void:
	_chunk_data.clear()
	clear()

## Render a single chunk.
func _render_chunk(chunk_coords: Vector2i, data: Dictionary) -> void:
	if not data.has("elevation") or not data.has("moisture") or not data.has("biome"):
		return

	var world_start: Vector2i = _chunk_coords_to_world_start(chunk_coords)
	var elevation: PackedFloat32Array = data["elevation"]
	var moisture: PackedFloat32Array = data["moisture"]

	for y in range(CHUNK_SIZE):
		for x in range(CHUNK_SIZE):
			var world_x: int = world_start.x + x
			var world_y: int = world_start.y + y
			var tile_index: int = y * CHUNK_SIZE + x
			var elev: float = elevation.get(tile_index) if tile_index < elevation.size() else 0.5
			var moist: float = moisture.get(tile_index) if tile_index < moisture.size() else 0.5
			var tile_id: int = _get_tile_id(elev, moist, data["biome"])
			set_cell(Vector2i(x, y), 0, Vector2i(tile_id, 0))

## Get tile ID based on elevation and moisture.
func _get_tile_id(elevation: float, moisture: float, biome: String) -> int:
	if elevation < 0.3:
		return TILE_WATER
	elif elevation < 0.35:
		return TILE_SAND
	elif moisture > 0.6 and elevation > 0.6:
		return TILE_SNOW
	elif moisture > 0.6:
		if biome == "forest" or biome == "temperate_forest":
			return TILE_FOREST
		return TILE_MUD
	elif elevation > 0.7:
		return TILE_STONE
	elif elevation > 0.5:
		return TILE_DIRT
	else:
		if biome == "forest" or biome == "temperate_forest":
			return TILE_FOREST
		return TILE_GRASS

## Get the color for a tile ID.
func get_tile_color(tile_id: int) -> Color:
	match tile_id:
		TILE_WATER: return Color(0.2, 0.4, 0.8)
		TILE_SAND: return Color(0.8, 0.7, 0.4)
		TILE_GRASS: return Color(0.2, 0.6, 0.2)
		TILE_FOREST: return Color(0.15, 0.45, 0.15)
		TILE_DIRT: return Color(0.5, 0.4, 0.3)
		TILE_STONE: return Color(0.5, 0.5, 0.5)
		TILE_SNOW: return Color(0.9, 0.9, 0.95)
		TILE_MUD: return Color(0.4, 0.35, 0.25)
		_: return Color(0.5, 0.5, 0.5)

## Convert chunk coords to world start position.
func _chunk_coords_to_world_start(chunk_coords: Vector2i) -> Vector2i:
	return Vector2i(chunk_coords.x * CHUNK_SIZE, chunk_coords.y * CHUNK_SIZE)
