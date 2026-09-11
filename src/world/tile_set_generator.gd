## Builds Wildfall's illustrated terrain and resource TileSet from project art.
##
## The atlas files are intentionally kept at their original generated resolution.
## At startup each module is cropped and smoothly reduced to the game's 32px grid,
## keeping the world compatible with its existing coordinates and collision logic.
class_name TileSetGenerator
extends Node

const TILE_SIZE: int = 32
# Quiet ground can be composed at low material resolution and smoothly scaled.
# This keeps chunk streaming light enough to avoid gameplay hitches.
const MATERIAL_PIXELS_PER_TILE: int = 4

const TERRAIN_ATLAS_PATH := "res://assets/tiles/wildfall-terrain-atlas.png"
const RESOURCE_ATLAS_PATH := "res://assets/tiles/wildfall-resources-atlas.png"
const WATER_ANIMATION_PATH := "res://assets/tiles/wildfall-water-animation.png"
const GROUND_DETAILS_PATH := "res://assets/tiles/wildfall-ground-details.png"
const TERRAIN_ATLAS: Texture2D = preload("res://assets/tiles/wildfall-terrain-atlas.png")
const RESOURCE_ATLAS: Texture2D = preload("res://assets/tiles/wildfall-resources-atlas.png")
const WATER_ANIMATION: Texture2D = preload("res://assets/tiles/wildfall-water-animation.png")
const GROUND_DETAILS: Texture2D = preload("res://assets/tiles/wildfall-ground-details.png")

const WATER_FRAME_SOURCE_IDS := [100, 101, 102, 103]

# HarvestableResource creates a short-lived generator per spawned prop. Keep
# the cropped resource textures shared so chunk streaming never reprocesses an
# atlas for every tree, rock, and bush.
static var _resource_texture_cache: Dictionary = {}
static var _ground_detail_texture_cache: Dictionary = {}

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
		_add_tile(tile_set, get_water_source_id(frame), _create_water_texture(frame), true)

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

## Returns one sparse, transparent environment accent from the 4x2 detail
## sheet. These are deliberately separate sprites rather than pixels baked
## into the floor, allowing each biome to be re-scattered as chunks stream.
func get_ground_detail_texture(index: int) -> ImageTexture:
	if _ground_detail_texture_cache.has(index):
		return _ground_detail_texture_cache[index]
	var texture := _load_atlas_cell(GROUND_DETAILS_PATH, 4, 2, index)
	_ground_detail_texture_cache[index] = texture
	return texture

