## Persistent quick bar and expandable inventory window.
## The quick bar is always visible; opening the inventory grows the same
## window upward so its bottom row remains the player's quick bar.
class_name InventoryPanel
extends Control

const HOTBAR_SLOTS := 9
const BACKPACK_SLOTS := 27
const SLOT_SIZE := 68.0
const PANEL_WIDTH := 730.0
const CLOSED_HEIGHT := 78.0
const OPEN_HEIGHT := 404.0
const GRID_GAP := 6.0
const BACKPACK_GRID_TOP := 100.0
const HOTBAR_GRID_OPEN_TOP := BACKPACK_GRID_TOP + (SLOT_SIZE + GRID_GAP) * 3.0
const INVENTORY_SLOT_SCRIPT = preload("res://src/ui/inventory_slot.gd")

signal hotbar_assignment_changed(assignments: Array[String])
signal hotbar_slot_requested(slot_index: int)

var _items: Dictionary = {}
var _hotbar_items: Array[String] = ["", "", "", "", "", "", "", "", ""]
var _active_hotbar_slot := -1
var _move_source: Dictionary = {}
var _is_open := false

var _dim: ColorRect
var _window: Panel
var _header: Control
var _backpack_grid: GridContainer
var _hotbar_grid: GridContainer
var _hint_label: Label
var _backpack_slot_nodes: Array[Dictionary] = []
var _hotbar_slot_nodes: Array[Dictionary] = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_set_open(false)

## Update the inventory view. Hotbar assignments are owned by Player so they
## survive saves and are available to input handling even when this UI is shut.
func refresh(items: Dictionary, hotbar_items: Array[String]) -> void:
	_items = items.duplicate()
	_hotbar_items = _normalise_hotbar(hotbar_items)
	_refresh_slots()

func is_open() -> bool:
	return _is_open

func toggle() -> void:
	_set_open(not _is_open)

func open() -> void:
	_set_open(true)

func close() -> void:
	_set_open(false)

func set_active_hotbar_slot(slot_index: int) -> void:
	_active_hotbar_slot = slot_index if slot_index >= 0 and slot_index < HOTBAR_SLOTS else -1
	_refresh_slots()

func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.015, 0.025, 0.018, 0.70)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_window = Panel.new()
	_window.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_window.add_theme_stylebox_override("panel", _make_window_style())
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_window)

	_header = Control.new()
	_header.position = Vector2(32.0, 16.0)
	_header.size = Vector2(PANEL_WIDTH - 64.0, 42.0)
	_window.add_child(_header)

	var title := Label.new()
	title.text = "INVENTORY"
	title.position = Vector2.ZERO
	title.size = Vector2(300.0, 30.0)
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color(0.90, 0.92, 0.72))
	_header.add_child(title)

	_hint_label = Label.new()
	_hint_label.text = "Click an item, then a quick-bar slot to assign it  •  Esc / I to close"
	_hint_label.position = Vector2(0.0, 28.0)
	_hint_label.size = Vector2(PANEL_WIDTH - 64.0, 20.0)
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Color(0.64, 0.69, 0.57))
	_header.add_child(_hint_label)

	var backpack_label := Label.new()
	backpack_label.text = "BACKPACK"
	backpack_label.position = Vector2(42.0, 75.0)
	backpack_label.size = Vector2(240.0, 22.0)
	backpack_label.add_theme_font_size_override("font_size", 14)
	backpack_label.add_theme_color_override("font_color", Color(0.72, 0.77, 0.62))
	_window.add_child(backpack_label)

	_backpack_grid = _make_grid(9)
	_backpack_grid.position = Vector2(43.0, BACKPACK_GRID_TOP)
	_window.add_child(_backpack_grid)
	_backpack_slot_nodes = _create_slots(_backpack_grid, BACKPACK_SLOTS, false)

	var hotbar_label := Label.new()
	hotbar_label.text = "QUICK BAR  •  1–9 to select"
	# The label shares the backpack heading line so the quick bar can be the
	# fourth slot row, with exactly the same gap as every backpack row.
	hotbar_label.position = Vector2(420.0, 75.0)
	hotbar_label.size = Vector2(270.0, 20.0)
	hotbar_label.add_theme_font_size_override("font_size", 12)
	hotbar_label.add_theme_color_override("font_color", Color(0.64, 0.69, 0.57))
	hotbar_label.name = "HotbarLabel"
	_window.add_child(hotbar_label)

	_hotbar_grid = _make_grid(HOTBAR_SLOTS)
	_window.add_child(_hotbar_grid)
	_hotbar_slot_nodes = _create_slots(_hotbar_grid, HOTBAR_SLOTS, true)

