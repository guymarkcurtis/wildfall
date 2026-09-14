## Local-light capability for a placed object: radius, colour, energy,
## flicker, when the light is allowed to shine, and whether it needs power.
## Lights are cosmetic this pass (no AI/stealth/growth effects).
class_name LightProfile
extends Resource

## Light radius in pixels (drives the shared radial mask scale).
@export var radius_px: float = 96.0

@export var color: Color = Color(1.0, 0.82, 0.55, 1.0)

@export var energy: float = 1.0

## Add a subtle flicker (sinusoidal, not a per-frame tween).
@export var flicker: bool = false

## "night_only" shines at night/twilight; "always" ignores the clock.
@export_enum("night_only", "always") var daylight_policy: String = "night_only"

## When true the light only shines while the object is enabled/fuelled.
@export var requires_power: bool = true

func validate() -> Array[String]:
	var errors: Array[String] = []
	if radius_px <= 0.0:
		errors.append("radius_px (%.1f) must be positive" % radius_px)
	if energy < 0.0:
		errors.append("energy (%.2f) must be zero or positive" % energy)
	if daylight_policy != "night_only" and daylight_policy != "always":
		errors.append("daylight_policy '%s' is not supported (supported: night_only, always)" % daylight_policy)
	return errors
