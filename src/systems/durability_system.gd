## Manages durability for all tools in the game.
class_name DurabilitySystem
extends Node

# Dictionary of tool_id -> DurabilityComponent
var tool_durabilities: Dictionary = {}

# Signals
signal tool_worn_out(tool_id: String)
signal tool_repaired(tool_id: String)
signal durability_updated(tool_id: String, current: int, max: int)

## Initialize the durability system.
func initialize() -> void:
	print("DurabilitySystem: Initialized")

## Register a tool for durability tracking.
func register_tool(tool_id: String, max_durability: int = 100) -> DurabilityComponent:
	if tool_durabilities.has(tool_id):
		return tool_durabilities[tool_id]
	
	var component := DurabilityComponent.new()
	component.initialize(tool_id, max_durability)
	tool_durabilities[tool_id] = component
	return component

## Get durability component for a tool.
func get_durability(tool_id: String) -> DurabilityComponent:
	return tool_durabilities.get(tool_id)

## Use a tool (decrease durability).
func use_tool(tool_id: String, amount: int = 1) -> bool:
	var component := tool_durabilities.get(tool_id)
	if not component:
		register_tool(tool_id)
		component = tool_durabilities[tool_id]
	
	var success: bool = component.use(amount)
	if not success:
		tool_worn_out.emit(tool_id)
	else:
		durability_updated.emit(tool_id, component.current_durability, component.max_durability)
	return success

## Repair a tool.
func repair_tool(tool_id: String, amount: int = 1) -> void:
	var component := tool_durabilities.get(tool_id)
	if component:
		component.repair(amount)
		tool_repaired.emit(tool_id)
		durability_updated.emit(tool_id, component.current_durability, component.max_durability)

## Repair a tool to full condition.
func repair_tool_full(tool_id: String) -> void:
	var component := tool_durabilities.get(tool_id)
	if component:
		component.repair_full()
		tool_repaired.emit(tool_id)
		durability_updated.emit(tool_id, component.current_durability, component.max_durability)

## Check if a tool is broken.
func is_tool_broken(tool_id: String) -> bool:
	var component := tool_durabilities.get(tool_id)
	return component and component.is_broken()

## Check if a tool is usable.
func is_tool_usable(tool_id: String) -> bool:
	var component := tool_durabilities.get(tool_id)
	return component and component.is_usable()

## Get tool durability ratio.
func get_tool_ratio(tool_id: String) -> float:
	var component := tool_durabilities.get(tool_id)
	if component:
		return component.get_durability_ratio()
	return 1.0

## Get tool state.
func get_tool_state(tool_id: String) -> int:
	var component := tool_durabilities.get(tool_id)
	if component:
		return component.get_state()
	return 0

## Get all durability data for saving.
func serialize_all() -> Dictionary:
	var data := {}
	for tool_id in tool_durabilities:
		var component := tool_durabilities[tool_id]
		data[tool_id] = component.serialize()
	return data

## Restore durability from save data.
func deserialize_all(data: Dictionary) -> void:
	for tool_id in data:
		var component := tool_durabilities.get(tool_id)
		if component:
			component.deserialize(data[tool_id])
		else:
			# Create new component if not exists
			register_tool(tool_id)
			tool_durabilities[tool_id].deserialize(data[tool_id])

## Get tool count.
func get_tool_count() -> int:
	return tool_durabilities.size()

## Clear all durability data.
func clear_all() -> void:
	tool_durabilities.clear()
