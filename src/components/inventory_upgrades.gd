## Manages inventory upgrades and enhancements.
class_name InventoryUpgrades
extends Node

# Upgrade types
enum UpgradeType {
	SLOTS,      # Additional inventory slots
	WEIGHT,     # Weight capacity increase
	SORT,       # Auto-sort functionality
	SEARCH,     # Item search
	STACK,      # Increased stack sizes
	VAULT       # Secure storage
}

# Upgrade levels
enum UpgradeLevel {
	NONE,       # No upgrade
	BASIC,      # Level 1
	ADVANCED,   # Level 2
	MAX         # Level 3
}

# Upgrade data
var slot_upgrades: Dictionary = {}
var weight_upgrades: Dictionary = {}
var sort_unlocked: bool = false
var search_unlocked: bool = false
var stack_upgrades: Dictionary = {}
var vault_unlocked: bool = false

# Base values
const BASE_SLOTS: int = 36
const BASE_WEIGHT: float = 100.0
const BASE_STACK: int = 64

# Signals
signal slots_upgraded(new_slots: int)
signal weight_upgraded(new_capacity: float)
signal sort_unlocked_signal
signal search_unlocked_signal
signal stack_upgraded(new_stack: int)
signal vault_unlocked_signal

## Initialize the inventory upgrades system.
func initialize() -> void:
	_load_default_upgrades()
	print("InventoryUpgrades: Initialized")

## Load default upgrades.
func _load_default_upgrades() -> void:
	# Slot upgrades
	slot_upgrades["bag_1"] = {"slots": 9, "cost": 100, "level": UpgradeLevel.BASIC}
	slot_upgrades["bag_2"] = {"slots": 18, "cost": 250, "level": UpgradeLevel.ADVANCED}
	slot_upgrades["bag_3"] = {"slots": 36, "cost": 500, "level": UpgradeLevel.MAX}
	
	# Weight upgrades
	weight_upgrades["backpack_1"] = {"capacity": 50.0, "cost": 150, "level": UpgradeLevel.BASIC}
	weight_upgrades["backpack_2"] = {"capacity": 100.0, "cost": 300, "level": UpgradeLevel.ADVANCED}
	weight_upgrades["backpack_3"] = {"capacity": 200.0, "cost": 600, "level": UpgradeLevel.MAX}
	
	# Stack upgrades
	stack_upgrades["stack_1"] = {"size": 128, "cost": 200, "level": UpgradeLevel.BASIC}
	stack_upgrades["stack_2"] = {"size": 256, "cost": 400, "level": UpgradeLevel.ADVANCED}

## Get total slots.
func get_total_slots() -> int:
	var total := BASE_SLOTS
	for upgrade_id in slot_upgrades:
		if slot_upgrades[upgrade_id]["level"] != UpgradeLevel.NONE:
			total += slot_upgrades[upgrade_id]["slots"]
	return total

## Get total weight capacity.
func get_total_weight() -> float:
	var total := BASE_WEIGHT
	for upgrade_id in weight_upgrades:
		if weight_upgrades[upgrade_id]["level"] != UpgradeLevel.NONE:
			total += weight_upgrades[upgrade_id]["capacity"]
	return total

## Get max stack size.
func get_max_stack_size() -> int:
	var max_stack := BASE_STACK
	for upgrade_id in stack_upgrades:
		if stack_upgrades[upgrade_id]["level"] != UpgradeLevel.NONE:
			max_stack = max(max_stack, stack_upgrades[upgrade_id]["size"])
	return max_stack

## Purchase a slot upgrade.
func purchase_slot_upgrade(upgrade_id: String) -> bool:
	var upgrade := slot_upgrades.get(upgrade_id)
	if not upgrade or upgrade["level"] != UpgradeLevel.NONE:
		return false
	
	# Would check player has enough currency
	upgrade["level"] = upgrade["level"] + 1
	slot_upgraded.emit(get_total_slots())
	return true

## Purchase a weight upgrade.
func purchase_weight_upgrade(upgrade_id: String) -> bool:
	var upgrade := weight_upgrades.get(upgrade_id)
	if not upgrade or upgrade["level"] != UpgradeLevel.NONE:
		return false
	
	upgrade["level"] = upgrade["level"] + 1
	weight_upgraded.emit(get_total_weight())
	return true

## Purchase a stack upgrade.
func purchase_stack_upgrade(upgrade_id: String) -> bool:
	var upgrade := stack_upgrades.get(upgrade_id)
	if not upgrade or upgrade["level"] != UpgradeLevel.NONE:
		return false
	
	upgrade["level"] = upgrade["level"] + 1
	stack_upgraded.emit(get_max_stack_size())
	return true

## Unlock sort functionality.
func unlock_sort() -> bool:
	if sort_unlocked:
		return false
	sort_unlocked = true
	sort_unlocked_signal.emit()
	return true

## Unlock search functionality.
func unlock_search() -> bool:
	if search_unlocked:
		return false
	search_unlocked = true
	search_unlocked_signal.emit()
	return true

## Unlock vault storage.
func unlock_vault() -> bool:
	if vault_unlocked:
		return false
	vault_unlocked = true
	vault_unlocked_signal.emit()
	return true

## Check if sort is unlocked.
func is_sort_unlocked() -> bool:
	return sort_unlocked

## Check if search is unlocked.
func is_search_unlocked() -> bool:
	return search_unlocked

## Check if vault is unlocked.
func is_vault_unlocked() -> bool:
	return vault_unlocked

## Get upgrade level for a slot upgrade.
func get_slot_upgrade_level(upgrade_id: String) -> int:
	var upgrade := slot_upgrades.get(upgrade_id)
	if upgrade:
		return upgrade["level"]
	return UpgradeLevel.NONE

## Get upgrade cost.
func get_upgrade_cost(upgrade_type: int, upgrade_id: String) -> int:
	match upgrade_type:
		UpgradeType.SLOTS:
			var upgrade := slot_upgrades.get(upgrade_id)
			if upgrade:
				return upgrade["cost"]
		UpgradeType.WEIGHT:
			var upgrade := weight_upgrades.get(upgrade_id)
			if upgrade:
				return upgrade["cost"]
		UpgradeType.STACK:
			var upgrade := stack_upgrades.get(upgrade_id)
			if upgrade:
				return upgrade["cost"]
	return 0

## Serialize upgrade data.
func serialize() -> Dictionary:
	return {
		"slot_upgrades": slot_upgrades,
		"weight_upgrades": weight_upgrades,
		"stack_upgrades": stack_upgrades,
		"sort_unlocked": sort_unlocked,
		"search_unlocked": search_unlocked,
		"vault_unlocked": vault_unlocked
	}

## Deserialize upgrade data.
func deserialize(data: Dictionary) -> void:
	slot_upgrades = data.get("slot_upgrades", {})
	weight_upgrades = data.get("weight_upgrades", {})
	stack_upgrades = data.get("stack_upgrades", {})
	sort_unlocked = data.get("sort_unlocked", false)
	search_unlocked = data.get("search_unlocked", false)
	vault_unlocked = data.get("vault_unlocked", false)
