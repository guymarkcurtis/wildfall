## One-shot authoring tool: writes the BuildingDefinition .tres files it owns
## under data/buildings/ and the shared capability profiles under
## data/interactables/. Values are pinned to the M9 art contract
## (BUILDING_ART_REQUESTS.md 6.1-6.4): wood/stone structural parts map onto
## the tier structural sheets, the boundary/interior/exterior utility parts
## map onto their M9 sheets, and torch/chest/stations keep their legacy
## utility and station cells (contract 6.3). Re-running this tool must not
## touch hand-authored definition files.
##
## Run: godot --headless --path . --script tools/generate_building_definitions.gd
extends SceneTree

const BUILDINGS_DIR := "res://data/buildings"
const PROFILES_DIR := "res://data/interactables"
# M9 sheets. Legacy sheets are kept for the parts the contract leaves on
# their old cells (6.3): torch + chest on utilities, stations on stations.
const STRUCTURAL_SHEET_FMT := "res://assets/tiles/building/structural_%s.png"
const BOUNDARIES_WOOD_SHEET := "res://assets/tiles/building/boundaries_wood.png"
const INTERIOR_WOOD_SHEET := "res://assets/tiles/building/interior_wood.png"
const EXTERIOR_SHEET := "res://assets/tiles/building/exterior_props.png"
const UTILITIES_SHEET := "res://assets/tiles/wildfall-building-utilities.png"
const STATIONS_SHEET := "res://assets/tiles/wildfall-crafting-stations.png"
# Master-cell address per part type on a structural tier sheet (contract
# 6.1). Wood and stone share the layout; the tier selects the sheet.
const STRUCTURAL_CELL := {
	"foundation": Vector2i(0, 0),
	"floor": Vector2i(1, 0),
	"wall": Vector2i(0, 1),
	"window": Vector2i(0, 2),
	"door": Vector2i(0, 3),
	"stair": Vector2i(0, 4),
	"roof": Vector2i(0, 5),
	"pillar": Vector2i(1, 6),
	"ramp": Vector2i(0, 7),
}
# Part types rendered per tile edge: their four edge cells are the four
# consecutive cells starting at the master cell's column (contract 6.4).
const ORIENTED_PARTS := ["wall", "window", "door", "stair"]
# Down-stair rows run from column 4 on row 4; the up-stair masters occupy
# columns 0-3 (contract 6.4).
const DOWN_STAIR_COLUMN := 4
# Legacy utility cells, per contract 6.3 (the M9 parts listed separately
# above were the only utilities moved off this sheet).
const UTILITY_CELL_INDEX := {"torch": 0, "chest": 2}
const STATION_CELL_INDEX := {"campfire": 0, "furnace": 1, "workbench": 2, "anvil": 3}
# Build-palette group per managed id (BuildingDefinition.BUILD_GROUPS).
# This is the per-def half of the data side of the M9 box-4 split: the
# vocabulary list is structural, the assignment is content data. The
# structural parts derive from their part type; the utility rows need the
# id map (fence is a "wall" part type but belongs to the boundaries group).
const BUILD_GROUP := {
	"wooden_foundation": "structure", "wooden_floor": "structure",
	"wooden_wall": "structure", "wooden_pillar": "structure",
	"stone_foundation": "structure", "stone_floor": "structure",
	"stone_wall": "structure", "stone_pillar": "structure",
	"wooden_roof": "roof_cover", "stone_roof": "roof_cover",
	"wooden_stairs": "stairs_rail", "wooden_stairs_down": "stairs_rail",
	"wooden_ramp": "stairs_rail", "stone_stairs": "stairs_rail",
	"stone_stairs_down": "stairs_rail", "stone_ramp": "stairs_rail",
	"wooden_window": "doors_windows", "wooden_door": "doors_windows",
	"stone_window": "doors_windows", "stone_door": "doors_windows",
	"torch": "exterior", "farm_soil": "exterior",
	"campfire": "stations", "furnace": "stations", "workbench": "stations",
	"anvil": "stations", "chest": "furniture", "bed": "furniture",
	"fence": "boundaries",
}

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
	_save_profile("stair_connector_down.tres", _profile(ConnectorProfile, {"upper_story_offset": -1, "reserve_stairwell": true, "trigger_radius_px": 14.0}))
	# Appearance profiles (M9 6.6): the shared fuelled profile gets the hearth
	# sheet and its lit state moves to frame 1; the four station/utility
	# consumers that own a dedicated state sheet get their own profiles.
	_save_profile("chest_appearance.tres", _profile(AppearanceProfile, {
		"sheet_path": "res://assets/tiles/interactables/wood_chest.png",
		"states": {
			"closed": {"first_frame": 0, "frame_count": 1, "fps": 1.0, "loop": false},
			"opening": {"first_frame": 1, "frame_count": 1, "fps": 8.0, "loop": false},
			"open": {"first_frame": 2, "frame_count": 1, "fps": 1.0, "loop": false},
			"closing": {"first_frame": 1, "frame_count": 1, "fps": 8.0, "loop": false}
		},
		"initial_state": "closed",
		"interaction_opening_state": "opening",
		"interaction_open_state": "open",
		"interaction_closing_state": "closing",
		"interaction_closed_state": "closed"
	}))
	_save_profile("campfire_appearance.tres", _profile(AppearanceProfile, {
		"sheet_path": "res://assets/tiles/interactables/campfire.png",
		"states": {
			"unlit": {"first_frame": 0, "frame_count": 1, "fps": 1.0, "loop": false},
			"ignition": {"first_frame": 1, "frame_count": 1, "fps": 1.0, "loop": false},
			"burn A": {"first_frame": 2, "frame_count": 3, "fps": 4.0, "loop": true}
		},
		"initial_state": "unlit",
		"powered_state": "burn A",
		"unpowered_state": "unlit"
	}))
	_save_profile("furnace_appearance.tres", _profile(AppearanceProfile, {
		"sheet_path": "res://assets/tiles/interactables/furnace.png",
		"states": {
			"cold": {"first_frame": 0, "frame_count": 1, "fps": 1.0, "loop": false},
			"heating": {"first_frame": 1, "frame_count": 1, "fps": 2.0, "loop": false},
			"lit": {"first_frame": 2, "frame_count": 1, "fps": 4.0, "loop": true}
		},
		"initial_state": "cold",
		"powered_state": "lit",
		"unpowered_state": "cold"
	}))
	_save_profile("torch_appearance.tres", _profile(AppearanceProfile, {
		"sheet_path": "res://assets/tiles/interactables/torch.png",
		"states": {
			"unlit": {"first_frame": 0, "frame_count": 1, "fps": 1.0, "loop": false},
			"ignition": {"first_frame": 1, "frame_count": 1, "fps": 1.0, "loop": false},
			"flame A": {"first_frame": 2, "frame_count": 2, "fps": 4.0, "loop": true}
		},
		"initial_state": "unlit",
		"powered_state": "flame A",
		"unpowered_state": "unlit"
	}))
	_save_profile("workbench_appearance.tres", _profile(AppearanceProfile, {
		"sheet_path": "res://assets/tiles/interactables/workbench.png",
		"states": {
			"idle": {"first_frame": 0, "frame_count": 1, "fps": 1.0, "loop": false},
			"active": {"first_frame": 1, "frame_count": 1, "fps": 1.0, "loop": false}
		},
		"initial_state": "idle",
		"crafting_state": "active"
	}))
	_save_profile("fuelled_appearance.tres", _profile(AppearanceProfile, {
		"sheet_path": "res://assets/tiles/interactables/hearth.png",
		"states": {
			"unlit": {"first_frame": 0, "frame_count": 1, "fps": 1.0, "loop": false},
			"lit": {"first_frame": 1, "frame_count": 1, "fps": 4.0, "loop": true}
		},
		"initial_state": "unlit",
		"powered_state": "lit",
		"unpowered_state": "unlit"
	}))
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
		# Down-stair rows carry a 10th table column: the atlas column offset
		# of their row (4 instead of 0), so their four edge cells sit in
		# columns 4-7 of the shared row (contract 6.4).
		["wooden_stairs_down", "Wood Stairs (down)", "stair", "wood", "wood_building", 80, false, true, [{"item_id": "plank", "quantity": 3}], DOWN_STAIR_COLUMN],
		["wooden_ramp", "Wood Ramp", "ramp", "wood", "wood_building", 80, false, true, [{"item_id": "plank", "quantity": 2}]],
		["wooden_pillar", "Wood Pillar", "pillar", "wood", "wood_building", 120, true, true, [{"item_id": "plank", "quantity": 2}]],
		["stone_foundation", "Stone Foundation", "foundation", "stone", "stone_building", 180, false, false, [{"item_id": "stone_brick", "quantity": 2}]],
		["stone_floor", "Stone Floor", "floor", "stone", "stone_building", 150, false, true, [{"item_id": "stone_brick", "quantity": 1}]],
		["stone_wall", "Stone Wall", "wall", "stone", "stone_building", 220, true, true, [{"item_id": "stone_brick", "quantity": 3}]],
		["stone_window", "Stone Window", "window", "stone", "stone_building", 180, true, true, [{"item_id": "stone_brick", "quantity": 2}, {"item_id": "glass", "quantity": 1}]],
		["stone_door", "Stone Door", "door", "stone", "stone_building", 190, false, true, [{"item_id": "stone_brick", "quantity": 3}]],
		["stone_roof", "Stone Roof", "roof", "stone", "stone_building", 160, false, true, [{"item_id": "stone_brick", "quantity": 2}]],
		["stone_stairs", "Stone Stairs", "stair", "stone", "stone_building", 180, false, true, [{"item_id": "stone_brick", "quantity": 3}]],
		["stone_stairs_down", "Stone Stairs (down)", "stair", "stone", "stone_building", 180, false, true, [{"item_id": "stone_brick", "quantity": 3}], DOWN_STAIR_COLUMN],
		["stone_ramp", "Stone Ramp", "ramp", "stone", "stone_building", 170, false, true, [{"item_id": "stone_brick", "quantity": 2}]],
		["stone_pillar", "Stone Pillar", "pillar", "stone", "stone_building", 260, true, true, [{"item_id": "stone_brick", "quantity": 2}]],
	]
	for entry in table:
		var atlas_column_offset := 0
		if entry.size() > 9:
			atlas_column_offset = entry[9]
		_save_building(entry[0], entry[1], entry[2], entry[3], entry[4], entry[5], entry[6], entry[7], entry[8],
				atlas_column_offset)
	# Utilities: display names exactly as ItemDatabase spells them. Columns:
	# id, display name, part type, tier, visual family, technology, max
	# health, blocks movement, build cost. Gameplay values are pinned to the
	# shipped hand-authored definitions; fence is the one utility authored as
	# a wall part (edge layer, four edge orientations, wood research gate,
	# plank cost, wood visual family), so its row carries those explicitly
	# instead of the plain utility defaults.
	var utility_table := [
		["torch", "Torch", "utility", "primitive", "primitive", "", 50, false, []],
		["campfire", "Campfire", "utility", "primitive", "primitive", "", 50, false, []],
		["furnace", "Furnace", "utility", "primitive", "primitive", "", 50, false, []],
		["workbench", "Workbench", "utility", "primitive", "primitive", "", 50, false, []],
		["anvil", "Anvil", "utility", "primitive", "primitive", "", 50, false, []],
		["chest", "Chest", "utility", "primitive", "primitive", "", 50, false, []],
		["bed", "Bed", "utility", "primitive", "primitive", "", 50, false, []],
		["farm_soil", "Farm Soil", "utility", "primitive", "primitive", "", 50, false, []],
		["fence", "Fence", "wall", "wood", "wood", "wood_building", 50, true, [{"item_id": "plank", "quantity": 2}]],
	]
	for entry in utility_table:
		_save_building(entry[0], entry[1], entry[2], entry[3], entry[5], entry[6], entry[7], false, entry[8],
				0, entry[4])
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
	for stairs_down in ["wooden_stairs_down", "stone_stairs_down"]:
		_attach(stairs_down, "res://data/interactables/stair_connector_down.tres", "connector_profile")
	# Appearance profiles (M9 6.6): chest keeps the shared-name profile;
	# campfire/furnace/torch/workbench each own a dedicated state sheet.
	# hearth/brazier/yard_lantern/metal_lantern are hand-authored and keep
	# their shared fuelled_appearance reference, so they are not re-attached.
	_attach("chest", "res://data/interactables/chest_appearance.tres", "appearance_profile")
	for appearance in ["campfire", "furnace", "torch", "workbench"]:
		_attach(appearance, "res://data/interactables/%s_appearance.tres" % appearance, "appearance_profile")

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
		requires_lower_support: bool, cost: Array,
		atlas_column_offset: int = 0, visual_family: String = "") -> void:
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
	# Structural parts inherit the tier as their visual family. Utility rows
	# pass an explicit family (fence belongs to the wood boundary family
	# even though it shares the plain utility gameplay defaults' tier).
	definition.visual_family_id = visual_family if not visual_family.is_empty() else tier
	# M9 box 4: build-palette group. Every managed id has an entry in the
	# BUILD_GROUP map; an id missing one leaves the field empty and validate()
	# in BuildingDefinition catches it at authoring time.
	if BUILD_GROUP.has(item_id):
		definition.build_group = str(BUILD_GROUP[item_id])
	# M2 placement model: edge parts orient to the four tile edges; doors and
	# windows are edge fixtures that may replace a plain wall on the same
	# edge; supported parts require the "structure" tag below them. Stairs
	# orient too (M9 6.4): each stair family owns a row of four edge cells.
	if part_type in ORIENTED_PARTS:
		definition.allowed_orientations = PackedStringArray(["north", "east", "south", "west"])
	if part_type in ["window", "door"]:
		definition.occupancy_replacement = "edge_fixture"
	if requires_lower_support:
		definition.required_support_tags = PackedStringArray(["structure"])
	# Atlas metadata follows the M9 art contract. The 6.2 parts are matched
	# by id first, then the wood/stone structural parts by tier (6.1), then
	# the legacy utility and station cells 6.3 leaves behind.
	if item_id == "bed":
		definition.atlas_path = INTERIOR_WOOD_SHEET
		definition.atlas_cell = Vector2i(0, 0)
	elif item_id == "farm_soil":
		definition.atlas_path = EXTERIOR_SHEET
		definition.atlas_cell = Vector2i(0, 3)
	elif item_id == "fence":
		# The fence is authored as a wall part on the wood boundary sheet;
		# its four edge cells are the first four columns of the sheet's top
		# row (contract 6.2/6.4).
		definition.atlas_path = BOUNDARIES_WOOD_SHEET
		definition.atlas_cell = Vector2i(0, 0)
		definition.atlas_cells = {
			"north": Vector2i(0, 0), "east": Vector2i(1, 0),
			"south": Vector2i(2, 0), "west": Vector2i(3, 0)
		}
	elif tier == "wood" or tier == "stone":
		definition.atlas_path = STRUCTURAL_SHEET_FMT % tier
		var cell: Vector2i = STRUCTURAL_CELL[part_type]
		definition.atlas_cell = Vector2i(cell.x + atlas_column_offset, cell.y)
		definition.support_tags = PackedStringArray(["cover"] if part_type == "roof" else ["structure"])
		# Orientation-aware cells for the edge-rendered structural parts
		# (contract 6.4): four consecutive cells starting at the master
		# cell's column. Stair down-rows are offset to columns 4-7 via the
		# table's column offset.
		if part_type in ORIENTED_PARTS:
			var base: int = int(STRUCTURAL_CELL[part_type].x) + atlas_column_offset
			var row: int = int(STRUCTURAL_CELL[part_type].y)
			definition.atlas_cells = {
				"north": Vector2i(base, row), "east": Vector2i(base + 1, row),
				"south": Vector2i(base + 2, row), "west": Vector2i(base + 3, row)
			}
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
