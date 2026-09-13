## Interactive resource node that can be harvested.
class_name HarvestableResource
extends Area2D

const DEFAULT_HITBOX_RADIUS: float = 16.0
const FORAGE_PLANT_SHEET_PATH := "res://assets/resources/wildfall-forage-plants.png"
const TREE_TEXTURE_PATH := "res://assets/resources/tree-large.png"
const TREE_SHAKE_FRAME_PATHS: PackedStringArray = [
	"res://assets/resources/tree-shake/frame_01.png",
	"res://assets/resources/tree-shake/frame_02.png",
	"res://assets/resources/tree-shake/frame_03.png",
	"res://assets/resources/tree-shake/frame_04.png"
]
const TREE_SHAKE_FRAME_TIME := 0.055

# Resource data
var resource_type: String = ""
var display_name: String = ""
var max_health: float = 10.0
var current_health: float = 10.0
var yield_items: Array[Dictionary] = []
## Content-defined interaction/presentation metadata. New resource species
## carry these values from ResourceDefinition via ResourceSpawner rather than
## relying on their ID in this runtime node.
var harvest_group: String = ""
var visual_texture_path: String = ""
var visual_ground_anchor: bool = false
var visual_hit_animation_paths: PackedStringArray = []

# State
var is_destroyed: bool = false
var is_highlighted: bool = false

# Visual
var _sprite: Sprite2D = null
var _visual_pivot: Node2D = null
var _health_display: ProgressBar = null
static var _texture_cache: Dictionary = {}
static var _hit_frame_cache: Dictionary = {}
var _tree_shake_elapsed := -1.0

# Signals
signal health_changed(current: float, max: float)
signal resource_destroyed(item_id: String, quantity: int)
## Emitted exactly once when this node is depleted, even if every optional
## loot roll misses. World persistence listens to this rather than a drop.
signal resource_depleted
signal resource_hurt(amount: float)

## Initialize the resource.
func setup(resource_type: String, health: float, yields: Array[Dictionary], resource_display_name: String = "",
		harvest_group_value: String = "", texture_path: String = "", ground_anchor: bool = false,
		hit_animation_paths: PackedStringArray = PackedStringArray()) -> void:
	self.resource_type = resource_type
	self.max_health = health
	self.current_health = health
	self.yield_items = yields.duplicate()
	display_name = resource_display_name if not resource_display_name.is_empty() else _get_display_name(resource_type)
	harvest_group = harvest_group_value if not harvest_group_value.is_empty() else _get_legacy_harvest_group(resource_type)
	visual_texture_path = texture_path if not texture_path.is_empty() else _get_legacy_texture_path(resource_type)
	visual_ground_anchor = ground_anchor or _uses_legacy_ground_anchor(resource_type)
	visual_hit_animation_paths = hit_animation_paths if not hit_animation_paths.is_empty() else _get_legacy_hit_animation_paths(resource_type)
	_setup_visuals()
	_setup_collision()
	# Hundreds of streamed resources can be alive at once. Only a tree that is
	# actively shaking needs a per-frame callback.
	set_process(false)

## Set up visual representation.
func _setup_visuals() -> void:
	# A shared pivot keeps every resource anchored to the ground and lets the
	# large tree recoil without sliding its roots across the tile.
	_visual_pivot = Node2D.new()
	_visual_pivot.position = Vector2(16, 16)
	add_child(_visual_pivot)
	_sprite = Sprite2D.new()
	
	var texture: Texture2D = _get_resource_texture()
	if texture:
		_sprite.texture = texture
		_sprite.position = Vector2(0, -float(texture.get_height()) * 0.5) if visual_ground_anchor else Vector2.ZERO
	else:
		# Fallback: create a simple colored circle texture
		_sprite = _create_fallback_sprite()
		_sprite.position = Vector2.ZERO
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_visual_pivot.add_child(_sprite)
	_health_display = ProgressBar.new()
	_health_display.position = Vector2(-24, -18) if visual_ground_anchor else Vector2(0, -8)
	_health_display.size = Vector2(80, 5) if visual_ground_anchor else Vector2(32, 5)
	_health_display.show_percentage = false
	_health_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_display.visible = false
	add_child(_health_display)
	
	# Add collision shape
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = DEFAULT_HITBOX_RADIUS
	collision.shape = shape
	collision.position = Vector2(16, 16)
	add_child(collision)
	
	collision_layer = 1
	collision_mask = 0

