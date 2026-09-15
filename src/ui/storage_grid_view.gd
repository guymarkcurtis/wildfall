## One reusable slot-grid over any InventoryStorage — the single drag/drop,
## click, split, and tooltip implementation shared by chests, station
## ingredient/fuel/output rows, and the player inventory view inside the
## interactable panel. Slots render in the same visual language as the
## player inventory: item icon, stack count, hover tooltip.
##
## read_only grids accept no interaction at all. take_only grids (station
## output) let stacks leave by click, shift-click, or drag, but never
## receive drops — results wait there for the player to pick up.
class_name StorageGridView
extends GridContainer

signal slot_pressed(grid_id: String, index: int, mouse_button: int)
signal quick_transfer_requested(grid_id: String, index: int)
signal drag_transfer_requested(from_grid_id: String, from_index: int, to_grid_id: String, to_index: int)

const SLOT_SIZE := 56.0
const SLOT_GAP := 5.0

const COL_SLOT_BG := Color(0.12, 0.16, 0.12, 0.96)
const COL_SLOT_BORDER := Color(0.45, 0.55, 0.35, 0.8)
const COL_SELECTED_BG := Color(0.24, 0.32, 0.18, 0.9)
const COL_SELECTED_BORDER := Color(0.85, 0.92, 0.55, 1.0)
const COL_COUNT := Color(0.94, 0.94, 0.78)
const COL_BADGE_MET := Color(0.65, 0.88, 0.58)
const COL_BADGE_UNMET := Color(0.85, 0.45, 0.40)

var storage: InventoryStorage = null
var grid_id: String = ""
var read_only: bool = false
var take_only: bool = false
var selected_index: int = -1
## Ingredient contract for station input rows: index -> {"item_id", "needed"}.
## Rendered as a have/need badge (have counts the whole storage, which is
## what the craft consumes); empty required slots show a dim ghost icon.
var requirements: Dictionary = {}
## Storage indexes at or beyond this are hidden (per-recipe ingredient rows
## show exactly the slots the selected recipe needs, plus any stragglers).
var visible_slot_count: int = 1 << 30

var _slot_buttons: Array[StorageSlotButton] = []
var _icon_cache: Dictionary = {}

## One grid cell. Native Control drag-and-drop carries a storage-grid payload
## so the drop can be routed to the right grid and slot index.
class StorageSlotButton:
	extends Button

	var grid_id: String = ""
	var slot_index: int = -1
	var owner_grid: StorageGridView = null
	var icon_rect: TextureRect = null
	var count_label: Label = null
	var badge_label: Label = null

	func _ready() -> void:
		# flat stays off: a flat Button never draws its "normal" stylebox, which
		# would leave empty slots invisible.
		custom_minimum_size = Vector2(owner_grid.SLOT_SIZE, owner_grid.SLOT_SIZE)
		mouse_filter = Control.MOUSE_FILTER_PASS
		ensure_children()

	## Build the icon/count/badge children. Called from _ready AND directly
	## from setup(), because a grid may be populated before it enters the
	## tree (hidden panels build their layout on open).
	func ensure_children() -> void:
		if icon_rect != null:
			return

		icon_rect = TextureRect.new()
		icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon_rect.offset_left = 8.0
		icon_rect.offset_top = 8.0
		icon_rect.offset_right = -8.0
		icon_rect.offset_bottom = -8.0
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon_rect)

		count_label = Label.new()
		count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		count_label.offset_left = -26.0
		count_label.offset_top = -20.0
		count_label.offset_right = -4.0
		count_label.offset_bottom = -3.0
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.add_theme_font_size_override("font_size", 12)
		count_label.add_theme_color_override("font_color", owner_grid.COL_COUNT)
		count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		count_label.add_theme_constant_override("shadow_offset_x", 1)
		count_label.add_theme_constant_override("shadow_offset_y", 1)
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(count_label)

		badge_label = Label.new()
		badge_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge_label.offset_left = -34.0
		badge_label.offset_top = 2.0
		badge_label.offset_right = -3.0
		badge_label.offset_bottom = -16.0
		badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge_label.add_theme_font_size_override("font_size", 11)
		badge_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		badge_label.add_theme_constant_override("shadow_offset_x", 1)
		badge_label.add_theme_constant_override("shadow_offset_y", 1)
		badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(badge_label)

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
		preview.text = tooltip_text
		preview.custom_minimum_size = Vector2(120.0, 30.0)
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
		# Output rows are take-only: stacks leave but never land.
		if owner_grid.take_only:
			return false
		return typeof(data) == TYPE_DICTIONARY and bool(data.get("storage_grid", false))

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		owner_grid.drag_transfer_requested.emit(
				str(data.get("grid_id", "")), int(data.get("slot_index", -1)),
				grid_id, slot_index)

