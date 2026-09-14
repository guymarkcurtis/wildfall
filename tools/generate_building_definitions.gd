## One-shot authoring tool: writes every BuildingDefinition .tres under
## data/buildings/ and the shared capability profiles under
## data/interactables/, replacing BuildingManager's former hard-coded
## _init_definitions() table. Values are pinned to that table exactly
## (same ids, display names, tiers, health, costs) so placement, recipes,
## and old saves resolve unchanged.
##
## Run: godot --headless --path . --script tools/generate_building_definitions.gd
extends SceneTree

const BUILDINGS_DIR := "res://data/buildings"
const PROFILES_DIR := "res://data/interactables"
const PARTS_SHEET := "res://assets/tiles/wildfall-building-parts.png"
const UTILITIES_SHEET := "res://assets/tiles/wildfall-building-utilities.png"
const STATIONS_SHEET := "res://assets/tiles/wildfall-crafting-stations.png"
const PARTS_ROW_ORDER := ["foundation", "floor", "wall", "window", "door", "roof", "stair", "ramp", "pillar"]
const UTILITY_CELL_INDEX := {"torch": 0, "bed": 1, "chest": 2, "farm_soil": 3, "fence": 4}
const STATION_CELL_INDEX := {"campfire": 0, "furnace": 1, "workbench": 2, "anvil": 3}

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BUILDINGS_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROFILES_DIR))
	_write_profiles()
	_write_buildings()
	print("Building definitions: %d files, profiles: %d files" % \
			[_count_tres(BUILDINGS_DIR), _count_tres(PROFILES_DIR)])
	quit(0)

func _count_tres(directory: String) -> int:
	var dir := DirAccess.open(directory)
	var count := 0
	for file_name in dir.get_files():
		if file_name.ends_with(".tres"):
			count += 1
	return count

func _write_profiles() -> void:
	_save_profile("interaction_open.tres", _profile(InteractionProfile, {"verb": "Open", "range_px": 64.0, "ui_kind": "container"}))
	_save_profile("interaction_use.tres", _profile(InteractionProfile, {"verb": "Use", "range_px": 64.0, "ui_kind": "station"}))
	_save_profile("chest_container.tres", _profile(ContainerProfile, {"slot_count": 27, "max_weight": 200.0}))
	_save_profile("station_workbench.tres", _profile(StationProfile, {"recipe_group": "workbench", "input_slot_count": 2, "output_slot_count": 1}))
	_save_profile("station_campfire.tres", _profile(StationProfile, {"recipe_group": "campfire", "input_slot_count": 1, "output_slot_count": 1, "requires_power": true}))
	_save_profile("station_furnace.tres", _profile(StationProfile, {"recipe_group": "furnace", "input_slot_count": 1, "output_slot_count": 1, "requires_power": true}))
	_save_profile("station_anvil.tres", _profile(StationProfile, {"recipe_group": "anvil", "input_slot_count": 2, "output_slot_count": 1}))
	_save_profile("fuel_burnable.tres", _profile(FuelProfile, {"accepted_tags": PackedStringArray(["fuel"]), "seconds_per_unit": 300.0, "fuel_slot_count": 1, "consume_cadence_seconds": 1.0, "manual_toggle": true}))
	_save_profile("stair_connector.tres", _profile(ConnectorProfile, {"upper_story_offset": 1, "reserve_stairwell": true, "trigger_radius_px": 14.0}))
	_save_profile("light_campfire.tres", _profile(LightProfile, {"radius_px": 96.0, "color": Color(1.0, 0.72, 0.42), "energy": 1.1, "flicker": true, "daylight_policy": "night_only", "requires_power": true}))
	_save_profile("light_furnace.tres", _profile(LightProfile, {"radius_px": 64.0, "color": Color(1.0, 0.62, 0.35), "energy": 0.9, "flicker": false, "daylight_policy": "night_only", "requires_power": true}))
	_save_profile("light_torch.tres", _profile(LightProfile, {"radius_px": 80.0, "color": Color(1.0, 0.8, 0.5), "energy": 1.0, "flicker": true, "daylight_policy": "night_only", "requires_power": true}))

