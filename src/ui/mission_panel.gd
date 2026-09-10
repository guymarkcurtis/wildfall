## UI panel for displaying missions and objectives.
class_name MissionPanel
extends Control

@onready var mission_list: VBoxContainer = $MarginContainer/MissionList
@onready var active_label: Label = $MarginContainer/ActiveLabel
@onready var completed_label: Label = $MarginContainer/CompletedLabel
@onready var close_button: Button = $CloseButton

var mission_manager: MissionManager = null

# Signals
signal mission_accepted(mission_id: String)
signal mission_completed(mission_id: String)
signal panel_closed

func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close_pressed)

## Show the mission panel.
func show_panel(manager: MissionManager) -> void:
	mission_manager = manager
	visible = true
	_refresh_list()

## Refresh the mission list.
func _refresh_list() -> void:
	# Clear existing items
	for child in mission_list.get_children():
		if child != close_button:
			child.queue_free()
	
	if not mission_manager:
		return
	
	# Add active missions
	var active_missions := mission_manager.get_active_missions()
	for mission in active_missions:
		var item := _create_mission_item(mission, true)
		mission_list.add_child(item)
	
	# Add completed missions
	var completed_missions := mission_manager.get_completed_missions()
	for mission in completed_missions:
		var item := _create_mission_item(mission, false)
		mission_list.add_child(item)

## Create a mission list item.
func _create_mission_item(mission: Mission, is_active: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 60)
	
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	
	# Mission title
	var title_label := Label.new()
	title_label.text = mission.title
	title_label.modulate = Color(1.0, 0.9, 0.3) if is_active else Color(0.7, 0.7, 0.7)
	vbox.add_child(title_label)
	
	# Mission description
	var desc_label := Label.new()
	desc_label.text = mission.description
	desc_label.modulate = Color(0.8, 0.8, 0.8)
	vbox.add_child(desc_label)
	
	# Objective progress
	var progress_label := Label.new()
	var progress_pct := mission.get_progress_percentage()
	progress_label.text = "Progress: %d/%d (%.0f%%)" % [
		mission.objective_progress,
		mission.objective_target,
		progress_pct
	]
	if progress_pct >= 100.0:
		progress_label.modulate = Color(0.3, 0.8, 0.3)
	vbox.add_child(progress_label)
	
	# Reward
	var reward_label := Label.new()
	var rewards := []
	for item_id in mission.reward_items:
		rewards.append("%dx %s" % [mission.reward_items[item_id], item_id])
	if mission.reward_xp > 0:
		rewards.append("%d XP" % mission.reward_xp)
	reward_label.text = "Reward: " + ", ".join(rewards)
	reward_label.modulate = Color(0.6, 0.8, 0.6)
	vbox.add_child(reward_label)
	
	return panel

## Handle close button press.
func _on_close_pressed() -> void:
	visible = false
	panel_closed.emit()

## Hide the panel.
func hide_panel() -> void:
	visible = false

## Update mission display.
func update_mission(mission_id: String) -> void:
	_refresh_list()
