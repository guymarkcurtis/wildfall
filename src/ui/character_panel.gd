## The character screen (K): manage equipped armour, clothing, and the light
## source beside the player's inventory, in the same visual language as the
## inventory and device panels — icon slots, drag & drop, shift-click,
## tooltips. Equipment slots are the generic single-slot InventoryStorages
## owned by the player's EquipmentComponent (acceptance is a tag query in
## data); the light slot carries the L-toggle for the held light.
class_name CharacterPanel
extends Control

signal close_requested(reason: String)
signal toast_requested(text: String)
signal light_toggle_requested

const SLOT_COLUMNS := 9
const EQUIP_SLOT_SIZE := 64.0

# Palette shared with the inventory and interactable panels.
const COL_TITLE := Color(0.90, 0.92, 0.72)
const COL_TEXT := Color(0.91, 0.92, 0.84)
const COL_MUTED := Color(0.64, 0.69, 0.57)
const COL_ACCENT := Color(0.85, 0.92, 0.55)
const COL_GOOD := Color(0.65, 0.88, 0.58)

var is_open: bool = false

var _player: Player = null
var _item_database: ItemDatabase = null
var _equipment: EquipmentComponent = null

var _window: PanelContainer = null
var _player_grid: StorageGridView = null
var _player_capacity_label: Label = null
var _equip_grids: Dictionary = {} # slot name -> StorageGridView
var _light_status_label: Label = null
var _light_toggle_button: Button = null
var _selected: Dictionary = {} # {grid: String, index: int} or empty

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.015, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_window = PanelContainer.new()
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.add_theme_stylebox_override("panel", _make_window_style())
	center.add_child(_window)

func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()

## Bind the panel to a player. Safe before the panel is opened; the layout
## is (re)built on every open so it always mirrors live state.
func configure(player: Player, item_database: ItemDatabase) -> void:
	_player = player
	_item_database = item_database
	_equipment = player.equipment if player != null else null
	if _equipment != null:
		if not _equipment.changed.is_connected(_refresh):
			_equipment.changed.connect(_refresh)
		if not _equipment.light_changed.is_connected(_update_light_widgets):
			_equipment.light_changed.connect(_update_light_widgets)

func toggle() -> void:
	if is_open:
		close_panel()
	else:
		open_panel()

func open_panel() -> void:
	if _player == null:
		return
	_selected.clear()
	_build_layout()
	is_open = true
	visible = true
	_refresh()

func close_panel() -> void:
	is_open = false
	visible = false
	_selected.clear()
	for child in _window.get_children():
		_window.remove_child(child)
		child.queue_free()
	_player_grid = null
	_player_capacity_label = null
	_equip_grids.clear()
	_light_status_label = null
	_light_toggle_button = null

## Escape closes the topmost panel and consumes the key so no other UI or
## world action sees it.
func blocks_world_input() -> bool:
	return is_open

# --- Layout --------------------------------------------------------------

func _build_layout() -> void:
	for child in _window.get_children():
		_window.remove_child(child)
		child.queue_free()
	_equip_grids.clear()

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 16)
	_window.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 2)
	header.add_child(titles)
	var title := Label.new()
	title.text = "CHARACTER"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COL_TITLE)
	titles.add_child(title)
	var help := Label.new()
	help.text = "Drag or click to equip; shift-click moves a stack. L lights the equipped torch. Esc closes."
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", COL_MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(help)
	var close_button := Button.new()
	close_button.text = "✕"
	close_button.tooltip_text = "Close (Esc / K)"
	close_button.custom_minimum_size = Vector2(34, 34)
	_style_button(close_button, false)
	close_button.pressed.connect(func(): close_panel())
	header.add_child(close_button)
	root.add_child(header)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	root.add_child(body)

	# Equipment column: one labelled row per slot.
	var equip_column := VBoxContainer.new()
	equip_column.custom_minimum_size = Vector2(300.0, 0)
	equip_column.add_theme_constant_override("separation", 8)
	body.add_child(equip_column)
	equip_column.add_child(_make_heading("EQUIPPED"))
	for slot_name in EquipmentComponent.SLOT_ORDER:
		equip_column.add_child(_build_equip_row(slot_name))

	var separator := VSeparator.new()
	body.add_child(separator)

	# Inventory column: the same grid used by the inventory and device panels.
	var inventory_column := VBoxContainer.new()
	inventory_column.add_theme_constant_override("separation", 8)
	body.add_child(inventory_column)
	inventory_column.add_child(_make_heading("INVENTORY"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 6.0 * StorageGridView.SLOT_SIZE + 5.0 * StorageGridView.SLOT_GAP)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inventory_column.add_child(scroll)
	_player_grid = StorageGridView.new()
	_player_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_player_grid)
	_player_grid.setup(_player.inventory.get_storage(), "player", SLOT_COLUMNS)
	_wire_grid(_player_grid)
	_player_capacity_label = _make_muted_label("")
	inventory_column.add_child(_player_capacity_label)

