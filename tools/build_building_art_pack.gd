## Assembles the pixel-art source PNGs (see docs/BUILDING_ART_REQUESTS.md,
## section 5) into Wildfall's 16 building and interactable atlas sheets.
## This is a mechanical packer: it never generates, paints, or substitutes
## artwork. It blits the master cells, creates the derived orientation cells
## (east = 90 deg clockwise, south = 180 deg, west = 90 deg
## counter-clockwise, per the family maps' orientation tables), and leaves
## reserved cells fully transparent. The runtime never rotates sprites.
##
## Usage:
##   godot --headless --path . \
##     --script tools/build_building_art_pack.gd \
##     -- <masters-dir> [out-root]
##
## <masters-dir> holds one subdirectory per sheet. Family-map sheets
## (structural_*, boundaries_*, interior_*, exterior_props) use flat slot
## indices (<row>*columns+<col>) as file names; state sheets (wood_chest,
## campfire, furnace, workbench, torch, hearth) use frame indices.
## [out-root] defaults to the repository root; res:// paths are remapped
## onto it. The packer refuses to write any sheet that violates its
## contract and exits non-zero with every violation printed.
extends SceneTree

const CELL := 32
const FAMILY_DIR := "assets/tiles/building/"
const STATE_DIR := "assets/tiles/interactables/"

# Family A sheets whose slot layout is described by a family map resource
# (data/buildings/families/<sheet>.tres). Interior sheets are documented in the
# requests doc (section 3.3) but intentionally have no map resource, so
# their master slots are hard-coded below from the same doc.
const FAMILY_SHEETS := [
	"structural_wood",
	"structural_stone",
	"structural_metal",
	"boundaries_wood",
	"boundaries_stone",
	"boundaries_metal",
	"exterior_props",
]

# Interior sheet master flat indices (row * 8 + col), all in row 0.
# wood: bed, wooden_table, chair, shelf, rug, wardrobe.
# stone: cabinet, bookcase. metal: workshop_cabinet, metal_locker.
# Every other slot on an interior sheet is reserved.
const INTERIOR_MASTERS := {
	"interior_wood": [0, 2, 3, 4, 5, 6],
	"interior_stone": [1, 2],
	"interior_metal": [0, 1],
}

# Family B frame counts per state sheet (requests doc section 4).
const STATE_FRAMES := {
	"wood_chest": 3,
	"campfire": 5,
	"furnace": 3,
	"workbench": 2,
	"torch": 4,
	"hearth": 2,
}

var _failures: Array[String] = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var masters := "/tmp/godot-check/m9_gen"
	var out_root := ProjectSettings.globalize_path("res://")
	if args.size() >= 1:
		masters = args[0]
	if args.size() >= 2:
		out_root = args[1]
	if not DirAccess.dir_exists_absolute(masters):
		_fail(masters + " does not exist (masters directory).")
	for sheet_id in FAMILY_SHEETS:
		_build_family_sheet(masters, out_root, sheet_id)
	for sheet_id in INTERIOR_MASTERS:
		_build_interior_sheet(masters, out_root, sheet_id)
	for sheet_id in STATE_FRAMES:
		_build_state_sheet(masters, out_root, sheet_id)
	if not _failures.is_empty():
		for message in _failures:
			push_error(message)
		_fail("Building art pack incomplete: %d contract violation(s); no sheets were rewritten where invalid." % _failures.size())
	print("Building art pack assembled: 7 family + 3 interior + 6 state sheets under %s" % out_root)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


