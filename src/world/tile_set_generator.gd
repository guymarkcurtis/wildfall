## Generates proper tile sprites for terrain and resources.
class_name TileSetGenerator
extends Node

const TILE_SIZE: int = 32

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

## Generate the full tile set for terrain.
func generate_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	
	# Generate terrain tiles
	_generate_terrain_tiles(tile_set)
	
	# Generate resource tiles
	_generate_resource_tiles(tile_set)
	
	return tile_set

## Generate terrain tiles with proper sprites.
func _generate_terrain_tiles(tile_set: TileSet) -> void:
	var water_texture := _create_gradient_texture(Color(0.2, 0.4, 0.8), Color(0.3, 0.5, 0.9))
	_add_tile(tile_set, TILE_WATER, water_texture)
	
	var sand_texture := _create_gradient_texture(Color(0.8, 0.7, 0.4), Color(0.9, 0.8, 0.5))
	_add_tile(tile_set, TILE_SAND, sand_texture)
	
	var grass_texture := _create_gradient_texture(Color(0.2, 0.6, 0.2), Color(0.3, 0.7, 0.3))
	_add_tile(tile_set, TILE_GRASS, grass_texture)
	
	var forest_texture := _create_gradient_texture(Color(0.15, 0.45, 0.15), Color(0.2, 0.5, 0.2))
	_add_tile(tile_set, TILE_FOREST, forest_texture)
	
	var dirt_texture := _create_gradient_texture(Color(0.5, 0.4, 0.3), Color(0.6, 0.5, 0.4))
	_add_tile(tile_set, TILE_DIRT, dirt_texture)
	
	var stone_texture := _create_gradient_texture(Color(0.5, 0.5, 0.5), Color(0.6, 0.6, 0.6))
	_add_tile(tile_set, TILE_STONE, stone_texture)
	
	var snow_texture := _create_gradient_texture(Color(0.9, 0.9, 0.95), Color(1.0, 1.0, 1.0))
	_add_tile(tile_set, TILE_SNOW, snow_texture)
	
	var mud_texture := _create_gradient_texture(Color(0.4, 0.35, 0.25), Color(0.5, 0.45, 0.35))
	_add_tile(tile_set, TILE_MUD, mud_texture)

## Generate resource tiles with proper sprites.
func _generate_resource_tiles(tile_set: TileSet) -> void:
	# Tree - green circle with brown center
	var tree_texture := _create_tree_texture()
	_add_tile(tile_set, TILE_TREE, tree_texture)
	
	# Rock - gray irregular shape
	var rock_texture := _create_rock_texture()
	_add_tile(tile_set, TILE_ROCK, rock_texture)
	
	# Fibre - brown bundle
	var fibre_texture := _create_fibre_texture()
	_add_tile(tile_set, TILE_FIBRE, fibre_texture)
	
	# Berry bush - green with red dots
	var berry_texture := _create_berry_texture()
	_add_tile(tile_set, TILE_BERRY, berry_texture)
	
	# Iron ore - dark gray with sparkle
	var iron_ore_texture := _create_iron_ore_texture()
	_add_tile(tile_set, TILE_IRON_ORE, iron_ore_texture)
	
	# Coal - black with shine
	var coal_texture := _create_coal_texture()
	_add_tile(tile_set, TILE_COAL, coal_texture)
	
	# Gold ore - yellow with sparkle
	var gold_ore_texture := _create_gold_ore_texture()
	_add_tile(tile_set, TILE_GOLD_ORE, gold_ore_texture)

## Create a gradient texture.
func _create_gradient_texture(color1: Color, color2: Color) -> ImageTexture:
	var image := Image.new()
	image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var ratio := float(y) / float(TILE_SIZE)
			var color := color1.lerp(color2, ratio)
			# Add some noise for texture
			var noise := randf() * 0.05
			color = Color(
				clamp(color.r + noise, 0.0, 1.0),
				clamp(color.g + noise, 0.0, 1.0),
				clamp(color.b + noise, 0.0, 1.0),
				1.0
			)
			image.set_pixel(x, y, color)
	
	return ImageTexture.create_from_image(image)

## Create a tree texture.
func _create_tree_texture() -> ImageTexture:
	var image := Image.new()
	image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	
	# Background - grass green
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			image.set_pixel(x, y, Color(0.2, 0.6, 0.2))
	
	# Trunk - brown rectangle at bottom
	for y in range(20, 32):
		for x in range(12, 20):
			image.set_pixel(x, y, Color(0.4, 0.25, 0.1))
	
	# Canopy - green circle
	var center := Vector2(16, 14)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var dist := Vector2(float(x), float(y)).distance_to(center)
			if dist < 12.0:
				var intensity := 1.0 - (dist / 12.0)
				var color := Color(0.15, 0.45, 0.15).lerp(Color(0.3, 0.7, 0.3), intensity)
				image.set_pixel(x, y, color)
	
	return ImageTexture.create_from_image(image)

## Create a rock texture.
func _create_rock_texture() -> ImageTexture:
	var image := Image.new()
	image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	
	# Background - stone gray
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			image.set_pixel(x, y, Color(0.5, 0.5, 0.5))
	
	# Rock shape - irregular gray polygon
	var points := [
		Vector2(4, 20), Vector2(8, 12), Vector2(14, 8),
		Vector2(22, 10), Vector2(28, 16), Vector2(26, 24),
		Vector2(18, 28), Vector2(10, 26)
	]
	
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if _point_in_polygon(Vector2(float(x), float(y)), points):
				var noise := randf() * 0.1
				var color := Color(0.45 + noise, 0.45 + noise, 0.45 + noise)
				image.set_pixel(x, y, color)
	
	return ImageTexture.create_from_image(image)

