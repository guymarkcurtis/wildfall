## One reusable slot-grid over any InventoryStorage — the single drag/drop,
## click, split, and tooltip implementation shared by the player inventory
## view, chests, fuel slots, and station inputs/outputs. Read-only grids
## (output slots) render stacks but accept no interaction.
class_name StorageGridView
extends GridContainer

signal slot_pressed(grid_id: String, index: int, mouse_button: int)
signal quick_transfer_requested(grid_id: String, index: int)
signal drag_transfer_requested(from_grid_id: String, from_index: int, to_grid_id: String, to_index: int)

var storage: InventoryStorage = null
var grid_id: String = ""
var read_only: bool = false
var selected_index: int = -1

var _slot_buttons: Array[StorageSlotButton] = []

## One grid cell. Native Control drag-and-drop carries a storage-grid payload
## so the drop can be routed to the right grid and slot index.
class StorageSlotButton:
	extends Button

	var grid_id: String = ""
	var slot_index: int = -1
	var owner_grid: StorageGridView = null

	func _ready() -> void:
		flat = true
		custom_minimum_size = Vector2(64, 52)

	func _gui_input(event: InputEvent) -> void:
		var mouse := event as InputEventMouseButton
		if mouse == null or not mouse.pressed:
			return
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.shift_pressed:
			# Shift-click quick transfer: the whole stack crosses panels.
			owner_grid.quick_transfer_requested.emit(owner_grid.grid_id, slot_index)
			return
		if mouse.button_index == MOUSE_BUTTON_LEFT or mouse.button_index == MOUSE_BUTTON_RIGHT:
			owner_grid._on_slot_gui_input(slot_index, int(mouse.button_index))

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if owner_grid.read_only or owner_grid.storage == null:
			return null
		if owner_grid.storage.is_empty_slot(slot_index):
			return null
		var preview := Label.new()
		preview.text = text
		preview.custom_minimum_size = Vector2(100.0, 28.0)
		preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		preview.add_theme_font_size_override("font_size", 12)
		preview.add_theme_color_override("font_color", Color(0.92, 0.94, 0.82))
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.11, 0.16, 0.10, 0.96)
		style.border_color = Color(0.68, 0.78, 0.38, 0.96)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		preview.add_theme_stylebox_override("normal", style)
		set_drag_preview(preview)
		return {"storage_grid": true, "grid_id": grid_id, "slot_index": slot_index}

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return typeof(data) == TYPE_DICTIONARY and bool(data.get("storage_grid", false))

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		owner_grid.drag_transfer_requested.emit(
				str(data.get("grid_id", "")), int(data.get("slot_index", -1)),
				grid_id, slot_index)

func setup(p_storage: InventoryStorage, p_grid_id: String, columns: int = 9, p_read_only: bool = false) -> void:
	storage = p_storage
	grid_id = p_grid_id
	read_only = p_read_only
	columns = maxi(columns, 1)
	_slot_buttons.clear()
	for child in get_children():
		child.queue_free()
	for index in range(storage.slot_count() if storage != null else 0):
		var button := StorageSlotButton.new()
		button.owner_grid = self
		button.grid_id = grid_id
		button.slot_index = index
		add_child(button)
		_slot_buttons.append(button)
	refresh()

func refresh() -> void:
	if storage == null:
		return
	for button in _slot_buttons:
		var stack := storage.stack_at(button.slot_index)
		if stack.is_empty():
			button.text = ""
			button.tooltip_text = ""
			button.modulate = Color(1, 1, 1, 0.85)
			continue
		var quantity := int(stack.get("quantity", 0))
		var label := str(stack.get("item_id", "")).replace("_", " ")
		button.text = "%s\nx%d" % [label.capitalize(), quantity] if quantity > 1 else label.capitalize()
		button.tooltip_text = "%s (%d)" % [label.capitalize(), quantity]
		button.modulate = Color(1, 1, 1, 1)
	if selected_index >= 0:
		highlight_selected(selected_index)

func highlight_selected(index: int) -> void:
	selected_index = index
	for button in _slot_buttons:
		var style := StyleBoxFlat.new()
		if button.slot_index == selected_index and not read_only:
			style.bg_color = Color(0.24, 0.32, 0.18, 0.9)
			style.border_color = Color(0.85, 0.92, 0.55, 1.0)
		else:
			style.bg_color = Color(0.08, 0.12, 0.08, 0.85)
			style.border_color = Color(0.45, 0.55, 0.35, 0.8)
		style.set_border_width_all(1)
		style.set_corner_radius_all(3)
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)

func _on_slot_gui_input(index: int, mouse_button: int) -> void:
	if read_only:
		return
	slot_pressed.emit(grid_id, index, mouse_button)