func setup(p_storage: InventoryStorage, p_grid_id: String, p_columns: int = 9,
		p_read_only: bool = false, p_take_only: bool = false) -> void:
	storage = p_storage
	grid_id = p_grid_id
	read_only = p_read_only
	take_only = p_take_only
	requirements = {}
	visible_slot_count = 1 << 30
	# Assign the GridContainer property (a same-named parameter would shadow it).
	columns = maxi(p_columns, 1)
	add_theme_constant_override("h_separation", int(SLOT_GAP))
	add_theme_constant_override("v_separation", int(SLOT_GAP))
	_slot_buttons.clear()
	_icon_cache.clear()
	for child in get_children():
		child.queue_free()
	for index in range(storage.slot_count() if storage != null else 0):
		var button := StorageSlotButton.new()
		button.owner_grid = self
		button.grid_id = grid_id
		button.slot_index = index
		add_child(button)
		button.ensure_children()
		_slot_buttons.append(button)
		_style_slot_button(button, false)
	refresh()

func refresh() -> void:
	if storage == null:
		return
	for button in _slot_buttons:
		button.visible = button.slot_index < visible_slot_count
		var stack := storage.stack_at(button.slot_index)
		var requirement: Dictionary = requirements.get(button.slot_index, {})
		var required_id := str(requirement.get("item_id", ""))
		var required_count := int(requirement.get("needed", 0))
		var item_id := str(stack.get("item_id", ""))
		var quantity := int(stack.get("quantity", 0))
		if item_id != "":
			button.icon_rect.texture = _icon_for(item_id)
			button.icon_rect.modulate = Color(1, 1, 1, 1)
			button.count_label.text = str(quantity) if quantity > 1 else ""
			button.tooltip_text = _tooltip_for(item_id, quantity, stack)
		elif required_id != "":
			# Ghost preview: the ingredient this slot is waiting for.
			button.icon_rect.texture = _icon_for(required_id)
			button.icon_rect.modulate = Color(1, 1, 1, 0.22)
			button.count_label.text = ""
			button.tooltip_text = "%s — needs %d" % [_name_for(required_id), required_count]
		else:
			button.icon_rect.texture = null
			button.count_label.text = ""
			button.tooltip_text = "Empty slot"
		if required_id != "":
			var have := storage.quantity_of(required_id)
			button.badge_label.text = "%d/%d" % [have, required_count]
			button.badge_label.add_theme_color_override("font_color",
					COL_BADGE_MET if have >= required_count else COL_BADGE_UNMET)
		else:
			button.badge_label.text = ""
	if selected_index >= 0:
		highlight_selected(selected_index)

func highlight_selected(index: int) -> void:
	selected_index = index
	for button in _slot_buttons:
		_style_slot_button(button, button.slot_index == selected_index and not read_only)

## Slot chrome is applied eagerly at creation and re-applied on selection
## changes, so empty grids (output, fuel, ghost ingredients) still read as
## slots instead of invisible buttons.
func _style_slot_button(button: StorageSlotButton, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	if selected:
		style.bg_color = COL_SELECTED_BG
		style.border_color = COL_SELECTED_BORDER
	else:
		style.bg_color = COL_SLOT_BG
		style.border_color = COL_SLOT_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)

func _on_slot_gui_input(index: int, mouse_button: int) -> void:
	if read_only:
		return
	slot_pressed.emit(grid_id, index, mouse_button)

func _icon_for(item_id: String) -> Texture2D:
	if _icon_cache.has(item_id):
		return _icon_cache[item_id]
	var texture: Texture2D = null
	# The grid may refresh during teardown, when it is outside the tree.
	var database := get_node_or_null("/root/Main/ItemDatabase") as ItemDatabase \
			if is_inside_tree() else null
	if database != null:
		var item := database.get_item(item_id)
		if item != null and not item.texture_path.is_empty():
			texture = TexturePackManager.get_texture(item.texture_path)
	# Only cache hits: a miss is usually "not in the tree yet" (panels build
	# their layout before attaching), and the next refresh should retry.
	if texture != null:
		_icon_cache[item_id] = texture
	return texture

func _name_for(item_id: String) -> String:
	var database := get_node_or_null("/root/Main/ItemDatabase") as ItemDatabase \
			if is_inside_tree() else null
	if database != null:
		return database.get_item_display_name(item_id)
	return item_id.capitalize()

func _tooltip_for(item_id: String, quantity: int, stack: Dictionary) -> String:
	var text := "%s (%d)" % [_name_for(item_id), quantity]
	var durability := int(stack.get("durability", 0))
	if durability > 0:
		var max_durability := int(storage.max_durations.get(item_id, 0))
		if max_durability > 0:
			text += " — %d/%d durability" % [durability, max_durability]
	return text
