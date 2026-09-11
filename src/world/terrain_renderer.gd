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
var _tile_set: TileSet = null
# Sibling under Main; provides per-tile biome ids for smooth biome borders.
var world_generator: Node = null

## Set up the tile set.
func _ready() -> void:
	_create_tile_set()
	world_generator = get_node_or_null("../WorldGenerator")

## Create the tile set with proper sprites.
func _create_tile_set() -> void:
	# Load and use TileSetGenerator
	var generator_script: GDScript = load("res://src/world/tile_set_generator.gd")
	var generator: Node = generator_script.new()
	add_child(generator)
	_tile_set = generator.call("generate_tile_set")
	tile_set = _tile_set
	generator.queue_free()

## Update terrain for a chunk.
func update_chunk(chunk_coords: Vector2i, data: Dictionary) -> void:
	_chunk_data[str(chunk_coords)] = data
	_render_chunk(chunk_coords, data)

## Clear all terrain.
func clear_all() -> void:
	_chunk_data.clear()
	clear()

## Clear rendered tiles for one chunk (used when the chunk is unloaded).
## (Godot 4.6's TileMapLayer has no rectangle-erase method, and
## PackedVector2iArray is not nameable in GDScript annotations in this
## engine build, so the chunk's 16x16 cells are erased one by one.)
func clear_chunk(chunk_coords: Vector2i) -> void:
	_chunk_data.erase(str(chunk_coords))
	var world_start: Vector2i = _chunk_coords_to_world_start(chunk_coords)
	for y in range(CHUNK_SIZE):
		for x in range(CHUNK_SIZE):
			erase_cell(world_start + Vector2i(x, y))

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
			# Per-tile biome where the generator is available (smooth biome
			# borders); otherwise the chunk's dominant biome.
			var biome_id: String = data["biome"]
			if world_generator != null and is_instance_valid(world_generator) \
					and world_generator.has_method("get_biome_at_world"):
				biome_id = world_generator.get_biome_at_world(world_x, world_y)
			var tile_id: int = _get_tile_id(elev, moist, biome_id)
			# Each tile is its own 1x1 atlas source (source id == tile id), so the
			# cell must be placed at the world coordinate and at atlas coord (0,0).
			set_cell(world_start + Vector2i(x, y), tile_id, Vector2i(0, 0))

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