## Builds one family-map sheet. The map is the slot source of truth: its
## orientation tables say which derived slot belongs to which master and in
## which orientation; the packer inverts those tables to drive rotation.
func _build_family_sheet(masters: String, out_root: String, sheet_id: String) -> void:
	var before := _failures.size()
	var map := load("res://data/buildings/families/%s.tres" % sheet_id) as AtlasFamilyMap
	if map == null:
		_failures.append("%s: family map resource missing" % sheet_id)
		return
	var map_errors := map.validate()
	if not map_errors.is_empty():
		for error_message in map_errors:
			_failures.append("%s: %s" % [sheet_id, error_message])
		return
	var columns := map.columns
	var rows := map.rows
	var cell := map.cell_size
	if cell != CELL:
		_failures.append("%s: family map cell size %d != contract %d px" % [sheet_id, cell, CELL])
		return
	# Map each derived slot back to the orientation it must display in.
	# "north" is the master cell itself and needs no rotation.
	var orientation_of := {}
	for part in map.orientation_slots:
		var table: Dictionary = map.orientation_slots[part]
		for orientation in table:
			if orientation != "north":
				orientation_of[int(table[orientation])] = orientation
	var canvas := Image.create_empty(columns * cell, rows * cell, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.TRANSPARENT)
	var master_cache := {}
	var master_ink := {}
	for index in range(columns * rows):
		var rec: Variant = map.slots.get(index)
		if rec == null:
			_failures.append("%s: slot %d missing from family map" % [sheet_id, index])
			continue
		var status: String = str(rec.get("status", ""))
		match status:
			"reserved":
				pass  # stays fully transparent
			"master":
				var source := _image(masters.path_join("%s/%d.png" % [sheet_id, index]))
				if source == null:
					_failures.append("%s: master slot %d has no source cell" % [sheet_id, index])
					continue
				if source.get_size() != Vector2i(cell, cell):
					_failures.append("%s: master slot %d is %dx%d, contract is %dx%d" % [sheet_id, index, source.get_width(), source.get_height(), cell, cell])
					continue
				_blit(canvas, source, index, columns, cell)
				master_cache[index] = source
				master_ink[index] = _ink(source)
			"derived":
				var master_index := int(rec.get("master", -1))
				var orientation: String = str(orientation_of.get(index, ""))
				if orientation == "":
					_failures.append("%s: derived slot %d is not named by any orientation table" % [sheet_id, index])
					continue
				if not master_cache.has(master_index):
					_failures.append("%s: derived slot %d references missing or invalid master slot %d" % [sheet_id, index, master_index])
					continue
				_blit(canvas, _transposed(master_cache[master_index], orientation), index, columns, cell)
			_:
				_failures.append("%s: slot %d has unknown status '%s'" % [sheet_id, index, status])
	# Post-pass: verify the assembled canvas against the map's contract.
	for index in range(columns * rows):
		var rec: Variant = map.slots.get(index)
		if rec == null:
			continue
		var status: String = str(rec.get("status", ""))
		var ink := _cell_ink(canvas, index, columns, cell)
		match status:
			"reserved":
				if ink != 0:
					_failures.append("%s: reserved slot %d is not fully transparent (%d opaque px)" % [sheet_id, index, ink])
			"master", "derived":
				if ink == 0:
					_failures.append("%s: slot %d has no art" % [sheet_id, index])
				elif status == "derived":
					var master_index := int(rec.get("master", -1))
					if master_ink.has(master_index) and ink != int(master_ink[master_index]):
						_failures.append("%s: derived slot %d has %d opaque px, master slot %d has %d (rotation must preserve ink)" % [sheet_id, index, ink, master_index, int(master_ink[master_index])])
	if master_cache.is_empty() and _failures.size() == before:
			_failures.append("%s: family map declares no usable master" % sheet_id)
	if _failures.size() == before:
		_save(canvas, out_root.path_join(map.atlas_path.trim_prefix("res://")))
		print("OK   %s (%dx%d, %d slots)" % [map.atlas_path, columns * cell, rows * cell, columns * rows])
	elif _failures.size() > before:
		print("FAIL %s: %d problem(s), sheet not written" % [sheet_id, _failures.size() - before])


## Builds one interior sheet (no family map resource by contract; master
## slots come from the requests doc). All non-master slots stay transparent.
func _build_interior_sheet(masters: String, out_root: String, sheet_id: String) -> void:
	var before := _failures.size()
	var canvas := Image.create_empty(8 * CELL, 4 * CELL, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.TRANSPARENT)
	for index in range(8 * 4):
		if not (INTERIOR_MASTERS[sheet_id] as Array).has(index):
			continue
		var source := _image(masters.path_join("%s/%d.png" % [sheet_id, index]))
		if source == null:
			_failures.append("%s: master slot %d has no source cell" % [sheet_id, index])
			continue
		if source.get_size() != Vector2i(CELL, CELL):
			_failures.append("%s: master slot %d is %dx%d, contract is %dx%d" % [sheet_id, index, source.get_width(), source.get_height(), CELL, CELL])
			continue
		_blit(canvas, source, index, 8, CELL)
	for index in range(8 * 4):
		var ink := _cell_ink(canvas, index, 8, CELL)
		if (INTERIOR_MASTERS[sheet_id] as Array).has(index):
			if ink == 0:
				_failures.append("%s: master slot %d has no art" % [sheet_id, index])
		elif ink != 0:
			_failures.append("%s: reserved slot %d is not fully transparent (%d opaque px)" % [sheet_id, index, ink])
	if _failures.size() == before:
		_save(canvas, out_root.path_join(FAMILY_DIR + sheet_id + ".png"))
		print("OK   res://%s%s.png (256x128, %d masters)" % [FAMILY_DIR, sheet_id, (INTERIOR_MASTERS[sheet_id] as Array).size()])
	elif _failures.size() > before:
		print("FAIL %s: %d problem(s), sheet not written" % [sheet_id, _failures.size() - before])


