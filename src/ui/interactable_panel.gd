## The single shared panel for interacting with placed objects, presented in
## the same visual language as the player inventory (icon slots, drag &
## drop, shift-click) inside one centred window: a device column beside the
## player's own inventory grid, so every transfer is one drag. Containers
## (M5) show their storage grid; stations show recipe cards, per-recipe
## ingredient slots with have/need badges, an optional single fuel slot with
## live burn status, a timed craft progress bar, and take-only output slots
## where finished items wait for pickup. There is no per-object duplicate UI.
class_name InteractablePanel
extends Control

## Emitted for EVERY close path (Escape, button, manager reasons); the
## InteractionManager owns the actual close pipeline and stays idempotent.
signal close_requested(reason: String)
signal station_craft_requested(recipe_id: String)
## "Fill ingredients" from the player inventory for the selected recipe.
signal station_fill_requested(recipe_id: String)
signal fuel_toggle_requested
## Human wording for a refused transfer ("No room in that slot", ...). The
## InteractionManager routes it to the HUD toast lane; the panel itself only
## owns the wording, never the presentation.
signal toast_requested(text: String)

const SLOT_COLUMNS := 9
const DEVICE_COLUMN_MIN_WIDTH := 420.0
const RECIPE_ROW_MIN_HEIGHT := 38.0
const RECIPE_LIST_MAX_HEIGHT := 128.0

# Palette shared with the player inventory panel.
const COL_TITLE := Color(0.90, 0.92, 0.72)
const COL_TEXT := Color(0.91, 0.92, 0.84)
const COL_MUTED := Color(0.64, 0.69, 0.57)
const COL_ACCENT := Color(0.85, 0.92, 0.55)
const COL_GOOD := Color(0.65, 0.88, 0.58)
const COL_BAD := Color(0.85, 0.45, 0.40)

var object_grid: StorageGridView = null
var player_grid: StorageGridView = null
var output_grid: StorageGridView = null
var fuel_grid: StorageGridView = null
var is_open: bool = false

var _dim: ColorRect = null
var _window: PanelContainer = null
var _title_label: Label = null
var _help_label: Label = null
var _body: HBoxContainer = null
var _device_column: VBoxContainer = null
var _player_column: VBoxContainer = null
var _recipe_list: VBoxContainer = null
var _recipe_scroll: ScrollContainer = null
var _ingredient_grid: StorageGridView = null
var _ingredient_hint: Label = null
var _fuel_section: VBoxContainer = null
var _fuel_status_label: Label = null
var _fuel_accepted_label: Label = null
var _fuel_toggle_button: Button = null
var _craft_status_label: Label = null
var _progress_bar: ProgressBar = null
var _craft_button: Button = null
var _fill_button: Button = null
var _object_capacity_label: Label = null
var _player_capacity_label: Label = null

var _player_storage: InventoryStorage = null
var _object_storage: InventoryStorage = null
var _output_storage: InventoryStorage = null
var _fuel_storage: InventoryStorage = null
var _recipes: Array[RecipeDefinition] = []
var _selected: Dictionary = {} # {grid: String, index: int} or empty
var _selected_recipe_id := ""
var _fuel_accepted_hint := "" # accepted fuel tags, for the filtered-slot toast
var _fuel_enabled := false
var _fuel_seconds := 0.0
var _requires_power := false
var _powered := true
var _job: Dictionary = {} # live StationCrafting job view, pushed per frame

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP # world clicks never leak through
	visible = false

	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.02, 0.015, 0.7)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	# The centre area owns placement rather than a manual offset. This remains
	# correct on first layout, resize, and any aspect ratio.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# A PanelContainer (not a bare Panel) so the window sizes to its content.
	_window = PanelContainer.new()
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.add_theme_stylebox_override("panel", _make_window_style())
	center.add_child(_window)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 16)
	_window.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	root.add_child(_build_header())

	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 24)
	root.add_child(_body)

func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		close_requested.emit("escape")
		get_viewport().set_input_as_handled()

# --- Opening -------------------------------------------------------------

