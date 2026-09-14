## Vertical-connector capability for a placed object (stairs first; later
## ladders, hatches, portals). The generic traversal runtime reads this
## profile from the BuildingDefinition — never the item id.
class_name ConnectorProfile
extends Resource

## Story the upper landing sits on, relative to the connector's own story
## (1 = one story up this pass).
@export var upper_story_offset: int = 1

## When true the connector reserves the floor slot directly above its tile as
## the stairwell opening: no floor can be placed there, and the connector's
## own record owns both landings.
@export var reserve_stairwell: bool = true

## Interaction radius around the landing centre that triggers traversal.
@export var trigger_radius_px: float = 14.0

func validate() -> Array[String]:
	var errors: Array[String] = []
	if upper_story_offset < 1:
		errors.append("upper_story_offset (%d) must be at least 1 this pass" % upper_story_offset)
	if trigger_radius_px <= 0.0:
		errors.append("trigger_radius_px (%.1f) must be positive" % trigger_radius_px)
	return errors
