## The single shared panel for interacting with placed objects: title, close
## button, backdrop, contextual help, a player-inventory view, and a content
## area the InteractionManager fills per the object's interaction profile.
## Chests (M5), stations, and fuel (M6+) all present through this panel —
## there is no per-object duplicate UI.
class_name InteractablePanel
extends Control

## Emitted for EVERY close path (Escape, button, manager reasons); the
## InteractionManager owns the actual close pipeline and stays idempotent.
signal close_requested(reason: String)
signal station_craft_requested(recipe_id: String)
signal fuel_toggle_requested

var object_grid: StorageGridView = null
var player_grid: StorageGridView = null
var output_grid: StorageGridView = null
var fuel_grid: StorageGridView = null
var is_open: bool = false

var _dim: ColorRect = null
var _window: Panel = null
var _title_label: Label = null
var _help_label: Label = null
var _content_box: HBoxContainer = null
var _object_capacity_label: Label = null
var _player_capacity_label: Label = null
var _player_storage: InventoryStorage = null
var _object_storage: InventoryStorage = null
var _output_storage: InventoryStorage = null
var _fuel_storage: InventoryStorage = null
var _station_recipe_box: VBoxContainer = null
var _selected: Dictionary = {} # {grid: String, index: int} or empty

const SLOT_COLUMNS := 9

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP # world clicks never leak through
	visible = false

	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.02, 0.015, 0.7)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_window = Panel.new()
	_window.set_anchors_preset(Control.PRESET_CENTER)
	_window.custom_minimum_size = Vector2(660, 330)
	_window.position -= Vector2(330, 165)
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.1, 0.07, 0.98)
	style.border_color = Color(0.66, 0.74, 0.44, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	_window.add_theme_stylebox_override("panel", style)
	add_child(_window)

	_title_label = Label.new()
	_title_label.position = Vector2(24, 14)
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.78))
	_window.add_child(_title_label)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.flat = true
	close_button.position = Vector2(618, 10)
	close_button.custom_minimum_size = Vector2(30, 30)
	close_button.pressed.connect(func(): close_requested.emit("button"))
	_window.add_child(close_button)

	_help_label = Label.new()
	_help_label.position = Vector2(24, 44)
	_help_label.add_theme_font_size_override("font_size", 12)
	_help_label.add_theme_color_override("font_color", Color(0.62, 0.68, 0.55))
	_window.add_child(_help_label)

	_content_box = HBoxContainer.new()
	_content_box.position = Vector2(24, 72)
	_content_box.custom_minimum_size = Vector2(612, 240)
	_content_box.add_theme_constant_override("separation", 24)
	_window.add_child(_content_box)

	_object_capacity_label = Label.new()
	_object_capacity_label.position = Vector2(24, 306)
	_object_capacity_label.size = Vector2(280, 20)
	_object_capacity_label.add_theme_font_size_override("font_size", 11)
	_object_capacity_label.add_theme_color_override("font_color", Color(0.66, 0.72, 0.54))
	_window.add_child(_object_capacity_label)

	_player_capacity_label = Label.new()
	_player_capacity_label.position = Vector2(338, 306)
	_player_capacity_label.size = Vector2(280, 20)
	_player_capacity_label.add_theme_font_size_override("font_size", 11)
	_player_capacity_label.add_theme_color_override("font_color", Color(0.66, 0.72, 0.54))
	_window.add_child(_player_capacity_label)

func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		close_requested.emit("escape")
		get_viewport().set_input_as_handled()

## Open the panel chrome over one placed object. The object grid (left) shows
## the record's container storage; the player grid (right) is the player's
## own inventory storage — one shared grid implementation each.
func open_for(title: String, help: String, object_storage: InventoryStorage,
		player_storage: InventoryStorage) -> void:
	_object_storage = object_storage
	_player_storage = player_storage
	_title_label.text = title
	_help_label.text = help
	_selected.clear()

	if object_grid != null:
		object_grid.queue_free()
	if player_grid != null:
		player_grid.queue_free()

	object_grid = StorageGridView.new()
	_content_box.add_child(object_grid)
	object_grid.setup(object_storage, "object", SLOT_COLUMNS)
	object_grid.slot_pressed.connect(_on_grid_slot_pressed)
	object_grid.quick_transfer_requested.connect(_on_quick_transfer)
	object_grid.drag_transfer_requested.connect(_on_drag_transfer)

	player_grid = StorageGridView.new()
	_content_box.add_child(player_grid)
	player_grid.setup(player_storage, "player", SLOT_COLUMNS)
	player_grid.slot_pressed.connect(_on_grid_slot_pressed)
	player_grid.quick_transfer_requested.connect(_on_quick_transfer)
	player_grid.drag_transfer_requested.connect(_on_drag_transfer)

	is_open = true
	visible = true
	_refresh()