func _profile(script: GDScript, values: Dictionary) -> Resource:
	var resource: Resource = script.new()
	for key in values:
		resource.set(key, values[key])
	return resource

func _save_profile(file_name: String, profile: Resource) -> void:
	profile.resource_name = file_name.get_basename()
	var path := "%s/%s" % [PROFILES_DIR, file_name]
	var error := ResourceSaver.save(profile, path)
	if error != OK:
		push_error("Could not save %s (error %d)" % [path, error])

func _write_buildings() -> void:
	# Id, display name, part_type, tier, technology, max_health,
	# blocks_movement, requires_lower_support, cost. Pinned to the exact
	# values the former BuildingManager._init_definitions() authored.
	var table := [
		["wooden_foundation", "Wood Foundation", "foundation", "wood", "wood_building", 90, false, false, [{"item_id": "plank", "quantity": 2}]],
		["wooden_floor", "Wood Floor", "floor", "wood", "wood_building", 70, false, true, [{"item_id": "plank", "quantity": 1}]],
		["wooden_wall", "Wood Wall", "wall", "wood", "wood_building", 100, true, true, [{"item_id": "plank", "quantity": 3}]],
		["wooden_window", "Wood Window", "window", "wood", "wood_building", 80, true, true, [{"item_id": "plank", "quantity": 2}, {"item_id": "glass", "quantity": 1}]],
		# Doors no longer block movement (M2): a door is the walkable opening
		# in a wall edge, which is what makes a built room enterable.
		["wooden_door", "Wood Door", "door", "wood", "wood_building", 90, false, true, [{"item_id": "plank", "quantity": 3}]],
		["wooden_roof", "Wood Roof", "roof", "wood", "wood_building", 75, false, true, [{"item_id": "plank", "quantity": 2}]],
		["wooden_stairs", "Wood Stairs", "stair", "wood", "wood_building", 80, false, true, [{"item_id": "plank", "quantity": 3}]],
		["wooden_ramp", "Wood Ramp", "ramp", "wood", "wood_building", 80, false, true, [{"item_id": "plank", "quantity": 2}]],
		["wooden_pillar", "Wood Pillar", "pillar", "wood", "wood_building", 120, true, true, [{"item_id": "plank", "quantity": 2}]],
		["stone_foundation", "Stone Foundation", "foundation", "stone", "stone_building", 180, false, false, [{"item_id": "stone_brick", "quantity": 2}]],
		["stone_floor", "Stone Floor", "floor", "stone", "stone_building", 150, false, true, [{"item_id": "stone_brick", "quantity": 1}]],
		["stone_wall", "Stone Wall", "wall", "stone", "stone_building", 220, true, true, [{"item_id": "stone_brick", "quantity": 3}]],
		["stone_window", "Stone Window", "window", "stone", "stone_building", 180, true, true, [{"item_id": "stone_brick", "quantity": 2}, {"item_id": "glass", "quantity": 1}]],
		["stone_door", "Stone Door", "door", "stone", "stone_building", 190, false, true, [{"item_id": "stone_brick", "quantity": 3}]],
		["stone_roof", "Stone Roof", "roof", "stone", "stone_building", 160, false, true, [{"item_id": "stone_brick", "quantity": 2}]],
		["stone_stairs", "Stone Stairs", "stair", "stone", "stone_building", 180, false, true, [{"item_id": "stone_brick", "quantity": 3}]],
		["stone_ramp", "Stone Ramp", "ramp", "stone", "stone_building", 170, false, true, [{"item_id": "stone_brick", "quantity": 2}]],
		["stone_pillar", "Stone Pillar", "pillar", "stone", "stone_building", 260, true, true, [{"item_id": "stone_brick", "quantity": 2}]],
	]
	for entry in table:
		_save_building(entry[0], entry[1], entry[2], entry[3], entry[4], entry[5], entry[6], entry[7], entry[8])
	# Utilities: display names exactly as ItemDatabase spells them.
	var utility_names := {"torch": "Torch", "campfire": "Campfire", "furnace": "Furnace",
			"workbench": "Workbench", "anvil": "Anvil", "chest": "Chest",
			"bed": "Bed", "farm_soil": "Farm Soil", "fence": "Fence"}
	for item_id in utility_names:
		_save_building(item_id, utility_names[item_id], "utility", "primitive", "", 50, item_id == "fence", false, [])
	# Capability references (profile assets are saved first, so these load
	# as external ExtResource references).
	_attach("chest", "res://data/interactables/interaction_open.tres", "interaction_profile")
	_attach("chest", "res://data/interactables/chest_container.tres", "container_profile")
	for station_id in ["workbench", "campfire", "furnace", "anvil"]:
		_attach(station_id, "res://data/interactables/interaction_use.tres", "interaction_profile")
		_attach(station_id, "res://data/interactables/station_%s.tres" % station_id, "station_profile")
	for fuelled in ["campfire", "furnace", "torch"]:
		_attach(fuelled, "res://data/interactables/interaction_use.tres", "interaction_profile")
		_attach(fuelled, "res://data/interactables/fuel_burnable.tres", "fuel_profile")
		_attach(fuelled, "res://data/interactables/light_%s.tres" % fuelled, "light_profile")
	for stairs in ["wooden_stairs", "stone_stairs"]:
		_attach(stairs, "res://data/interactables/stair_connector.tres", "connector_profile")

