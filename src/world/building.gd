## Placeable structure with health, collision, and a colored placeholder.
class_name Building
extends StaticBody2D

const TILE_SIZE: float = 32.0
## Placeholder tints for parts whose authored atlas art has not landed yet.
## Keyed by visual family — structural material vocabulary, like the layer
## names, never content: adding a new part or tier needs a data asset with a
## family (and an optional per-part override color), not a code branch.
const PLACEHOLDER_FAMILY_COLORS := {
	"wood": Color(0.55, 0.35, 0.18, 0.95),
	"stone": Color(0.55, 0.55, 0.58, 0.95),
	"metal": Color(0.45, 0.48, 0.55, 0.95),
	"primitive": Color(0.5, 0.55, 0.4, 0.95),
}
const PLACEHOLDER_DEFAULT_COLOR := Color(0.5, 0.55, 0.4, 0.95)

var building_id: String = ""
var display_name: String = "Building"
var health: int = 50
var max_health: int = 50
var tile_coords: Vector2i = Vector2i.ZERO
var story: int = 0
var part_type: String = "utility"
var tier: String = ""
var blocks_movement: bool = true
var layer: String = "object"
var orientation: String = ""

## The authored BuildingDefinition this part was placed from (null in legacy
## test contexts); capability data (interaction profile, container, ...) is
## read from here — never inferred from the item id.
var definition: Variant = null

## Stable identity derived from the placement. Owned by the BuildingRecord;
## kept here for UI ownership and save-keyed lookups. Never a NodePath,
## creation order, or random id.
var placement_key: String = ""

## Per-placed-object runtime state for the capabilities its definition
## declares (container contents, fuel remaining, enabled flag, ...). The
## authoritative copy lives on the BuildingRecord and is serialized inside
## the building's save entry as `state`. Generic by design.
var capability_state: Dictionary = {}

## How far an edge part's art nudges toward its oriented edge (cheap
## readability for the edge model until the dedicated edge art lands).
const EDGE_VISUAL_OFFSET: float = 6.0
## How far a wall fixture's art hangs past its wall face: a wall nudges 6 px
## toward its edge, a fixture mounted on that face sits just outside it.
const FIXTURE_VISUAL_OFFSET: float = 12.0
## Per-story visual offset in the EXTERIOR presentation: each story's parts
## rise one full tile straight up per story — a south-facing billboard
## projection (the Stardew-style building look). The topmost roof caps the
## structure, and every story's south wall row shows in full below the mass
## above it as that floor's front facade (doors and windows on the south
## face show their own art there). Node position and collision never move;
## interior and build views keep their exact top-down alignment.
const EXTERIOR_STORY_OFFSET := Vector2(0.0, -TILE_SIZE)
## Cosmetic lights outside this radius cannot affect the active view, so they
## stay disabled without needing a per-light manager scan.
const LIGHT_CULL_RADIUS_PX: float = 960.0

var _body: Polygon2D = null
var _part_sprite: Sprite2D = null
## Front-elevation sprite for the exterior billboard projection (the
## part's facade_atlas art on its south-facing wall face). Created only
## for parts whose definition ships facade art; visibility is owned by
## set_presentation (exterior shell parts facing south only).
var _facade_sprite: Sprite2D = null
var _appearance_sprite: Sprite2D = null
var _appearance_state: String = ""
## Position within the current state's frame strip (0-based). Looping states
## advance this every frame from authored fps data; one-shot transition states
## are stepped by the open/close coroutine instead.
var _state_frame_index: int = 0
var _state_frame_accumulator: float = 0.0
## Bumped on every state change; in-flight transition coroutines abort when
## the token moves (a fast close must cancel a pending settle, not fight it).
var _transition_token: int = 0
var _light: PointLight2D = null
static var _shared_light_texture: GradientTexture2D = null
## BuildingManager owns the global nearest-first cap. Individual buildings
## still perform their cheap range/daylight checks, but never self-promote
## above that shared cap.
var _light_budget_allowed := true
var _label: Label = null
var _health_bar: ProgressBar = null
## Current per-story presentation offset applied to the visual children (see
## set_visual_offset and EXTERIOR_STORY_OFFSET).
var visual_offset: Vector2 = Vector2.ZERO
## Setup-time base position of every visual child, so set_visual_offset can
## re-anchor them relative to where the part actually sits on the grid.
var _visual_base: Dictionary = {}

