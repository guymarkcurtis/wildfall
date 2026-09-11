## Small in-game build palette. It exposes the parts the player actually owns
## and explains the build controls instead of relying on an invisible wheel.
class_name BuildPalette
extends Control

signal part_selected(item_id: String)

var _manager: BuildingManager = null
var _item_database: ItemDatabase = null
var _window: PanelContainer = null
var _story_label: Label = null
var _status_label: Label = null
var _parts_list: VBoxContainer = null
var _last_signature := ""

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	visible = false

func configure(manager: BuildingManager, item_database: ItemDatabase) -> void:
	_manager = manager
	_item_database = item_database
	if _manager != null:
		_manager.build_mode_changed.connect(_on_build_mode_changed)
		_manager.build_story_changed.connect(_on_build_story_changed)
		_manager.placement_failed.connect(show_status)
	_refresh()

func _process(_delta: float) -> void:
	if visible:
		_refresh_if_changed()

func show_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message

func _build_ui() -> void:
	_window = PanelContainer.new()
	_window.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_window.offset_left = -322.0
	_window.offset_top = 92.0
	_window.offset_right = -14.0
	_window.offset_bottom = 540.0
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.add_theme_stylebox_override("panel", _make_style())
	add_child(_window)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	_window.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var title := Label.new()
	title.text = "BUILD"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.90, 0.92, 0.72))
	column.add_child(title)

	_story_label = Label.new()
	_story_label.add_theme_font_size_override("font_size", 14)
	_story_label.add_theme_color_override("font_color", Color(0.72, 0.80, 0.58))
	column.add_child(_story_label)

	var instructions := Label.new()
	instructions.text = "Click a part to select it.  LMB places • wheel cycles • [ / ] changes story • B closes"
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.add_theme_font_size_override("font_size", 12)
	instructions.add_theme_color_override("font_color", Color(0.64, 0.69, 0.57))
	column.add_child(instructions)

	var divider := HSeparator.new()
	column.add_child(divider)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280.0, 270.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	_parts_list = VBoxContainer.new()
	_parts_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_parts_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_parts_list)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.88, 0.75, 0.47))
	column.add_child(_status_label)

func _on_build_mode_changed(enabled: bool, _selected_item_id: String) -> void:
	visible = enabled
	if enabled:
		show_status("Choose a part, then click a clear tile to place it")
	_refresh()

func _on_build_story_changed(_story: int) -> void:
	show_status("Construction story changed")
	_refresh()

func _refresh_if_changed() -> void:
	if _manager == null:
		return
	var signature := "%d|%s|%s" % [_manager.selected_story, _manager.selected_item_id, ",".join(_manager.get_owned_building_items())]
	if signature != _last_signature:
		_refresh()

func _refresh() -> void:
	if _story_label == null:
		return
	if _manager == null:
		_story_label.text = "Build system unavailable"
		return
	_story_label.text = "Story %d of %d" % [_manager.selected_story + 1, BuildingManager.MAX_STORIES]
	var items := _manager.get_owned_building_items()
	_last_signature = "%d|%s|%s" % [_manager.selected_story, _manager.selected_item_id, ",".join(items)]
	for child in _parts_list.get_children():
		child.queue_free()
	if items.is_empty():
		var empty := Label.new()
		empty.text = "No building parts in your inventory. Open crafting with C and make parts from planks or stone bricks."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", Color(0.72, 0.66, 0.50))
		_parts_list.add_child(empty)
		return
	for item_id in items:
		_parts_list.add_child(_make_part_button(item_id))

func _make_part_button(item_id: String) -> Button:
	var button := Button.new()
	var definition: Variant = _manager.get_definition(item_id) if _manager != null else null
	var display := _item_database.get_item_display_name(item_id) if _item_database != null else item_id.capitalize()
	var part_type := str(definition.get("part_type")) if definition != null else "part"
	var tier := str(definition.get("tier")) if definition != null else ""
	var count := _manager.player.inventory.get_item_quantity(item_id) if _manager != null and _manager.player != null else 0
	button.text = "%s  ×%d   %s %s" % [display, count, tier.capitalize(), part_type]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(270.0, 34.0)
	button.disabled = item_id == _manager.selected_item_id
	button.tooltip_text = "Selected" if button.disabled else "Select %s" % display
	button.pressed.connect(func() -> void: part_selected.emit(item_id))
	return button

func _make_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.075, 0.055, 0.97)
	style.border_color = Color(0.40, 0.50, 0.28, 0.94)
	style.set_border_width_all(2)
	style.set_corner_radius_all(7)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size = 8
	return style