func _build_equip_row(slot_name: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var slot_storage := _equipment.get_slot_storage(slot_name)

	var grid := StorageGridView.new()
	grid.custom_minimum_size = Vector2(EQUIP_SLOT_SIZE + 16.0, EQUIP_SLOT_SIZE + 8.0)
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	row.add_child(grid)
	grid.setup(slot_storage, slot_name, 1)
	_wire_grid(grid)
	_equip_grids[slot_name] = grid

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var label := Label.new()
	label.text = _slot_label(slot_name)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", COL_TEXT)
	info.add_child(label)
	var hint := _make_muted_label(_slot_hint(slot_name))
	info.add_child(hint)
	if slot_name == "light":
		var light_row := HBoxContainer.new()
		light_row.add_theme_constant_override("separation", 8)
		info.add_child(light_row)
		_light_status_label = _make_muted_label("")
		_light_status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		light_row.add_child(_light_status_label)
		_light_toggle_button = Button.new()
		_light_toggle_button.text = "Turn on"
		_light_toggle_button.custom_minimum_size = Vector2(96, 28)
		_light_toggle_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_style_button(_light_toggle_button, true)
		_light_toggle_button.pressed.connect(func(): light_toggle_requested.emit())
		light_row.add_child(_light_toggle_button)
	return row

func _slot_label(slot_name: String) -> String:
	match slot_name:
		"armor": return "Armour"
		"clothing": return "Clothing"
		"light": return "Light source"
	return slot_name.capitalize()

func _slot_hint(slot_name: String) -> String:
	match slot_name:
		"armor": return "Accepts armour items"
		"clothing": return "Accepts clothing items"
		"light": return "Accepts light sources — press L to light"
	return ""

## The tag phrase used in rejection toasts ("That slot only accepts …").
func _slot_tag_phrase(slot_name: String) -> String:
	match slot_name:
		"armor": return "armour"
		"clothing": return "clothing"
		"light": return "light sources"
	return "specific items"

func _make_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", COL_MUTED)
	return label

func _make_muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COL_MUTED)
	return label

func _make_window_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.075, 0.055, 0.98)
	style.border_color = Color(0.41, 0.50, 0.28, 0.96)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0.0, 3.0)
	return style

func _style_button(button: Button, accent: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.30, 0.40, 0.19) if accent else Color(0.16, 0.22, 0.14)
	normal.border_color = COL_ACCENT if accent else Color(0.45, 0.55, 0.35, 0.9)
	normal.set_border_width_all(1 if not accent else 2)
	normal.set_corner_radius_all(5)
	normal.content_margin_left = 12.0
	normal.content_margin_right = 12.0
	normal.content_margin_top = 5.0
	normal.content_margin_bottom = 5.0
	var hover := normal.duplicate()
	hover.bg_color = Color(0.38, 0.50, 0.23) if accent else Color(0.22, 0.30, 0.18)
	var pressed_style := normal.duplicate()
	pressed_style.bg_color = Color(0.24, 0.32, 0.15) if accent else Color(0.12, 0.17, 0.10)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.12, 0.15, 0.11)
	disabled.border_color = Color(0.35, 0.42, 0.30, 0.6)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color(0.94, 0.95, 0.84) if accent else COL_TEXT)
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.60, 0.50))

func _wire_grid(grid: StorageGridView) -> void:
	grid.slot_pressed.connect(_on_grid_slot_pressed)
	grid.quick_transfer_requested.connect(_on_quick_transfer)
	grid.drag_transfer_requested.connect(_on_drag_transfer)

# --- Transfer semantics (all through the transactional InventoryTransfer) --

func _storage_for(grid_id: String) -> InventoryStorage:
	if grid_id == "player":
		return _player.inventory.get_storage() if _player != null else null
	if EquipmentComponent.SLOT_TAGS.has(grid_id):
		return _equipment.get_slot_storage(grid_id)
	return null

## Equipping and unequipping both cross to the other side.
func _other_storage(grid_id: String) -> InventoryStorage:
	if grid_id == "player":
		return null # nothing automatic: equip goes to a specific slot
	return _player.inventory.get_storage() if _player != null else null

func _on_grid_slot_pressed(grid_id: String, index: int, mouse_button: int) -> void:
	if mouse_button == MOUSE_BUTTON_RIGHT:
		return # no split: equipment is whole-item
	if _selected.is_empty():
		var storage := _storage_for(grid_id)
		if storage != null and storage.quantity_at(index) > 0:
			_selected = {"grid": grid_id, "index": index}
		_refresh()
		return
	if str(_selected["grid"]) == grid_id and int(_selected["index"]) == index:
		_selected.clear()
		_refresh()
		return
	var from_storage := _storage_for(str(_selected["grid"]))
	var to_storage := _storage_for(grid_id)
	if from_storage == null or to_storage == null:
		_selected.clear()
		_refresh()
		return
	var outcome := InventoryTransfer.transfer(from_storage, int(_selected["index"]),
			to_storage, index, from_storage.quantity_at(int(_selected["index"])))
	if int(outcome[InventoryTransfer.RESULT_MOVED]) > 0 or bool(outcome[InventoryTransfer.RESULT_SWAPPED]):
		_selected.clear()
	else:
		_toast_for_rejection(grid_id, str(outcome[InventoryTransfer.RESULT_REJECTED]))
	_refresh()