## M6's station form deliberately reuses the same chrome, player inventory,
## and input-grid transfer implementation as containers. Output is read-only;
## recipes are supplied by the station profile group, never an object id.
func open_station(title: String, help: String, input_storage: InventoryStorage,
		output_storage: InventoryStorage, player_storage: InventoryStorage,
		recipes: Array[RecipeDefinition]) -> void:
	open_for(title, help, input_storage, player_storage)
	_output_storage = output_storage
	if output_grid != null:
		output_grid.queue_free()
	output_grid = StorageGridView.new()
	_content_box.add_child(output_grid)
	output_grid.setup(output_storage, "output", 1, true)
	if _station_recipe_box != null:
		_station_recipe_box.queue_free()
	_station_recipe_box = VBoxContainer.new()
	_station_recipe_box.position = Vector2(24, 250)
	_station_recipe_box.size = Vector2(612, 54)
	_station_recipe_box.add_theme_constant_override("separation", 4)
	_window.add_child(_station_recipe_box)
	var recipes_label := Label.new()
	recipes_label.text = "Station recipes"
	recipes_label.add_theme_font_size_override("font_size", 12)
	_station_recipe_box.add_child(recipes_label)
	for recipe in recipes:
		var button := Button.new()
		button.text = "Craft %dx %s" % [recipe.result_quantity, recipe.result_item_id.replace("_", " ").capitalize()]
		button.tooltip_text = recipe.get_cost_string()
		button.pressed.connect(func(): station_craft_requested.emit(recipe.recipe_id))
		_station_recipe_box.add_child(button)
	_refresh()

func configure_fuel(storage: InventoryStorage, enabled: bool, seconds_remaining: float,
		accepted_fuel_hint: String = "") -> void:
	_fuel_storage = storage
	if fuel_grid != null:
		fuel_grid.queue_free()
	fuel_grid = StorageGridView.new()
	_content_box.add_child(fuel_grid)
	fuel_grid.setup(storage, "fuel", 1)
	fuel_grid.slot_pressed.connect(_on_grid_slot_pressed)
	fuel_grid.quick_transfer_requested.connect(_on_quick_transfer)
	fuel_grid.drag_transfer_requested.connect(_on_drag_transfer)
	var status := "Disabled"
	if enabled:
		status = "Lit" if seconds_remaining > 0.0 else "Out of fuel"
	var status_label := Label.new()
	status_label.text = "Status: %s  •  %.0fs remaining" % [status, seconds_remaining]
	_window.add_child(status_label)
	status_label.position = Vector2(24, 218)
	if not accepted_fuel_hint.is_empty():
		var hint_label := Label.new()
		hint_label.text = "Accepts: %s" % accepted_fuel_hint
		_window.add_child(hint_label)
		hint_label.position = Vector2(24, 238)
	var toggle := Button.new()
	toggle.text = "Turn off" if enabled else "Turn on"
	toggle.pressed.connect(func(): fuel_toggle_requested.emit())
	_window.add_child(toggle)
	toggle.position = Vector2(24, 258)
	_refresh()

func close_panel() -> void:
	is_open = false
	visible = false
	_selected.clear()

## Public refresh for the InteractionManager (storage changed underneath).
func refresh_grids() -> void:
	_refresh()

## Escape closes the topmost panel and consumes the key so no other UI or
## world action sees it.
func blocks_world_input() -> bool:
	return is_open

# --- Transfer semantics (all through the transactional InventoryTransfer) ---

