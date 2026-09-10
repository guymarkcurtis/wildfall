## UI component for inventory upgrades.
class_name InventoryUpgradesUI
extends Control

@onready var slots_label: Label = $SlotsLabel
@onready var weight_label: Label = $WeightLabel
@onready var stack_label: Label = $StackLabel
@onready var sort_button: Button = $SortButton
@onready var search_button: Button = $SearchButton
@onready var vault_button: Button = $VaultButton
@onready var upgrade_list: VBoxContainer = $UpgradeList

var inventory_upgrades: InventoryUpgrades = null

# Signals
signal upgrade_purchased(upgrade_type: int, upgrade_id: String)
signal feature_unlocked(feature: String)
signal panel_closed

func _ready() -> void:
	visible = false
	sort_button.pressed.connect(_on_sort_pressed)
	search_button.pressed.connect(_on_search_pressed)
	vault_button.pressed.connect(_on_vault_pressed)

## Show the upgrades panel.
func show_panel(upgrades: InventoryUpgrades) -> void:
	inventory_upgrades = upgrades
	visible = true
	_refresh_display()

## Refresh the display.
func _refresh_display() -> void:
	if not inventory_upgrades:
		return
	
	slots_label.text = "Slots: %d" % inventory_upgrades.get_total_slots()
	weight_label.text = "Weight: %.1f / %.1f" % [0, inventory_upgrades.get_total_weight()]
	stack_label.text = "Stack: %d" % inventory_upgrades.get_max_stack_size()
	
	# Update button states
	sort_button.disabled = not inventory_upgrades.is_sort_unlocked()
	search_button.disabled = not inventory_upgrades.is_search_unlocked()
	vault_button.disabled = not inventory_upgrades.is_vault_unlocked()
	
	# Refresh upgrade list
	_refresh_upgrade_list()

## Refresh upgrade list.
func _refresh_upgrade_list() -> void:
	# Clear existing items
	for child in upgrade_list.get_children():
		if child != sort_button and child != search_button and child != vault_button:
			child.queue_free()
	
	# Add slot upgrades
	for upgrade_id in ["bag_1", "bag_2", "bag_3"]:
		var level := inventory_upgrades.get_slot_upgrade_level(upgrade_id)
		if level != InventoryUpgrades.UpgradeLevel.NONE:
			var item := _create_upgrade_item("slot", upgrade_id, level)
			upgrade_list.add_child(item)
	
	# Add weight upgrades
	for upgrade_id in ["backpack_1", "backpack_2", "backpack_3"]:
		var level := inventory_upgrades.get_slot_upgrade_level(upgrade_id)
		if level != InventoryUpgrades.UpgradeLevel.NONE:
			var item := _create_upgrade_item("weight", upgrade_id, level)
			upgrade_list.add_child(item)

## Create an upgrade item.
func _create_upgrade_item(upgrade_type: String, upgrade_id: String, level: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 30)
	
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hbox)
	
	# Upgrade name
	var name_label := Label.new()
	name_label.text = upgrade_id.capitalize()
	hbox.add_child(name_label)
	
	# Level indicator
	var level_label := Label.new()
	match level:
		InventoryUpgrades.UpgradeLevel.BASIC:
			level_label.text = "★"
		InventoryUpgrades.UpgradeLevel.ADVANCED:
			level_label.text = "★★"
		InventoryUpgrades.UpgradeLevel.MAX:
			level_label.text = "★★★"
	level_label.modulate = Color(1.0, 0.9, 0.3)
	hbox.add_child(level_label)
	
	return panel

## Handle sort button press.
func _on_sort_pressed() -> void:
	if inventory_upgrades and inventory_upgrades.is_sort_unlocked():
		feature_unlocked.emit("sort")

## Handle search button press.
func _on_search_pressed() -> void:
	if inventory_upgrades and inventory_upgrades.is_search_unlocked():
		feature_unlocked.emit("search")

## Handle vault button press.
func _on_vault_pressed() -> void:
	if inventory_upgrades and inventory_upgrades.is_vault_unlocked():
		feature_unlocked.emit("vault")

## Hide the panel.
func hide_panel() -> void:
	visible = false
	panel_closed.emit()

## Purchase an upgrade.
func purchase_upgrade(upgrade_type: int, upgrade_id: String) -> bool:
	if not inventory_upgrades:
		return false
	
	match upgrade_type:
		InventoryUpgrades.UpgradeType.SLOTS:
			return inventory_upgrades.purchase_slot_upgrade(upgrade_id)
		InventoryUpgrades.UpgradeType.WEIGHT:
			return inventory_upgrades.purchase_weight_upgrade(upgrade_id)
		InventoryUpgrades.UpgradeType.STACK:
			return inventory_upgrades.purchase_stack_upgrade(upgrade_id)
	return false
