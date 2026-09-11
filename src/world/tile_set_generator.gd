## Builds Wildfall's illustrated terrain and resource TileSet from project art.
##
## The atlas files are intentionally kept at their original generated resolution.
## At startup each module is cropped and smoothly reduced to the game's 32px grid,
## keeping the world compatible with its existing coordinates and collision logic.
class_name TileSetGenerator
extends Node

const TILE_SIZE: int = 32

const TERRAIN_ATLAS_PATH := "res://assets/tiles/wildfall-terrain-atlas.png"
const RESOURCE_ATLAS_PATH := "res://assets/tiles/wildfall-resources-atlas.png"
const WATER_ANIMATION_PATH := "res://assets/tiles/wildfall-water-animation.png"
const TERRAIN_ATLAS: Texture2D = preload("res://assets/tiles/wildfall-terrain-atlas.png")
const RESOURCE_ATLAS: Texture2D = preload("res://assets/tiles/wildfall-resources-atlas.png")
const WATER_ANIMATION: Texture2D = preload("res://assets/tiles/wildfall-water-animation.png")

const WATER_FRAME_SOURCE_IDS := [100, 101, 102, 103]

# HarvestableResource creates a short-lived generator per spawned prop. Keep
# the cropped resource textures shared so chunk streaming never reprocesses an
# atlas for every tree, rock, and bush.
static var _resource_texture_cache: Dictionary = {}
# Full-resolution material cells, retained for the chunk surface compositor.
# These are sampled in world-space rather than repeated as 32px tiles.
static var _terrain_surface_cache: Dictionary = {}

# Terrain tile IDs
const TILE_WATER: int = 0
const TILE_SAND: int = 1
const TILE_GRASS: int = 2
const TILE_FOREST: int = 3
const TILE_DIRT: int = 4
const TILE_STONE: int = 5
const TILE_SNOW: int = 6
const TILE_MUD: int = 7

# Resource tile IDs
const TILE_TREE: int = 10
const TILE_ROCK: int = 11
const TILE_FIBRE: int = 12
const TILE_BERRY: int = 13
const TILE_IRON_ORE: int = 14
const TILE_COAL: int = 15
const TILE_GOLD_ORE: int = 16
const TILE_CRYSTAL: int = 17

## Generate the complete in-memory tile set used by TerrainRenderer.
func generate_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.set_tile_size(Vector2i(TILE_SIZE, TILE_SIZE))
	_generate_terrain_tiles(tile_set)
	_generate_resource_tiles(tile_set)
	return tile_set

## Source ID for a frame in the four-frame water loop.
func get_water_source_id(frame: int) -> int:
	return WATER_FRAME_SOURCE_IDS[posmod(frame, WATER_FRAME_SOURCE_IDS.size())]

func _generate_terrain_tiles(tile_set: TileSet) -> void:
	# Water is placed in four different TileSet sources so TerrainRenderer can
	# switch all water cells together without changing the game's tile IDs.
	for frame in range(WATER_FRAME_SOURCE_IDS.size()):
		_add_tile(tile_set, get_water_source_id(frame), _create_water_texture(frame))

	_add_tile(tile_set, TILE_SAND, _create_terrain_texture(TILE_SAND))
	_add_tile(tile_set, TILE_GRASS, _create_terrain_texture(TILE_GRASS))
	_add_tile(tile_set, TILE_FOREST, _create_terrain_texture(TILE_FOREST))
	_add_tile(tile_set, TILE_DIRT, _create_terrain_texture(TILE_DIRT))
	_add_tile(tile_set, TILE_STONE, _create_terrain_texture(TILE_STONE), true)
	_add_tile(tile_set, TILE_SNOW, _create_terrain_texture(TILE_SNOW))
	_add_tile(tile_set, TILE_MUD, _create_terrain_texture(TILE_MUD))

func _generate_resource_tiles(tile_set: TileSet) -> void:
	_add_tile(tile_set, TILE_TREE, _create_tree_texture())
	_add_tile(tile_set, TILE_ROCK, _create_rock_texture())
	_add_tile(tile_set, TILE_FIBRE, _create_fibre_texture())
	_add_tile(tile_set, TILE_BERRY, _create_berry_texture())
	_add_tile(tile_set, TILE_IRON_ORE, _create_iron_ore_texture())
	_add_tile(tile_set, TILE_COAL, _create_coal_texture())
	_add_tile(tile_set, TILE_GOLD_ORE, _create_gold_ore_texture())
	_add_tile(tile_set, TILE_CRYSTAL, _create_crystal_texture())

## The terrain sheet is ordered row-major as water, sand, grass, forest,
## dirt, stone, snow, mud. Water is supplied by its dedicated animation strip.
func _create_terrain_texture(tile_id: int) -> ImageTexture:
	return _load_atlas_cell(TERRAIN_ATLAS_PATH, 4, 2, tile_id)

func _create_water_texture(frame: int) -> ImageTexture:
	return _load_atlas_cell(WATER_ANIMATION_PATH, 4, 1, frame)

## Resource order in the illustrated sheet: tree, rock, fibre, berry, iron,
## coal, gold, crystal.
func _create_tree_texture() -> ImageTexture:
	return _load_resource_texture(0)

func _create_rock_texture() -> ImageTexture:
	return _load_resource_texture(1)