signal building_destroyed
signal building_damaged(current_health: int, max_health: int)

func setup(item_id: String, item_name: String, tile: Vector2i, hp: int = 50, story_level: int = 0, definition: Variant = null, placement_layer: String = "", edge_orientation: String = "") -> void:
	building_id = item_id
	display_name = item_name
	tile_coords = tile
	story = story_level
	health = hp
	max_health = hp
	placement_key = "%d:%d:%d" % [tile.x, tile.y, story]
	layer = placement_layer if placement_layer != "" else (str(definition.effective_placement_layer()) if definition != null else "object")
	orientation = edge_orientation
	self.definition = definition
	# Aligned top-down: the node (and its collision) stays at the part's grid
	# position — every story shares the same world X/Y (the floor-plan
	# model). Interior and build views keep exact alignment; only the
	# EXTERIOR view shifts each story's visuals (set_visual_offset /
	# set_presentation), never the node or collision.
	position = Vector2(tile) * TILE_SIZE
	part_type = str(definition.get("part_type")) if definition != null else "utility"
	tier = str(definition.get("tier")) if definition != null else ""
	blocks_movement = bool(definition.get("blocks_movement")) if definition != null else _id_blocks(item_id)
	z_index = _render_band()
	_setup_visuals()
	_setup_collision()
	_setup_light()
	# Base positions for the per-story visual offset: every visual child,
	# never the collision shape (which must stay grid-anchored).
	_visual_base.clear()
	for child in get_children():
		if child is CollisionShape2D:
			continue
		if not (child is Node2D):
			# UI overlays (name label, health bar) are Controls, not
			# grid-anchored 2D art; they never take the exterior offset.
			continue
		_visual_base[child] = child.position
	set_visual_offset(Vector2.ZERO)

func _process(delta: float) -> void:
	_update_light()
	_advance_appearance_frames(delta)

func _id_blocks(item_id: String) -> bool:
	return item_id.ends_with("wall") or item_id == "fence" or item_id == "wooden_door"