## Open the panel chrome over one placed object. The object grid (left) shows
## the record's container storage; the player grid (right) is the player's
## own inventory storage — one shared grid implementation each. A null
## object storage leaves the device column to a later configure_fuel().
func open_for(title: String, help: String, object_storage: InventoryStorage,
		player_storage: InventoryStorage) -> void:
	_object_storage = object_storage
	_player_storage = player_storage
	_output_storage = null
	_fuel_storage = null
	_recipes = []
	_selected_recipe_id = ""
	_job = {}
	_title_label.text = title
	_help_label.text = help
	_selected.clear()
	_reset_body()

	_device_column = _make_column()
	_body.add_child(_device_column)
	if object_storage != null:
		_device_column.add_child(_make_heading("CONTAINER"))
		object_grid = StorageGridView.new()
		_device_column.add_child(object_grid)
		object_grid.setup(object_storage, "object", SLOT_COLUMNS)
		_wire_grid(object_grid)
		_object_capacity_label = _make_muted_label("")
		_device_column.add_child(_object_capacity_label)

	_player_column = _make_column()
	_body.add_child(_player_column)
	_build_player_column()

	_finish_open()

## M6+ station form: recipe cards, per-recipe ingredient slots, optional fuel
## controls (configure_fuel), timed-craft progress, and take-only output —
## beside the same player inventory as containers.
## options: {"requires_power": bool, "selected_recipe_id": String}.
func open_station(title: String, help: String, input_storage: InventoryStorage,
		output_storage: InventoryStorage, player_storage: InventoryStorage,
		recipes: Array[RecipeDefinition], options: Dictionary = {}) -> void:
	_object_storage = input_storage
	_player_storage = player_storage
	_output_storage = output_storage
	_fuel_storage = null
	_recipes = recipes
	_requires_power = bool(options.get("requires_power", false))
	_powered = true
	_job = {}
	_title_label.text = title
	_help_label.text = help
	_selected.clear()
	_reset_body()

	_device_column = _make_column(DEVICE_COLUMN_MIN_WIDTH)
	_body.add_child(_device_column)

	_device_column.add_child(_make_heading("RECIPES"))
	_recipe_scroll = ScrollContainer.new()
	_recipe_scroll.custom_minimum_size = Vector2(0,
			minf(RECIPE_ROW_MIN_HEIGHT * recipes.size() + 6.0, RECIPE_LIST_MAX_HEIGHT))
	_recipe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_device_column.add_child(_recipe_scroll)
	_recipe_list = VBoxContainer.new()
	_recipe_list.add_theme_constant_override("separation", 4)
	_recipe_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_recipe_scroll.add_child(_recipe_list)
	_build_recipe_buttons()

	_device_column.add_child(_make_heading("INGREDIENTS"))
	_ingredient_grid = StorageGridView.new()
	_device_column.add_child(_ingredient_grid)
	_ingredient_grid.setup(input_storage, "object", maxi(input_storage.slot_count(), 1))
	_wire_grid(_ingredient_grid)
	_ingredient_hint = _make_muted_label("Pick a recipe to see its ingredient slots.")
	_device_column.add_child(_ingredient_hint)

	_fuel_section = VBoxContainer.new()
	_fuel_section.add_theme_constant_override("separation", 4)
	_fuel_section.visible = false
	_device_column.add_child(_fuel_section)

	_craft_status_label = _make_muted_label("")
	_device_column.add_child(_craft_status_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.custom_minimum_size = Vector2(0, 14)
	_progress_bar.show_percentage = false
	_progress_bar.visible = false
	var bar_background := StyleBoxFlat.new()
	bar_background.bg_color = Color(0.10, 0.14, 0.10, 0.96)
	bar_background.set_corner_radius_all(4)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.55, 0.66, 0.30, 1.0)
	bar_fill.set_corner_radius_all(4)
	_progress_bar.add_theme_stylebox_override("background", bar_background)
	_progress_bar.add_theme_stylebox_override("fill", bar_fill)
	_device_column.add_child(_progress_bar)

	var craft_row := HBoxContainer.new()
	craft_row.add_theme_constant_override("separation", 8)
	_device_column.add_child(craft_row)
	_fill_button = Button.new()
	_fill_button.text = "Fill ingredients"
	_fill_button.tooltip_text = "Pull the selected recipe's ingredients from your inventory"
	_fill_button.custom_minimum_size = Vector2(150, 36)
	_style_button(_fill_button, false)
	_fill_button.pressed.connect(_on_fill_pressed)
	craft_row.add_child(_fill_button)
	_craft_button = Button.new()
	_craft_button.text = "Craft"
	_craft_button.custom_minimum_size = Vector2(160, 36)
	_craft_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(_craft_button, true)
	_craft_button.pressed.connect(_on_craft_pressed)
	craft_row.add_child(_craft_button)

	var output_row := HBoxContainer.new()
	output_row.add_theme_constant_override("separation", 8)
	_device_column.add_child(output_row)
	var output_label := _make_heading("OUTPUT")
	output_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	output_row.add_child(output_label)
	output_grid = StorageGridView.new()
	output_row.add_child(output_grid)
	output_grid.setup(output_storage, "output", maxi(output_storage.slot_count(), 1), false, true)
	_wire_grid(output_grid)
	var take_button := Button.new()
	take_button.text = "Take"
	take_button.tooltip_text = "Move finished items into your inventory"
	take_button.custom_minimum_size = Vector2(84, 36)
	_style_button(take_button, false)
	take_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	take_button.pressed.connect(_on_take_all_pressed)
	output_row.add_child(take_button)

	_player_column = _make_column()
	_body.add_child(_player_column)
	_build_player_column()

	_apply_recipe_selection(str(options.get("selected_recipe_id", "")), true)
	_finish_open()

