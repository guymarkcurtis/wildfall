## Compact in-game research panel for the survival progression tree.
class_name TechnologyPanel
extends Control

signal unlock_requested(technology_id: String)

var _technology_system: TechnologySystem = null
var _item_database: ItemDatabase = null
var _player: Player = null
var _window: PanelContainer = null
var _entries: VBoxContainer = null
var _status: Label = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	visible = false

func configure(technology_system: TechnologySystem, item_database: ItemDatabase, player: Player) -> void:
	_technology_system = technology_system
	_item_database = item_database
	_player = player
	_refresh()

func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()

func show_status(message: String) -> void:
	if _status != null:
		_status.text = message

func refresh() -> void:
	_refresh()

func _build_ui() -> void:
	_window = PanelContainer.new()
	_window.set_anchors_preset(Control.PRESET_CENTER)
	_window.offset_left = -245.0
	_window.offset_top = -230.0
	_window.offset_right = 245.0
	_window.offset_bottom = 230.0
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.add_theme_stylebox_override("panel", _make_style())
	add_child(_window)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	_window.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)

	var title := Label.new()
	title.text = "TECHNOLOGY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.90, 0.92, 0.72))
	column.add_child(title)

	var help := Label.new()
	help.text = "Spend gathered resources to unlock the next construction tier.  U closes"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.64, 0.69, 0.57))
	column.add_child(help)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430.0, 310.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_entries = VBoxContainer.new()
	_entries.add_theme_constant_override("separation", 8)
	_entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_entries)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color(0.88, 0.75, 0.47))
	column.add_child(_status)

func _refresh() -> void:
	if _entries == null:
		return
	for child in _entries.get_children():
		child.queue_free()
	if _technology_system == null:
		return
	for technology_id in _technology_system.technology_order:
		var definition := _technology_system.get_definition(technology_id)
		if definition != null:
			_entries.add_child(_make_entry(definition))

func _make_entry(definition: TechnologyDefinition) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _entry_style(_technology_system.is_unlocked(definition.id)))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)

	var title := Label.new()
	title.text = "%s  %s" % ["✓" if _technology_system.is_unlocked(definition.id) else "○", definition.display_name]
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.65, 0.88, 0.58) if _technology_system.is_unlocked(definition.id) else Color(0.90, 0.92, 0.72))
	column.add_child(title)

	var description := Label.new()
	description.text = definition.description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 12)
	description.add_theme_color_override("font_color", Color(0.78, 0.80, 0.74))
	column.add_child(description)

	if not definition.prerequisites.is_empty():
		var requires := Label.new()
		requires.text = "Requires: %s" % _technology_names(definition.prerequisites)
		requires.add_theme_font_size_override("font_size", 11)
		requires.add_theme_color_override("font_color", Color(0.67, 0.72, 0.62))
		column.add_child(requires)

	var cost := Label.new()
	cost.text = "Cost: %s" % _cost_text(definition.unlock_cost)
	cost.add_theme_font_size_override("font_size", 11)
	cost.add_theme_color_override("font_color", Color(0.88, 0.75, 0.47))
	column.add_child(cost)

	var button := Button.new()
	var researched := _technology_system.is_unlocked(definition.id)
	button.text = "Researched" if researched else "Research"
	button.disabled = researched or not _technology_system.can_unlock(definition.id, _player.inventory if _player != null else null)
	button.tooltip_text = "Already researched" if researched else _technology_system.get_unlock_failure_reason(definition.id, _player.inventory if _player != null else null)
	button.pressed.connect(func() -> void: unlock_requested.emit(definition.id))
	column.add_child(button)
	return panel

func _technology_names(ids: PackedStringArray) -> String:
	var names := PackedStringArray()
	for technology_id in ids:
		var definition := _technology_system.get_definition(technology_id)
		names.append(definition.display_name if definition != null else technology_id)
	return ", ".join(names)

func _cost_text(cost: Array[Dictionary]) -> String:
	if cost.is_empty():
		return "Free"
	var parts := PackedStringArray()
	for entry in cost:
		var item_id := str(entry.get("item_id", ""))
		var display := _item_database.get_item_display_name(item_id) if _item_database != null else item_id.replace("_", " ")
		parts.append("%d %s" % [int(entry.get("quantity", 0)), display])
	return ", ".join(parts)

func _make_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.075, 0.055, 0.98)
	style.border_color = Color(0.40, 0.50, 0.28, 0.94)
	style.set_border_width_all(2)
	style.set_corner_radius_all(7)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	style.shadow_size = 10
	return style

func _entry_style(researched: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.17, 0.11, 0.9) if researched else Color(0.12, 0.12, 0.10, 0.9)
	style.border_color = Color(0.32, 0.56, 0.32, 0.75) if researched else Color(0.34, 0.37, 0.28, 0.72)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	return style
