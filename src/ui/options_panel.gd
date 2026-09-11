## Shared options overlay (title and pause). Autosave is the first real setting.
class_name OptionsPanel
extends ColorRect

signal closed

var _checkbox: CheckButton = null
var _pack_picker: OptionButton = null
var _apply_pack_button: Button = null
var _texture_status: Label = null
var _preview_tiles: Array[TextureRect] = []
var _pending_pack_id := "stock"

func _ready() -> void:
	color = Color(0.0, 0.0, 0.0, 0.55)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

func open() -> void:
	visible = true
	if _checkbox:
		_checkbox.set_pressed_no_signal(SaveSystem.is_autosave_enabled())
	_refresh_texture_packs()

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520.0, 620.0)
	var style := StyleBoxFlat.new()
	style.bg_color = MenuStyle.PANEL
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(MenuStyle.make_label("Options", 26, MenuStyle.TITLE))

	_checkbox = CheckButton.new()
	_checkbox.text = "Autosave every 5 minutes"
	_checkbox.add_theme_color_override("font_color", MenuStyle.TITLE)
	_checkbox.button_pressed = SaveSystem.is_autosave_enabled()
	_checkbox.toggled.connect(_on_autosave_toggled)
	box.add_child(_checkbox)

	box.add_child(MenuStyle.make_label("Keeps the last 2 autosaves. Manual saves are unlimited.", 13, MenuStyle.MUTED))

	var divider := HSeparator.new()
	box.add_child(divider)
	box.add_child(MenuStyle.make_label("Texture Packs", 20, MenuStyle.TITLE))
	box.add_child(MenuStyle.make_label("Swap visual packs live. Packs only change art, never collisions or saves.", 13, MenuStyle.MUTED))
	_pack_picker = OptionButton.new()
	_pack_picker.custom_minimum_size = Vector2(360.0, 34.0)
	_pack_picker.item_selected.connect(_on_texture_pack_selected)
	box.add_child(_pack_picker)
	_apply_pack_button = MenuStyle.make_button("Apply Texture Pack", 300.0)
	_apply_pack_button.pressed.connect(_on_apply_texture_pack)
	box.add_child(_apply_pack_button)

	box.add_child(MenuStyle.make_label("Live preview", 13, MenuStyle.MUTED))
	var preview_row := HBoxContainer.new()
	preview_row.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_row.add_theme_constant_override("separation", 8)
	box.add_child(preview_row)
	for path in ["res://assets/ground/water.png", "res://assets/ground/sand.png", "res://assets/ground/grass.png"]:
		var preview := TextureRect.new()
		preview.custom_minimum_size = Vector2(112.0, 58.0)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		preview.tooltip_text = path.get_file().get_basename().capitalize()
		preview_row.add_child(preview)
		_preview_tiles.append(preview)

	var export_btn := MenuStyle.make_button("Export Stock Texture Card + Reference", 300.0)
	export_btn.pressed.connect(_on_export_stock_reference)
	box.add_child(export_btn)
	var refinement_btn := MenuStyle.make_button("Create / Open Editable Refinement Pack", 300.0)
	refinement_btn.pressed.connect(_on_create_refinement_pack)
	box.add_child(refinement_btn)
	var folder_btn := MenuStyle.make_button("Open Texture Pack Folder", 300.0)
	folder_btn.pressed.connect(TexturePackManager.open_pack_folder)
	box.add_child(folder_btn)
	_texture_status = MenuStyle.make_label("", 12, MenuStyle.MUTED)
	_texture_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_texture_status)

	var back := MenuStyle.make_button("Back", 160.0)
	back.pressed.connect(_on_back)
	box.add_child(back)

func _on_autosave_toggled(enabled: bool) -> void:
	SaveSystem.set_autosave_enabled(enabled)

func _refresh_texture_packs() -> void:
	if _pack_picker == null:
		return
	var active := TexturePackManager.get_active_pack_id()
	_pending_pack_id = active
	_pack_picker.clear()
	for pack_id in TexturePackManager.get_available_pack_ids():
		_pack_picker.add_item(pack_id.capitalize().replace("_", " "))
		_pack_picker.set_item_metadata(_pack_picker.item_count - 1, pack_id)
		if pack_id == active:
			_pack_picker.select(_pack_picker.item_count - 1)
	if _texture_status != null:
		_texture_status.text = "Active pack: %s" % active.capitalize().replace("_", " ")
	if _apply_pack_button != null:
		_apply_pack_button.text = "Apply %s" % active.capitalize().replace("_", " ")
		_apply_pack_button.disabled = true
	_refresh_texture_preview()

func _on_texture_pack_selected(index: int) -> void:
	if _pack_picker == null:
		return
	_pending_pack_id = str(_pack_picker.get_item_metadata(index))
	if _apply_pack_button != null:
		_apply_pack_button.text = "Apply %s" % _pending_pack_id.capitalize().replace("_", " ")
		_apply_pack_button.disabled = _pending_pack_id == TexturePackManager.get_active_pack_id()
	if _texture_status != null:
		_texture_status.text = "Selected %s. Press Apply Texture Pack." % _pending_pack_id.capitalize().replace("_", " ")

func _on_apply_texture_pack() -> void:
	if not TexturePackManager.set_active_pack_id(_pending_pack_id):
		if _texture_status != null:
			_texture_status.text = "Could not apply that texture pack."
		return
	_refresh_texture_packs()
	if _texture_status != null:
		_texture_status.text = "Applied %s. Preview and world visuals refreshed." % _pending_pack_id.capitalize().replace("_", " ")

func _refresh_texture_preview() -> void:
	var preview_paths := ["res://assets/ground/water.png", "res://assets/ground/sand.png", "res://assets/ground/grass.png"]
	for index in range(min(_preview_tiles.size(), preview_paths.size())):
		_preview_tiles[index].texture = TexturePackManager.get_texture(preview_paths[index])

func _on_export_stock_reference() -> void:
	var result := TexturePackManager.export_stock_reference()
	_refresh_texture_packs()
	if _texture_status != null:
		_texture_status.text = "Exported reference pack and texture card to %s" % str(result.get("pack_path", "texture_packs"))

func _on_create_refinement_pack() -> void:
	var result := TexturePackManager.create_refinement_pack()
	TexturePackManager.set_active_pack_id(TexturePackManager.REFINEMENT_PACK)
	_refresh_texture_packs()
	if _texture_status != null:
		_texture_status.text = "Editable pack ready at %s" % str(result.get("pack_path", "texture_packs"))

func _on_back() -> void:
	visible = false
	closed.emit()
