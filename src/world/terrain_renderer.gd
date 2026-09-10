## Renders chunk terrain using TileMapLayer.
## Placeholder implementation using colored rects.
class_name TerrainRenderer
extends Node

const CHUNK_SIZE: int = 16

@onready var tile_map: TileMapLayer = $TileMapLayer

var _chunk_data: Dictionary = {}

## Set up the tile map.
func _ready() -> void:
	# Placeholder: set up a simple tile set
	# In a full implementation, this would use a proper TileSet
	pass

## Update terrain for a chunk.
func update_chunk(chunk_coords: Vector2i, data: Dictionary) -> void:
	_chunk_data[str(chunk_coords)] = data
	_render_chunk(chunk_coords, data)

## Clear all terrain.
func clear_all() -> void:
	_chunk_data.clear()
	tile_map.clear()

## Render a single chunk.
func _render_chunk(chunk_coords: Vector2i, data: Dictionary) -> void:
	if not data.has("elevation") or not data.has("biome"):
		return

	var biome_id: String = data["biome"]
	var elevation: PackedFloat32Array = data["elevation"]

	# Placeholder rendering: use colors based on biome
	# In a full implementation, this would set tile IDs
	var world_start := ChunkSystem.chunk_coords_to_world_start(chunk_coords)

	# For now, just log that rendering would happen
	pass

## Get the color for a biome.
func get_biome_color(biome_id: String) -> Color:
	match biome_id:
		"grassland":
			return Color(0.2, 0.6, 0.2)
		"desert":
			return Color(0.8, 0.7, 0.4)
		"tundra":
			return Color(0.8, 0.8, 0.9)
		"forest":
			return Color(0.15, 0.45, 0.15)
		_:
			return Color(0.5, 0.5, 0.5)
