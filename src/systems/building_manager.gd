## Player-driven building placement and demolition on the 32px grid.
class_name BuildingManager
extends Node2D

const TILE_SIZE: int = 32

var buildings: Dictionary = {}  # Vector2i -> Building
var build_mode: bool = false
var selected_item_id: String = ""

var player: Player = null
var item_database: ItemDatabase = null

var _ghost: Polygon2D = null
var _owned: PackedStringArray = []
var _select_index: int = 0

signal building_placed(building_id: String, coords: Vector2i)
signal building_removed(building_id: String, coords: Vector2i)
signal build_mode_changed(enabled: bool, selected_item_id: String)

func _ready() -> void:
	_ghost = Polygon2D.new()
	_ghost.polygon = PackedVector2Array([
		Vector2(2, 2), Vector2(30, 2), Vector2(30, 30), Vector2(2, 30)
	])
	_ghost.color = Color(0.4, 0.9, 0.4, 0.35)
	_ghost.visible = false
	_ghost.z_index = 20
	add_child(_ghost)

func _process(_delta: float) -> void:
	if not build_mode:
		_ghost.visible = false
		return
	_refresh_owned()
	if _owned.is_empty():
		selected_item_id = ""
		_ghost.visible = false
		return
	if selected_item_id == "" or not _owned.has(selected_item_id):
		_select_index = 0
		selected_item_id = _owned[0]
		build_mode_changed.emit(true, selected_item_id)
	var tile := _mouse_tile()
	_ghost.position = Vector2(tile * TILE_SIZE)
	_ghost.visible = true
	_ghost.color = Color(0.3, 0.85, 0.35, 0.4) if can_place(tile) else Color(0.85, 0.25, 0.2, 0.4)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_build"):
		set_build_mode(not build_mode)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("demolish"):
		_demolish_near_player()
		get_viewport().set_input_as_handled()
		return
	if not build_mode:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if not mouse.pressed:
			return
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			try_place_at(_mouse_tile())
			get_viewport().set_input_as_handled()
		elif mouse.button_index == MOUSE_BUTTON_RIGHT:
			set_build_mode(false)
			get_viewport().set_input_as_handled()
		elif mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			cycle_selection(-1)
			get_viewport().set_input_as_handled()
		elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cycle_selection(1)
			get_viewport().set_input_as_handled()

func set_build_mode(enabled: bool) -> void:
	build_mode = enabled
	if build_mode:
		_refresh_owned()
		if not _owned.is_empty():
			_select_index = clampi(_select_index, 0, _owned.size() - 1)
			selected_item_id = _owned[_select_index]
		else:
			selected_item_id = ""
	else:
		selected_item_id = ""
		if _ghost:
			_ghost.visible = false
	build_mode_changed.emit(build_mode, selected_item_id)

func cycle_selection(step: int) -> void:
	_refresh_owned()
	if _owned.is_empty():
		selected_item_id = ""
		return
	_select_index = posmod(_select_index + step, _owned.size())
	selected_item_id = _owned[_select_index]
	build_mode_changed.emit(build_mode, selected_item_id)

func can_place(tile: Vector2i) -> bool:
	if selected_item_id == "":
		return false
	if buildings.has(tile):
		return false
	if player == null or player.inventory == null:
		return false
	if not player.inventory.has_item(selected_item_id, 1):
		return false
	return true

## Place the currently selected building, consuming one inventory item.
func try_place_at(tile: Vector2i) -> bool:
	if not can_place(tile):
		return false
	return place_building_item(selected_item_id, tile)

## Test/API placement: consume `item_id` from the given inventory and spawn.
func place_building_item(item_id: String, tile: Vector2i, inventory: InventoryComponent = null) -> bool:
	var inv: InventoryComponent = inventory
	if inv == null and player != null:
		inv = player.inventory
	if inv == null or item_id == "" or buildings.has(tile):
		return false
	if not inv.has_item(item_id, 1):
		return false
	inv.remove_item(item_id, 1)
	var display: String = item_id
	if item_database != null and item_database.has_item(item_id):
		display = item_database.get_item_display_name(item_id)
	var building := Building.new()
	building.setup(item_id, display, tile, 50)
	building.building_destroyed.connect(_on_building_destroyed.bind(building))
	add_child(building)
	buildings[tile] = building
	building_placed.emit(item_id, tile)
	return true

func demolish_at(tile: Vector2i) -> bool:
	if not buildings.has(tile):
		return false
	var building: Building = buildings[tile]
	_remove_building(building, true)
	return true

func get_building_count() -> int:
	return buildings.size()

func clear_all() -> void:
	for tile in buildings.keys():
		var building: Building = buildings[tile]
		if is_instance_valid(building):
			building.queue_free()
	buildings.clear()
	set_build_mode(false)

func _demolish_near_player() -> void:
	if player == null:
		return
	var nearest: Building = null
	var best: float = 56.0
	for building in buildings.values():
		if not is_instance_valid(building):
			continue
		var dist: float = building.position.distance_to(player.global_position)
		if dist < best:
			best = dist
			nearest = building
	if nearest != null:
		_remove_building(nearest, true)

func _remove_building(building: Building, refund: bool) -> void:
	var tile: Vector2i = building.tile_coords
	var item_id: String = building.building_id
	buildings.erase(tile)
	if refund and player != null and player.inventory != null and item_id != "":
		player.inventory.add_item(item_id, 1)
	building_removed.emit(item_id, tile)
	if is_instance_valid(building):
		building.queue_free()

func _on_building_destroyed(building: Building) -> void:
	_remove_building(building, false)

func _mouse_tile() -> Vector2i:
	var world: Vector2 = player.get_global_mouse_position() if player != null else Vector2.ZERO
	return Vector2i(int(floor(world.x / float(TILE_SIZE))), int(floor(world.y / float(TILE_SIZE))))

func _refresh_owned() -> void:
	_owned = PackedStringArray()
	if player == null or player.inventory == null or item_database == null:
		return
	var items: Dictionary = player.inventory.get_all_items()
	for item_id in items:
		var def: ItemDefinition = item_database.get_item(str(item_id))
		if def != null and def.category == "building" and int(items[item_id]) > 0:
			_owned.append(str(item_id))