## Fuel controls for fuel-capable objects (stations and fuel-only devices).
## Renders a single filtered fuel slot with live burn status and the on/off
## toggle inside the device column.
func configure_fuel(storage: InventoryStorage, enabled: bool, seconds_remaining: float,
		accepted_fuel_hint: String = "") -> void:
	_fuel_storage = storage
	_fuel_enabled = enabled
	_fuel_seconds = seconds_remaining
	_fuel_accepted_hint = accepted_fuel_hint
	if _fuel_section == null:
		_fuel_section = VBoxContainer.new()
		_fuel_section.add_theme_constant_override("separation", 4)
		if _device_column != null:
			_device_column.add_child(_fuel_section)
	_fuel_section.visible = true
	for child in _fuel_section.get_children():
		child.queue_free()

	var fuel_row := HBoxContainer.new()
	fuel_row.add_theme_constant_override("separation", 10)
	_fuel_section.add_child(fuel_row)
	fuel_grid = StorageGridView.new()
	fuel_row.add_child(fuel_grid)
	fuel_grid.setup(storage, "fuel", 1)
	_wire_grid(fuel_grid)

	var fuel_info := VBoxContainer.new()
	fuel_info.add_theme_constant_override("separation", 2)
	fuel_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fuel_row.add_child(fuel_info)
	_fuel_status_label = _make_muted_label("")
	fuel_info.add_child(_fuel_status_label)
	_fuel_accepted_label = _make_muted_label("")
	fuel_info.add_child(_fuel_accepted_label)
	_fuel_toggle_button = Button.new()
	_fuel_toggle_button.custom_minimum_size = Vector2(120, 30)
	_fuel_toggle_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_style_button(_fuel_toggle_button, false)
	_fuel_toggle_button.pressed.connect(func(): fuel_toggle_requested.emit())
	fuel_info.add_child(_fuel_toggle_button)
	_refresh()
	_update_station_widgets()

## Per-frame device state pushed by the InteractionManager: power/fuel state
## and the live craft job, so status text, the progress bar, and the craft
## button stay truthful without the panel owning any simulation.
func update_station_runtime(state: Dictionary) -> void:
	_powered = bool(state.get("powered", true))
	_fuel_enabled = bool(state.get("enabled", false))
	_fuel_seconds = float(state.get("fuel_seconds", 0.0))
	var job: Variant = state.get("job", {})
	_job = job if typeof(job) == TYPE_DICTIONARY else {}
	_update_station_widgets()

func close_panel() -> void:
	is_open = false
	visible = false
	_selected.clear()

## Public refresh for the InteractionManager (storage changed underneath).
func refresh_grids() -> void:
	_refresh()

## Escape closes the topmost panel and consumes the key so no other UI or
## world action sees it.
func blocks_world_input() -> bool:
	return is_open

# --- Layout helpers ------------------------------------------------------

func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 2)
	header.add_child(titles)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", COL_TITLE)
	titles.add_child(_title_label)
	_help_label = Label.new()
	_help_label.add_theme_font_size_override("font_size", 12)
	_help_label.add_theme_color_override("font_color", COL_MUTED)
	_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_help_label)
	var close_button := Button.new()
	close_button.text = "✕"
	close_button.tooltip_text = "Close (Esc)"
	close_button.custom_minimum_size = Vector2(34, 34)
	_style_button(close_button, false)
	close_button.pressed.connect(func(): close_requested.emit("button"))
	header.add_child(close_button)
	return header