func _make_grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", GRID_GAP)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	return grid

func _create_slots(grid: GridContainer, count: int, is_hotbar: bool) -> Array[Dictionary]:
	var nodes: Array[Dictionary] = []
	for index in range(count):
		var slot: Variant = INVENTORY_SLOT_SCRIPT.new()
		slot.set("is_hotbar", is_hotbar)
		slot.set("slot_index", index)
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(slot)
		slot.pressed.connect(_on_slot_pressed.bind(is_hotbar, index))
		slot.drag_received.connect(_on_slot_dropped)

		var background := ColorRect.new()
		background.color = Color(0.12, 0.16, 0.12, 0.96)
		background.set_anchors_preset(Control.PRESET_FULL_RECT)
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(background)

		var selected := ColorRect.new()
		selected.color = Color(0.78, 0.86, 0.38, 0.30)
		selected.set_anchors_preset(Control.PRESET_FULL_RECT)
		selected.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(selected)

		var number := Label.new()
		number.text = str(index + 1) if is_hotbar else ""
		number.position = Vector2(6.0, 3.0)
		number.size = Vector2(20.0, 18.0)
		number.add_theme_font_size_override("font_size", 11)
		number.add_theme_color_override("font_color", Color(0.70, 0.75, 0.58))
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(number)

		var item_label := Label.new()
		item_label.position = Vector2(5.0, 17.0)
		item_label.size = Vector2(SLOT_SIZE - 10.0, 37.0)
		item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		item_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item_label.add_theme_font_size_override("font_size", 11)
		item_label.add_theme_color_override("font_color", Color(0.91, 0.92, 0.84))
		item_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(item_label)

		var quantity := Label.new()
		quantity.position = Vector2(38.0, 49.0)
		quantity.size = Vector2(24.0, 15.0)
		quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		quantity.add_theme_font_size_override("font_size", 12)
		quantity.add_theme_color_override("font_color", Color(0.94, 0.94, 0.78))
		quantity.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(quantity)

		nodes.append({
			"slot": slot,
			"background": background,
			"selected": selected,
			"item_label": item_label,
			"quantity": quantity
		})
	return nodes

func _set_open(value: bool) -> void:
	_is_open = value
	if _dim == null or _window == null:
		return
	_dim.visible = _is_open
	_header.visible = _is_open
	_backpack_grid.visible = _is_open
	_window.get_node("HotbarLabel").visible = _is_open
	if _is_open:
		_window.offset_left = -PANEL_WIDTH * 0.5
		_window.offset_top = -OPEN_HEIGHT - 12.0
		_window.offset_right = PANEL_WIDTH * 0.5
		_window.offset_bottom = -12.0
		_hotbar_grid.position = Vector2(43.0, HOTBAR_GRID_OPEN_TOP)
	else:
		_window.offset_left = -PANEL_WIDTH * 0.5
		_window.offset_top = -CLOSED_HEIGHT - 12.0
		_window.offset_right = PANEL_WIDTH * 0.5
		_window.offset_bottom = -12.0
		_hotbar_grid.position = Vector2(43.0, 5.0)
	_move_source.clear()
	_refresh_slots()

func _on_slot_pressed(is_hotbar: bool, index: int) -> void:
	var item_id := _item_for_slot(is_hotbar, index)
	if not _is_open:
		if is_hotbar:
			hotbar_slot_requested.emit(index)
		return
	if _move_source.is_empty():
		if item_id != "":
			_move_source = {"is_hotbar": is_hotbar, "index": index, "item_id": item_id}
			_hint_label.text = "Selected %s — click a quick-bar slot to assign it, or a backpack slot to remove it" % _display_name(item_id)
			_refresh_slots()
		return
	if bool(_move_source["is_hotbar"]) == is_hotbar and int(_move_source["index"]) == index:
		_move_source.clear()
		_hint_label.text = "Click an item, then a quick-bar slot to assign it  •  Esc / I to close"
		_refresh_slots()
		return
	_move_item_to(is_hotbar, index)

