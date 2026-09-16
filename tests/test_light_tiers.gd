## Coverage for round, tier-scaled local lights:
## 1. Placed-object light masks use the player's centred radial geometry
##    (a bare FILL_RADIAL defaults to a corner-anchored quarter disc).
## 2. Building light profiles scale with building tier in data
##    (metal > stone > wood), with the pinned primitive values untouched.
## 3. Handheld light items scale glow strength with their rarity tier in
##    data (common torch < uncommon stone lantern < rare iron lantern) and
##    are accepted by the tag-driven light slot; the player's held light
##    follows the equipped tier.
## Run: godot --headless --path . --script tests/test_light_tiers.gd
extends SceneTree

var _failures := 0
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_shared_radial_geometry()
	_test_building_profile_tiers()
	_test_handheld_light_items()
	_test_player_light_follows_tier()
	print("Light tier failures: %d (%d checks)" % [_failures, _checks])
	quit(_failures)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures += 1
		push_error("[FAIL] %s" % label)

## First PointLight2D child of a placed building (its light capability node).
func _building_light(building: Building) -> PointLight2D:
	for child in building.get_children():
		if child is PointLight2D:
			return child
	return null

# --- 1. Round geometry: shared building mask == player held-light mask ---

func _test_shared_radial_geometry() -> void:
	var registry := BuildingContentRegistry.new()
	registry.discover()
	var definition := registry.get_definition("hearth")
	var building := Building.new()
	building.setup("hearth", "Stone Hearth", Vector2i(0, 0), 90, 0, definition)
	var light := _building_light(building)
	_check(light != null, "A placed hearth owns a profile-driven PointLight2D")
	if light == null or not light.texture is GradientTexture2D:
		return
	var mask: GradientTexture2D = light.texture
	_check(mask.fill == GradientTexture2D.FILL_RADIAL,
			"Shared building light mask is a radial gradient")
	_check(mask.width == 128 and mask.height == 128,
			"Shared building light mask keeps the 128 px size the player light uses")
	_check(mask.fill_from == Vector2(0.5, 0.5),
			"Radial fill is anchored at the texture centre (round halo)")
	_check(mask.fill_to == Vector2(0.5, 0.0),
			"Radial edge sits at half height (centred circle, not a corner quarter disc)")
	_check(light.blend_mode == Light2D.BLEND_MODE_ADD,
			"Placed lights blend additively like the player's held light")
	_check(is_equal_approx(light.texture_scale, 112.0 / 64.0),
			"Texture scale maps the 128 px mask to the profile radius")
	# The two masks are separate resources but must share the exact centred
	# geometry, so placed lights and the carried light read as one effect.
	var world := Node.new()
	root.add_child(world)
	var database := ItemDatabase.new()
	database.name = "ItemDatabase"
	database.initialize()
	world.add_child(database)
	var player := Player.new()
	player.name = "Player"
	world.add_child(player)
	var held: PointLight2D = player.get_node_or_null("HeldLight")
	_check(held != null and held.texture is GradientTexture2D,
			"The player's held light still uses a gradient mask")
	if held != null and held.texture is GradientTexture2D:
		var held_mask: GradientTexture2D = held.texture
		_check(held_mask.fill == mask.fill and held_mask.width == mask.width
				and held_mask.height == mask.height
				and held_mask.fill_from == mask.fill_from
				and held_mask.fill_to == mask.fill_to,
				"Player held light and shared building mask share one centred radial geometry")
	world.queue_free()

# --- 2. Building light tiers are data (LightProfile values, not code) ---

func _test_building_profile_tiers() -> void:
	var registry := BuildingContentRegistry.new()
	registry.discover()
	# Pinned primitive values must not drift when tiers are added.
	var torch := registry.get_definition("torch").light_profile as LightProfile
	var campfire := registry.get_definition("campfire").light_profile as LightProfile
	var furnace := registry.get_definition("furnace").light_profile as LightProfile
	_check(torch != null and torch.resource_name == "light_torch"
			and is_equal_approx(torch.radius_px, 80.0) and is_equal_approx(torch.energy, 1.0),
			"torch keeps its pinned primitive profile (80 px, 1.0)")
	_check(campfire != null and campfire.resource_name == "light_campfire"
			and is_equal_approx(campfire.radius_px, 96.0) and is_equal_approx(campfire.energy, 1.1),
			"campfire keeps its pinned primitive profile (96 px, 1.1)")
	_check(furnace != null and furnace.resource_name == "light_furnace"
			and is_equal_approx(furnace.radius_px, 64.0) and is_equal_approx(furnace.energy, 0.9),
			"furnace keeps its pinned primitive profile (64 px, 0.9)")
	# The lantern families carry the tier-scaled profiles.
	var yard := registry.get_definition("yard_lantern").light_profile as LightProfile
	var hearth := registry.get_definition("hearth").light_profile as LightProfile
	var brazier := registry.get_definition("brazier").light_profile as LightProfile
	var metal := registry.get_definition("metal_lantern").light_profile as LightProfile
	_check(yard != null and yard.resource_name == "light_torch",
			"yard_lantern (wood tier) stays on the wood-tier torch baseline")
	_check(hearth != null and hearth.resource_name == "light_stone"
			and is_equal_approx(hearth.radius_px, 112.0) and is_equal_approx(hearth.energy, 1.35),
			"hearth (stone tier) re-points to the stronger stone profile")
	_check(brazier != null and brazier.resource_name == "light_stone",
			"brazier (stone tier) re-points to the stronger stone profile")
	_check(metal != null and metal.resource_name == "light_metal"
			and is_equal_approx(metal.radius_px, 144.0) and is_equal_approx(metal.energy, 1.7),
			"metal_lantern (metal tier) re-points to the strongest metal profile")
	_check(metal != null and hearth != null
			and metal.radius_px > hearth.radius_px and hearth.radius_px > yard.radius_px
			and metal.energy > hearth.energy and hearth.energy > yard.energy,
			"Building light strength scales with tier: metal > stone > wood")
	for profile in [hearth, brazier, metal]:
		if profile != null:
			_check(profile.validate().is_empty(),
					"%s light profile passes authoring validation" % profile.resource_name)

