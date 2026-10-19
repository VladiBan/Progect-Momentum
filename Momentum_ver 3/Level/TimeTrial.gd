extends Node3D

## A small movement course with a start gate, checkpoint, finish gate and stopwatch.

@onready var player: CharacterBody3D = $Player

var _player_start_transform: Transform3D
var _checkpoint_transform: Transform3D
var _checkpoint_is_set := false
var _timer_running := false
var _finished := false
var _elapsed := 0.0
var _best_time := INF

var _timer_label: Label
var _status_label: Label
var _best_label: Label
var _checkpoint_marker: MeshInstance3D


func _ready() -> void:
	_create_environment()
	_build_course()
	_build_gates_and_triggers()
	_create_hud()

	_player_start_transform = player.global_transform
	_checkpoint_transform = _player_start_transform


func _process(delta: float) -> void:
	if _timer_running:
		_elapsed += delta
		_timer_label.text = _format_time(_elapsed)

	if is_instance_valid(player) and player.global_position.y < -12.0:
		_respawn_player(_checkpoint_transform)
		if _timer_running:
			_status_label.text = "RESPAWN // TIMER CONTINUES"
		else:
			_status_label.text = "RESPAWN // CROSS THE START GATE"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_reset_run()


func _create_environment() -> void:
	var world := WorldEnvironment.new()
	world.name = "TimeTrialEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.028, 0.055)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.40, 0.52, 0.68)
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.35
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.name = "CourseLight"
	sun.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)


func _build_course() -> void:
	# The start runway and low tunnel.
	_add_box("Start Runway", Vector3(0.0, -0.5, -1.5), Vector3(12.0, 1.0, 26.0), Color(0.10, 0.14, 0.21))
	_add_box("Tunnel Roof", Vector3(0.0, 1.70, -8.0), Vector3(5.3, 0.5, 5.0), Color(0.95, 0.38, 0.10), true)
	_add_box("Tunnel Left Wall", Vector3(-2.55, 0.75, -8.0), Vector3(0.4, 1.5, 5.0), Color(0.95, 0.38, 0.10), true)
	_add_box("Tunnel Right Wall", Vector3(2.55, 0.75, -8.0), Vector3(0.4, 1.5, 5.0), Color(0.95, 0.38, 0.10), true)

	# Small floor markers lead players into the slide tunnel.
	for i in range(6):
		_add_box(
			"Runway Marker %02d" % i,
			Vector3(0.0, 0.003, -2.5 - float(i) * 1.4),
			Vector3(0.16, 0.006, 0.55),
			Color(0.10, 0.86, 1.0),
			true
		)

	# A stepping-stone sequence. Each platform changes both height and direction.
	_add_box("Jump Platform 1", Vector3(0.0, -0.25, -16.5), Vector3(4.2, 0.5, 3.2), Color(0.05, 0.58, 0.78), true)
	_add_box("Jump Platform 2", Vector3(-2.0, 0.35, -21.0), Vector3(3.4, 0.6, 3.2), Color(0.05, 0.48, 0.72), true)
	_add_box("Jump Platform 3", Vector3(1.5, 0.70, -25.8), Vector3(3.5, 0.5, 3.2), Color(0.12, 0.42, 0.78), true)
	_add_box("Jump Platform 4", Vector3(0.0, 1.05, -30.5), Vector3(4.0, 0.5, 3.2), Color(0.23, 0.35, 0.82), true)

	# A narrow wall-run bridge. The side walls sit just outside the bridge edges.
	_add_box("Wall Run Bridge", Vector3(0.0, 1.05, -36.3), Vector3(3.5, 0.5, 8.4), Color(0.08, 0.28, 0.42), true)
	_add_box("Wall Run Left", Vector3(-1.95, 3.25, -36.3), Vector3(0.4, 4.4, 8.2), Color(0.05, 0.72, 0.86), true)
	_add_box("Wall Run Right", Vector3(1.95, 3.25, -36.3), Vector3(0.4, 4.4, 8.2), Color(0.05, 0.72, 0.86), true)

	# Checkpoint and final pair of jumps.
	_add_box("Checkpoint Platform", Vector3(1.5, 1.6, -43.8), Vector3(4.0, 0.5, 4.0), Color(0.08, 0.48, 0.28), true)
	_add_box("Final Jump Platform", Vector3(-0.7, 2.0, -49.0), Vector3(3.5, 0.5, 3.5), Color(0.43, 0.25, 0.75), true)
	_add_box("Finish Platform", Vector3(0.0, 2.0, -54.5), Vector3(8.0, 0.5, 7.0), Color(0.30, 0.13, 0.42), true)


func _build_gates_and_triggers() -> void:
	# Start arch.
	_add_box("Start Arch Left", Vector3(-4.7, 1.2, 2.0), Vector3(0.35, 2.4, 0.35), Color(1.0, 0.58, 0.08), true)
	_add_box("Start Arch Right", Vector3(4.7, 1.2, 2.0), Vector3(0.35, 2.4, 0.35), Color(1.0, 0.58, 0.08), true)
	_add_box("Start Arch Top", Vector3(0.0, 2.5, 2.0), Vector3(9.75, 0.3, 0.35), Color(1.0, 0.58, 0.08), true)
	_create_trigger("StartGate", Vector3(0.0, 1.1, 2.0), Vector3(10.0, 2.2, 0.5), _on_start_gate_entered)

	# Bright checkpoint pad/arch.
	_checkpoint_marker = _add_box("Checkpoint Beacon", Vector3(1.5, 2.02, -43.8), Vector3(2.2, 0.08, 2.2), Color(0.15, 1.0, 0.42), true)
	_create_trigger("CheckpointGate", Vector3(1.5, 2.8, -43.8), Vector3(3.8, 2.2, 3.8), _on_checkpoint_entered)

	# Finish arch and trigger.
	_add_box("Finish Arch Left", Vector3(-3.3, 3.5, -55.5), Vector3(0.3, 2.5, 0.3), Color(1.0, 0.18, 0.46), true)
	_add_box("Finish Arch Right", Vector3(3.3, 3.5, -55.5), Vector3(0.3, 2.5, 0.3), Color(1.0, 0.18, 0.46), true)
	_add_box("Finish Arch Top", Vector3(0.0, 4.8, -55.5), Vector3(6.9, 0.3, 0.3), Color(1.0, 0.18, 0.46), true)
	_create_trigger("FinishGate", Vector3(0.0, 3.3, -55.5), Vector3(7.5, 2.5, 0.65), _on_finish_gate_entered)