func _move_item_to(target_is_hotbar: bool, target_index: int) -> void:
	var source_item: String = str(_move_source.get("item_id", ""))
	if source_item == "":
		return
	if target_is_hotbar:
		if bool(_move_source.get("is_hotbar", false)):
			var source_index := int(_move_source["index"])
			var displaced := _hotbar_items[target_index]
			_hotbar_items[target_index] = source_item
			_hotbar_items[source_index] = displaced
		else:
			# A hotbar binding is a reference to an inventory stack. Replacing it
			# automatically returns the displaced item to the backpack view.
			for index in range(HOTBAR_SLOTS):
				if _hotbar_items[index] == source_item:
					_hotbar_items[index] = ""
			_hotbar_items[target_index] = source_item
	elif bool(_move_source.get("is_hotbar", false)):
		_hotbar_items[int(_move_source["index"])] = ""
	else:
		_move_source.clear()
		return
	_move_source.clear()
	_hint_label.text = "Click an item, then a quick-bar slot to assign it  •  Esc / I to close"
	hotbar_assignment_changed.emit(_hotbar_items.duplicate())
	_refresh_slots()

func _on_slot_dropped(source_is_hotbar: bool, source_index: int, target_is_hotbar: bool, target_index: int) -> void:
	var item_id := _item_for_slot(source_is_hotbar, source_index)
	if item_id == "":
		return
	_move_source = {"is_hotbar": source_is_hotbar, "index": source_index, "item_id": item_id}
	_move_item_to(target_is_hotbar, target_index)

func _refresh_slots() -> void:
	if _hotbar_slot_nodes.is_empty():
		return
	for index in range(HOTBAR_SLOTS):
		_set_slot(_hotbar_slot_nodes[index], _hotbar_items[index], int(_items.get(_hotbar_items[index], 0)), true, index)
	var backpack_items := _backpack_items()
	for index in range(BACKPACK_SLOTS):
		var item_id := backpack_items[index] if index < backpack_items.size() else ""
		_set_slot(_backpack_slot_nodes[index], item_id, int(_items.get(item_id, 0)), false, index)

func _set_slot(slot: Dictionary, item_id: String, quantity: int, is_hotbar: bool, index: int) -> void:
	var selected := (is_hotbar and index == _active_hotbar_slot) or (
		not _move_source.is_empty()
		and bool(_move_source.get("is_hotbar", false)) == is_hotbar
		and int(_move_source.get("index", -1)) == index
	)
	(slot["selected"] as ColorRect).visible = selected
	(slot["background"] as ColorRect).color = Color(0.24, 0.31, 0.19, 0.98) if selected else Color(0.12, 0.16, 0.12, 0.96)
	(slot["item_label"] as Label).text = _display_name(item_id) if item_id != "" else ""
	(slot["quantity"] as Label).text = str(quantity) if quantity > 1 else ""
	var button: Button = slot["slot"]
	button.set("item_id", item_id)
	button.set("item_name", _display_name(item_id))
	button.tooltip_text = "%s (%d)" % [_display_name(item_id), quantity] if item_id != "" else "Empty slot"

func _backpack_items() -> Array[String]:
	var result: Array[String] = []
	var assigned: Dictionary = {}
	for item_id in _hotbar_items:
		if item_id != "":
			assigned[item_id] = true
	var ids: Array = _items.keys()
	ids.sort()
	for id in ids:
		var item_id := str(id)
		if not assigned.has(item_id):
			result.append(item_id)
	return result

func _item_for_slot(is_hotbar: bool, index: int) -> String:
	if is_hotbar:
		return _hotbar_items[index]
	var backpack_items := _backpack_items()
	return backpack_items[index] if index < backpack_items.size() else ""

func _normalise_hotbar(items: Array[String]) -> Array[String]:
	var result: Array[String] = ["", "", "", "", "", "", "", "", ""]
	var seen: Dictionary = {}
	for index in range(min(items.size(), HOTBAR_SLOTS)):
		var item_id := str(items[index])
		if item_id != "" and _items.has(item_id) and not seen.has(item_id):
			result[index] = item_id
			seen[item_id] = true
	return result

func _display_name(item_id: String) -> String:
	if item_id == "":
		return ""
	var item_db := get_tree().root.get_node_or_null("Main/ItemDatabase")
	return item_db.get_item_display_name(item_id) if item_db != null else item_id.capitalize()

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
