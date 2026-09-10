## UI panel for crafting items from recipes.
class_name CraftingPanel
extends Control

@onready var recipe_list: VBoxContainer = $Panel/VBoxContainer/RecipeList
@onready var selected_recipe_label: Label = $Panel/VBoxContainer/SelectedRecipe
@onready var ingredients_label: Label = $Panel/VBoxContainer/Ingredients
@onready var craft_button: Button = $Panel/VBoxContainer/CraftButton
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

var _crafting: "CraftingComponent" = null
var _inventory: "InventoryComponent" = null
var _selected_recipe: String = ""

signal closed

func _ready() -> void:
	visible = false
	$Panel.self_modulate.a = 0.9
	craft_button.disabled = true
	close_button.pressed.connect(_on_close_pressed)

## Set the crafting component and inventory.
func set_crafting(crafting: "CraftingComponent", inventory: "InventoryComponent") -> void:
	_crafting = crafting
	_inventory = inventory
	_crafting.recipe_crafted.connect(_on_recipe_crafted)
	_crafting.recipe_failed.connect(_on_recipe_failed)
	_refresh_recipes()

## Show the panel.
func show_panel() -> void:
	visible = true
	_refresh_recipes()

## Hide the panel.
func hide_panel() -> void:
	visible = false
	closed.emit()

## Refresh the recipe list.
func _refresh_recipes() -> void:
	if not _crafting:
		return

	# Clear existing recipes
	for child in recipe_list.get_children():
		if child != selected_recipe_label and child != ingredients_label and child != craft_button and child != close_button:
			child.queue_free()

	# Add recipes
	var recipes: Dictionary = _crafting.get_recipes()
	for recipe_id in recipes:
		var recipe: RecipeDefinition = recipes[recipe_id]
		var btn := Button.new()
		btn.text = recipe.display_name
		btn.custom_minimum_size = Vector2(200, 30)
		btn.pressed.connect(_on_recipe_selected.bind(recipe_id))
		recipe_list.add_child(btn)

## Select a recipe.
func _on_recipe_selected(recipe_id: String) -> void:
	_selected_recipe = recipe_id
	var recipe: RecipeDefinition = _crafting.get_recipe(recipe_id)
	if recipe:
		selected_recipe_label.text = recipe.display_name
		# Show ingredients
		var ing_text: String = "Ingredients:\n"
		for ing in recipe.ingredients:
			var has: int = _inventory.get_item_quantity(ing["item_id"]) if _inventory else 0
			var color: String = "[color=#90EE90]" if has >= ing["quantity"] else "[color=#FF6B6B]"
			ing_text += "%s%s%s: %d/%d\n" % [color, ing["item_id"], "[/color]", has, ing["quantity"]]
		ingredients_label.text = ing_text

		# Enable/disable craft button
		craft_button.disabled = not _crafting.can_craft(recipe_id, _inventory) if _inventory else true

## Craft the selected recipe.
func _on_craft_pressed() -> void:
	if _selected_recipe and _inventory:
		_crafting.craft_recipe(_selected_recipe, _inventory)

## Handle successful craft.
func _on_recipe_crafted(recipe_id: String) -> void:
	selected_recipe_label.text = "Crafted: %s" % recipe_id
	_refresh_recipes()

## Handle craft failure.
func _on_recipe_failed(recipe_id: String, reason: String) -> void:
	selected_recipe_label.text = "Failed: %s" % reason
	_refresh_recipes()

## Handle close button.
func _on_close_pressed() -> void:
	hide_panel()

## Called when game event bus signals to toggle crafting.
func _on_toggle_crafting() -> void:
	if visible:
		hide_panel()
	else:
		show_panel()