# --- 3. Handheld light items scale with their rarity tier (data) ---

func _test_handheld_light_items() -> void:
	var database := ItemDatabase.new()
	database.initialize()
	var light_items := database.get_items_with_tag("light_source")
	_check(light_items == ["iron_lantern", "stone_lantern", "torch"],
			"The light_source tag now covers all three handheld tiers (sorted data query)")
	var torch := database.get_item("torch")
	var stone_lantern := database.get_item("stone_lantern")
	var iron_lantern := database.get_item("iron_lantern")
	_check(torch != null and torch.rarity == "common"
			and is_equal_approx(torch.light_radius_px, 200.0)
			and is_equal_approx(torch.light_energy, 1.25),
			"torch keeps its pinned common-tier glow (200 px, 1.25)")
	_check(stone_lantern != null and stone_lantern.rarity == "uncommon"
			and is_equal_approx(stone_lantern.light_radius_px, 264.0)
			and is_equal_approx(stone_lantern.light_energy, 1.6)
			and stone_lantern.has_tag("light_source"),
			"stone_lantern is an uncommon-tier light with a stronger glow in data")
	_check(iron_lantern != null and iron_lantern.rarity == "rare"
			and is_equal_approx(iron_lantern.light_radius_px, 336.0)
			and is_equal_approx(iron_lantern.light_energy, 2.0)
			and iron_lantern.has_tag("light_source"),
			"iron_lantern is a rare-tier light with the strongest glow in data")
	_check(stone_lantern != null and iron_lantern != null and torch != null
			and iron_lantern.light_radius_px > stone_lantern.light_radius_px
			and stone_lantern.light_radius_px > torch.light_radius_px
			and iron_lantern.light_energy > stone_lantern.light_energy
			and stone_lantern.light_energy > torch.light_energy,
			"Handheld glow strength scales with item tier: rare > uncommon > common")
	_check(stone_lantern != null and not stone_lantern.has_tag("fuel")
			and iron_lantern != null and not iron_lantern.has_tag("fuel"),
			"Handheld lights are light sources, not building fuel (tag discipline)")
	var stone_recipe := database.get_recipe("stone_lantern")
	var iron_recipe := database.get_recipe("iron_lantern")
	_check(stone_recipe != null and stone_recipe.crafting_station == "workbench"
			and stone_recipe.technology_id == "stone_building",
			"stone_lantern is crafted at the workbench behind stone research")
	_check(iron_recipe != null and iron_recipe.crafting_station == "workbench"
			and iron_recipe.technology_id == "metalworking",
			"iron_lantern is crafted at the workbench behind metalworking research")
	for item in [stone_lantern, iron_lantern]:
		if item != null:
			_check(not item.texture_path.is_empty() and FileAccess.file_exists(item.texture_path),
					"%s pickup icon resolves to an existing asset" % item.item_id)

# --- 4. The player's held light follows the equipped tier ---

func _test_player_light_follows_tier() -> void:
	var world := Node.new()
	root.add_child(world)
	var database := ItemDatabase.new()
	database.name = "ItemDatabase"
	database.initialize()
	world.add_child(database)
	var player := Player.new()
	player.name = "Player"
	world.add_child(player)
	var held_light: PointLight2D = player.get_node_or_null("HeldLight")
	_check(held_light != null, "The player carries a held light")
	if held_light == null:
		world.queue_free()
		return
	player.equipment.get_slot_storage("light").add_item("stone_lantern", 1)
	_check(player.toggle_held_light() == "lit" and held_light.visible,
			"L lights the equipped uncommon stone lantern")
	_check(is_equal_approx(held_light.energy, 1.6)
			and is_equal_approx(held_light.texture_scale, 264.0 * 2.0 / 128.0),
			"Held light reads radius/energy from the stone lantern's tier data")
	player.equipment.get_slot_storage("light").clear()
	_check(not held_light.visible,
			"Unequipping the light hides the held light")
	player.equipment.get_slot_storage("light").add_item("iron_lantern", 1)
	_check(held_light.visible,
			"Re-equipping a stronger tier keeps the light on (toggle state persists)")
	_check(is_equal_approx(held_light.energy, 2.0)
			and is_equal_approx(held_light.texture_scale, 336.0 * 2.0 / 128.0),
			"Held light upgrades to the rare iron lantern's stronger glow")
	player.equipment.get_slot_storage("light").clear()
	player.equipment.get_slot_storage("light").add_item("torch", 1)
	_check(is_equal_approx(held_light.energy, 1.25)
			and is_equal_approx(held_light.texture_scale, 200.0 * 2.0 / 128.0),
			"Downgrading to the common torch steps the glow back down in data")
	world.queue_free()
