## How the interaction router treats a placed object: the verb, the range,
## the HUD prompt, and which panel kind opens. Attached to a
## BuildingDefinition by reference — never selected by item id in code.
class_name InteractionProfile
extends Resource

## Interaction verb shown in the prompt ("Open", "Use", ...).
@export var verb: String = "Open"

## Maximum interaction distance in pixels from the player.
@export var range_px: float = 64.0

## HUD prompt subject, e.g. "Wood Chest" -> "E Open Wood Chest".
## Empty falls back to the building's display name.
@export var prompt: String = ""

## Which shared panel opens: "container", "station", or "none" (custom/later).
@export_enum("container", "station", "none") var ui_kind: String = "container"

func validate() -> Array[String]:
	var errors: Array[String] = []
	if verb.strip_edges() == "":
		errors.append("interaction verb is empty; the HUD prompt needs a verb")
	if range_px <= 0.0:
		errors.append("range_px (%.1f) must be positive" % range_px)
	return errors
