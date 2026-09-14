## Data description of one generated building atlas sheet: canvas geometry
## plus the role, owner, and derivation of every slot on it. The packer
## (tools/build_building_art_pack.gd) and the art harness
## (tests/test_building_art.gd) both read these maps, so the cell layout
## lives in data rather than in tool code. One map per sheet family; the
## three interior sheets have no map resource because no runtime code
## consumes their cell addresses (they are documented in the art contract
## instead).
class_name AtlasFamilyMap
extends Resource

## Stable map id (also the sheet file name, e.g. "structural_wood").
@export var id: String = ""

## Sheet path the game loads (res://...png).
@export var atlas_path: String = ""

@export var columns: int = 8
@export var rows: int = 4

## Pixel size of one cell.
@export var cell_size: int = 32

## Slot index (row * columns + column) -> slot record:
##   "role": String       slot role on the sheet ("foundation", "wall", ...)
##   "owner": String      BuildingDefinition id the slot belongs to ("" when
##                        the slot is reserved or derived)
##   "status": String     "master" | "derived" | "reserved"
##   "master": int        slot index of the generated master (derived slots)
##   "master_of": Array   slot indices this master derives (masters only)
##   "generated": bool    true when a source was generated for the slot
## Reserved slots stay fully transparent on the sheet.
@export var slots: Dictionary = {}

## For sheets holding 4-orientation parts: part role ("wall", "window",
## "door", "stair_up", "stair_down", "stair", "fence", "gate", "rail") ->
## {orientation -> slot index}, i.e. {"north": 8, "east": 9, "south": 10,
## "west": 11}. The packer derives each listed slot from its "north" master;
## the per-definition atlas_cells map mirrors these same slots. Empty
## dictionary for sheets whose parts are not orientable.
@export var orientation_slots: Dictionary = {}

func validate() -> Array[String]:
	var errors: Array[String] = []
	if id == "":
		errors.append("%s: map id is empty" % resource_name)
	if atlas_path == "":
		errors.append("%s: atlas_path is empty" % id)
	if columns * cell_size <= 0 or rows * cell_size <= 0:
		errors.append("%s: invalid canvas geometry (%dx%d, cell %d)" % [id, columns, rows, cell_size])
	return errors