func _on_grid_slot_pressed(grid_id: String, index: int, mouse_button: int) -> void:
	if mouse_button == MOUSE_BUTTON_RIGHT:
		# Deterministic split: right-click moves half the stack to the other
		# grid (the ceil half stays, so a stack can be divided repeatedly).
		var from_storage := _storage_for(grid_id)
		var to_storage := _other_storage(grid_id)
		if from_storage == null or to_storage == null:
			return
		var quantity := from_storage.quantity_at(index)
		if quantity <= 0:
			return
		var item_id := from_storage.item_id_at(index)
		var half := maxi(1, quantity / 2)
		var target_slot := to_storage.find_receiving_slot_for(item_id, half)
		if target_slot >= 0:
			InventoryTransfer.transfer(from_storage, index, to_storage, target_slot, half)
		_selected.clear()
		_refresh()
		return
	# Left click: select, or move the selection into the clicked slot.
	if _selected.is_empty():
		var storage := _storage_for(grid_id)
		if storage.quantity_at(index) > 0:
			_selected = {"grid": grid_id, "index": index}
		_refresh()
		return
	if str(_selected["grid"]) == grid_id and int(_selected["index"]) == index:
		_selected.clear()
		_refresh()
		return
	var from_storage := _storage_for(str(_selected["grid"]))
	var to_storage := _storage_for(grid_id)
	var outcome := InventoryTransfer.transfer(from_storage, int(_selected["index"]),
			to_storage, index, from_storage.quantity_at(int(_selected["index"])))
	if int(outcome[InventoryTransfer.RESULT_MOVED]) > 0 or bool(outcome[InventoryTransfer.RESULT_SWAPPED]):
		_selected.clear()
	_refresh()

## Shift-click: move the whole stack to the other grid (first slots that
## accept it), via the transactional transfer routine.
func _on_quick_transfer(grid_id: String, index: int) -> void:
	var from_storage := _storage_for(grid_id)
	var to_storage := _other_storage(grid_id)
	if from_storage == null or to_storage == null:
		return
	var item_id := from_storage.item_id_at(index)
	if item_id == "":
		return
	InventoryTransfer.transfer_between(from_storage, to_storage, item_id,
			from_storage.quantity_at(index))
	_selected.clear()
	_refresh()

func _on_drag_transfer(from_grid: String, from_index: int, to_grid: String, to_index: int) -> void:
	var from_storage := _storage_for(from_grid)
	var to_storage := _storage_for(to_grid)
	if from_storage == null or to_storage == null:
		return
	InventoryTransfer.transfer(from_storage, from_index, to_storage, to_index,
			from_storage.quantity_at(from_index))
	_selected.clear()
	_refresh()

func _storage_for(grid_id: String) -> InventoryStorage:
	if grid_id == "object":
		return _object_storage
	if grid_id == "player":
		return _player_storage
	if grid_id == "output":
		return _output_storage
	if grid_id == "fuel":
		return _fuel_storage
	return null

func _other_storage(grid_id: String) -> InventoryStorage:
	if grid_id == "object" or grid_id == "fuel":
		return _player_storage
	return _object_storage

func _refresh() -> void:
	if object_grid != null:
		object_grid.refresh()
		object_grid.highlight_selected(int(_selected.get("index", -1)) if str(_selected.get("grid", "")) == "object" else -1)
	if player_grid != null:
		player_grid.refresh()
		player_grid.highlight_selected(int(_selected.get("index", -1)) if str(_selected.get("grid", "")) == "player" else -1)
	if output_grid != null:
		output_grid.refresh()
	if fuel_grid != null:
		fuel_grid.refresh()
	if _object_capacity_label != null:
		_object_capacity_label.text = _storage_summary("Container", _object_storage)
	if _player_capacity_label != null:
		_player_capacity_label.text = _storage_summary("Inventory", _player_storage)

func _storage_summary(label: String, storage: InventoryStorage) -> String:
	if storage == null:
		return "%s unavailable" % label
	var contents := "Empty" if storage.occupied_count() == 0 else "%d/%d slots" % [storage.occupied_count(), storage.slot_count()]
	return "%s: %s  %.0f / %.0f weight" % [label, contents, storage.total_weight(), storage.max_weight]