func _add_box(
	box_name: String,
	box_position: Vector3,
	box_size: Vector3,
	color: Color,
	glow: bool = false
) -> MeshInstance3D:
	var body := StaticBody3D.new()
	body.name = box_name.replace(" ", "") + "Body"
	body.position = box_position
	body.collision_layer = 1
	body.collision_mask = 1

	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box_size
	collision.shape = box_shape
	body.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = box_name.replace(" ", "") + "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh_instance.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.28
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	add_child(body)
	return mesh_instance


func _create_trigger(
	trigger_name: String,
	trigger_position: Vector3,
	trigger_size: Vector3,
	callback: Callable
) -> Area3D:
	var area := Area3D.new()
	area.name = trigger_name
	area.position = trigger_position
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	area.monitorable = false

	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = trigger_size
	collision.shape = box_shape
	area.add_child(collision)
	area.body_entered.connect(callback)
	add_child(area)
	return area


func _create_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TimeTrialHUD"
	layer.layer = 20
	add_child(layer)

	var panel := PanelContainer.new()
	panel.name = "TimerPanel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -220.0
	panel.offset_right = 220.0
	panel.offset_top = 18.0
	panel.offset_bottom = 164.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.018, 0.035, 0.06, 0.92)
	panel_style.border_color = Color(0.08, 0.78, 0.96, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 14.0
	panel_style.content_margin_right = 14.0
	panel_style.content_margin_top = 8.0
	panel_style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", panel_style)
	layer.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)

	var title := Label.new()
	title.text = "MOMENTUM  /  TIME TRIAL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.20, 0.86, 1.0))
	column.add_child(title)

	_timer_label = Label.new()
	_timer_label.text = "00:00.000"
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 34)
	_timer_label.add_theme_color_override("font_color", Color(0.94, 0.98, 1.0))
	column.add_child(_timer_label)

	_status_label = Label.new()
	_status_label.text = "CROSS THE START GATE TO BEGIN"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", Color(0.45, 0.84, 0.95))
	column.add_child(_status_label)

	_best_label = Label.new()
	_best_label.text = "WASD MOVE  •  SPACE JUMP  •  SHIFT SLIDE  •  R RESTART"
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_label.add_theme_font_size_override("font_size", 10)
	_best_label.add_theme_color_override("font_color", Color(0.64, 0.72, 0.81))
	column.add_child(_best_label)


func _on_start_gate_entered(body: Node3D) -> void:
	if body != player or _timer_running or _finished:
		return
	_elapsed = 0.0
	_timer_running = true
	_status_label.text = "RUNNING  // GET TO THE FINISH"


func _on_checkpoint_entered(body: Node3D) -> void:
	if body != player or _checkpoint_is_set:
		return
	_checkpoint_transform = player.global_transform
	_checkpoint_is_set = true
	_status_label.text = "CHECKPOINT SET  // KEEP GOING"
	if is_instance_valid(_checkpoint_marker):
		var material := _checkpoint_marker.material_override as StandardMaterial3D
		if material:
			material.albedo_color = Color(0.22, 1.0, 0.45)
			material.emission = material.albedo_color


func _on_finish_gate_entered(body: Node3D) -> void:
	if body != player or not _timer_running or _finished:
		return
	_timer_running = false
	_finished = true
	_timer_label.text = _format_time(_elapsed)
	if _elapsed < _best_time:
		_best_time = _elapsed
	_status_label.text = "FINISHED  // PRESS R TO RUN AGAIN"
	_best_label.text = "BEST THIS SESSION: " + _format_time(_best_time)


func _respawn_player(target_transform: Transform3D) -> void:
	player.global_transform = target_transform
	player.velocity = Vector3.ZERO
	player.set("is_sliding", false)
	player.set("is_wall_running", false)
	player.set("is_crouched", false)
	player.set("slide_time", 0.0)
	player.set("jump_buffer_timer", 0.0)
	player.set("slide_buffer_timer", 0.0)
	player.set("coyote_timer", 0.0)
	player.set("wall_run_timer", 0.0)
	player.set("slide_camera_blend", 0.0)
	player.call("_set_slide_effects", false)
	player.call("_set_crouched", false)


func _reset_run() -> void:
	_timer_running = false
	_finished = false
	_elapsed = 0.0
	_checkpoint_is_set = false
	_checkpoint_transform = _player_start_transform
	_respawn_player(_player_start_transform)
	_timer_label.text = "00:00.000"
	_status_label.text = "CROSS THE START GATE TO BEGIN"
	_best_label.text = "WASD MOVE  •  SPACE JUMP  •  SHIFT SLIDE  •  R RESTART"


func _format_time(time_seconds: float) -> String:
	var total_ms := maxi(0, int(time_seconds * 1000.0))
	var minutes := int(total_ms / 60000)
	var seconds := int(total_ms / 1000) % 60
	var milliseconds := total_ms % 1000
	return "%02d:%02d.%03d" % [minutes, seconds, milliseconds]