func _build_player_column() -> void:
	_player_column.add_child(_make_heading("INVENTORY"))
	# Height-capped scroll: inventories larger than six rows scroll instead of
	# stretching the window (sandbox grants 200 slots).
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 6.0 * StorageGridView.SLOT_SIZE + 5.0 * StorageGridView.SLOT_GAP)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_player_column.add_child(scroll)
	player_grid = StorageGridView.new()
	player_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(player_grid)
	player_grid.setup(_player_storage, "player", SLOT_COLUMNS)
	_wire_grid(player_grid)
	_player_capacity_label = _make_muted_label("")
	_player_column.add_child(_player_capacity_label)

func _build_recipe_buttons() -> void:
	for recipe in _recipes:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = _recipe_button_group()
		button.text = _recipe_button_text(recipe)
		button.tooltip_text = "%s\n%s\nTime: %s" % [_recipe_display_name(recipe),
				recipe.get_cost_string(), _recipe_time_text(recipe)]
		button.custom_minimum_size = Vector2(0, RECIPE_ROW_MIN_HEIGHT - 4.0)
		button.icon = _icon_for(recipe.result_item_id)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 13)
		_style_button(button, false)
		_style_toggle_button(button)
		button.pressed.connect(_on_recipe_pressed.bind(recipe.recipe_id))
		_recipe_list.add_child(button)

var _recipe_group_ref: ButtonGroup = null

func _recipe_button_group() -> ButtonGroup:
	if _recipe_group_ref == null:
		_recipe_group_ref = ButtonGroup.new()
	return _recipe_group_ref

func _make_column(min_width: float = 0.0) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	if min_width > 0.0:
		column.custom_minimum_size = Vector2(min_width, 0)
	return column

func _make_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", COL_MUTED)
	return label

func _make_muted_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COL_MUTED)
	return label

func _reset_body() -> void:
	object_grid = null
	player_grid = null
	output_grid = null
	fuel_grid = null
	_ingredient_grid = null
	_recipe_list = null
	_recipe_scroll = null
	_fuel_section = null
	_fuel_status_label = null
	_fuel_accepted_label = null
	_fuel_toggle_button = null
	_craft_status_label = null
	_progress_bar = null
	_craft_button = null
	_fill_button = null
	_object_capacity_label = null
	_player_capacity_label = null
	_recipe_group_ref = null
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()

func _finish_open() -> void:
	is_open = true
	visible = true
	_refresh()

func _make_window_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.075, 0.055, 0.98)
	style.border_color = Color(0.41, 0.50, 0.28, 0.96)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0.0, 3.0)
	return style

func _style_button(button: Button, accent: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.30, 0.40, 0.19) if accent else Color(0.16, 0.22, 0.14)
	normal.border_color = COL_ACCENT if accent else Color(0.45, 0.55, 0.35, 0.9)
	normal.set_border_width_all(1 if not accent else 2)
	normal.set_corner_radius_all(5)
	normal.content_margin_left = 12.0
	normal.content_margin_right = 12.0
	normal.content_margin_top = 6.0
	normal.content_margin_bottom = 6.0
	var hover := normal.duplicate()
	hover.bg_color = Color(0.38, 0.50, 0.23) if accent else Color(0.22, 0.30, 0.18)
	var pressed_style := normal.duplicate()
	pressed_style.bg_color = Color(0.24, 0.32, 0.15) if accent else Color(0.12, 0.17, 0.10)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.12, 0.15, 0.11)
	disabled.border_color = Color(0.35, 0.42, 0.30, 0.6)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color(0.94, 0.95, 0.84) if accent else COL_TEXT)
	button.add_theme_color_override("font_hover_color", Color(0.97, 0.98, 0.88))
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.60, 0.50))

## Toggle-mode buttons (recipe cards) get an explicit checked look; the
## shared styleboxes would otherwise leave selection invisible.
func _style_toggle_button(button: Button) -> void:
	var checked := StyleBoxFlat.new()
	checked.bg_color = Color(0.26, 0.34, 0.17)
	checked.border_color = COL_ACCENT
	checked.set_border_width_all(2)
	checked.set_corner_radius_all(5)
	checked.content_margin_left = 12.0
	checked.content_margin_right = 12.0
	checked.content_margin_top = 6.0
	checked.content_margin_bottom = 6.0
	button.add_theme_stylebox_override("pressed", checked)
	button.add_theme_color_override("font_pressed_color", Color(0.97, 0.98, 0.88))

