## Generic storage capability for a placed object: how many slots, how much
## weight, what the slot filters accept, and any default contents. The same
## runtime path serves chests, fuel hoppers, and station inputs/outputs.
class_name ContainerProfile
extends Resource

## Fixed number of indexed slots.
@export var slot_count: int = 27

## Total weight capacity across all slots.
@export var max_weight: float = 200.0

## Item tags accepted in every slot; empty accepts everything. Fuel hoppers
## would author ["fuel"] here instead of code listing item ids.
@export var accepted_tags: PackedStringArray = PackedStringArray()

## Starting contents: [{item_id, quantity}] filled into slots in order.
@export var default_contents: Array[Dictionary] = []

func accepts_item(item: ItemDefinition) -> bool:
	if item == null:
		return false
	if accepted_tags.is_empty():
		return true
	for tag in accepted_tags:
		if item.has_tag(tag):
			return true
	return false

func validate() -> Array[String]:
	var errors: Array[String] = []
	if slot_count <= 0:
		errors.append("slot_count (%d) must be positive" % slot_count)
	if max_weight < 0.0:
		errors.append("max_weight (%.1f) must be zero or positive" % max_weight)
	for index in range(default_contents.size()):
		var entry: Dictionary = default_contents[index]
		if str(entry.get("item_id", "")).is_empty():
			errors.append("default_contents[%d] has no item_id" % index)
		elif int(entry.get("quantity", 0)) <= 0:
			errors.append("default_contents[%d] (%s) has a non-positive quantity" % \
					[index, str(entry.get("item_id"))])
	return errors
