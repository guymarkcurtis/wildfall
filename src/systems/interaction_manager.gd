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
## Human wording for StationCrafting failure reasons; unknown reasons fall
## back to the raw reason so no failure is ever silently swallowed.
const CRAFT_FAILURE_MESSAGES := {
	"technology_locked": "Technology locked — research it first",
	"unpowered": "The station is unpowered",
	"missing_inputs": "Missing ingredients — fill the input slots",
	"output_full": "Output is full — collect the result first",
	"missing_surface": "Missing a surface for this recipe",
	"wrong_station": "This recipe belongs to another station",
	"not_a_station": "This object has no station",
	"invalid": "Invalid craft request",
}

var building_manager: BuildingManager = null
var player: Player = null
var current_target: Building = null
var open_building: Building = null
var open_record: BuildingRecord = null
var open_panel: InteractablePanel = null
## Gold frame around the tile of the interactable the player would act on.
## One generic marker for every profile-driven object — no per-station code.
var _focus_marker: Node2D = null

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
	_build_focus_marker()

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
	_update_focus_marker()
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
	# Panel-side rejection feedback (capacity, filters, swaps) rides the same
	# HUD toast lane as mission/tool feedback.
	panel.toast_requested.connect(_on_panel_toast)
	if not bool(builder.call(building, record, panel)):
		panel.queue_free()
		return false
	# This marks the start of the data-authored opening transition before the
	# object is considered open by the manager.
	building.set_interaction_open(true)
	# Stations that declare a crafting_state (data) show their in-use
	# presentation for as long as the panel stays open.
	building.set_crafting_active(true)
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
		open_building.set_crafting_active(false)
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
	if open_record != null and open_record.fuel_storage != null \
			and open_record.fuel_storage.changed.is_connected(_on_open_storage_changed):
		open_record.fuel_storage.changed.disconnect(_on_open_storage_changed)
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

## The gold frame around the current target's tile. It rides the target's
## own render band (story base + layer offset + 1) so it always draws over the
## object it points at, and it hides whenever nothing is targetable — which
## also includes every panel-open frame, since _refresh_target skips then.
func _update_focus_marker() -> void:
	if _focus_marker == null:
		return
	if current_target == null or not is_instance_valid(current_target):
		_focus_marker.visible = false
		return
	_focus_marker.visible = true
	_focus_marker.position = Vector2(current_target.tile_coords) * Building.TILE_SIZE
	_focus_marker.z_index = int(current_target.z_index) + 1

## One generic focus frame for every interactable: four thin strips just
## outside the 32 px tile, tinted to the HUD prompt gold. The object keeps its
## own data-authored presentation (a station's in-range glow, ...) underneath.
func _build_focus_marker() -> void:
	if _focus_marker != null:
		return
	_focus_marker = Node2D.new()
	_focus_marker.name = "FocusMarker"
	_focus_marker.z_index = 6
	_focus_marker.visible = false
	add_child(_focus_marker)
	var color := Color(0.95, 0.93, 0.66, 0.55)
	for side in ["north", "south", "west", "east"]:
		var polygon := Polygon2D.new()
		polygon.polygon = _frame_strip(side)
		polygon.color = color
		_focus_marker.add_child(polygon)

## A 2 px strip just outside one tile edge (the frame's cross-section).
func _frame_strip(side: String) -> PackedVector2Array:
	match side:
		"north":
			return PackedVector2Array([Vector2(-2, -2), Vector2(34, -2),
					Vector2(34, 0), Vector2(-2, 0)])
		"south":
			return PackedVector2Array([Vector2(-2, 32), Vector2(34, 32),
					Vector2(34, 34), Vector2(-2, 34)])
		"west":
			return PackedVector2Array([Vector2(-2, -2), Vector2(0, -2),
					Vector2(0, 34), Vector2(-2, 34)])
		_:
			return PackedVector2Array([Vector2(32, -2), Vector2(34, -2),
					Vector2(34, 34), Vector2(32, 34)])

