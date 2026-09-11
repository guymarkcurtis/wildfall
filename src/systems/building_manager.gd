## Modular, story-aware building placement for Wildfall's top-down cutaway.
## Each world tile can contain one structural part on each story (ground plus
## three upper stories). The active story is the construction plane.
class_name BuildingManager
extends Node2D

const TILE_SIZE := 32
const STORY_RISE := 12.0
const MAX_STORIES := 4
const CRAFTING_STATION_IDS = ["campfire", "furnace", "workbench", "anvil"]
const CRAFTING_STATION_RANGE := 72.0
const BUILDING_DEFINITION_SCRIPT = preload("res://resources/building_definition.gd")

var buildings: Dictionary = {} # Vector3i(x, y, story) -> Building
var definitions: Dictionary = {} # item_id -> BuildingDefinition resource
var build_mode := false
var selected_item_id := ""
var selected_story := 0

var player: Player = null
var item_database: ItemDatabase = null
var technology_system: TechnologySystem = null

var _ghost: Polygon2D = null
var _owned: PackedStringArray = []
var _select_index := 0

signal building_placed(building_id: String, coords: Vector2i)
signal building_removed(building_id: String, coords: Vector2i)
signal build_mode_changed(enabled: bool, selected_item_id: String)
signal build_story_changed(story: int)
signal placement_failed(reason: String)

