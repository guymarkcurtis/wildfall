## The single owner of object interaction state: which placed interactable is
## targeted, which one is open, and every close path. Targets resolve
## deterministically (distance, then stable placement key) from authored
## InteractionProfile data — no item-name branches. Panel content is supplied
## per ui_kind through registered view builders, so M6 adds the station view
## as data plus one builder, not a parallel UI.
class_name InteractionManager
extends Node2D

signal panel_closed(reason: String)

const RANGE_MARGIN_PX := 12.0

var building_manager: BuildingManager = null
var player: Player = null
var current_target: Building = null
var open_building: Building = null
var open_record: BuildingRecord = null
var open_panel: InteractablePanel = null

var _view_builders: Dictionary = {} # ui_kind -> Callable(building, record, panel) -> bool
var _open_close_handlers: Array = []
var _bound_building_manager: BuildingManager = null

func _ready() -> void:
	var parent := get_parent()
	if parent != null:
		player = parent.get_node_or_null("Player") as Player
		building_manager = parent.get_node_or_null("BuildingManager") as BuildingManager
	var hud := parent.get_node_or_null("HUD") if parent != null else null
	if hud != null and hud.has_method("set_interaction_prompt"):
		pass # HUD prompt publishes directly; keep the lookup local per frame.
	# M4 ships the container view; the station view registers in M6.
	register_view_builder("container", Callable(self, "_build_container_view"))
	register_view_builder("station", Callable(self, "_build_station_view"))
	_ensure_building_manager_binding()

## A view builder returns true when it opened content for the panel.
func register_view_builder(ui_kind: String, builder: Callable) -> void:
	_view_builders[ui_kind] = builder

func _process(_delta: float) -> void:
	# Pause always closes the panel (title transitions free the whole scene).
	var pause_menu := get_parent().get_node_or_null("PauseMenu") if get_parent() != null else null
	if pause_menu != null and pause_menu.visible and open_panel != null:
		close("pause")
	_refresh_target()
	_publish_prompt()
	_close_if_out_of_range()

func ui_blocks_world() -> bool:
	return open_panel != null and is_instance_valid(open_panel) and open_panel.blocks_world_input()

## The prompt for the HUD ("E Open Wood Chest"), or "" when nothing is
## targetable or a panel is already open.
func current_prompt() -> String:
	if open_panel != null:
		return ""
	if current_target == null or not is_instance_valid(current_target):
		return ""
	return current_target.get_interaction_prompt()

## E-press entry point. With a panel open, E closes it. With a target, E
## opens it. Returns true when the press was consumed (so the player does
## not also swing at the world).
func try_interact() -> bool:
	if open_panel != null:
		close("toggle")
		return true
	if current_target == null or not is_instance_valid(current_target):
		return false
	return open(current_target)

## Open one interactable. Opening another object closes the current one
## first ("switched").
func open(building: Building) -> bool:
	_ensure_building_manager_binding()
	if building == null or not is_instance_valid(building) or building_manager == null:
		return false
	var profile := building.get_interaction_profile()
	if profile == null:
		return false
	var builder: Callable = _view_builders.get(str(profile.ui_kind), Callable())
	if not builder.is_valid():
		# No view for this ui_kind yet (station arrives in M6): not consumed.
		return false
	if open_panel != null:
		close("switched")
	var record := building_manager.get_record_for_building(building)
	if record == null:
		return false
	var panel := InteractablePanel.new()
	var hud := get_parent().get_node_or_null("HUD")
	(hud if hud != null else self).add_child(panel)
	panel.close_requested.connect(close)
	if not bool(builder.call(building, record, panel)):
		panel.queue_free()
		return false
	# This marks the start of the data-authored opening transition before the
	# object is considered open by the manager.
	building.set_interaction_open(true)
	open_building = building
	open_record = record
	open_panel = panel
	# Removal/damage of the open object closes it (signals; queue_free-safe).
	building.building_damaged.connect(_on_open_building_damaged)
	building.building_destroyed.connect(_on_open_building_destroyed)
	panel.is_open = true
	panel.visible = true
	return true

## The one close pipeline. Safe to call twice, from any reason, even after
## the panel or object was freed.
func close(reason: String) -> void:
	if open_panel == null and open_building == null and open_record == null:
		return # already closed: every path is idempotent
	if open_building != null and is_instance_valid(open_building):
		open_building.set_interaction_open(false)
		if open_building.building_damaged.is_connected(_on_open_building_damaged):
			open_building.building_damaged.disconnect(_on_open_building_damaged)
		if open_building.building_destroyed.is_connected(_on_open_building_destroyed):
			open_building.building_destroyed.disconnect(_on_open_building_destroyed)
	if open_panel != null and is_instance_valid(open_panel):
		open_panel.close_panel()
		open_panel.queue_free()
	if open_record != null and open_record.container_storage != null:
		open_record.container_storage.changed.disconnect(_on_open_storage_changed)
	if open_record != null and open_record.station_input_storage != null \
			and open_record.station_input_storage.changed.is_connected(_on_open_storage_changed):
		open_record.station_input_storage.changed.disconnect(_on_open_storage_changed)
	if open_record != null and open_record.station_output_storage != null \
			and open_record.station_output_storage.changed.is_connected(_on_open_storage_changed):
		open_record.station_output_storage.changed.disconnect(_on_open_storage_changed)
	open_panel = null
	open_building = null
	open_record = null
	panel_closed.emit(reason)

# --- Internals ---