func _wire_grid(grid: StorageGridView) -> void:
	grid.slot_pressed.connect(_on_grid_slot_pressed)
	grid.quick_transfer_requested.connect(_on_quick_transfer)
	grid.drag_transfer_requested.connect(_on_drag_transfer)

# --- Recipe selection ----------------------------------------------------

func _recipe_by_id(recipe_id: String) -> RecipeDefinition:
	for recipe in _recipes:
		if recipe.recipe_id == recipe_id:
			return recipe
	return null

func _recipe_display_name(recipe: RecipeDefinition) -> String:
	var database := get_tree().root.get_node_or_null("Main/ItemDatabase") as ItemDatabase
	if database != null:
		return database.get_item_display_name(recipe.result_item_id)
	return recipe.result_item_id.capitalize()

func _recipe_time_text(recipe: RecipeDefinition) -> String:
	var seconds := int(ceil(float(recipe.craft_time)))
	return "%ds" % seconds if seconds > 0 else "instant"

func _recipe_button_text(recipe: RecipeDefinition) -> String:
	var quantity_suffix := "" if recipe.result_quantity == 1 \
			else "  x%d" % recipe.result_quantity
	return "%s%s   ·   %s" % [_recipe_display_name(recipe), quantity_suffix,
			_recipe_time_text(recipe)]

func _on_recipe_pressed(recipe_id: String) -> void:
	_apply_recipe_selection(recipe_id, false)

## Apply a recipe's ingredient contract to the input storage: one filtered
## slot per distinct ingredient (extra slots hidden), with have/need badges.
## Anything the new contract refuses is returned to the player inventory so
## no ingredient is ever stranded in a hidden slot.
func _apply_recipe_selection(recipe_id: String, silent: bool) -> void:
	var recipe := _recipe_by_id(recipe_id)
	if recipe == null or _object_storage == null:
		return
	var changed_recipe := _selected_recipe_id != recipe_id
	_selected_recipe_id = recipe_id
	var required: Dictionary = recipe.required_items
	var returned := 0
	if changed_recipe and _player_storage != null:
		for index in range(_object_storage.slot_count()):
			var item_id := _object_storage.item_id_at(index)
			if item_id == "" or required.has(item_id):
				continue
			returned += int(InventoryTransfer.transfer_between(_object_storage,
					_player_storage, item_id, _object_storage.quantity_at(index))
					.get(InventoryTransfer.RESULT_MOVED, 0))
	for index in range(_object_storage.slot_count()):
		_object_storage.clear_slot_filter(index)
	var slot := 0
	for item_id in required:
		if slot >= _object_storage.slot_count():
			break
		var wanted := str(item_id)
		_object_storage.set_slot_filter(slot, func(candidate: String) -> bool:
			return candidate == wanted)
		slot += 1
	if _ingredient_grid != null:
		var requirements: Dictionary = {}
		var index := 0
		for item_id in required:
			requirements[index] = {"item_id": str(item_id), "needed": int(required[item_id])}
			index += 1
		_ingredient_grid.requirements = requirements
		# Keep any slot that still holds an item the contract could not
		# return (full inventory) visible so it is never lost from view.
		var occupied_beyond := -1
		for check_index in range(_object_storage.slot_count()):
			if _object_storage.item_id_at(check_index) != "":
				occupied_beyond = check_index
		_ingredient_grid.visible_slot_count = maxi(required.size(), occupied_beyond + 1)
		if _ingredient_hint != null:
			_ingredient_hint.text = "Badges show have / need — fill every slot to craft."
	if returned > 0 and not silent:
		toast_requested.emit("Returned %d item%s to your inventory"
				% [returned, "" if returned == 1 else "s"])
	_refresh()

# --- Craft / fill / output actions ---------------------------------------

func _on_craft_pressed() -> void:
	if _selected_recipe_id != "" and _job.is_empty():
		station_craft_requested.emit(_selected_recipe_id)

func _on_fill_pressed() -> void:
	if _selected_recipe_id != "":
		station_fill_requested.emit(_selected_recipe_id)

