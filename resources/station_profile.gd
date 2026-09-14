## Crafting-station capability for a placed object: which recipe group it
## serves, how many persistent input/output slots it owns, and whether it
## must be powered (fuelled) to craft. Recipe matching queries the group
## key against RecipeDefinition.crafting_station values — no station names
## in gameplay code.
class_name StationProfile
extends Resource

## Recipe group this station serves; matches RecipeDefinition.crafting_station.
@export var recipe_group: String = ""

## Persistent ingredient slots (InventoryStorage indexes).
@export var input_slot_count: int = 0

## Persistent output slots; the craft result lands here (usually 1).
@export var output_slot_count: int = 1

## Shared capacity across each persistent station surface. Kept on the
## profile so saves cannot inflate a station by editing max_weight.
@export var max_weight: float = 200.0

## When true the station only crafts while its fuel/toggle state is enabled.
@export var requires_power: bool = false

## "immediate" this pass; timed queues are a documented later extension.
@export var queue_policy: String = "immediate"

func validate() -> Array[String]:
	var errors: Array[String] = []
	if recipe_group.strip_edges() == "":
		errors.append("recipe_group is empty; the station could not serve any recipes")
	if input_slot_count < 0:
		errors.append("input_slot_count (%d) must be zero or positive" % input_slot_count)
	if output_slot_count < 0:
		errors.append("output_slot_count (%d) must be zero or positive" % output_slot_count)
	if max_weight < 0.0:
		errors.append("max_weight (%.1f) must be zero or positive" % max_weight)
	if queue_policy != "immediate":
		errors.append("queue_policy '%s' is not supported (supported: immediate)" % queue_policy)
	return errors