func _refresh_target() -> void:
	current_target = null
	if player == null or not is_instance_valid(player) or ui_blocks_world():
		return
	if building_manager == null:
		return
	var best: Building = null
	var best_distance := INF
	var best_key := ""
	for record in building_manager.get_all_records():
		var building := record.node
		if building == null or not is_instance_valid(building):
			continue
		if not building.can_interact(player):
			continue
		var center := building.global_position + Vector2(Building.TILE_SIZE, Building.TILE_SIZE) * 0.5
		var distance := center.distance_to(player.global_position)
		var key := building.placement_key
		if best == null or distance < best_distance - 0.001 \
				or (distance < best_distance + 0.001 and key < best_key):
			best = building
			best_distance = distance
			best_key = key
	current_target = best

func _publish_prompt() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var hud := parent.get_node_or_null("HUD")
	if hud != null and hud.has_method("set_interaction_prompt"):
		hud.set_interaction_prompt(current_prompt())

func _close_if_out_of_range() -> void:
	if open_panel == null or open_building == null or not is_instance_valid(open_building):
		return
	var profile := open_building.get_interaction_profile()
	if profile == null or player == null or not is_instance_valid(player):
		return
	var center := open_building.global_position + Vector2(Building.TILE_SIZE, Building.TILE_SIZE) * 0.5
	if center.distance_to(player.global_position) > profile.range_px + RANGE_MARGIN_PX:
		close("out_of_range")

func _on_open_building_damaged(_current: int, _max: int) -> void:
	close("damaged")

func _on_open_building_destroyed() -> void:
	close("removed")

func _on_open_storage_changed() -> void:
	if open_panel != null and is_instance_valid(open_panel):
		open_panel.refresh_grids()

func _on_demolition_blocked(record: BuildingRecord, _reason: String) -> void:
	# The player has been told why removal failed; never leave a panel open over
	# the protected object, even if this signal fires after a repeat input.
	if open_record == record:
		close("demolition_blocked")

func _ensure_building_manager_binding() -> void:
	if _bound_building_manager == building_manager or building_manager == null:
		return
	if _bound_building_manager != null and is_instance_valid(_bound_building_manager) \
			and _bound_building_manager.demolition_blocked.is_connected(_on_demolition_blocked):
		_bound_building_manager.demolition_blocked.disconnect(_on_demolition_blocked)
	if not building_manager.demolition_blocked.is_connected(_on_demolition_blocked):
		building_manager.demolition_blocked.connect(_on_demolition_blocked)
	_bound_building_manager = building_manager

## The M4 container view: object storage and player storage side by side,
## both rendered by the shared StorageGridView, moved by InventoryTransfer.
func _build_container_view(building: Building, record: BuildingRecord, panel: InteractablePanel) -> bool:
	var storage := record.get_container_storage()
	if storage == null:
		return false
	if player != null and player.inventory != null:
		storage.stack_sizes = player.inventory.get_stack_sizes()
		storage.max_durations = player.inventory.get_duration_caps()
	var title := building.get_interaction_prompt().capitalize()
	var help := "Left click to select, click the other side to move. Shift click quick-moves, right click splits half. Esc closes."
	panel.open_for(title, help, storage, player.inventory.get_storage())
	var changed := Callable(self, "_on_open_storage_changed")
	if not storage.changed.is_connected(changed):
		storage.changed.connect(changed)
	return true

func _build_station_view(building: Building, record: BuildingRecord, panel: InteractablePanel) -> bool:
	if player == null or player.inventory == null or building.definition == null \
			or building.definition.station_profile == null:
		return false
	var inputs := record.get_station_input_storage()
	var outputs := record.get_station_output_storage()
	if inputs == null or outputs == null:
		return false
	inputs.stack_sizes = player.inventory.get_stack_sizes()
	outputs.stack_sizes = player.inventory.get_stack_sizes()
	inputs.max_durations = player.inventory.get_duration_caps()
	outputs.max_durations = player.inventory.get_duration_caps()
	var database := get_parent().get_node_or_null("ItemDatabase") as ItemDatabase
	if database == null:
		return false
	var recipes := database.get_recipes_for_station(building.definition.station_profile.recipe_group)
	var power_note := ""
	if building.definition.station_profile.requires_power:
		power_note = " Powered: %s." % ("yes" if bool(record.capability_state.get("enabled", false)) else "no")
	panel.open_station(building.get_interaction_prompt().capitalize(),
			"Move ingredients into input slots, then choose a recipe. Output is read-only." + power_note,
			inputs, outputs, player.inventory.get_storage(), recipes)
	panel.station_craft_requested.connect(_on_station_craft_requested.bind(record))
	for storage in [inputs, outputs]:
		if not storage.changed.is_connected(_on_open_storage_changed):
			storage.changed.connect(_on_open_storage_changed)
	return true

func _on_station_craft_requested(recipe_id: String, record: BuildingRecord) -> void:
	if open_record != record or player == null or player.inventory == null:
		return
	var database := get_parent().get_node_or_null("ItemDatabase") as ItemDatabase
	var recipe := database.get_recipe(recipe_id) if database != null else null
	if recipe == null:
		return
	var technology := get_parent().get_node_or_null("TechnologySystem")
	var unlocked: bool = GameSession.is_creative() or technology == null or technology.is_unlocked(recipe.technology_id)
	StationCrafting.fill_inputs(record, player.inventory.get_storage(), recipe)
	var result := StationCrafting.craft(record, player.inventory.get_storage(), recipe, unlocked)
	var hud := get_parent().get_node_or_null("HUD")
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast("Crafted %s" % recipe.result_item_id.replace("_", " ") if bool(result.success) else "Crafting: %s" % str(result.reason).replace("_", " "))
	_on_open_storage_changed()
