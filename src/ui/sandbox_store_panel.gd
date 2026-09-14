## Full item generator for Building Sandbox. It reads directly from the
## ItemDatabase, so every current and future collectible is testable without
## a separately curated shop catalog.
class_name SandboxStorePanel
extends Control

var _inventory: InventoryComponent = null
var _item_database: ItemDatabase = null
var _list: VBoxContainer = null
var _status: Label = null
var _search: LineEdit = null
var _entries: Array[String] = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

func configure(inventory: InventoryComponent, item_database: ItemDatabase) -> void:
	_inventory = inventory
	_item_database = item_database
	_rebuild_entries()

func open() -> void:
	if not GameSession.is_building_sandbox():
		return
	visible = true
	if _search != null:
		_search.grab_focus()
	_rebuild_entries()

func close() -> void:
	visible = false

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.60)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700.0, 560.0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	panel.add_child(box)
	box.add_child(MenuStyle.make_label("SUPPLY STORE", 26, MenuStyle.TITLE))
	box.add_child(MenuStyle.make_label("Sandbox items are free. Get one for tools, or a stack for building and recipe tests.", 13, MenuStyle.MUTED))
	_search = LineEdit.new()
	_search.placeholder_text = "Search every collectible…"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(0.0, 36.0)
	_search.text_changed.connect(func(_value: String) -> void: _rebuild_entries())
	box.add_child(_search)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(650.0, 380.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_list)
	_status = MenuStyle.make_label("", 13, MenuStyle.MUTED)
	box.add_child(_status)
	var close_button := MenuStyle.make_button("Close", 180.0)
	close_button.pressed.connect(close)
	box.add_child(close_button)

func _rebuild_entries() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	_entries.clear()
	if _item_database == null:
		return
	var query := _search.text.strip_edges().to_lower() if _search != null else ""
	for item_id_variant in _item_database.items:
		var item_id := str(item_id_variant)
		if item_id == "hand":
			continue
		var item: ItemDefinition = _item_database.get_item(item_id)
		if item == null:
			continue
		var haystack := "%s %s %s" % [item_id, item.display_name, item.category]
		if not query.is_empty() and not haystack.to_lower().contains(query):
			continue
		_entries.append(item_id)
	_entries.sort_custom(func(a: String, b: String) -> bool:
		return _item_database.get_item_display_name(a).naturalnocasecmp_to(_item_database.get_item_display_name(b)) < 0
	)
	for item_id in _entries:
		_list.add_child(_make_row(item_id))
	if _entries.is_empty():
		_list.add_child(MenuStyle.make_label("No collectibles match that search.", 14, MenuStyle.MUTED))

func _make_row(item_id: String) -> Control:
	var item: ItemDefinition = _item_database.get_item(item_id)
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(640.0, 42.0)
	row.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = item.display_name
	name_label.tooltip_text = "%s  •  %s" % [item_id, item.category.capitalize()]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", MenuStyle.TITLE)
	row.add_child(name_label)
	var one := MenuStyle.make_button("Get 1", 88.0)
	one.custom_minimum_size = Vector2(88.0, 34.0)
	one.pressed.connect(_grant.bind(item_id, 1))
	row.add_child(one)
	var stack := MenuStyle.make_button("Get Stack", 108.0)
	stack.custom_minimum_size = Vector2(108.0, 34.0)
	stack.pressed.connect(_grant.bind(item_id, max(1, item.stack_size)))
	row.add_child(stack)
	return row

func _grant(item_id: String, quantity: int) -> void:
	if _inventory == null or _item_database == null:
		return
	var remainder := _inventory.add_item(item_id, quantity)
	var accepted := quantity - remainder
	var name := _item_database.get_item_display_name(item_id)
	if accepted > 0:
		_status.text = "Added %d × %s" % [accepted, name]
	else:
		_status.text = "No room for %s — clear a slot or make space." % name

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.060, 0.048, 0.985)
	style.border_color = Color(0.63, 0.70, 0.35, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(7)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style