## Route a panel rejection message ("No room in that slot", ...) to the HUD
## toast lane. Test worlds without a HUD simply drop the toast.
func _on_panel_toast(text: String) -> void:
	if text.is_empty():
		return
	var parent := get_parent()
	if parent == null:
		return
	var hud := parent.get_node_or_null("HUD")
	if hud != null and hud.has_method("show_toast"):
		hud.show_toast(text)

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
	var help := "Click to select, click to move. Shift sends the whole stack; right-click splits half. Esc closes."
	panel.open_for(title, help, storage, player.inventory.get_storage())
	var changed := Callable(self, "_on_open_storage_changed")
	if not storage.changed.is_connected(changed):
		storage.changed.connect(changed)
	return true

func _build_station_view(building: Building, record: BuildingRecord, panel: InteractablePanel) -> bool:
	if player == null or player.inventory == null or building.definition == null:
		return false
	if building.definition.station_profile == null:
		return _build_fuel_view(building, record, panel)
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
			"Add ingredients, then pick a recipe. Esc closes." + power_note,
			inputs, outputs, player.inventory.get_storage(), recipes)
	panel.station_craft_requested.connect(_on_station_craft_requested.bind(record))
	for storage in [inputs, outputs]:
		if not storage.changed.is_connected(_on_open_storage_changed):
			storage.changed.connect(_on_open_storage_changed)
	_setup_fuel_controls(record, panel)
	return true

func _build_fuel_view(building: Building, record: BuildingRecord, panel: InteractablePanel) -> bool:
	if building.definition.fuel_profile == null:
		return false
	var storage := record.get_fuel_storage()
	if storage == null:
		return false
	storage.stack_sizes = player.inventory.get_stack_sizes()
	panel.open_for(building.get_interaction_prompt().capitalize(), "Insert a fuel the station accepts, then turn it on.", storage, player.inventory.get_storage())
	_setup_fuel_controls(record, panel)
	return true

func _setup_fuel_controls(record: BuildingRecord, panel: InteractablePanel) -> void:
	if record.definition == null or record.definition.fuel_profile == null or player == null:
		return
	var profile: FuelProfile = record.definition.fuel_profile
	var storage := record.get_fuel_storage()
	storage.stack_sizes = player.inventory.get_stack_sizes()
	var database := get_parent().get_node_or_null("ItemDatabase") as ItemDatabase
	for index in range(storage.slot_count()):
		storage.set_slot_filter(index, func(item_id: String) -> bool:
			var item := database.get_item(item_id) if database != null else null
			if item == null:
				return false
			for tag in profile.accepted_tags:
				if item.has_tag(tag):
					return true
			return false)
	panel.configure_fuel(storage, bool(record.capability_state.get("enabled", false)),
			float(record.capability_state.get("fuel_seconds_remaining", 0.0)),
			", ".join(profile.accepted_tags))
	panel.fuel_toggle_requested.connect(_on_fuel_toggle_requested.bind(record))
	if not storage.changed.is_connected(_on_open_storage_changed):
		storage.changed.connect(_on_open_storage_changed)

func _on_fuel_toggle_requested(record: BuildingRecord) -> void:
	if open_record != record:
		return
	record.capability_state["enabled"] = not bool(record.capability_state.get("enabled", false))
	_on_open_storage_changed()

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
	# Craft feedback rides the panel's single toast lane; the manager owns the wording.
	if open_panel != null and is_instance_valid(open_panel):
		if bool(result.success):
			open_panel.toast_requested.emit("Crafted %dx %s" % [recipe.result_quantity, recipe.result_item_id.replace("_", " ").capitalize()])
		else:
			open_panel.toast_requested.emit(str(CRAFT_FAILURE_MESSAGES.get(str(result.reason), "Crafting failed")))
	_on_open_storage_changed()
