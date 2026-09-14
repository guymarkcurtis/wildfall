## M9 art-contract harness (docs/BUILDING_ART_REQUESTS.md, section 8.2).
## Verifies the 16 generated building/interactable sheets that ship in the
## repository:
##   - every AtlasFamilyMap in data: the sheet exists, its canvas equals the
##     contracted dimensions, every generated/owned slot holds art (derived
##     orientation slots included - the packer's rotation contract), every
##     reserved slot is fully transparent, and every definition's
##     atlas_cell / atlas_cells reference for that sheet resolves inside it;
##   - the three interior sheets (no map resource by contract design): the
##     section 6.2 owner table is pinned here - owned cells hold art, every
##     other cell is transparent, and each owner definition points at its
##     contracted cell;
##   - the six Family B state sheets: exact canvas size, alpha channel,
##     every frame strip non-empty, and every consuming AppearanceProfile
##     references the sheet through PACK_ASSETS with all of its state frame
##     ranges inside the sheet.
## The stock manifest (regenerated from PACK_ASSETS in test_ground_pack)
## covers the same 16 paths; the membership check here pins D7 directly.
## Run: godot --headless --path . --script tests/test_building_art.gd
extends SceneTree

const CELL := 32
const BUILDINGS_COUNT := 68

## Contracted canvas sizes for the sheets that have a family map resource
## (doc section 2.2 inventory: 3 structural 8x8, 3 boundaries 8x4,
## 1 exterior 8x4).
var FAMILY_SHEET_SIZES: Dictionary = {
	"structural_wood": [256, 256],
	"structural_stone": [256, 256],
	"structural_metal": [256, 256],
	"boundaries_wood": [256, 128],
	"boundaries_stone": [256, 128],
	"boundaries_metal": [256, 128],
	"exterior_props": [256, 128],
}

## Interior sheets have no AtlasFamilyMap resource by contract design
## (section 7: no runtime code consumes their cell addresses), so the
## section 6.2 owner table is pinned here. Rows are [def_id, column, row].
var INTERIOR_SHEETS: Dictionary = {
	"interior_wood": [
		["bed", 0, 0],
		["wooden_table", 2, 0],
		["chair", 3, 0],
		["shelf", 4, 0],
		["rug", 5, 0],
		["wardrobe", 6, 0],
	],
	"interior_stone": [
		["cabinet", 1, 0],
		["bookcase", 2, 0],
	],
	"interior_metal": [
			["workshop_cabinet", 0, 0],
		["metal_locker", 1, 0],
	],
}

## Family B state sheets: one 32px column, frames stacked top to bottom.
var STATE_SHEET_SIZES: Dictionary = {
	"wood_chest": [32, 96],
	"campfire": [32, 160],
	"furnace": [32, 96],
	"workbench": [32, 64],
	"torch": [32, 128],
	"hearth": [32, 64],
}

var _failures := 0
var _checks := 0
var _registry: BuildingContentRegistry

func _initialize() -> void:
	_registry = BuildingContentRegistry.new()
	_registry.discover()
	_check(_registry.definitions.size() == BUILDINGS_COUNT,
			"Definition registry discovered all %d definitions (got %d)" % [BUILDINGS_COUNT, _registry.definitions.size()])
	_test_pack_assets_membership()
	_test_family_maps()
	_test_interior_sheets()
	_test_state_sheets()
	print("Building art contract: %d failures (%d checks)" % [_failures, _checks])
	quit(_failures)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("[PASS] %s" % label)
	else:
		_failures += 1
		push_error("[FAIL] %s" % label)

## D7: the stock manifest (test_ground_pack) covers PACK_ASSETS wholesale,
## so pin all 16 M9 sheet paths against the list directly.
func _test_pack_assets_membership() -> void:
	var all_sheets: Array[String] = []
	for sheet_id in FAMILY_SHEET_SIZES:
		all_sheets.append("res://assets/tiles/building/%s.png" % sheet_id)
	for sheet_id in INTERIOR_SHEETS:
		all_sheets.append("res://assets/tiles/building/%s.png" % sheet_id)
	for sheet_id in STATE_SHEET_SIZES:
		all_sheets.append("res://assets/tiles/interactables/%s.png" % sheet_id)
	_check(all_sheets.size() == 16, "The M9 inventory lists exactly 16 new sheets (got %d)" % all_sheets.size())
	var missing: Array[String] = []
	for sheet_path in all_sheets:
		if not _in_pack_assets(sheet_path):
			missing.append(sheet_path)
	var missing_note := ""
	if not missing.is_empty():
		missing_note = " (missing: %s)" % str(missing)
	_check(missing.is_empty(), "All 16 M9 sheets are listed in TexturePackManager.PACK_ASSETS" + missing_note)