## Compose a quiet, continuous ground material. The palette is sampled in world
## space so the faint painted texture crosses chunk and tile borders without
## repeating. Props, plants and rocks are rendered later as independent nodes.
func create_contiguous_chunk_image(world_start: Vector2i, tile_ids: PackedInt32Array,
		chunk_size: int, water_frame: int) -> Image:
	var image := Image.create_empty(chunk_size * MATERIAL_PIXELS_PER_TILE,
			chunk_size * MATERIAL_PIXELS_PER_TILE,
			false, Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var tile_x: int = x / MATERIAL_PIXELS_PER_TILE
			var tile_y: int = y / MATERIAL_PIXELS_PER_TILE
			var tile_index: int = tile_y * chunk_size + tile_x
			var tile_id: int = tile_ids[tile_index] if tile_index < tile_ids.size() else TILE_GRASS
			var scale: int = TILE_SIZE / MATERIAL_PIXELS_PER_TILE
			var world_x: int = (world_start.x * TILE_SIZE) + x * scale + scale / 2
			var world_y: int = (world_start.y * TILE_SIZE) + y * scale + scale / 2
			var colour: Color = _material_colour(tile_id, world_x, world_y, water_frame)
			# Feather only the edge between differing materials. This preserves
			# shorelines and biome shapes without a hard 32px checkerboard seam.
			var edge_distance: int = min(min(x % MATERIAL_PIXELS_PER_TILE, MATERIAL_PIXELS_PER_TILE - 1 - (x % MATERIAL_PIXELS_PER_TILE)),
					min(y % MATERIAL_PIXELS_PER_TILE, MATERIAL_PIXELS_PER_TILE - 1 - (y % MATERIAL_PIXELS_PER_TILE)))
			if edge_distance < 1:
				var neighbour_id := _nearest_different_neighbour(tile_ids, chunk_size, tile_x, tile_y, x, y, tile_id)
				if neighbour_id >= 0:
					var neighbour_colour := _material_colour(neighbour_id, world_x, world_y, water_frame)
					colour = neighbour_colour.lerp(colour, float(edge_distance + 1) / 2.0)
			image.set_pixel(x, y, colour)
	return image

func _nearest_different_neighbour(tile_ids: PackedInt32Array, chunk_size: int,
		tile_x: int, tile_y: int, pixel_x: int, pixel_y: int, tile_id: int) -> int:
	var candidates: Array[Vector2i] = []
	if pixel_x % MATERIAL_PIXELS_PER_TILE < 1: candidates.append(Vector2i(-1, 0))
	if pixel_x % MATERIAL_PIXELS_PER_TILE > MATERIAL_PIXELS_PER_TILE - 2: candidates.append(Vector2i(1, 0))
	if pixel_y % MATERIAL_PIXELS_PER_TILE < 1: candidates.append(Vector2i(0, -1))
	if pixel_y % MATERIAL_PIXELS_PER_TILE > MATERIAL_PIXELS_PER_TILE - 2: candidates.append(Vector2i(0, 1))
	for direction in candidates:
		var nx := tile_x + direction.x
		var ny := tile_y + direction.y
		if nx < 0 or nx >= chunk_size or ny < 0 or ny >= chunk_size:
			continue
		var neighbour: int = tile_ids[ny * chunk_size + nx]
		if neighbour != tile_id:
			return neighbour
	return -1

func _material_colour(tile_id: int, world_x: int, world_y: int, water_frame: int) -> Color:
	var base := _base_colour(tile_id)
	# Continuous value-noise gives each biome a real surface character: broad
	# soil shifts plus fine mineral grain. It is world-space sampled, so it
	# never repeats as a tile or accidentally becomes a baked prop layer.
	var broad: float = _value_noise(world_x, world_y, 96)
	# Fine grain is analytic rather than another four-corner noise lookup.
	# It keeps the material tactile while halving chunk composition work.
	var grain: float = 0.5 + 0.5 * sin(float(world_x) * 0.167 + float(world_y) * 0.113) \
			* sin(float(world_x) * -0.071 + float(world_y) * 0.149)
	var variation := (broad - 0.5) * 0.095 + (grain - 0.5) * 0.050
	variation += sin(float(world_x) * 0.022 + float(world_y) * 0.013) * 0.018
	if tile_id == TILE_WATER:
		variation += sin(float(world_x) * 0.036 + float(world_y) * 0.018 + water_frame * 1.57) * 0.025
		return Color(
			clampf(base.r + variation * 0.55, 0.0, 1.0),
			clampf(base.g + variation * 0.80, 0.0, 1.0),
			clampf(base.b + variation, 0.0, 1.0), 1.0
		)
	var warmth: float = (grain - 0.5) * 0.024
	return Color(
		clampf(base.r + variation + warmth, 0.0, 1.0),
		clampf(base.g + variation * 0.86, 0.0, 1.0),
		clampf(base.b + variation * 0.66 - warmth, 0.0, 1.0), 1.0
	)

func _value_noise(world_x: int, world_y: int, cell_size: int) -> float:
	var grid_x: int = floori(float(world_x) / float(cell_size))
	var grid_y: int = floori(float(world_y) / float(cell_size))
	var tx: float = float(posmod(world_x, cell_size)) / float(cell_size)
	var ty: float = float(posmod(world_y, cell_size)) / float(cell_size)
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var top := lerpf(_hash_grid(grid_x, grid_y), _hash_grid(grid_x + 1, grid_y), tx)
	var bottom := lerpf(_hash_grid(grid_x, grid_y + 1), _hash_grid(grid_x + 1, grid_y + 1), tx)
	return lerpf(top, bottom, ty)

func _hash_grid(grid_x: int, grid_y: int) -> float:
	# Integer hashing is cheaper than a random object and stays stable across
	# chunk loads, including negative coordinates.
	var value: int = grid_x * 374761393 + grid_y * 668265263
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0x7fffffff) / 2147483647.0

func _base_colour(tile_id: int) -> Color:
	match tile_id:
		TILE_WATER: return Color("#1b4b50")
		TILE_SAND: return Color("#b28d54")
		TILE_GRASS: return Color("#587143")
		TILE_FOREST: return Color("#314431")
		TILE_DIRT: return Color("#796044")
		TILE_STONE: return Color("#687078")
		TILE_SNOW: return Color("#c8d2d2")
		TILE_MUD: return Color("#504b38")
		_: return Color("#587143")

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
		GROUND_DETAILS_PATH:
			atlas = GROUND_DETAILS
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