## Builds one Family B state sheet: frames blitted top to bottom into a
## 32 x (32 * frames) canvas.
func _build_state_sheet(masters: String, out_root: String, sheet_id: String) -> void:
	var before := _failures.size()
	var frames := int(STATE_FRAMES[sheet_id])
	var canvas := Image.create_empty(CELL, frames * CELL, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.TRANSPARENT)
	for frame in range(frames):
		var source := _image(masters.path_join("%s/%d.png" % [sheet_id, frame]))
		if source == null:
			_failures.append("%s: frame %d has no source cell" % [sheet_id, frame])
			continue
		if source.get_size() != Vector2i(CELL, CELL):
			_failures.append("%s: frame %d is %dx%d, contract is %dx%d" % [sheet_id, frame, source.get_width(), source.get_height(), CELL, CELL])
			continue
		canvas.blit_rect(source, Rect2i(Vector2i.ZERO, Vector2i(CELL, CELL)), Vector2i(0, frame * CELL))
	for frame in range(frames):
		var ink := 0
		for y in range(frame * CELL, (frame + 1) * CELL):
			for x in range(CELL):
				if canvas.get_pixel(x, y).a > 0:
					ink += 1
		if ink == 0:
			_failures.append("%s: frame %d has no art" % [sheet_id, frame])
	if _failures.size() == before:
		_save(canvas, out_root.path_join(STATE_DIR + sheet_id + ".png"))
		print("OK   res://%s%s.png (32x%d, %d frames)" % [STATE_DIR, sheet_id, frames * CELL, frames])
	elif _failures.size() > before:
		print("FAIL %s: %d problem(s), sheet not written" % [sheet_id, _failures.size() - before])


func _image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var result := Image.new()
	if result.load(path) != OK or result.is_empty():
		return null
	if result.get_format() != Image.FORMAT_RGBA8:
		result.convert(Image.FORMAT_RGBA8)
	return result


func _blit(canvas: Image, source: Image, index: int, columns: int, cell: int) -> void:
	canvas.blit_rect(source, Rect2i(Vector2i.ZERO, Vector2i(cell, cell)), Vector2i((index % columns) * cell, (index / columns) * cell))


func _ink(img: Image) -> int:
	var count := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0:
				count += 1
	return count


func _cell_ink(canvas: Image, index: int, columns: int, cell: int) -> int:
	var count := 0
	var origin := Vector2i((index % columns) * cell, (index / columns) * cell)
	for y in range(origin.y, origin.y + cell):
		for x in range(origin.x, origin.x + cell):
			if canvas.get_pixel(x, y).a > 0:
				count += 1
	return count


# Manual pixel rotation: the Image.TRANSPOSE_* enum constants do not parse
# in Godot 4.7.2 GDScript, so the packer transposes by hand (directions
# verified against the doc's east/south/west definitions).
func _transposed(source: Image, orientation: String) -> Image:
	var out := Image.create_empty(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
	var w := source.get_width()
	var h := source.get_height()
	for y in range(h):
		for x in range(w):
			var c := source.get_pixel(x, y)
			var dest := Vector2i(x, y)
			match orientation:
				"east":
					dest = Vector2i(h - 1 - y, x)
				"south":
					dest = Vector2i(w - 1 - x, h - 1 - y)
				"west":
					dest = Vector2i(y, w - 1 - x)
			out.set_pixel(dest.x, dest.y, c)
	return out


func _save(img: Image, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if img.save_png(path) != OK:
		_fail("Could not write %s" % path)