## (a)-(d) for every AtlasFamilyMap in data.
func _test_family_maps() -> void:
	var dir := DirAccess.open("res://data/buildings/families")
	_check(dir != null, "data/buildings/families directory exists")
	if dir == null:
		return
	var found: Array[AtlasFamilyMap] = []
	var files := dir.get_files()
	files.sort()
	for file_name in files:
		if file_name.ends_with(".tres"):
			var map := load("res://data/buildings/families/%s" % file_name) as AtlasFamilyMap
			if map != null:
				found.append(map)
	var map_ids: Array[String] = []
	for map in found:
		map_ids.append(map.id)
	map_ids.sort()
	var expected_ids: Array[String] = []
	for sheet_id in FAMILY_SHEET_SIZES:
		expected_ids.append(str(sheet_id))
	expected_ids.sort()
	var map_id_note := ""
	if str(map_ids) != str(expected_ids):
		map_id_note = " (got %s)" % str(map_ids)
	_check(str(map_ids) == str(expected_ids),
			"Family maps under data/buildings/families exactly match the contracted 7-sheet inventory" + map_id_note)
	for map in found:
		_check_family_map(map)

func _check_family_map(map: AtlasFamilyMap) -> void:
	var label := map.id
	var expected: Variant = FAMILY_SHEET_SIZES.get(label)
	_check(expected != null, "%s: map id matches a contracted sheet" % label)
	if expected == null:
		return
	var contracted_size := Vector2i(int(expected[0]), int(expected[1]))
	var img := _load_image(map.atlas_path)
	_check(img != null, "%s: sheet exists at %s" % [label, map.atlas_path])
	if img == null:
		return
	_check(img.get_size() == contracted_size,
			"%s: canvas is the contracted %dx%d (got %dx%d)" % [label, contracted_size.x, contracted_size.y, img.get_width(), img.get_height()])
	_check(map.columns * map.cell_size == img.get_width() and map.rows * map.cell_size == img.get_height(),
			"%s: family map geometry matches the sheet canvas" % label)
	_check(map.validate().is_empty(), "%s: family map resource validates" % label)
	_check(map.atlas_path.ends_with(label + ".png"), "%s: atlas_path file name matches the map id" % label)
	if img.get_size() != contracted_size:
		return  # pixel checks below assume the contracted canvas
	# (b) + (c): slot roles drive which pixels may be inked.
	for index in range(map.columns * map.rows):
		var rec: Variant = map.slots.get(index)
		if rec == null:
			_check(false, "%s: slot %d is missing from the family map" % [label, index])
			continue
		var status: String = str(rec.get("status", ""))
		var ink := _cell_ink(img, Vector2i((index % map.columns) * map.cell_size, (index / map.columns) * map.cell_size), Vector2i(map.cell_size, map.cell_size))
		match status:
			"master":
				_check(ink > 0, "%s: generated slot %d holds art" % [label, index])
			"derived":
				_check(ink > 0, "%s: derived orientation slot %d holds art" % [label, index])
			"reserved":
				_check(ink == 0, "%s: reserved slot %d is fully transparent" % [label, index])
			_:
				_check(false, "%s: slot %d has unknown status '%s'" % [label, index, status])
	# (d) every definition pointing at this sheet must resolve inside it.
	for def_id in _registry.definitions:
		var def_value: Variant = _registry.definitions[def_id]
		if def_value == null:
			continue
		var def := def_value as BuildingDefinition
		if def == null or def.atlas_path != map.atlas_path:
			continue
		if def.atlas_cell != Vector2i(-1, -1):
			_check(_cell_inside(def.atlas_cell, map), "%s: def '%s' atlas_cell %s resolves inside the sheet" % [label, def_id, str(def.atlas_cell)])
		for orientation_name in def.atlas_cells:
			var cell_value: Variant = def.atlas_cells[orientation_name]
			_check(typeof(cell_value) == TYPE_VECTOR2I and _cell_inside(cell_value as Vector2i, map),
					"%s: def '%s' atlas_cells['%s'] resolves inside the sheet" % [label, def_id, str(orientation_name)])

func _cell_inside(cell: Vector2i, map: AtlasFamilyMap) -> bool:
	return cell.x >= 0 and cell.x < map.columns and cell.y >= 0 and cell.y < map.rows

## Interior sheets: no map resource by design; the section 6.2 owner table
## is the contract on both sides (sheet pixels and definition references).
func _test_interior_sheets() -> void:
	for sheet_id in INTERIOR_SHEETS:
		var label := str(sheet_id)
		var sheet_path := "res://assets/tiles/building/%s.png" % label
		var img := _load_image(sheet_path)
		_check(img != null, "%s: sheet exists at %s" % [label, sheet_path])
		if img == null:
			continue
		_check(img.get_size() == Vector2i(256, 128),
				"%s: canvas is the contracted 256x128 (got %dx%d)" % [label, img.get_width(), img.get_height()])
		if img.get_size() != Vector2i(256, 128):
			continue
		var owners: Array = INTERIOR_SHEETS[sheet_id]
		var owned_flat := {}
		for row in owners:
			var def_id := str(row[0])
			var col := int(row[1])
			var row_index := int(row[2])
			owned_flat[row_index * 8 + col] = true
			var def_value: Variant = _registry.definitions.get(def_id)
			var def := def_value as BuildingDefinition
			_check(def != null, "%s: owner definition '%s' is registered" % [label, def_id])
			if def == null:
				continue
			_check(def.atlas_path == sheet_path, "%s: def '%s' references the interior sheet" % [label, def_id])
			_check(def.atlas_cell == Vector2i(col, row_index),
					"%s: def '%s' atlas_cell is the contracted %d,%d (got %s)" % [label, def_id, col, row_index, str(def.atlas_cell)])
		for index in range(32):
			var ink := _cell_ink(img, Vector2i((index % 8) * CELL, (index / 8) * CELL), Vector2i(CELL, CELL))
			if owned_flat.has(index):
				_check(ink > 0, "%s: owned slot %d holds art" % [label, index])
			else:
				_check(ink == 0, "%s: reserved slot %d is fully transparent" % [label, index])