## Get texture for resource type.
func _get_resource_texture() -> Texture2D:
	if not visual_texture_path.is_empty():
		if _texture_cache.has(visual_texture_path):
			return _texture_cache[visual_texture_path]
		var bespoke_texture := TexturePackManager.get_texture(visual_texture_path)
		if bespoke_texture != null:
			_texture_cache[visual_texture_path] = bespoke_texture
		return bespoke_texture
	if _texture_cache.has(resource_type):
		if resource_type != "plant":
			return _texture_cache[resource_type]
	if resource_type == "plant":
		return _get_forage_plant_texture()
	var generator: Node = load("res://src/world/tile_set_generator.gd").new()
	var texture: ImageTexture = null
	
	match resource_type:
		"rock":
			texture = generator.call("_create_rock_texture")
		"fibre":
			texture = generator.call("_create_fibre_texture")
		"berry_bush":
			texture = generator.call("_create_berry_texture")
		"iron_ore":
			texture = generator.call("_create_iron_ore_texture")
		"coal":
			texture = generator.call("_create_coal_texture")
		"gold_ore":
			texture = generator.call("_create_gold_ore_texture")
	
	if texture != null:
		_texture_cache[resource_type] = texture
	return texture

func reload_visual_texture() -> void:
	_texture_cache.clear()
	_hit_frame_cache.clear()
	if _sprite != null:
		_sprite.texture = _get_resource_texture()
		if visual_ground_anchor and _sprite.texture != null:
			_sprite.position = Vector2(0, -float(_sprite.texture.get_height()) * 0.5)

## Plant is the one spawned resource that did not belong to the original
## eight-cell resource atlas. Use the new 2x2 forage sheet and pick a stable
## visual from its tile position so these no longer appear as colour boxes.
func _get_forage_plant_texture() -> ImageTexture:
	var tile_x := int(floor(position.x / 32.0))
	var tile_y := int(floor(position.y / 32.0))
	var variant := posmod(tile_x * 31 + tile_y * 17, 4)
	var cache_key := "plant_%d" % variant
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]
	var sheet := TexturePackManager.get_image(FORAGE_PLANT_SHEET_PATH)
	if sheet == null or sheet.is_empty():
		return null
	var cell_width := sheet.get_width() / 2
	var cell_height := sheet.get_height() / 2
	var cell := sheet.get_region(Rect2i(
		(variant % 2) * cell_width, (variant / 2) * cell_height,
		cell_width, cell_height
	))
	var used := cell.get_used_rect()
	if used.size.x > 0 and used.size.y > 0:
		cell = cell.get_region(used)
	cell.resize(32, 32, Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(cell)
	_texture_cache[cache_key] = texture
	return texture

## Create a fallback colored sprite.
func _create_fallback_sprite() -> Sprite2D:
	var image := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	var color: Color = _get_resource_color()
	for y in range(32):
		for x in range(32):
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = Vector2(16, 16)
	return sprite

## Get color for resource type.
func _get_resource_color() -> Color:
	match resource_type:
		"tree": return Color(0.2, 0.6, 0.2)
		"rock": return Color(0.5, 0.5, 0.5)
		"fibre": return Color(0.6, 0.5, 0.3)
		"berry_bush": return Color(0.3, 0.7, 0.3)
		"iron_ore": return Color(0.4, 0.4, 0.4)
		"coal": return Color(0.2, 0.2, 0.2)
		"gold_ore": return Color(0.9, 0.7, 0.2)
		"plant": return Color(0.4, 0.75, 0.35)
		_: return Color(0.5, 0.5, 0.5)

## Set up collision detection.
func _setup_collision() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

## Check if a body is the player.
func _is_player(body: Node) -> bool:
	return body is CharacterBody2D and body.has_method("get_world_position")

## Handle body entering area.
func _on_body_entered(body: Node) -> void:
	if _is_player(body) and not is_destroyed:
		_highlight()

## Handle body leaving area.
func _on_body_exited(body: Node) -> void:
	if _is_player(body):
		_unhighlight()

## Highlight the resource.
func _highlight() -> void:
	is_highlighted = true
	if _sprite:
		_sprite.modulate = Color(1.0, 1.0, 0.8, 1.0)

## Unhighlight the resource.
func _unhighlight() -> void:
	is_highlighted = false
	if _sprite:
		_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

## Damage the resource. Returns true if destroyed.
func damage(amount: float, tool: String = "") -> bool:
	if is_destroyed or amount <= 0:
		return false

	current_health = max(0.0, current_health - amount)
	if _health_display != null:
		_health_display.visible = true
		_health_display.value = get_health_ratio() * 100.0
	if _sprite != null and is_inside_tree():
		_sprite.modulate = Color(1.8, 1.5, 1.0)
		create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.18)
	if visual_ground_anchor:
		_start_tree_shake()
	resource_hurt.emit(amount)
	health_changed.emit(current_health, max_health)

	if current_health <= 0:
		return destroy()
	return false