func _create_fibre_texture() -> ImageTexture:
	return _load_resource_texture(2)

func _create_berry_texture() -> ImageTexture:
	return _load_resource_texture(3)

func _create_iron_ore_texture() -> ImageTexture:
	return _load_resource_texture(4)

func _create_coal_texture() -> ImageTexture:
	return _load_resource_texture(5)

func _create_gold_ore_texture() -> ImageTexture:
	return _load_resource_texture(6)

func _create_crystal_texture() -> ImageTexture:
	return _load_resource_texture(7)

func _load_resource_texture(index: int) -> ImageTexture:
	if _resource_texture_cache.has(index):
		return _resource_texture_cache[index]
	var texture := _load_atlas_cell(RESOURCE_ATLAS_PATH, 4, 2, index)
	_resource_texture_cache[index] = texture
	return texture

## Compose a chunk from the original high-resolution material art. Sampling is
## anchored to world pixels, so two neighbouring cells of the same material
## share a continuous image instead of visibly repeating a 32px tile.
func create_contiguous_chunk_image(world_start: Vector2i, tile_ids: PackedInt32Array,
		chunk_size: int, water_frame: int) -> Image:
	var image := Image.create_empty(chunk_size * TILE_SIZE, chunk_size * TILE_SIZE,
			false, Image.FORMAT_RGBA8)
	for y in range(chunk_size):
		for x in range(chunk_size):
			var index: int = y * chunk_size + x
			var tile_id: int = tile_ids[index] if index < tile_ids.size() else TILE_GRASS
			var source := _get_continuous_surface(tile_id, water_frame)
			if source == null or source.is_empty():
				continue
			var world_pixel := Vector2i(
				(world_start.x + x) * TILE_SIZE,
				(world_start.y + y) * TILE_SIZE
			)
			var source_x: int = posmod(world_pixel.x, max(1, source.get_width() - TILE_SIZE))
			var source_y: int = posmod(world_pixel.y, max(1, source.get_height() - TILE_SIZE))
			image.blit_rect(source, Rect2i(source_x, source_y, TILE_SIZE, TILE_SIZE),
					Vector2i(x * TILE_SIZE, y * TILE_SIZE))
	return image

func _get_continuous_surface(tile_id: int, water_frame: int) -> Image:
	if tile_id == TILE_WATER:
		return _get_atlas_surface(WATER_ANIMATION, 4, 1, water_frame, "water_%d" % water_frame)
	return _get_atlas_surface(TERRAIN_ATLAS, 4, 2, tile_id, "terrain_%d" % tile_id)

func _get_atlas_surface(atlas: Texture2D, columns: int, rows: int, index: int,
		cache_key: String) -> Image:
	if _terrain_surface_cache.has(cache_key):
		return _terrain_surface_cache[cache_key]
	if atlas == null:
		return null
	var sheet := atlas.get_image()
	if sheet == null or sheet.is_empty():
		return null
	var cell_width: int = sheet.get_width() / columns
	var cell_height: int = sheet.get_height() / rows
	var column: int = posmod(index, columns)
	var row: int = clampi(index / columns, 0, rows - 1)
	var surface := sheet.get_region(Rect2i(
		column * cell_width, row * cell_height, cell_width, cell_height
	))
	_terrain_surface_cache[cache_key] = surface
	return surface

## Crops a source module, smooths it to the current world tile size, and
## preserves alpha for resource sprites.
func _load_atlas_cell(path: String, columns: int, rows: int, index: int) -> ImageTexture:
	var atlas: Texture2D = null
	match path:
		TERRAIN_ATLAS_PATH:
			atlas = TERRAIN_ATLAS
		RESOURCE_ATLAS_PATH:
			atlas = RESOURCE_ATLAS
		WATER_ANIMATION_PATH:
			atlas = WATER_ANIMATION
	var sheet: Image = atlas.get_image() if atlas != null else null
	if sheet == null or sheet.is_empty() or columns <= 0 or rows <= 0:
		push_warning("Wildfall art atlas could not be loaded: %s" % path)
		return _create_fallback_texture()

	var cell_width: int = sheet.get_width() / columns
	var cell_height: int = sheet.get_height() / rows
	var column: int = posmod(index, columns)
	var row: int = clampi(index / columns, 0, rows - 1)
	var region := Rect2i(column * cell_width, row * cell_height, cell_width, cell_height)
	var cell: Image = sheet.get_region(region)
	cell.resize(TILE_SIZE, TILE_SIZE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(cell)

func _create_fallback_texture() -> ImageTexture:
	var image := Image.create_empty(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.12, 0.22, 0.19, 1.0))
	return ImageTexture.create_from_image(image)

func _add_tile(tile_set: TileSet, tile_id: int, texture: ImageTexture, collide: bool = false) -> void:
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	source.create_tile(Vector2i(0, 0))
	tile_set.add_source(source, tile_id)
	if not collide:
		return
	if tile_set.get_physics_layers_count() == 0:
		tile_set.add_physics_layer()
	var tile_data: TileData = source.get_tile_data(Vector2i(0, 0), 0)
	if tile_data == null:
		return
	tile_data.add_collision_polygon(0)
	var half := float(TILE_SIZE) * 0.5
	tile_data.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)
	]))