func _setup_visuals() -> void:
	var edge_offset := _edge_visual_offset()
	_body = Polygon2D.new()
	var inset: float = 2.0
	_body.polygon = PackedVector2Array([
		Vector2(inset, inset),
		Vector2(TILE_SIZE - inset, inset),
		Vector2(TILE_SIZE - inset, TILE_SIZE - inset),
		Vector2(inset, TILE_SIZE - inset)
	])
	_body.color = _placeholder_color()
	_body.position = edge_offset
	add_child(_body)
	_setup_appearance_visual(edge_offset)
	var atlas := _definition_atlas()
	if not atlas.is_empty():
		# Every placed part renders from the atlas reference its own
		# BuildingDefinition carries (sheet path + cell); the flat color
		# placeholder stays as the fallback when a part has no reference
		# yet or its sheet is missing. No per-item-id lookups anywhere.
		# Parts with a state-sheet appearance get their base atlas sprite on
		# top of the appearance sprite (the appearance sheet carries the
		# animated states; the atlas cell keeps the static base art underneath).
		_body.color = Color(0.0, 0.0, 0.0, 0.0)
		_part_sprite = Sprite2D.new()
		_part_sprite.position = Vector2(TILE_SIZE, TILE_SIZE) * 0.5 + edge_offset
		_part_sprite.region_enabled = true
		_part_sprite.region_rect = Rect2(float(atlas["cell"].x) * TILE_SIZE, float(atlas["cell"].y) * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		_part_sprite.texture = TexturePackManager.get_texture(atlas["path"])
		add_child(_part_sprite)
	# The facade sprite stacks above the top-down art: exterior mode swaps
	# the south-facing shell face to the authored front elevation, every
	# other view keeps the top-down cell.
	var facade := _definition_facade_atlas()
	if not facade.is_empty():
		_facade_sprite = Sprite2D.new()
		_facade_sprite.position = Vector2(TILE_SIZE, TILE_SIZE) * 0.5 + edge_offset
		_facade_sprite.region_enabled = true
		_facade_sprite.region_rect = Rect2(float(facade["cell"].x) * TILE_SIZE, float(facade["cell"].y) * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		_facade_sprite.texture = TexturePackManager.get_texture(facade["path"])
		_facade_sprite.visible = false
		add_child(_facade_sprite)

	_label = Label.new()
	_label.text = "%s  L%d" % [display_name, story + 1]
	_label.position = Vector2(0.0, -16.0)
	_label.add_theme_font_size_override("font_size", 10)
	# The world already identifies usable objects through the focused
	# interaction prompt. Persistent labels turn a furnished room into an
	# unreadable wall of text, so names are not drawn over normal play.
	_label.visible = false
	add_child(_label)

	_health_bar = ProgressBar.new()
	_health_bar.min_value = 0
	_health_bar.max_value = max_health
	_health_bar.value = health
	_health_bar.custom_minimum_size = Vector2(TILE_SIZE, 4)
	_health_bar.position = Vector2(0.0, -6.0)
	_health_bar.show_percentage = false
	# A pristine structure needs no combat-style health UI. Reveal this only
	# after damage, where it is actionable feedback rather than visual noise.
	_health_bar.visible = health < max_health
	add_child(_health_bar)

func reload_visual_texture() -> void:
	if _part_sprite != null and definition != null:
		var atlas := _definition_atlas()
		if not atlas.is_empty():
			_part_sprite.texture = TexturePackManager.get_texture(atlas["path"])
	if _facade_sprite != null and definition != null:
		var facade := _definition_facade_atlas()
		if not facade.is_empty():
			_facade_sprite.texture = TexturePackManager.get_texture(facade["path"])
	if _appearance_sprite != null and definition != null and definition.appearance_profile != null:
		_appearance_sprite.texture = TexturePackManager.get_texture(definition.appearance_profile.sheet_path)

## One shared radial texture backs every profile-driven local light. The
## profile controls radius, colour, energy, flicker, and daylight policy;
## buildings supply no ID-specific presentation logic.
func _setup_light() -> void:
	if definition == null or definition.light_profile == null:
		return
	var profile: LightProfile = definition.light_profile
	if _shared_light_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		_shared_light_texture = GradientTexture2D.new()
		_shared_light_texture.gradient = gradient
		_shared_light_texture.width = 128
		_shared_light_texture.height = 128
		_shared_light_texture.fill = GradientTexture2D.FILL_RADIAL
		# Anchor the radial fill at the texture centre (half-height above
		# bottom) — exactly the geometry the player's held light uses. Without
		# explicit from/to vectors Godot defaults to a corner-anchored fill,
		# which renders every placed light as an off-centre quarter disc.
		_shared_light_texture.fill_from = Vector2(0.5, 0.5)
		_shared_light_texture.fill_to = Vector2(0.5, 0.0)
	_light = PointLight2D.new()
	_light.texture = _shared_light_texture
	# Same additive blend as the player's held light, so placed lights and
	# the carried one read as the same effect at any tier.
	_light.blend_mode = Light2D.BLEND_MODE_ADD
	_light.position = Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	_light.color = profile.color
	_light.energy = profile.energy
	_light.texture_scale = profile.radius_px / 64.0
	_light.visible = false
	add_child(_light)

func _update_light() -> void:
	if _light == null or definition == null or definition.light_profile == null:
		return
	var profile: LightProfile = definition.light_profile
	var parent := get_parent()
	var main := parent.get_parent() if parent != null else null
	var cycle := main.get_node_or_null("DayNightCycle") as DayNightCycle if main != null else null
	var player := main.get_node_or_null("Player") as Node2D if main != null else null
	var in_light_budget := player == null or global_position.distance_to(player.global_position) <= LIGHT_CULL_RADIUS_PX
	var allowed_by_daylight := profile.daylight_policy == "always" or (cycle != null and cycle.is_nighttime())
	var powered := not profile.requires_power or bool(capability_state.get("enabled", false))
	_light.visible = _light_budget_allowed and in_light_budget and allowed_by_daylight and powered
	if definition.appearance_profile != null:
		var appearance: AppearanceProfile = definition.appearance_profile
		set_appearance_state(appearance.powered_state if powered else appearance.unpowered_state)
	if _light.visible:
		_light.energy = profile.energy * (1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.08 if profile.flicker else 1.0)

## BuildingManager calls this after deterministic nearest-first selection.
## Kept on the generic light capability so new light-bearing content needs no
## manager or item-ID branch.
func set_light_budget_allowed(allowed: bool) -> void:
	_light_budget_allowed = allowed

func has_local_light() -> bool:
	return _light != null and definition != null and definition.light_profile != null

## Build an authored state-sheet sprite when art is available. Assets may
## provide states before their dedicated sheet ships; in that case the normal
## atlas remains the honest visual fallback while state transitions still work.
func _setup_appearance_visual(edge_offset: Vector2) -> void:
	if definition == null or definition.appearance_profile == null:
		return
	var profile: AppearanceProfile = definition.appearance_profile
	if profile.sheet_path.is_empty() or not FileAccess.file_exists(profile.sheet_path):
		return
	_appearance_sprite = Sprite2D.new()
	_appearance_sprite.position = Vector2(TILE_SIZE, TILE_SIZE) * 0.5 + edge_offset
	_appearance_sprite.region_enabled = true
	_appearance_sprite.texture = TexturePackManager.get_texture(profile.sheet_path)
	add_child(_appearance_sprite)
	set_appearance_state(profile.initial_state)

## Set one data-authored visual state. The state machine is generic: neither
## this method nor callers identify individual buildings.
func set_appearance_state(state_name: String) -> void:
	if definition == null or definition.appearance_profile == null or state_name.is_empty():
		return
	var profile: AppearanceProfile = definition.appearance_profile
	var state: Variant = profile.states.get(state_name, null)
	if typeof(state) != TYPE_DICTIONARY:
		return
	_appearance_state = state_name
	_state_frame_index = 0
	_state_frame_accumulator = 0.0
	_apply_appearance_frame()

## Paint the current state's current frame from its authored strip position.
func _apply_appearance_frame() -> void:
	if _appearance_sprite == null or _appearance_state == "":
		return
	if definition == null or definition.appearance_profile == null:
		return
	var profile: AppearanceProfile = definition.appearance_profile
	var state: Variant = profile.states.get(_appearance_state, null)
	if typeof(state) != TYPE_DICTIONARY:
		return
	var first_frame := int(state.get("first_frame", 0))
	_appearance_sprite.region_rect = Rect2(0.0,
			float((first_frame + _state_frame_index) * profile.frame_size.y),
			float(profile.frame_size.x), float(profile.frame_size.y))

## Step the current state one authored frame forward (wraps inside its own
## frame_count). Shared by the looping playback in _process and the
## transition coroutine.
func _advance_appearance_step() -> void:
	if _appearance_state == "":
		return
	if definition == null or definition.appearance_profile == null:
		return
	var state: Variant = definition.appearance_profile.states.get(_appearance_state, null)
	if typeof(state) != TYPE_DICTIONARY:
		return
	var frame_count := int(state.get("frame_count", 1))
	if frame_count <= 0:
		return
	_state_frame_index = (_state_frame_index + 1) % frame_count
	_apply_appearance_frame()

## Looping multi-frame states (a burning fire, a flickering torch) play from
## their own _process using the authored fps — this is what keeps the
## presentation alive at 32 px. One-frame states and one-shot transitions do
## nothing here; a transition coroutine or a static frame owns them.
func _advance_appearance_frames(delta: float) -> void:
	if _appearance_sprite == null or _appearance_state == "":
		return
	if definition == null or definition.appearance_profile == null:
		return
	var state: Variant = definition.appearance_profile.states.get(_appearance_state, null)
	if typeof(state) != TYPE_DICTIONARY:
		return
	var frame_count := int(state.get("frame_count", 1))
	if frame_count <= 1 or not bool(state.get("loop", false)):
		return
	var fps := float(state.get("fps", 0.0))
	if fps <= 0.0:
		return
	_state_frame_accumulator += delta
	var frame_duration := 1.0 / fps
	while _state_frame_accumulator >= frame_duration:
		_state_frame_accumulator -= frame_duration
		_advance_appearance_step()

## Inform a profile-driven appearance that its interaction has opened or
## closed. The authored transition state plays frame by frame at its own fps
## (a hold when it is a single frame) and then settles into the resting state;
## a fast re-trigger bumps the token and cancels the in-flight settle. Opening
## begins before the panel is marked open; forced closes take the same
## authored path. UI openness itself is never serialized.
func set_interaction_open(is_open: bool) -> void:
	if definition == null or definition.appearance_profile == null:
		return
	var profile: AppearanceProfile = definition.appearance_profile
	var transition := profile.interaction_opening_state if is_open else profile.interaction_closing_state
	var resting := profile.interaction_open_state if is_open else profile.interaction_closed_state
	_transition_token += 1
	if transition.is_empty():
		if not resting.is_empty():
			set_appearance_state(resting)
		return
	var token := _transition_token
	set_appearance_state(transition)
	var state: Variant = profile.states.get(transition, null)
	if typeof(state) == TYPE_DICTIONARY:
		var fps := float(state.get("fps", 0.0))
		var frame_count := maxi(int(state.get("frame_count", 1)), 1)
		var frame_duration := 0.1
		if fps > 0.0:
			frame_duration = 1.0 / fps
		for i in range(frame_count):
			if is_inside_tree():
				await get_tree().create_timer(frame_duration).timeout
			if token != _transition_token or not is_inside_tree():
				return
			_advance_appearance_step()
	# Settle only while the transition still owns the presentation: another
	# profile-driven switch (e.g. a station's in-use state) wins the fight.
	if not resting.is_empty() and _appearance_state == transition:
		set_appearance_state(resting)

## Toggle the profile's in-use presentation (e.g. a workbench being worked)
## for as long as the player's station panel stays open. Fully data-driven:
## profiles opt in with a crafting_state, and resting reverts to the profile's
## own initial_state, so no object-specific names reach the code.
func set_crafting_active(is_active: bool) -> void:
	if definition == null or definition.appearance_profile == null:
		return
	var profile: AppearanceProfile = definition.appearance_profile
	if is_active:
		if not profile.crafting_state.is_empty():
			set_appearance_state(profile.crafting_state)
	elif not profile.initial_state.is_empty():
		# The manager calls set_interaction_open(false) and this in the same
		# tick: while an authored interaction transition (opening/closing)
		# still owns the presentation, the transition coroutine settles into
		# the resting state — snapping here would skip the closing frame.
		if _appearance_state != profile.interaction_opening_state \
				and _appearance_state != profile.interaction_closing_state:
			set_appearance_state(profile.initial_state)

## Nudge direction for edge parts so their oriented side reads from above,
## and for wall fixtures, how far past the wall face their art hangs (a
## fixture mounts on the outside of the edge it is anchored on).
func _edge_visual_offset() -> Vector2:
	match layer:
		"edge":
			match orientation:
				"north":
					return Vector2(0.0, -EDGE_VISUAL_OFFSET)
				"south":
					return Vector2(0.0, EDGE_VISUAL_OFFSET)
				"west":
					return Vector2(-EDGE_VISUAL_OFFSET, 0.0)
				"east":
					return Vector2(EDGE_VISUAL_OFFSET, 0.0)
				_:
					return Vector2.ZERO
		"fixture":
			match orientation:
				"north":
					return Vector2(0.0, -FIXTURE_VISUAL_OFFSET)
				"south":
					return Vector2(0.0, FIXTURE_VISUAL_OFFSET)
				"west":
					return Vector2(-FIXTURE_VISUAL_OFFSET, 0.0)
				"east":
					return Vector2(FIXTURE_VISUAL_OFFSET, 0.0)
				_:
					# A fixture always has an orientation ("" resolves to
					# north when it is placed); default to the north face.
					return Vector2(0.0, -FIXTURE_VISUAL_OFFSET)
		_:
			return Vector2.ZERO

## The authored atlas reference for this part, or {} when it keeps the
## colored placeholder (no definition, no cell, or the art sheet is not
## present yet). Presentation is data: the sheet path and cell live on the
## part's own BuildingDefinition, so new content needs no code change here.
## Orientable parts carry an atlas_cells map; the cell for this part's
## current orientation wins, with the single atlas_cell as the fallback.
func _definition_atlas() -> Dictionary:
	if definition == null:
		return {}
	var path := str(definition.get("atlas_path"))
	var cell: Vector2i = definition.get("atlas_cell")
	var cells: Dictionary = definition.get("atlas_cells")
	if not orientation.is_empty() and cells.has(orientation):
		cell = cells[orientation]
	if path.is_empty() or cell == Vector2i(-1, -1) or not FileAccess.file_exists(path):
		return {}
	return {"path": path, "cell": cell}

## The authored front-elevation reference for this part, or {} when it has
## no facade art (no definition, no cell, or the sheet is missing). Same
## data-driven contract as _definition_atlas.
func _definition_facade_atlas() -> Dictionary:
	if definition == null:
		return {}
	var path := str(definition.get("facade_atlas_path"))
	var cell: Vector2i = definition.get("facade_atlas_cell")
	if path.is_empty() or cell == Vector2i(-1, -1) or not FileAccess.file_exists(path):
		return {}
	return {"path": path, "cell": cell}

## Placeholder tint: the part's optional per-part override color when authored,
## otherwise its visual family's tint, otherwise the neutral default.
func _placeholder_color() -> Color:
	if definition == null:
		return PLACEHOLDER_DEFAULT_COLOR
	var override: Color = definition.get("placeholder_color")
	if override.a > 0.0:
		return override
	return PLACEHOLDER_FAMILY_COLORS.get(str(definition.get("visual_family_id")), PLACEHOLDER_DEFAULT_COLOR)

func _setup_collision() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	var center := Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	if layer == "edge" and blocks_movement:
		# Edge walls occupy a strip along their oriented edge, so a room's
		# own floor tile stays walkable and the same edge can't double-book.
		var horizontal := orientation == "north" or orientation == "south" or orientation == ""
		rect.size = Vector2(TILE_SIZE - 4.0, 8.0) if horizontal else Vector2(8.0, TILE_SIZE - 4.0)
		match orientation:
			"north", "":
				center = Vector2(TILE_SIZE * 0.5, 4.0)
			"south":
				center = Vector2(TILE_SIZE * 0.5, TILE_SIZE - 4.0)
			"west":
				center = Vector2(4.0, TILE_SIZE * 0.5)
			"east":
				center = Vector2(TILE_SIZE - 4.0, TILE_SIZE * 0.5)
	else:
		rect.size = Vector2(TILE_SIZE - 4.0, TILE_SIZE - 4.0)
	shape.shape = rect
	shape.position = center
	add_child(shape)
	# Stories own dedicated collision bits, so the player's mask (owned by
	# the active-story state) only ever sees the active story's bodies.
	collision_layer = BuildingRecord.STORY_COLLISION_BASE << clampi(story, 0, BuildingRecord.MAX_STORIES - 1)
	collision_mask = 0
	if not blocks_movement or layer == "overhead":
		# Walkable parts and roofs never block anyone.
		collision_layer = 0

## Within-band z for this part's placement layer.
func _render_band() -> int:
	var story_band := clampi(story, 0, BuildingRecord.MAX_STORIES - 1) * BuildingRecord.STORY_Z_STRIDE
	return story_band + int(BuildingRecord.LAYER_Z.get(layer, 2))

## Reposition the visual children around their setup-time base positions by
## `offset`. Only the exterior presentation passes a non-zero value (one
## EXTERIOR_STORY_OFFSET step per story — straight up, the south-facing
## billboard stack); interior and build views pass zero. The node position
## and collision never move, so movement rules are untouched.
func set_visual_offset(offset: Vector2) -> void:
	visual_offset = offset
	for child in _visual_base:
		if child is Node2D and is_instance_valid(child):
			(child as Node2D).position = Vector2(_visual_base[child]) + offset

## Presentation policy, applied by the BuildingManager after every placement,
## removal, story change, and doorway crossing. The manager chooses a MODE;
## this node only applies it:
##   "build":    the construction story in full colour, ~14% blueprints
##                above it, ~25% ghosts below it (the placement preview).
##   "interior": the cutaway for the level the player is on: that story in
##                full colour (overheads on it fade so the room reads),
##                every OTHER story hidden — standing on a floor, the level
##                below is not a ghost floor, it is simply gone from view.
##   "exterior": the building seen from outside: the shell — exterior-facing
##                walls/doors/windows/fixtures and every roof — renders at
##                full colour on ALL stories so a multi-storey build reads
##                as mass, while interior parts ghost at ~25% (orientation
##                only). Each story's visuals shift by one
##                EXTERIOR_STORY_OFFSET step per story (one tile straight
##                up, the south-facing billboard stack); node position and
##                collision stay grid-anchored in every mode.
func set_presentation(mode: String, focus_story: int, roofs_visible: bool = true, shell_part: bool = false) -> void:
	set_visual_offset(EXTERIOR_STORY_OFFSET * story if mode == "exterior" else Vector2.ZERO)
	# The front elevation shows only from outside, only on shell parts that
	# face the viewer (the south wall row — each story's front facade under
	# the mass above it). Every other mode keeps the top-down art.
	if _facade_sprite != null:
		_facade_sprite.visible = mode == "exterior" and shell_part \
				and layer == "edge" and orientation == "south"
	match mode:
		"build":
			var delta := story - focus_story
			if delta > 0:
				visible = true
				modulate = Color(0.75, 0.85, 1.0, 0.14) # blueprint hint
				return
			visible = true
			if delta < 0:
				modulate = Color(1.0, 1.0, 1.0, 0.25)
				return
			if layer == "overhead":
				# The roof stays on the construction story unless the F5
				# toggle hides it.
				modulate = Color(1.0, 1.0, 1.0, 1.0 if roofs_visible else 0.0)
				visible = roofs_visible
				return
			modulate = Color(1.0, 1.0, 1.0, 1.0)
		"interior":
			if story != focus_story:
				visible = false
				return
			visible = true
			if layer == "overhead":
				# The room reads through its own overhead.
				modulate = Color(1.0, 1.0, 1.0, 0.4 if roofs_visible else 0.0)
				visible = roofs_visible
				return
			modulate = Color(1.0, 1.0, 1.0, 1.0)
		"exterior":
			if shell_part:
				if layer == "overhead":
					# The roof is the view itself; the F5 toggle still hides it.
					modulate = Color(1.0, 1.0, 1.0, 1.0 if roofs_visible else 0.0)
					visible = roofs_visible
					return
				visible = true
				modulate = Color(1.0, 1.0, 1.0, 1.0)
				return
			# Interior parts seen from outside: orientation only.
			visible = true
			modulate = Color(1.0, 1.0, 1.0, 0.25)

func take_damage(amount: float) -> bool:
	if amount <= 0 or health <= 0:
		return false
	health = maxi(0, health - int(amount))
	if _health_bar:
		_health_bar.value = health
		_health_bar.visible = health < max_health
	building_damaged.emit(health, max_health)
	if health <= 0:
		building_destroyed.emit()
		return true
	return false

func get_building_id() -> String:
	return building_id

# --- Interactable capability (M4) ---
# One generic runtime path: capability data comes from the definition's
# InteractionProfile; nothing here branches on the building's identity.

## The authored interaction profile, or null when this object is not
## interactable at all.
func get_interaction_profile() -> InteractionProfile:
	if definition == null:
		return null
	return definition.interaction_profile

## Whether `player` may interact right now: an interaction profile exists and
## the player is within the authored range.
func can_interact(player: Node2D) -> bool:
	var profile := get_interaction_profile()
	if profile == null or player == null:
		return false
	var center := global_position + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	return center.distance_to(player.global_position) <= profile.range_px

## HUD prompt text, e.g. "Open Wood Chest".
func get_interaction_prompt() -> String:
	var profile := get_interaction_profile()
	if profile == null:
		return ""
	var subject := profile.prompt
	if subject.is_empty():
		subject = display_name
	return "%s %s" % [profile.verb, subject]