## Shift-click: whole stack between the equipment side and the inventory.
func _on_quick_transfer(grid_id: String, index: int) -> void:
	var from_storage := _storage_for(grid_id)
	if from_storage == null:
		return
	var item_id := from_storage.item_id_at(index)
	if item_id == "":
		return
	var target := _quick_transfer_target(grid_id, item_id)
	if target == null:
		_toast_for_rejection(grid_id, "no_fit")
		return
	var outcome := InventoryTransfer.transfer_between(from_storage, target, item_id,
			from_storage.quantity_at(index))
	if int(outcome[InventoryTransfer.RESULT_MOVED]) <= 0:
		_toast_for_rejection(grid_id, str(outcome[InventoryTransfer.RESULT_REJECTED]))
	_selected.clear()
	_refresh()

## Shift-clicking an inventory stack equips it into the first slot whose tag
## accepts it; shift-clicking an equipped stack unequips it.
func _quick_transfer_target(grid_id: String, item_id: String) -> InventoryStorage:
	if grid_id != "player":
		return _player.inventory.get_storage() if _player != null else null
	for slot_name in EquipmentComponent.SLOT_ORDER:
		var slot_storage := _equipment.get_slot_storage(slot_name)
		if slot_storage != null and slot_storage.find_receiving_slot_for(item_id, 1) >= 0:
			return slot_storage
	return null

func _on_drag_transfer(from_grid: String, from_index: int, to_grid: String, to_index: int) -> void:
	var from_storage := _storage_for(from_grid)
	var to_storage := _storage_for(to_grid)
	if from_storage == null or to_storage == null:
		return
	var outcome := InventoryTransfer.transfer(from_storage, from_index, to_storage, to_index,
			from_storage.quantity_at(from_index))
	if int(outcome[InventoryTransfer.RESULT_MOVED]) <= 0 \
			and not bool(outcome[InventoryTransfer.RESULT_SWAPPED]):
		_toast_for_rejection(to_grid, str(outcome[InventoryTransfer.RESULT_REJECTED]))
	_selected.clear()
	_refresh()

## Translate the transfer layer's rejection codes into the words a player
## hears; equipment context names the slot's tag.
func _toast_for_rejection(grid_id: String, reason: String) -> void:
	var text := ""
	match reason:
		"full", "occupied":
			text = "No room in that slot"
		"filtered":
			if EquipmentComponent.SLOT_TAGS.has(grid_id):
				text = "That slot only accepts %s" % _slot_tag_phrase(grid_id)
			else:
				text = "That slot only accepts specific items"
		"cannot_swap":
			text = "Those two stacks can't swap"
		"no_target":
			text = "Nothing is equipped to move"
		"no_fit":
			text = "No equipment slot accepts that item"
		"no_space":
			text = "No room on the other side"
		_:
			if reason != "":
				text = "Can't move that"
	if text != "":
		toast_requested.emit(text)

# --- Refresh -------------------------------------------------------------

func _refresh() -> void:
	if _player_grid != null:
		_player_grid.refresh()
		_player_grid.highlight_selected(int(_selected.get("index", -1)) if str(_selected.get("grid", "")) == "player" else -1)
	for slot_name in _equip_grids:
		var grid := _equip_grids[slot_name] as StorageGridView
		grid.refresh()
		grid.highlight_selected(int(_selected.get("index", -1)) if str(_selected.get("grid", "")) == slot_name else -1)
	if _player_capacity_label != null and _player != null:
		var storage := _player.inventory.get_storage()
		var contents := "Empty" if storage.occupied_count() == 0 else "%d/%d slots" % [storage.occupied_count(), storage.slot_count()]
		_player_capacity_label.text = "Inventory: %s  ·  %.0f / %.0f weight" % [contents, storage.total_weight(), storage.max_weight]
	_update_light_widgets()

func _update_light_widgets() -> void:
	if _light_status_label == null or _equipment == null:
		return
	var item_id := _equipment.light_item_id()
	if item_id == "":
		_light_status_label.text = "No light equipped"
		_light_status_label.add_theme_color_override("font_color", COL_MUTED)
		_light_toggle_button.disabled = true
		_light_toggle_button.text = "Turn on"
		return
	var light_name := ""
	if _item_database != null:
		light_name = _item_database.get_item_display_name(item_id)
	else:
		light_name = item_id.capitalize()
	if _equipment.light_enabled:
		_light_status_label.text = "Lit — %s" % light_name
		_light_status_label.add_theme_color_override("font_color", COL_GOOD)
		_light_toggle_button.text = "Turn off"
	else:
		_light_status_label.text = "Unlit — %s" % light_name
		_light_status_label.add_theme_color_override("font_color", COL_MUTED)
		_light_toggle_button.text = "Turn on"
	_light_toggle_button.disabled = false