func _on_take_all_pressed() -> void:
	if _output_storage == null or _player_storage == null:
		return
	var moved := 0
	for index in range(_output_storage.slot_count()):
		var item_id := _output_storage.item_id_at(index)
		if item_id == "":
			continue
		moved += int(InventoryTransfer.transfer_between(_output_storage, _player_storage,
				item_id, _output_storage.quantity_at(index)).get(InventoryTransfer.RESULT_MOVED, 0))
	if moved <= 0:
		toast_requested.emit("No room in your inventory")
	_refresh()

## Output slots are take-only: any click moves that result into the player
## inventory. There is deliberately no way to put items back in.
func _take_from_output(index: int) -> void:
	if _output_storage == null or _player_storage == null:
		return
	var item_id := _output_storage.item_id_at(index)
	if item_id == "":
		return
	var moved := int(InventoryTransfer.transfer_between(_output_storage, _player_storage,
			item_id, _output_storage.quantity_at(index)).get(InventoryTransfer.RESULT_MOVED, 0))
	if moved <= 0:
		toast_requested.emit("No room in your inventory")
	_refresh()

# --- Transfer semantics (all through the transactional InventoryTransfer) --

func _on_grid_slot_pressed(grid_id: String, index: int, mouse_button: int) -> void:
	if grid_id == "output":
		_take_from_output(index)
		return
	if mouse_button == MOUSE_BUTTON_RIGHT:
		# Deterministic split: right-click moves half the stack to the other
		# grid (the ceil half stays, so a stack can be divided repeatedly).
		var from_storage := _storage_for(grid_id)
		var to_storage := _other_storage(grid_id)
		if from_storage == null or to_storage == null:
			return
		var quantity := from_storage.quantity_at(index)
		if quantity <= 0:
			return
		var item_id := from_storage.item_id_at(index)
		var half := maxi(1, quantity / 2)
		var target_slot := to_storage.find_receiving_slot_for(item_id, half)
		if target_slot < 0:
			_toast_for_rejection(grid_id, "no_space")
		else:
			var outcome := InventoryTransfer.transfer(from_storage, index, to_storage,
					target_slot, half)
			if int(outcome[InventoryTransfer.RESULT_MOVED]) <= 0:
				_toast_for_rejection(grid_id, str(outcome[InventoryTransfer.RESULT_REJECTED]))
		_selected.clear()
		_refresh()
		return
	# Left click: select, or move the selection into the clicked slot.
	if _selected.is_empty():
		var storage := _storage_for(grid_id)
		if storage != null and storage.quantity_at(index) > 0:
			_selected = {"grid": grid_id, "index": index}
		_refresh()
		return
	if str(_selected["grid"]) == grid_id and int(_selected["index"]) == index:
		_selected.clear()
		_refresh()
		return
	var from_storage := _storage_for(str(_selected["grid"]))
	var to_storage := _storage_for(grid_id)
	if from_storage == null or to_storage == null:
		_selected.clear()
		_refresh()
		return
	var outcome := InventoryTransfer.transfer(from_storage, int(_selected["index"]),
			to_storage, index, from_storage.quantity_at(int(_selected["index"])))
	if int(outcome[InventoryTransfer.RESULT_MOVED]) > 0 or bool(outcome[InventoryTransfer.RESULT_SWAPPED]):
		_selected.clear()
	else:
		_toast_for_rejection(grid_id, str(outcome[InventoryTransfer.RESULT_REJECTED]))
	_refresh()

## Shift-click: move the whole stack to the other grid (first slots that
## accept it), via the transactional transfer routine.
func _on_quick_transfer(grid_id: String, index: int) -> void:
	if grid_id == "output":
		_take_from_output(index)
		return
	var from_storage := _storage_for(grid_id)
	var to_storage := _other_storage(grid_id)
	if from_storage == null or to_storage == null:
		return
	var item_id := from_storage.item_id_at(index)
	if item_id == "":
		return
	var outcome := InventoryTransfer.transfer_between(from_storage, to_storage, item_id,
			from_storage.quantity_at(index))
	if int(outcome[InventoryTransfer.RESULT_MOVED]) <= 0:
		_toast_for_rejection(grid_id, str(outcome[InventoryTransfer.RESULT_REJECTED]))
	_selected.clear()
	_refresh()