func _ready() -> void:
	_init_definitions()
	_ghost = Polygon2D.new()
	_ghost.polygon = PackedVector2Array([
		Vector2(2, 2), Vector2(30, 2), Vector2(30, 30), Vector2(2, 30)
	])
	_ghost.color = Color(0.4, 0.9, 0.4, 0.35)
	_ghost.visible = false
	_ghost.z_index = 40
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
	_ghost.position = Vector2(tile * TILE_SIZE) + Vector2(0.0, -selected_story * STORY_RISE)
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
	if event.is_action_pressed("build_level_up"):
		set_selected_story(selected_story + 1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("build_level_down"):
		set_selected_story(selected_story - 1)
		get_viewport().set_input_as_handled()
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

func set_selected_story(story: int) -> void:
	var next_story := clampi(story, 0, MAX_STORIES - 1)
	if selected_story == next_story:
		return
	selected_story = next_story
	_apply_cutaway()
	build_story_changed.emit(selected_story)

func cycle_selection(step: int) -> void:
	_refresh_owned()
	if _owned.is_empty():
		selected_item_id = ""
		return
	_select_index = posmod(_select_index + step, _owned.size())
	selected_item_id = _owned[_select_index]
	build_mode_changed.emit(build_mode, selected_item_id)

func select_item(item_id: String) -> bool:
	_refresh_owned()
	var index := _owned.find(item_id)
	if index < 0:
		return false
	_select_index = index
	selected_item_id = item_id
	build_mode_changed.emit(build_mode, selected_item_id)
	return true

func get_owned_building_items() -> Array[String]:
	_refresh_owned()
	var result: Array[String] = []
	for item_id in _owned:
		result.append(item_id)
	return result

func get_definition(item_id: String) -> Variant:
	return definitions.get(item_id)

func can_place(tile: Vector2i, story: int = selected_story) -> bool:
	if selected_item_id == "" or story < 0 or story >= MAX_STORIES:
		return false
	if buildings.has(_cell(tile, story)):
		return false
	if player == null or player.inventory == null or not player.inventory.has_item(selected_item_id, 1):
		return false
	var definition: Variant = get_definition(selected_item_id)
	if definition == null:
		return false
	if not _is_item_unlocked(selected_item_id):
		return false
	if story > 0 and bool(definition.get("requires_lower_support")) and not _has_lower_support(tile, story):
		return false
	return true

## Place the selected structural part on the active construction story.
func try_place_at(tile: Vector2i) -> bool:
	if not can_place(tile):
		placement_failed.emit(_placement_failure_reason(tile, selected_story))
		return false
	return place_building_item(selected_item_id, tile, null, selected_story)

## Test/API placement. A story of -1 means the active construction plane.
func place_building_item(item_id: String, tile: Vector2i, inventory: InventoryComponent = null, story: int = -1) -> bool:
	var target_story: int = selected_story if story < 0 else story
	var inv: InventoryComponent = inventory if inventory != null else (player.inventory if player != null else null)
	var definition: Variant = get_definition(item_id)
	if inv == null or item_id == "" or definition == null or target_story < 0 or target_story >= MAX_STORIES:
		return false
	if not _is_item_unlocked(item_id):
		return false
	if buildings.has(_cell(tile, target_story)) or not inv.has_item(item_id, 1):
		return false
	if target_story > 0 and bool(definition.get("requires_lower_support")) and not _has_lower_support(tile, target_story):
		return false
	inv.remove_item(item_id, 1)
	var display := str(definition.get("display_name"))
	var building := Building.new()
	building.setup(item_id, display, tile, int(definition.get("max_health")), target_story, definition)
	building.building_destroyed.connect(_on_building_destroyed.bind(building))
	add_child(building)
	buildings[_cell(tile, target_story)] = building
	_apply_cutaway()
	building_placed.emit(item_id, tile)
	return true

func demolish_at(tile: Vector2i, story: int = selected_story) -> bool:
	var cell := _cell(tile, story)
	if not buildings.has(cell):
		return false
	_remove_building(buildings[cell], true)
	return true

func get_building_at(tile: Vector2i, story: int = selected_story) -> Building:
	return buildings.get(_cell(tile, story)) as Building

func get_building_count() -> int:
	return buildings.size()

## Ground-story stations are usable within this radius. Keeping this in the
## building manager makes station craft checks follow placed/demolished/saved
## buildings automatically instead of maintaining a second station registry.
func get_nearby_station_ids(world_position: Vector2, interaction_range: float = CRAFTING_STATION_RANGE) -> PackedStringArray:
	var nearby := PackedStringArray()
	for candidate in buildings.values():
		var building := candidate as Building
		if building == null or not is_instance_valid(building) or building.story != 0 or not CRAFTING_STATION_IDS.has(building.building_id):
			continue
		var station_center: Vector2 = building.global_position + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
		if station_center.distance_to(world_position) <= interaction_range and not nearby.has(building.building_id):
			nearby.append(building.building_id)
	nearby.sort()
	return nearby

func has_station_near(station_id: String, world_position: Vector2, interaction_range: float = CRAFTING_STATION_RANGE) -> bool:
	return get_nearby_station_ids(world_position, interaction_range).has(station_id)

func refresh_texture_pack() -> void:
	for building in buildings.values():
		if is_instance_valid(building) and building.has_method("reload_visual_texture"):
			building.reload_visual_texture()

func serialize() -> Array:
	var out: Array = []
	for cell in buildings:
		var building: Building = buildings[cell]
		if not is_instance_valid(building):
			continue
		out.append({
			"item_id": building.building_id,
			"x": building.tile_coords.x,
			"y": building.tile_coords.y,
			"story": building.story,
			"health": building.health
		})
	return out

func deserialize(data: Variant) -> void:
	clear_all()
	if typeof(data) != TYPE_ARRAY:
		return
	for entry in data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var tile := Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
		restore_building(str(entry.get("item_id", "")), tile, int(entry.get("health", 50)), int(entry.get("story", 0)))

## Spawn a saved building without consuming inventory.
func restore_building(item_id: String, tile: Vector2i, health: int = 50, story: int = 0) -> bool:
	var definition: Variant = get_definition(item_id)
	if definition == null or buildings.has(_cell(tile, story)):
		return false
	var building := Building.new()
	building.setup(item_id, str(definition.get("display_name")), tile, int(definition.get("max_health")), story, definition)
	building.health = clampi(health, 0, building.max_health)
	building.building_destroyed.connect(_on_building_destroyed.bind(building))
	add_child(building)
	buildings[_cell(tile, story)] = building
	_apply_cutaway()
	building_placed.emit(item_id, tile)
	return true

func clear_all() -> void:
	for building in buildings.values():
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
		if not is_instance_valid(building) or building.story != selected_story:
			continue
		var dist: float = building.position.distance_to(player.global_position)
		if dist < best:
			best = dist
			nearest = building
	if nearest != null:
		_remove_building(nearest, true)

func _remove_building(building: Building, refund: bool) -> void:
	var cell := _cell(building.tile_coords, building.story)
	var item_id := building.building_id
	buildings.erase(cell)
	if refund and player != null and player.inventory != null and item_id != "":
		player.inventory.add_item(item_id, 1)
	building_removed.emit(item_id, building.tile_coords)
	if is_instance_valid(building):
		building.queue_free()

func _on_building_destroyed(building: Building) -> void:
	_remove_building(building, false)

func _has_lower_support(tile: Vector2i, story: int) -> bool:
	var lower := get_building_at(tile, story - 1)
	if lower == null:
		return false
	return ["foundation", "floor", "wall", "pillar", "stair", "ramp"].has(lower.part_type)

func _placement_failure_reason(tile: Vector2i, story: int) -> String:
	if selected_item_id == "":
		return "No building part selected"
	if buildings.has(_cell(tile, story)):
		return "That story tile is already occupied"
	if player == null or player.inventory == null or not player.inventory.has_item(selected_item_id, 1):
		return "You do not have that building part"
	var definition: Variant = get_definition(selected_item_id)
	if definition == null:
		return "That item is not a placeable building part"
	if not _is_item_unlocked(selected_item_id):
		var technology_id := str(definition.get("technology_id"))
		var technology_name := technology_id.replace("_", " ").capitalize()
		if technology_system != null:
			var technology := technology_system.get_definition(technology_id)
			if technology != null:
				technology_name = technology.display_name
		return "Research %s before building this" % technology_name
	if story > 0 and bool(definition.get("requires_lower_support")) and not _has_lower_support(tile, story):
		return "Upper stories need a floor, foundation, wall, pillar, stair, or ramp below"
	return "That part cannot be placed here"

func _apply_cutaway() -> void:
	for building in buildings.values():
		if is_instance_valid(building):
			building.set_cutaway_story(selected_story)

func _cell(tile: Vector2i, story: int) -> Vector3i:
	return Vector3i(tile.x, tile.y, story)

func _mouse_tile() -> Vector2i:
	var world := player.get_global_mouse_position() if player != null else Vector2.ZERO
	# Undo the visual rise of the active construction plane before snapping.
	world.y += selected_story * STORY_RISE
	return Vector2i(int(floor(world.x / float(TILE_SIZE))), int(floor(world.y / float(TILE_SIZE))))

func _refresh_owned() -> void:
	_owned = PackedStringArray()
	if player == null or player.inventory == null or item_database == null:
		return
	var items := player.inventory.get_all_items()
	for item_id in items:
		if definitions.has(str(item_id)) and int(items[item_id]) > 0 and _is_item_unlocked(str(item_id)):
			_owned.append(str(item_id))
	_owned.sort()

func _is_item_unlocked(item_id: String) -> bool:
	var definition: Variant = get_definition(item_id)
	if definition == null:
		return false
	var technology_id := str(definition.get("technology_id"))
	return technology_id.is_empty() or technology_system == null or technology_system.is_unlocked(technology_id)

func _init_definitions() -> void:
	# Wood is intentionally complete and easy to understand: every part has a
	# single-tile footprint, so players can freely compose rooms and stories.
	_define("wooden_foundation", "Wood Foundation", "foundation", "wood", "wood_building", 90, false, false, [{"item_id": "plank", "quantity": 2}])
	_define("wooden_floor", "Wood Floor", "floor", "wood", "wood_building", 70, false, true, [{"item_id": "plank", "quantity": 1}])
	_define("wooden_wall", "Wood Wall", "wall", "wood", "wood_building", 100, true, true, [{"item_id": "plank", "quantity": 3}])
	_define("wooden_window", "Wood Window", "window", "wood", "wood_building", 80, true, true, [{"item_id": "plank", "quantity": 2}, {"item_id": "glass", "quantity": 1}])
	_define("wooden_door", "Wood Door", "door", "wood", "wood_building", 90, true, true, [{"item_id": "plank", "quantity": 3}])
	_define("wooden_roof", "Wood Roof", "roof", "wood", "wood_building", 75, false, true, [{"item_id": "plank", "quantity": 2}])
	_define("wooden_stairs", "Wood Stairs", "stair", "wood", "wood_building", 80, false, true, [{"item_id": "plank", "quantity": 3}])
	_define("wooden_ramp", "Wood Ramp", "ramp", "wood", "wood_building", 80, false, true, [{"item_id": "plank", "quantity": 2}])
	_define("wooden_pillar", "Wood Pillar", "pillar", "wood", "wood_building", 120, true, true, [{"item_id": "plank", "quantity": 2}])
	_define("stone_foundation", "Stone Foundation", "foundation", "stone", "stone_building", 180, false, false, [{"item_id": "stone_brick", "quantity": 2}])
	_define("stone_floor", "Stone Floor", "floor", "stone", "stone_building", 150, false, true, [{"item_id": "stone_brick", "quantity": 1}])
	_define("stone_wall", "Stone Wall", "wall", "stone", "stone_building", 220, true, true, [{"item_id": "stone_brick", "quantity": 3}])
	_define("stone_window", "Stone Window", "window", "stone", "stone_building", 180, true, true, [{"item_id": "stone_brick", "quantity": 2}, {"item_id": "glass", "quantity": 1}])
	_define("stone_door", "Stone Door", "door", "stone", "stone_building", 190, true, true, [{"item_id": "stone_brick", "quantity": 3}])
	_define("stone_roof", "Stone Roof", "roof", "stone", "stone_building", 160, false, true, [{"item_id": "stone_brick", "quantity": 2}])
	_define("stone_stairs", "Stone Stairs", "stair", "stone", "stone_building", 180, false, true, [{"item_id": "stone_brick", "quantity": 3}])
	_define("stone_ramp", "Stone Ramp", "ramp", "stone", "stone_building", 170, false, true, [{"item_id": "stone_brick", "quantity": 2}])
	_define("stone_pillar", "Stone Pillar", "pillar", "stone", "stone_building", 260, true, true, [{"item_id": "stone_brick", "quantity": 2}])
	for item_id in ["torch", "campfire", "furnace", "workbench", "anvil", "chest", "bed", "farm_soil", "fence"]:
		_define(item_id, item_database.get_item_display_name(item_id) if item_database != null else item_id.capitalize(), "utility", "primitive", "", 50, item_id == "fence", false, [])

func _define(item_id: String, display_name: String, part_type: String, tier: String, technology_id: String, max_health: int, blocks_movement: bool, requires_lower_support: bool, cost: Array) -> void:
	var definition: Variant = BUILDING_DEFINITION_SCRIPT.new()
	definition.set("id", item_id)
	definition.set("display_name", display_name)
	definition.set("part_type", part_type)
	definition.set("tier", tier)
	definition.set("technology_id", technology_id)
	definition.set("max_health", max_health)
	definition.set("blocks_movement", blocks_movement)
	definition.set("requires_lower_support", requires_lower_support)
	definition.set("build_cost", cost)
	definitions[item_id] = definition
