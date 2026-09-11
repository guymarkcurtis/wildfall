## Static boot intent shared between the title screen and the game scene.
## Not an autoload: TitleScreen writes these, Main reads and clears them.
## game_mode is chosen at New Game (or restored from a save) and cannot
## be changed mid-run.
class_name GameSession
extends RefCounted

const MODE_SURVIVAL := "survival"
const MODE_CREATIVE := "creative"

enum BootAction {
	NEW_GAME,
	LOAD_GAME
}

static var boot_action: BootAction = BootAction.NEW_GAME
static var load_path: String = "user://saves/slot_1.json"
static var game_mode: String = MODE_SURVIVAL

static func request_new_game(mode: String = MODE_SURVIVAL) -> void:
	boot_action = BootAction.NEW_GAME
	set_game_mode(mode)

static func set_game_mode(mode: String) -> void:
	if mode == MODE_CREATIVE:
		game_mode = MODE_CREATIVE
	else:
		game_mode = MODE_SURVIVAL

static func is_creative() -> bool:
	return game_mode == MODE_CREATIVE

static func is_survival() -> bool:
	return not is_creative()

static func mode_label(mode: String = "") -> String:
	var value: String = mode if mode != "" else game_mode
	return "Creative" if value == MODE_CREATIVE else "Survival"

static func request_load_game(path: String = "") -> void:
	boot_action = BootAction.LOAD_GAME
	if path != "":
		load_path = path

static func wants_load() -> bool:
	return boot_action == BootAction.LOAD_GAME

## Read-and-reset so a later New Game is not treated as a load.
static func consume_load() -> bool:
	if boot_action != BootAction.LOAD_GAME:
		return false
	boot_action = BootAction.NEW_GAME
	return true

static func go_to_game(tree: SceneTree) -> void:
	tree.change_scene_to_file("res://scenes/main.tscn")

static func go_to_title(tree: SceneTree) -> void:
	boot_action = BootAction.NEW_GAME
	tree.paused = false
	tree.change_scene_to_file("res://scenes/title.tscn")