func _on_drag_transfer(from_grid: String, from_index: int, to_grid: String, to_index: int) -> void:
	if to_grid == "output":
		return # take-only: drops never land on output slots
	var from_storage := _storage_for(from_grid)
	var to_storage := _storage_for(to_grid)
	if from_storage == null or to_storage == null:
		return
	var outcome := InventoryTransfer.transfer(from_storage, from_index, to_storage, to_index,
			from_storage.quantity_at(from_index))
	if int(outcome[InventoryTransfer.RESULT_MOVED]) <= 0 \
			and not bool(outcome[InventoryTransfer.RESULT_SWAPPED]):
		_toast_for_rejection(to_grid, str(outcome[InventoryTransfer.RESULT_REJECTED]))
	_selected.clear()
	_refresh()

## Translate the transfer layer's rejection codes into the words a player
## hears. The transfer layer stays generic (no presentation); the panel owns
## the wording. Grid context matters: the same "filtered" code on a fuel slot
## names the accepted tags, on an ingredient slot it points at the badge.
func _toast_for_rejection(grid_id: String, reason: String) -> void:
	var text := ""
	match reason:
		"full", "occupied":
			text = "No room in that slot"
		"filtered":
			if grid_id == "fuel" and not _fuel_accepted_hint.is_empty():
				text = "That fuel slot only accepts: %s" % _fuel_accepted_hint
			elif grid_id == "object" and not _recipes.is_empty():
				text = "That ingredient slot only accepts the item shown on it"
			else:
				text = "That slot only accepts specific items"
		"cannot_swap":
			text = "Those two stacks can't swap"
		"no_space":
			text = "No room on the other side"
		_:
			if reason != "":
				text = "Can't move that"
	if text != "":
		toast_requested.emit(text)

func _storage_for(grid_id: String) -> InventoryStorage:
	if grid_id == "object":
		return _object_storage
	if grid_id == "player":
		return _player_storage
	if grid_id == "output":
		return _output_storage
	if grid_id == "fuel":
		return _fuel_storage
	return null

## Everything moves to or from the player's inventory: containers swap with
## their object storage, stations take ingredients/fuel in and results out.
func _other_storage(grid_id: String) -> InventoryStorage:
	if grid_id == "player":
		return _object_storage
	return _player_storage

# --- Refresh -------------------------------------------------------------

func _refresh() -> void:
	if object_grid != null:
		object_grid.refresh()
		object_grid.highlight_selected(int(_selected.get("index", -1)) if str(_selected.get("grid", "")) == "object" else -1)
	if _ingredient_grid != null:
		_ingredient_grid.refresh()
		_ingredient_grid.highlight_selected(int(_selected.get("index", -1)) if str(_selected.get("grid", "")) == "object" else -1)
	if player_grid != null:
		player_grid.refresh()
		player_grid.highlight_selected(int(_selected.get("index", -1)) if str(_selected.get("grid", "")) == "player" else -1)
	if output_grid != null:
		output_grid.refresh()
	if fuel_grid != null:
		fuel_grid.refresh()
	if _object_capacity_label != null:
		_object_capacity_label.text = _storage_summary("Container", _object_storage)
	if _player_capacity_label != null:
		_player_capacity_label.text = _storage_summary("Inventory", _player_storage)
	_update_station_widgets()

func _storage_summary(label: String, storage: InventoryStorage) -> String:
	if storage == null:
		return "%s unavailable" % label
	var contents := "Empty" if storage.occupied_count() == 0 else "%d/%d slots" % [storage.occupied_count(), storage.slot_count()]
	return "%s: %s  ·  %.0f / %.0f weight" % [label, contents, storage.total_weight(), storage.max_weight]

# --- Station widget state ------------------------------------------------

func _icon_for(item_id: String) -> Texture2D:
	if item_id.is_empty():
		return null
	var database := get_tree().root.get_node_or_null("Main/ItemDatabase") as ItemDatabase
	if database == null:
		return null
	var item := database.get_item(item_id)
	if item == null or item.texture_path.is_empty():
		return null
	return TexturePackManager.get_texture(item.texture_path)

func _selected_recipe() -> RecipeDefinition:
	return _recipe_by_id(_selected_recipe_id)

## Live truth for the fuel row, progress bar, and craft button. Kept cheap —
## the InteractionManager pushes this every frame while the panel is open.
func _update_station_widgets() -> void:
	_update_fuel_widgets()
	_update_craft_widgets()

