## Manages resource harvesting and interactions.
class_name HarvestSystem
extends Node

# Tool tiers and their multipliers
const TOOL_Tiers: Dictionary = {
	"hand": 1.0,
	"primitive_stone": 1.5,
	"stone": 2.0,
	"wooden": 2.5,
	"iron": 4.0,
	"metal": 6.0,
	"advanced": 10.0
}

# Signals
signal resource_harvested(item_id: String, quantity: int, coords: Vector2i)
signal resource_damaged(resource: HarvestableResource, amount: float)
signal harvest_attempt_failed(reason: String)

## Harvest a resource using the player's equipped tool.
func harvest_resource(resource: HarvestableResource, player_inventory, tool_id: String = "") -> bool:
	if resource.is_destroyed_check():
		harvest_attempt_failed.emit("Resource already destroyed")
		return false

	# Get tool multiplier
	var multiplier: float = _get_tool_multiplier(tool_id)
	var damage: float = 1.0 * multiplier

	# Apply damage
	resource.damage(damage)
	resource_damaged.emit(resource, damage)

	# Check if destroyed
	if resource.is_destroyed_check():
		# Resource will emit resource_destroyed signal when destroyed
		# We listen to that to add items to inventory
		_add_yield_items_to_inventory(resource, player_inventory)
		return true

	return false

## Get tool multiplier for a tool ID.
func _get_tool_multiplier(tool_id: String) -> float:
	# Default to hand if no tool
	if tool_id == "" or tool_id == "hand":
		return TOOL_Tiers["hand"]

	# Check tool tier
	if tool_id.begins_with("primitive_"):
		return TOOL_Tiers["primitive_stone"]
	elif tool_id.begins_with("stone_") or tool_id == "stone":
		return TOOL_Tiers["stone"]
	elif tool_id.begins_with("wooden_"):
		return TOOL_Tiers["wooden"]
	elif tool_id.begins_with("iron_") or tool_id == "iron":
		return TOOL_Tiers["iron"]
	elif tool_id.begins_with("metal_"):
		return TOOL_Tiers["metal"]
	else:
		return TOOL_Tiers["hand"]

## Add yield items from a destroyed resource to inventory.
func _add_yield_items_to_inventory(resource: HarvestableResource, inventory) -> void:
	var yields: Array[Dictionary] = resource.get_yields()
	for yield_entry in yields:
		var item_id: String = yield_entry["item_id"]
		var min_qty: int = yield_entry.get("min_qty", 1)
		var max_qty: int = yield_entry.get("max_qty", 1)
		var chance: float = yield_entry.get("chance", 1.0)

		if randf() < chance:
			var qty: int = randi() % (max_qty - min_qty + 1) + min_qty
			inventory.add_item(item_id, qty)
			resource_harvested.emit(item_id, qty, resource.position)

## Check if a resource is within interaction range of the player.
func is_within_range(resource: HarvestableResource, player_position: Vector2, range: float = 64.0) -> bool:
	return resource.position.distance_to(player_position) <= range

## Get all nearby resources for a player.
func get_nearby_resources(resources: Array[HarvestableResource], player_position: Vector2, range: float = 64.0) -> Array[HarvestableResource]:
	var nearby: Array[HarvestableResource] = []
	for resource in resources:
		if not resource.is_destroyed_check() and is_within_range(resource, player_position, range):
			nearby.append(resource)
	return nearby

## Create a new resource node.
func create_resource(resource_type: String, coords: Vector2i, world_seed: int) -> HarvestableResource:
	var resource := HarvestableResource.new()
	var health: float = _get_resource_health(resource_type)
	var yields: Array[Dictionary] = _get_resource_yields(resource_type)
	resource.setup(resource_type, health, yields)
	resource.position = Vector2(coords)
	return resource

## Get default health for a resource type.
func _get_resource_health(resource_type: String) -> float:
	match resource_type:
		"tree": return 5.0
		"rock": return 8.0
		"fibre": return 3.0
		"berry_bush": return 2.0
		"iron_ore": return 10.0
		"coal": return 6.0
		"gold_ore": return 12.0
		_: return 5.0

## Get default yields for a resource type.
func _get_resource_yields(resource_type: String) -> Array[Dictionary]:
	match resource_type:
		"tree":
			return [
				{"item_id": "wood", "min_qty": 2, "max_qty": 5, "chance": 1.0},
				{"item_id": "fibre", "min_qty": 1, "max_qty": 3, "chance": 0.5}
			]
		"rock":
			return [
				{"item_id": "stone", "min_qty": 2, "max_qty": 4, "chance": 1.0},
				{"item_id": "clay", "min_qty": 1, "max_qty": 2, "chance": 0.3}
			]
		"fibre":
			return [
				{"item_id": "fibre", "min_qty": 3, "max_qty": 6, "chance": 1.0}
			]
		"berry_bush":
			return [
				{"item_id": "berry", "min_qty": 2, "max_qty": 5, "chance": 1.0}
			]
		"iron_ore":
			return [
				{"item_id": "iron_ore", "min_qty": 1, "max_qty": 3, "chance": 1.0},
				{"item_id": "stone", "min_qty": 1, "max_qty": 2, "chance": 0.5}
			]
		"coal":
			return [
				{"item_id": "coal", "min_qty": 1, "max_qty": 3, "chance": 1.0}
			]
		"gold_ore":
			return [
				{"item_id": "gold_ore", "min_qty": 1, "max_qty": 2, "chance": 1.0},
				{"item_id": "stone", "min_qty": 1, "max_qty": 2, "chance": 0.5}
			]
		_:
			return [
				{"item_id": resource_type, "min_qty": 1, "max_qty": 2, "chance": 1.0}
			]
