## UI element for an inventory slot.
class_name SlotUI
extends Control

var index: int = 0
var item_id: String = ""
var quantity: int = 0

@onready var item_label: Label = $ItemLabel
@onready var quantity_label: Label = $QuantityLabel
@onready var background: ColorRect = $Background
@onready var selected_overlay: ColorRect = $SelectedOverlay

func _ready() -> void:
	visible = false

## Update slot display.
func update(item_id: String, quantity: int) -> void:
	self.item_id = item_id
	self.quantity = quantity
	
	if item_id == "":
		item_label.text = ""
		quantity_label.text = ""
		background.color = Color(0.2, 0.2, 0.2, 0.5)
	else:
		item_label.text = item_id
		if quantity > 1:
			quantity_label.text = str(quantity)
		else:
			quantity_label.text = ""
		background.color = Color(0.3, 0.3, 0.3, 0.8)

## Set selection state.
func set_selected(selected: bool) -> void:
	selected_overlay.visible = selected

## Handle click.
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		$SlotButton.pressed = true