func _update_fuel_widgets() -> void:
	if _fuel_status_label == null:
		return
	if _fuel_enabled:
		var total_seconds := int(_fuel_seconds)
		_fuel_status_label.text = "Burning — %d:%02d remaining" % [int(total_seconds / 60.0), total_seconds % 60] \
				if _fuel_seconds > 0.0 else "Out of fuel"
		_fuel_status_label.add_theme_color_override("font_color",
				COL_GOOD if _fuel_seconds > 0.0 else COL_BAD)
	else:
		_fuel_status_label.text = "Off"
		_fuel_status_label.add_theme_color_override("font_color", COL_MUTED)
	_fuel_accepted_label.text = "Accepts: %s" % _fuel_accepted_hint \
			if not _fuel_accepted_hint.is_empty() else ""
	if _fuel_toggle_button != null:
		_fuel_toggle_button.text = "Turn off" if _fuel_enabled else "Turn on"

func _update_craft_widgets() -> void:
	if _craft_status_label == null:
		return
	var recipe := _selected_recipe()
	# Active job: progress bar and a disabled craft button.
	if not _job.is_empty():
		var total := maxf(float(_job.get("total", 1.0)), 0.0001)
		var remaining := maxf(float(_job.get("remaining", 0.0)), 0.0)
		var job_recipe := _recipe_by_id(str(_job.get("recipe_id", "")))
		var job_name := _recipe_display_name(job_recipe) if job_recipe != null else "item"
		_progress_bar.visible = true
		_progress_bar.value = 1.0 - remaining / total
		if _requires_power and not _powered:
			_craft_status_label.text = "Crafting paused — the station is unpowered"
			_craft_status_label.add_theme_color_override("font_color", COL_BAD)
		elif remaining <= 0.0:
			_craft_status_label.text = "%s finished — no room in the output slot" % job_name
			_craft_status_label.add_theme_color_override("font_color", COL_BAD)
		else:
			_craft_status_label.text = "Crafting %s — %ds left" % [job_name, int(ceil(remaining))]
			_craft_status_label.add_theme_color_override("font_color", COL_TEXT)
		_craft_button.disabled = true
		_craft_button.text = "Crafting…"
		_fill_button.disabled = true
		return
	_progress_bar.visible = false
	_fill_button.disabled = _selected_recipe_id == ""
	if recipe == null:
		_craft_status_label.text = "Pick a recipe to craft." if not _recipes.is_empty() \
				else "This station has no recipes."
		_craft_status_label.add_theme_color_override("font_color", COL_MUTED)
		_craft_button.disabled = true
		_craft_button.text = "Craft"
		return
	_craft_button.text = "Craft %s (%s)" % [_recipe_display_name(recipe), _recipe_time_text(recipe)]
	var missing := _missing_ingredients(recipe)
	if not missing.is_empty():
		_craft_status_label.text = "Missing: %s" % ", ".join(missing)
		_craft_status_label.add_theme_color_override("font_color", COL_BAD)
		_craft_button.disabled = true
	elif _requires_power and not _powered:
		_craft_status_label.text = "Station is unpowered — add fuel and turn it on"
		_craft_status_label.add_theme_color_override("font_color", COL_BAD)
		_craft_button.disabled = true
	elif _output_storage != null and not _output_can_receive(recipe):
		_craft_status_label.text = "Output is full — take the result first"
		_craft_status_label.add_theme_color_override("font_color", COL_BAD)
		_craft_button.disabled = true
	else:
		_craft_status_label.text = "Ready to craft."
		_craft_status_label.add_theme_color_override("font_color", COL_GOOD)
		_craft_button.disabled = false

func _missing_ingredients(recipe: RecipeDefinition) -> Array[String]:
	var missing: Array[String] = []
	var database := get_tree().root.get_node_or_null("Main/ItemDatabase") as ItemDatabase
	for item_id in recipe.required_items:
		var needed := int(recipe.required_items[item_id])
		var have := _object_storage.quantity_of(str(item_id)) if _object_storage != null else 0
		if have < needed:
			var display_name := str(item_id).replace("_", " ").capitalize()
			if database != null:
				display_name = database.get_item_display_name(str(item_id))
			missing.append("%dx %s" % [needed - have, display_name])
	return missing

func _output_can_receive(recipe: RecipeDefinition) -> bool:
	var remaining := recipe.result_quantity
	for index in range(_output_storage.slot_count()):
		remaining -= _output_storage.acceptance_at(index, recipe.result_item_id, remaining)
		if remaining <= 0:
			return true
	return false