## Create a fibre texture.
func _create_fibre_texture() -> ImageTexture:
	var image := Image.new()
	image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	
	# Background - light brown
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			image.set_pixel(x, y, Color(0.6, 0.5, 0.3))
	
	# Fibre strands - diagonal brown lines
	for i in range(-10, 20):
		for j in range(-10, 20):
			var x := i + j
			var y := i - j + 16
			if 0 <= x < TILE_SIZE and 0 <= y < TILE_SIZE:
				if (i + j) % 3 == 0:
					image.set_pixel(x, y, Color(0.5, 0.4, 0.2))
	
	return ImageTexture.create_from_image(image)

## Create a berry bush texture.
func _create_berry_texture() -> ImageTexture:
	var image := Image.new()
	image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	
	# Background - green
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			image.set_pixel(x, y, Color(0.2, 0.5, 0.2))
	
	# Bush - darker green circle
	var center := Vector2(16, 16)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var dist := Vector2(float(x), float(y)).distance_to(center)
			if dist < 14.0:
				var color := Color(0.15, 0.4, 0.15)
				image.set_pixel(x, y, color)
	
	# Berries - red dots
	var berry_positions := [
		Vector2(8, 10), Vector2(14, 8), Vector2(20, 12),
		Vector2(10, 18), Vector2(16, 20), Vector2(22, 18),
		Vector2(12, 14), Vector2(18, 14)
	]
	for berry in berry_positions:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var px := int(berry.x) + dx
				var py := int(berry.y) + dy
				if 0 <= px < TILE_SIZE and 0 <= py < TILE_SIZE:
					var dist := Vector2(float(dx), float(dy)).length()
					if dist <= 2.0:
						image.set_pixel(px, py, Color(0.8, 0.2, 0.2))
	
	return ImageTexture.create_from_image(image)

## Create an iron ore texture.
func _create_iron_ore_texture() -> ImageTexture:
	var image := Image.new()
	image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	
	# Background - dark gray stone
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			image.set_pixel(x, y, Color(0.3, 0.3, 0.3))
	
	# Iron ore - lighter gray specks
	for i in range(15):
		var x := randi() % TILE_SIZE
		var y := randi() % TILE_SIZE
		var size := randi() % 4 + 2
		for dy in range(-size, size):
			for dx in range(-size, size):
				var px := x + dx
				var py := y + dy
				if 0 <= px < TILE_SIZE and 0 <= py < TILE_SIZE:
					var dist := Vector2(float(dx), float(dy)).length()
					if dist <= float(size):
						image.set_pixel(px, py, Color(0.6, 0.6, 0.6))
	
	return ImageTexture.create_from_image(image)

## Create a coal texture.
func _create_coal_texture() -> ImageTexture:
	var image := Image.new()
	image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	
	# Background - dark gray
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			image.set_pixel(x, y, Color(0.2, 0.2, 0.2))
	
	# Coal - black lumps with shine
	for i in range(10):
		var x := randi() % (TILE_SIZE - 6) + 3
		var y := randi() % (TILE_SIZE - 6) + 3
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var px := x + dx
				var py := y + dy
				if 0 <= px < TILE_SIZE and 0 <= py < TILE_SIZE:
					var dist := Vector2(float(dx), float(dy)).length()
					if dist <= 4.0:
						var shine := 0.1 if dist > 3.0 else 0.3
						image.set_pixel(px, py, Color(shine, shine, shine))
	
	return ImageTexture.create_from_image(image)

## Create a gold ore texture.
func _create_gold_ore_texture() -> ImageTexture:
	var image := Image.new()
	image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	
	# Background - dark gray stone
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			image.set_pixel(x, y, Color(0.35, 0.35, 0.35))
	
	# Gold ore - yellow specks
	for i in range(12):
		var x := randi() % TILE_SIZE
		var y := randi() % TILE_SIZE
		var size := randi() % 3 + 1
		for dy in range(-size, size + 1):
			for dx in range(-size, size + 1):
				var px := x + dx
				var py := y + dy
				if 0 <= px < TILE_SIZE and 0 <= py < TILE_SIZE:
					var dist := Vector2(float(dx), float(dy)).length()
					if dist <= float(size):
						image.set_pixel(px, py, Color(0.9, 0.7, 0.2))
	
	return ImageTexture.create_from_image(image)

## Check if a point is inside a polygon.
func _point_in_polygon(point: Vector2, polygon: Array[Vector2]) -> bool:
	var inside := false
	var n := polygon.size()
	for i in range(n):
		var j := (i + 1) % n
		var yi := polygon[i].y
		var yj := polygon[j].y
		var xi := polygon[i].x
		var xj := polygon[j].x
		if ((yi > point.y) != (yj > point.y)) and \
		   (point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi):
			inside = not inside
	return inside

## Add a tile to the tile set.
func _add_tile(tile_set: TileSet, tile_id: int, texture: ImageTexture) -> void:
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	source.add_texture_rect(Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(0, 0))
	tile_set.add_texture_source(source, tile_id)
