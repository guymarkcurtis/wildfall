## Animated visual states for a placed object, authored as data: which sheet
## to use, its frame grid, and the named state sequences (open/closed,
## unlit/ignite/burning...). State changes come from capability events, never
## building-id checks. The legacy atlas cell remains the fallback while a
## definition ships without an appearance profile.
class_name AppearanceProfile
extends Resource

## State-sheet PNG (vertical 1-column strip). Empty = no state sheet yet;
## the building falls back to its legacy atlas cell or colour placeholder.
@export var sheet_path: String = ""

## Pixel size of one frame (32x32 this pass).
@export var frame_size: Vector2i = Vector2i(32, 32)

## Named state sequences: state name -> {first_frame: int, frame_count: int,
## fps: float, loop: bool}. Authored data; the runtime interprets it.
@export var states: Dictionary = {}

## State to show when the object spawns (e.g. "closed" / "unlit").
@export var initial_state: String = ""

## Interaction transition states. Empty fields opt a profile out of that
## transition; content chooses its own state names, never the runtime.
@export var interaction_opening_state: String = ""
@export var interaction_open_state: String = ""
@export var interaction_closing_state: String = ""
@export var interaction_closed_state: String = ""

## Capability-state presentation for fuelled/toggled objects. These state
## names are authored per profile, allowing a fire, furnace, torch, or future
## object to use its own animation vocabulary without runtime name branches.
@export var powered_state: String = ""
@export var unpowered_state: String = ""

## Optional in-use presentation for stations: shown while the player has
## this station's panel open (e.g. a workbench being worked), and cleared
## back to initial_state when it closes. Empty opts the profile out.
@export var crafting_state: String = ""

func validate() -> Array[String]:
	var errors: Array[String] = []
	if frame_size.x <= 0 or frame_size.y <= 0:
		errors.append("frame_size %s must be positive on both axes" % str(frame_size))
	if not sheet_path.is_empty() and not FileAccess.file_exists(sheet_path):
		errors.append("sheet_path '%s' does not exist" % sheet_path)
	for state_name in states:
		var state: Variant = states[state_name]
		if typeof(state) != TYPE_DICTIONARY:
			errors.append("state '%s' must be a dictionary with first_frame/frame_count" % str(state_name))
			continue
		if int(state.get("frame_count", 0)) <= 0:
			errors.append("state '%s' has a non-positive frame_count" % str(state_name))
	if not initial_state.is_empty() and not states.has(initial_state):
		errors.append("initial_state '%s' is not a named state" % initial_state)
	for state_name in [interaction_opening_state, interaction_open_state,
			interaction_closing_state, interaction_closed_state, powered_state,
			unpowered_state, crafting_state]:
		if not state_name.is_empty() and not states.has(state_name):
			errors.append("interaction state '%s' is not a named state" % state_name)
	return errors
