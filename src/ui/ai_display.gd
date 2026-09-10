## UI component for displaying AI state.
class_name AIDisplay
extends Control

@onready var state_label: Label = $StateLabel
@onready var behavior_label: Label = $BehaviorLabel
@onready var speed_label: Label = $SpeedLabel

var ai_system: AdvancedAI = None

func _ready() -> void:
	visible = false

## Update AI display.
func update(ai: AdvancedAI) -> void:
	ai_system = ai
	if not ai:
		visible = false
		return
	
	visible = true
	
	# Update state
	match ai.get_current_state():
		AdvancedAI.AIState.IDLE:
			state_label.text = "Idle"
		AdvancedAI.AIState.PATROL:
			state_label.text = "Patrol"
		AdvancedAI.AIState.CHASE:
			state_label.text = "Chase"
		AdvancedAI.AIState.ATTACK:
			state_label.text = "Attack"
		AdvancedAI.AIState.FLEE:
			state_label.text = "Flee"
		AdvancedAI.AIState.HUNT:
			state_label.text = "Hunt"
		AdvancedAI.AIState.SHADOW:
			state_label.text = "Shadow"
	
	# Update behavior
	match ai.get_behavior():
		AdvancedAI.BehaviorProfile.PASSIVE:
			behavior_label.text = "Passive"
		AdvancedAI.BehaviorProfile.NEUTRAL:
			behavior_label.text = "Neutral"
		AdvancedAI.BehaviorProfile.HOSTILE:
			behavior_label.text = "Hostile"
		AdvancedAI.BehaviorProfile.STALKER:
			behavior_label.text = "Stalker"
		AdvancedAI.BehaviorProfile.SHADOWY:
			behavior_label.text = "Shadow"
	
	# Update speed
	speed_label.text = "Speed: %.0f" % ai.get_speed()

## Hide the UI.
func hide_ui() -> void:
	visible = false

## Show the UI.
func show_ui() -> void:
	visible = true