func _attach(item_id: String, profile_path: String, property: String) -> void:
	var path := "%s/%s.tres" % [BUILDINGS_DIR, item_id]
	var definition: BuildingDefinition = load(path)
	if definition == null:
		push_error("Missing %s while attaching %s" % [path, profile_path])
		return
	definition.set(property, load(profile_path))
	ResourceSaver.save(definition, path)

func _save_building(item_id: String, display_name: String, part_type: String, tier: String,
		technology_id: String, max_health: int, blocks_movement: bool,
		requires_lower_support: bool, cost: Array) -> void:
	var definition := BuildingDefinition.new()
	definition.id = item_id
	definition.display_name = display_name
	definition.part_type = part_type
	definition.tier = tier
	definition.technology_id = technology_id
	definition.max_health = max_health
	definition.blocks_movement = blocks_movement
	definition.requires_lower_support = requires_lower_support
	var typed_cost: Array[Dictionary] = []
	for entry in cost:
		typed_cost.append(entry)
	definition.build_cost = typed_cost
	definition.visual_family_id = tier
	# M2 placement model: edge parts orient to the four tile edges; doors and
	# windows are edge fixtures that may replace a plain wall on the same
	# edge; supported parts require the "structure" tag below them.
	if part_type in ["wall", "window", "door"]:
		definition.allowed_orientations = PackedStringArray(["north", "east", "south", "west"])
	if part_type in ["window", "door"]:
		definition.occupancy_replacement = "edge_fixture"
	if requires_lower_support:
		definition.required_support_tags = PackedStringArray(["structure"])
	# Atlas metadata mirrors Building's legacy lookup tables so a later
	# milestone can move rendering onto definition data without visual change.
	if tier == "wood" or tier == "stone":
		definition.atlas_path = PARTS_SHEET
		definition.atlas_cell = Vector2i(0 if tier == "wood" else 1, PARTS_ROW_ORDER.find(part_type))
		definition.support_tags = PackedStringArray(["cover"] if part_type == "roof" else ["structure"])
	elif UTILITY_CELL_INDEX.has(item_id):
		definition.atlas_path = UTILITIES_SHEET
		definition.atlas_cell = Vector2i(int(UTILITY_CELL_INDEX[item_id]), 0)
	elif STATION_CELL_INDEX.has(item_id):
		definition.atlas_path = STATIONS_SHEET
		definition.atlas_cell = Vector2i(int(STATION_CELL_INDEX[item_id]), 0)
	var path := "%s/%s.tres" % [BUILDINGS_DIR, item_id]
	var error := ResourceSaver.save(definition, path)
	if error != OK:
		push_error("Could not save %s (error %d)" % [path, error])
