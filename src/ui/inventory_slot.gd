## One interactive inventory cell. It owns the native Control drag-and-drop
## contract while InventoryPanel remains responsible for item layout and saves.
class_name InventorySlot
extends Button

signal drag_received(source_is_hotbar: bool, source_index: int, target_is_hotbar: bool, target_index: int)

var is_hotbar := false
var slot_index := -1
var item_id := ""
var item_name := ""

func _ready() -> void:
	flat = true

func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_id == "":
		return null
	var preview := Label.new()
	preview.text = item_name
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
	return {
		"inventory_slot": true,
		"is_hotbar": is_hotbar,
		"slot_index": slot_index
	}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.get("inventory_slot", false):
		return false
	return bool(data.get("is_hotbar", false)) != is_hotbar or int(data.get("slot_index", -1)) != slot_index

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	drag_received.emit(
		bool(data.get("is_hotbar", false)),
		int(data.get("slot_index", -1)),
		is_hotbar,
		slot_index
	)