## Six Family B state sheets: exact canvas, alpha, non-empty frame strips,
## and every consuming profile's frame ranges inside the sheet.
func _test_state_sheets() -> void:
	for sheet_id in STATE_SHEET_SIZES:
		var label := str(sheet_id)
		var sheet_path := "res://assets/tiles/interactables/%s.png" % label
		var contracted_size := Vector2i(int(STATE_SHEET_SIZES[sheet_id][0]), int(STATE_SHEET_SIZES[sheet_id][1]))
		var img := _load_image(sheet_path)
		_check(img != null, "%s: state sheet exists at %s" % [label, sheet_path])
		if img == null:
			continue
		_check(img.get_size() == contracted_size,
				"%s: canvas is the contracted %dx%d (got %dx%d)" % [label, contracted_size.x, contracted_size.y, img.get_width(), img.get_height()])
		_check(_has_alpha(img), "%s: sheet has an alpha channel" % label)
		if img.get_size() != contracted_size:
			continue
		var frames := img.get_height() / CELL
		for frame in range(frames):
			var ink := _cell_ink(img, Vector2i(0, frame * CELL), Vector2i(CELL, CELL))
			_check(ink > 0, "%s: frame strip %d holds art" % [label, frame])
		var consumers: Array[AppearanceProfile] = _appearance_profiles_with_sheet(sheet_path)
		_check(consumers.size() >= 1, "%s: at least one appearance profile consumes the sheet" % label)
		for profile in consumers:
			var profile_name := str(profile.resource_name)
			_check(_in_pack_assets(profile.sheet_path), "%s: consumer '%s' sheet_path is a PACK_ASSETS entry" % [label, profile_name])
			for state_name in profile.states:
				var state: Variant = profile.states[state_name]
				if typeof(state) != TYPE_DICTIONARY:
					_check(false, "%s: consumer '%s' state '%s' is a dictionary" % [label, profile_name, str(state_name)])
					continue
				var first_frame := int(state.get("first_frame", 0))
				var frame_count := int(state.get("frame_count", 0))
				_check(first_frame >= 0 and first_frame + frame_count <= frames,
						"%s: consumer '%s' state '%s' spans frames %d..%d within the %d-frame sheet" % [label, profile_name, str(state_name), first_frame, first_frame + frame_count - 1, frames])

func _appearance_profiles_with_sheet(sheet_path: String) -> Array[AppearanceProfile]:
	var result: Array[AppearanceProfile] = []
	var dir := DirAccess.open("res://data/interactables")
	if dir == null:
		return result
	var files := dir.get_files()
	files.sort()
	for file_name in files:
		if file_name.ends_with(".tres"):
			var profile := load("res://data/interactables/%s" % file_name) as AppearanceProfile
			if profile != null and profile.sheet_path == sheet_path:
				result.append(profile)
	return result

func _in_pack_assets(res_path: String) -> bool:
	var relative := res_path
	if relative.begins_with("res://"):
		relative = relative.trim_prefix("res://")
	return TexturePackManager.PACK_ASSETS.has(relative)

func _load_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(path)) != OK or img.is_empty():
		return null
	return img

func _has_alpha(img: Image) -> bool:
	match img.get_format():
		Image.FORMAT_RGBA8, Image.FORMAT_RGBA4444, Image.FORMAT_LA8, Image.FORMAT_RGBA16, Image.FORMAT_RGBA16I, Image.FORMAT_DXT3, Image.FORMAT_DXT5, Image.FORMAT_BPTC_RGBA, Image.FORMAT_ETC2_RGBA8, Image.FORMAT_ETC2_RGB8A1:
			return true
		_:
			return false

func _cell_ink(img: Image, origin: Vector2i, size: Vector2i) -> int:
	if origin.x < 0 or origin.y < 0:
		return 0
	var count := 0
	var max_y := mini(img.get_height(), origin.y + size.y)
	var max_x := mini(img.get_width(), origin.x + size.x)
	for y in range(origin.y, max_y):
		for x in range(origin.x, max_x):
			if img.get_pixel(x, y).a > 0:
				count += 1
	return count
