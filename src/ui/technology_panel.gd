## Pannable technology tree with explicit prerequisite connections.
class_name TechnologyPanel
extends Control

signal unlock_requested(technology_id: String)

class TechCanvas extends Control:
	var links: Array[Dictionary] = []
	func _draw() -> void:
		for link in links:
			var start: Vector2 = link.get("start", Vector2.ZERO)
			var finish: Vector2 = link.get("finish", Vector2.ZERO)
			var colour: Color = link.get("colour", Color.GRAY)
			var elbow := (start.x + finish.x) * 0.5
			draw_polyline(PackedVector2Array([start, Vector2(elbow, start.y), Vector2(elbow, finish.y), finish]), colour, 3.0, true)
			draw_circle(finish, 5.0, colour)

var _technology_system: TechnologySystem = null
var _item_database: ItemDatabase = null
var _player: Player = null
var _window: PanelContainer = null
var _canvas: TechCanvas = null
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
	_window.offset_left = -550.0
	_window.offset_top = -320.0
	_window.offset_right = 550.0
	_window.offset_bottom = 320.0
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.add_theme_stylebox_override("panel", _make_style())
	add_child(_window)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 16)
	_window.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)
	var title := Label.new()
	title.text = "SURVIVAL TECHNOLOGY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color("e6e9b8"))
	column.add_child(title)
	var help := Label.new()
	help.text = "Follow the connected branches. Gather the shown materials to research the next tier.  U closes"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color("9aa88a"))
	column.add_child(help)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1040.0, 490.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(scroll)
	_canvas = TechCanvas.new()
	_canvas.name = "TechnologyTree"
	_canvas.custom_minimum_size = Vector2(1040.0, 470.0)
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(_canvas)
	_status = Label.new()
	_status.text = "Green nodes are researched. Amber nodes are available next."
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color("d6b66a"))
	column.add_child(_status)

func _refresh() -> void:
	if _canvas == null:
		return
	for child in _canvas.get_children():
		child.free()
	_canvas.links.clear()
	if _technology_system == null:
		return
	var positions: Dictionary = {}
	var row_by_depth: Dictionary = {}
	var max_depth := 0
	for technology_id in _technology_system.technology_order:
		var definition := _technology_system.get_definition(technology_id)
		if definition == null:
			continue
		var depth := _technology_depth(technology_id)
		max_depth = maxi(max_depth, depth)
		var row := int(row_by_depth.get(depth, 0))
		row_by_depth[depth] = row + 1
		var pos := Vector2(40.0 + depth * 310.0, 70.0 + row * 245.0)
		positions[technology_id] = pos
		var card := _make_entry(definition)
		card.position = pos
		card.size = Vector2(260.0, 195.0)
		_canvas.add_child(card)
	_canvas.custom_minimum_size.x = maxf(1040.0, 350.0 + max_depth * 310.0)
	for technology_id in _technology_system.technology_order:
		var definition := _technology_system.get_definition(technology_id)
		if definition == null or not positions.has(technology_id):
			continue
		for prerequisite in definition.prerequisites:
			if positions.has(prerequisite):
				_canvas.links.append({
					"start": positions[prerequisite] + Vector2(260.0, 97.0),
					"finish": positions[technology_id] + Vector2(0.0, 97.0),
					"colour": Color("65945a") if _technology_system.is_unlocked(prerequisite) else Color("55594b")
				})
	_canvas.queue_redraw()

func _technology_depth(technology_id: String, visiting: Dictionary = {}) -> int:
	if visiting.has(technology_id):
		return 0
	var definition := _technology_system.get_definition(technology_id)
	if definition == null or definition.prerequisites.is_empty():
		return 0
	var next_visiting := visiting.duplicate()
	next_visiting[technology_id] = true
	var depth := 0
	for prerequisite in definition.prerequisites:
		depth = maxi(depth, 1 + _technology_depth(prerequisite, next_visiting))
	return depth

func _make_entry(definition: TechnologyDefinition) -> PanelContainer:
	var researched := _technology_system.is_unlocked(definition.id)
	var available := not researched and _technology_system.can_unlock(definition.id, _player.inventory if _player != null else null)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _entry_style(researched, available))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)
	var eyebrow := Label.new()
	eyebrow.text = "RESEARCHED" if researched else ("AVAILABLE" if available else "LOCKED")
	eyebrow.add_theme_font_size_override("font_size", 10)
	eyebrow.add_theme_color_override("font_color", Color("83c878") if researched else (Color("e0b667") if available else Color("85897b")))
	column.add_child(eyebrow)
	var title := Label.new()
	title.text = definition.display_name
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color("edf0ce"))
	column.add_child(title)
	var description := Label.new()
	description.text = definition.description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description.add_theme_font_size_override("font_size", 11)
	description.add_theme_color_override("font_color", Color("b8bda9"))
	column.add_child(description)
	var cost := Label.new()
	cost.text = "COST  •  %s" % _cost_text(definition.unlock_cost)
	cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost.add_theme_font_size_override("font_size", 11)
	cost.add_theme_color_override("font_color", Color("d6b66a"))
	column.add_child(cost)
	var button := Button.new()
	button.text = "RESEARCHED" if researched else "RESEARCH"
	button.disabled = researched or not available
	button.tooltip_text = "Already researched" if researched else _technology_system.get_unlock_failure_reason(definition.id, _player.inventory if _player != null else null)
	button.pressed.connect(func() -> void: unlock_requested.emit(definition.id))
	column.add_child(button)
	return panel

func _cost_text(cost: Array[Dictionary]) -> String:
	if cost.is_empty():
		return "Free"
	var parts := PackedStringArray()
	for entry in cost:
		var item_id := str(entry.get("item_id", ""))
		var display := _item_database.get_item_display_name(item_id) if _item_database != null else item_id.replace("_", " ")
		parts.append("%d %s" % [int(entry.get("quantity", 0)), display])
	return "  •  ".join(parts)

func _make_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.040, 0.055, 0.045, 0.988)
	style.border_color = Color(0.43, 0.51, 0.28, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.58)
	style.shadow_size = 14
	return style

func _entry_style(researched: bool, available: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.17, 0.10, 0.97) if researched else (Color(0.17, 0.14, 0.075, 0.97) if available else Color(0.085, 0.09, 0.08, 0.95))
	style.border_color = Color("65945a") if researched else (Color("a98546") if available else Color("41463d"))
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style
