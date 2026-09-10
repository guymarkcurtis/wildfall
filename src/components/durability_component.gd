## Manages tool durability and wear.
class_name DurabilityComponent
extends Node

const MAX_DURABILITY: int = 100

# Tool states
enum ToolState {
	PERFECT,      # 100-80%
	USED,         # 79-50%
	WORN,         # 49-20%
	BROKEN        # 19-0%
}

# Current durability
var current_durability: int = MAX_DURABILITY
var max_durability: int = MAX_DURABILITY
var tool_id: String = ""

# Signals
signal durability_changed(current: int, max: int)
signal tool_broken
signal tool_repaired

## Initialize with a tool.
func initialize(tool_id: String, max_durability: int = MAX_DURABILITY) -> void:
	self.tool_id = tool_id
	self.max_durability = max_durability
	self.current_durability = max_durability
	durability_changed.emit(current_durability, max_durability)

## Get the current tool state.
func get_state() -> ToolState:
	var ratio: float = float(current_durability) / float(max_durability)
	if ratio >= 0.8:
		return ToolState.PERFECT
	elif ratio >= 0.5:
		return ToolState.USED
	elif ratio >= 0.2:
		return ToolState.WORN
	else:
		return ToolState.BROKEN

## Get durability ratio (0.0 to 1.0).
func get_durability_ratio() -> float:
	return clamp(float(current_durability) / float(max_durability), 0.0, 1.0)

## Check if tool is broken.
func is_broken() -> bool:
	return current_durability <= 0

## Check if tool is usable.
func is_usable() -> bool:
	return current_durability > 0

## Use the tool (decrease durability).
func use(amount: int = 1) -> bool:
	if is_broken():
		return false
	
	current_durability = max(0, current_durability - amount)
	durability_changed.emit(current_durability, max_durability)
	
	if is_broken():
		tool_broken.emit()
		return false
	
	return true

## Repair the tool.
func repair(amount: int) -> void:
	current_durability = min(max_durability, current_durability + amount)
	durability_changed.emit(current_durability, max_durability)
	tool_repaired.emit()

## Repair to full condition.
func repair_full() -> void:
	current_durability = max_durability
	durability_changed.emit(current_durability, max_durability)
	tool_repaired.emit()

## Get durability color based on state.
func get_color() -> Color:
	match get_state():
		ToolState.PERFECT:
			return Color(0.3, 0.8, 0.3)  # Green
		ToolState.USED:
			return Color(0.8, 0.8, 0.3)  # Yellow
		ToolState.WORN:
			return Color(0.9, 0.5, 0.2)  # Orange
		ToolState.BROKEN:
			return Color(0.8, 0.3, 0.3)  # Red
		_:
			return Color(1.0, 1.0, 1.0)

## Get durability as string.
func get_durability_string() -> String:
	return "%d/%d" % [current_durability, max_durability]

## Serialize durability state.
func serialize() -> Dictionary:
	return {
		"tool_id": tool_id,
		"current_durability": current_durability,
		"max_durability": max_durability
	}

## Deserialize durability state.
func deserialize(data: Dictionary) -> void:
	tool_id = data.get("tool_id", "")
	current_durability = data.get("current_durability", max_durability)
	max_durability = data.get("max_durability", MAX_DURABILITY)
	durability_changed.emit(current_durability, max_durability)
