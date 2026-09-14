## Fuel-burning capability: which item tags are accepted, burn seconds per
## unit, how many fuel slots exist, and the consumption cadence. Acceptance
## is a tag query over ItemDefinition.tags — never a named item list.
class_name FuelProfile
extends Resource

## Item tags accepted as fuel (shipped vocabulary: "fuel").
@export var accepted_tags: PackedStringArray = PackedStringArray(["fuel"])

## Burn seconds granted per single accepted item.
@export var seconds_per_unit: float = 300.0

## Number of fuel slots (1 this pass).
@export var fuel_slot_count: int = 1

## How often the remaining burn time ticks down, in seconds.
@export var consume_cadence_seconds: float = 1.0

## Whether the interaction panel offers an on/off toggle.
@export var manual_toggle: bool = true

func validate() -> Array[String]:
	var errors: Array[String] = []
	if accepted_tags.is_empty():
		errors.append("accepted_tags is empty; this fuel consumer could accept nothing")
	if seconds_per_unit <= 0.0:
		errors.append("seconds_per_unit (%.1f) must be positive" % seconds_per_unit)
	if fuel_slot_count <= 0:
		errors.append("fuel_slot_count (%d) must be positive" % fuel_slot_count)
	if consume_cadence_seconds <= 0.0:
		errors.append("consume_cadence_seconds (%.1f) must be positive" % consume_cadence_seconds)
	return errors