## Destroy the resource and yield items.
func destroy() -> bool:
	if is_destroyed:
		return false

	is_destroyed = true
	resource_depleted.emit()

	# Queue only after the loot handlers run. Godot 4 defers the actual free
	# to the end of the frame, keeping this node valid during those handlers.
	for yield_entry in yield_items:
		var item_id: String = yield_entry["item_id"]
		var min_qty: int = yield_entry.get("min_qty", 1)
		var max_qty: int = yield_entry.get("max_qty", 1)
		var chance: float = yield_entry.get("chance", 1.0)

		if randf() < chance:
			var qty: int = randi() % (max_qty - min_qty + 1) + min_qty
			resource_destroyed.emit(item_id, qty)

	# Keep the final tree impact visible for the short shake before removing it.
	if visual_ground_anchor and is_inside_tree():
		get_tree().create_timer(TREE_SHAKE_FRAME_TIME * 6.0).timeout.connect(queue_free)
	else:
		queue_free()
	return true

func _process(delta: float) -> void:
	if _tree_shake_elapsed < 0.0 or _sprite == null:
		return
	_tree_shake_elapsed += delta
	var frame_index := int(_tree_shake_elapsed / TREE_SHAKE_FRAME_TIME)
	var frames := _get_hit_frames()
	if not frames.is_empty() and frame_index < frames.size():
		_sprite.texture = frames[frame_index]
		_sprite.position = Vector2(0, -float(_sprite.texture.get_height()) * 0.5) if visual_ground_anchor else Vector2.ZERO
		_visual_pivot.rotation = sin(_tree_shake_elapsed * 55.0) * 0.018
	elif frames.is_empty() and _tree_shake_elapsed < TREE_SHAKE_FRAME_TIME * 4.0:
		_visual_pivot.rotation = sin(_tree_shake_elapsed * 55.0) * 0.018
	else:
		_sprite.texture = _get_resource_texture()
		_sprite.position = Vector2(0, -float(_sprite.texture.get_height()) * 0.5) if visual_ground_anchor else Vector2.ZERO
		_visual_pivot.rotation = 0.0
		_tree_shake_elapsed = -1.0
		set_process(false)

func _start_tree_shake() -> void:
	_tree_shake_elapsed = 0.0
	set_process(true)
	if _visual_pivot != null:
		_visual_pivot.rotation = -0.025

func _get_hit_frames() -> Array[Texture2D]:
	var cache_key := "|".join(visual_hit_animation_paths)
	if _hit_frame_cache.has(cache_key):
		return _hit_frame_cache[cache_key]
	var frames: Array[Texture2D] = []
	for path in visual_hit_animation_paths:
		var frame := TexturePackManager.get_texture(path)
		if frame != null:
			frames.append(frame)
	_hit_frame_cache[cache_key] = frames
	return frames

func is_tree_shaking() -> bool:
	return _tree_shake_elapsed >= 0.0

## Get remaining health ratio.
func get_health_ratio() -> float:
	return clamp(current_health / max_health, 0.0, 1.0)

## Get the resource type.
func get_resource_type() -> String:
	return resource_type

## Get the yield items.
func get_yields() -> Array[Dictionary]:
	return yield_items.duplicate()

## Check if resource is destroyed.
func is_destroyed_check() -> bool:
	return is_destroyed

## Get display name for resource type.
func _get_display_name(resource_type: String) -> String:
	match resource_type:
		"tree": return "Tree"
		"rock": return "Rock"
		"fibre": return "Fibre Bundle"
		"berry_bush": return "Berry Bush"
		"iron_ore": return "Iron Ore Deposit"
		"coal": return "Coal Deposit"
		"gold_ore": return "Gold Ore Deposit"
		"plant": return "Plant"
		_: return resource_type.capitalize()

## Compatibility defaults retain the presentation and tool behaviour of
## manually-created legacy resource nodes. Data-discovered resources should
## provide these values from ResourceDefinition instead.
func _get_legacy_harvest_group(type: String) -> String:
	match type:
		"tree": return "tree"
		"rock", "iron_ore", "coal", "gold_ore": return "mineral"
		"plant", "fibre", "berry_bush": return "forage"
		_: return ""

func _get_legacy_texture_path(type: String) -> String:
	return TREE_TEXTURE_PATH if type == "tree" else ""

func _uses_legacy_ground_anchor(type: String) -> bool:
	return type == "tree"

func _get_legacy_hit_animation_paths(type: String) -> PackedStringArray:
	return TREE_SHAKE_FRAME_PATHS if type == "tree" else PackedStringArray()
