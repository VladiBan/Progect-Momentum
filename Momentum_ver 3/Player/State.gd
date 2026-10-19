class_name BaseState
extends Node

@export var display_name := "Idle"

signal transition(new_state_name: StringName)

func _ready():
	set_process(false)
	set_physics_process(false)

func enter():
	set_process(true)
	set_physics_process(true)

func exit():
	set_process(false)
	set_physics_process(false)

func update(_delta):
	pass

func physics_update(_delta):
	pass
