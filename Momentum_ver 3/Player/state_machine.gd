class_name State_Machine
extends Node

@export var CurrentState: BaseState
var states: Dictionary = {}	

func _ready():
	for child in get_children():
		if child is BaseState:
			states[child.name] = child
			child.transition.connect(on_child_transition)
		else:
			push_warning("State Machine: Child node is not a State")
	
	if CurrentState:
		CurrentState.enter()
	
func _process(delta):
	if CurrentState:
		CurrentState.update(delta)
		Debug.add_property("Current State", CurrentState.display_name, 1)
	
func _physics_process(delta):
	if CurrentState:
		CurrentState.physics_update(delta)
	
func on_child_transition(new_state_name: StringName):
	var newState = states.get(new_state_name)
	if newState != null:
		if newState != CurrentState:
			CurrentState.exit()
			newState.enter()
			CurrentState = newState
	else:
		push_warning("No state found for: " + new_state_name)
