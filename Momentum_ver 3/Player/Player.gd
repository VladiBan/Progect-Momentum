extends CharacterBody3D

# Responsive first-person movement controller for Godot 4.x.
# Keeps one move_and_slide() call per physics frame.

@export_group("Ground Movement")
@export var speed: float = 12.0
@export var max_ground_speed: float = 14.5
@export var ground_acceleration: float = 32.0
@export var ground_friction: float = 17.0
@export var ground_speed_excess_drag: float = 10.0

@export_group("Air Movement")
@export var air_acceleration: float = 10.0
@export var air_friction: float = 0.25
@export var max_air_speed: float = 18.5
@export var jump_velocity: float = 9.8
@export var gravity: float = 29.0
@export var max_fall_speed: float = 42.0
@export var jump_cut_multiplier: float = 0.55
@export var mouse_sensitivity: float = 0.1

@export_group("Jump Forgiveness")
@export var coyote_time: float = 0.14
@export var jump_buffer_time: float = 0.18
@export var slide_buffer_time: float = 0.22

@export_group("Slide")
@export var slide_min_speed: float = 4.5
@export var slide_initial_boost: float = 2.0
@export var slide_jump_boost: float = 1.8
@export var slide_jump_vertical_bonus: float = 0.25
@export var max_slide_speed: float = 17.5
@export var slide_start_friction: float = 0.45
@export var slide_end_friction: float = 1.8
@export var slide_duration: float = 0.9
@export var slide_steering: float = 7.0
@export var slide_collider_height: float = 1.2

@export_group("Wall Movement")
@export var wall_run_speed: float = 9.5
@export var wall_run_gravity: float = 7.0
@export var wall_run_duration: float = 1.1
@export var wall_kick_up: float = 9.8
@export var wall_kick_out: float = 7.5

@export_group("Slide Camera")
@export var slide_camera_drop: float = 0.36
@export var slide_camera_smoothness: float = 13.0

@export_group("Speedometer")
@export var speedometer_max_speed: float = 22.0
@export var show_speedometer: bool = true

@export_group("Effects")
@export var max_particle_amount: int = 50

@onready var camera: Camera3D = get_node_or_null("CameraPivot/Camera3D") as Camera3D
@onready var camera_pivot: Node3D = get_node_or_null("CameraPivot") as Node3D
@onready var particles: GPUParticles3D = get_node_or_null("particles") as GPUParticles3D
@onready var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
@onready var player_mesh: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D

var standing_capsule_height: float = 2.086
var standing_collision_y: float = 1.0
var standing_mesh_y: float = 1.0
var standing_mesh_scale: Vector3 = Vector3.ONE

var is_sliding: bool = false
var is_crouched: bool = false
var slide_time: float = 0.0
var slide_direction: Vector3 = Vector3.ZERO
var slide_buffer_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var coyote_timer: float = 0.0

var is_wall_running: bool = false
var wall_run_timer: float = 0.0
var wall_run_cooldown: float = 0.0
var wall_normal: Vector3 = Vector3.ZERO

var camera_pivot_default_position: Vector3 = Vector3.ZERO
var slide_camera_blend: float = 0.0

var speed_label: Label
var state_label: Label
var speed_bar: ProgressBar


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	Global.player = self

	if camera_pivot:
		camera_pivot_default_position = camera_pivot.position

	if collision_shape and collision_shape.shape is CapsuleShape3D:
		collision_shape.shape = collision_shape.shape.duplicate()
		var capsule := collision_shape.shape as CapsuleShape3D
		standing_capsule_height = capsule.height
		standing_collision_y = collision_shape.position.y

	if player_mesh:
		standing_mesh_y = player_mesh.position.y
		standing_mesh_scale = player_mesh.scale

	if particles:
		particles.emitting = false
		particles.amount = maxi(1, max_particle_amount)

	if show_speedometer:
		_create_speedometer()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		if camera:
			camera.rotation_degrees.x = clampf(
				camera.rotation_degrees.x - event.relative.y * mouse_sensitivity,
				-88.0,
				88.0
			)
	elif event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseButton and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	var grounded_at_start := is_on_floor()
	wall_run_cooldown = maxf(wall_run_cooldown - delta, 0.0)

	if grounded_at_start:
		coyote_timer = coyote_time
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)

	if Input.is_action_just_pressed("Jump"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)

	if Input.is_action_just_pressed("slide"):
		slide_buffer_timer = slide_buffer_time
	else:
		slide_buffer_timer = maxf(slide_buffer_timer - delta, 0.0)

	var input_2d := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var wish_dir := (global_transform.basis * Vector3(input_2d.x, 0.0, -input_2d.y)).normalized()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)

	# A buffered slide starts on landing, provided enough speed has been built.
	if (
		slide_buffer_timer > 0.0
		and grounded_at_start
		and not is_sliding
		and not is_wall_running
		and horizontal.length() >= slide_min_speed
	):
		is_sliding = true
		is_crouched = true
		slide_time = 0.0
		slide_direction = horizontal.normalized()
		horizontal = (horizontal + slide_direction * slide_initial_boost).limit_length(max_slide_speed)
		slide_buffer_timer = 0.0
		_set_crouched(true)
		_set_slide_effects(true)

	# Detect a wall using contact information from the last physics step.
	if (
		not grounded_at_start
		and is_on_wall()
		and horizontal.length() > 3.0
		and input_2d.length() > 0.1
		and not is_wall_running
		and wall_run_cooldown <= 0.0
	):
		var collision := get_last_slide_collision()
		if collision:
			var normal: Vector3 = collision.get_normal()
			if absf(normal.y) < 0.25:
				wall_normal = normal
				is_wall_running = true
				wall_run_timer = wall_run_duration

	# Jump buffering makes a slide jump possible even when both keys are pressed
	# shortly before landing. Wall kicks take priority over regular jumps.
	if jump_buffer_timer > 0.0:
		if is_wall_running:
			velocity.y = wall_kick_up
			horizontal = (horizontal + wall_normal * wall_kick_out).limit_length(max_air_speed)
			is_wall_running = false
			is_sliding = false
			jump_buffer_timer = 0.0
			coyote_timer = 0.0
			_set_slide_effects(false)
			_try_to_stand()
		elif coyote_timer > 0.0:
			if is_sliding:
				var slide_speed := horizontal.length()
				horizontal = (horizontal + slide_direction * slide_jump_boost).limit_length(max_air_speed)
				var speed_factor := clampf(slide_speed / maxf(max_slide_speed, 1.0), 0.0, 1.0)
				velocity.y = jump_velocity + slide_jump_vertical_bonus * speed_factor
			else:
				velocity.y = jump_velocity

			jump_buffer_timer = 0.0
			coyote_timer = 0.0
			is_sliding = false
			_set_slide_effects(false)
			_try_to_stand()

	if Input.is_action_just_released("Jump") and velocity.y > 0.0:
		velocity.y *= jump_cut_multiplier

	# Wall-run gravity is lower, but steering still uses normal movement input.
	if is_wall_running:
		wall_run_timer -= delta
		if (
			grounded_at_start
			or not is_on_wall()
			or input_2d.length() < 0.1
			or wall_run_timer <= 0.0
		):
			is_wall_running = false
			wall_run_cooldown = 0.25
		else:
			var along_wall := Vector3.UP.cross(wall_normal).normalized()
			if along_wall.dot(wish_dir) < 0.0:
				along_wall = -along_wall
			horizontal = along_wall * maxf(horizontal.length(), wall_run_speed)
			velocity.y = maxf(velocity.y - wall_run_gravity * delta, -3.0)

	# Sliding preserves momentum and lets the player steer without snapping to a
	# fixed walking speed. Friction ramps up near the end of a slide.
	if is_sliding:
		slide_time += delta
		var slide_t := clampf(slide_time / maxf(slide_duration, 0.01), 0.0, 1.0)
		var slide_friction := lerpf(slide_start_friction, slide_end_friction, slide_t)
		horizontal = horizontal.move_toward(Vector3.ZERO, slide_friction * delta)
		if wish_dir.length_squared() > 0.001 and horizontal.length_squared() > 0.001:
			horizontal = horizontal.move_toward(wish_dir * horizontal.length(), slide_steering * delta)
		horizontal = horizontal.limit_length(max_slide_speed)

		if slide_t >= 1.0 or horizontal.length() < 2.0 or not grounded_at_start:
			is_sliding = false
			_set_slide_effects(false)

	elif not is_wall_running:
		if wish_dir.length_squared() > 0.001:
			if grounded_at_start:
				horizontal = _accelerate(horizontal, wish_dir, ground_acceleration, speed, delta)
				# A soft cap avoids runaway ground speed without killing carried momentum.
				if horizontal.length() > max_ground_speed:
					var capped := horizontal.normalized() * max_ground_speed
					horizontal = horizontal.move_toward(capped, ground_speed_excess_drag * delta)
			else:
				horizontal = _accelerate(horizontal, wish_dir, air_acceleration, max_air_speed, delta)
				horizontal = horizontal.limit_length(max_air_speed)
		else:
			var friction := ground_friction if grounded_at_start else air_friction
			horizontal = horizontal.move_toward(Vector3.ZERO, friction * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if not grounded_at_start and not is_wall_running:
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)
	elif grounded_at_start and velocity.y < 0.0:
		velocity.y = 0.0

	# The pivot moves, not Camera3D.position. This keeps the camera animation
	# track from fighting the slide effect and preserves the player's look pitch.
	var camera_target := 1.0 if is_crouched else 0.0
	slide_camera_blend = lerpf(
		slide_camera_blend,
		camera_target,
		1.0 - exp(-slide_camera_smoothness * delta)
	)
	if camera_pivot:
		camera_pivot.position = camera_pivot_default_position + Vector3(
			0.0,
			-slide_camera_drop * slide_camera_blend,
			0.0
		)

	move_and_slide()

	# If a low ceiling blocks standing up, keep the short hitbox and camera height
	# until there is room. This check only runs while crouched, not every frame.
	if is_crouched and not is_sliding and _can_stand():
		_set_crouched(false)

	if is_wall_running and not is_on_wall():
		is_wall_running = false
		wall_run_cooldown = 0.25

	_update_speedometer()


func _accelerate(horizontal: Vector3, direction: Vector3, acceleration: float, wish_speed: float, delta: float) -> Vector3:
	if direction.length_squared() < 0.001:
		return horizontal
	var speed_in_wish_direction := horizontal.dot(direction)
	var speed_to_add := wish_speed - speed_in_wish_direction
	if speed_to_add <= 0.0:
		return horizontal
	var acceleration_step := minf(acceleration * delta, speed_to_add)
	return horizontal + direction * acceleration_step


func _can_stand() -> bool:
	if not collision_shape or not collision_shape.shape is CapsuleShape3D:
		return true

	var current_capsule := collision_shape.shape as CapsuleShape3D
	var standing_shape := current_capsule.duplicate() as CapsuleShape3D
	standing_shape.height = standing_capsule_height

	var standing_transform := collision_shape.global_transform
	var local_y_offset := standing_collision_y - collision_shape.position.y
	standing_transform.origin += global_transform.basis * Vector3(0.0, local_y_offset, 0.0)

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = standing_shape
	query.transform = standing_transform
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]

	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _try_to_stand() -> void:
	if _can_stand():
		_set_crouched(false)
	else:
		_set_crouched(true)


func _set_crouched(active: bool) -> void:
	is_crouched = active
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var capsule := collision_shape.shape as CapsuleShape3D
		if active:
			capsule.height = minf(slide_collider_height, standing_capsule_height)
			collision_shape.position.y = standing_collision_y - (standing_capsule_height - capsule.height) * 0.5
		else:
			capsule.height = standing_capsule_height
			collision_shape.position.y = standing_collision_y

	if player_mesh:
		if active:
			player_mesh.scale = Vector3(
				standing_mesh_scale.x,
				standing_mesh_scale.y * 0.62,
				standing_mesh_scale.z
			)
			player_mesh.position.y = standing_mesh_y * 0.62
		else:
			player_mesh.scale = standing_mesh_scale
			player_mesh.position.y = standing_mesh_y


func _create_speedometer() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SpeedometerLayer"
	layer.layer = 10
	add_child(layer)

	var panel := PanelContainer.new()
	panel.name = "SpeedometerPanel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -250.0
	panel.offset_top = -132.0
	panel.offset_right = -24.0
	panel.offset_bottom = -24.0
	layer.add_child(panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.035, 0.055, 0.88)
	panel_style.border_color = Color(0.1, 0.85, 1.0, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(5)
	panel_style.content_margin_left = 14.0
	panel_style.content_margin_right = 14.0
	panel_style.content_margin_top = 10.0
	panel_style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", panel_style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)

	var title := Label.new()
	title.text = "MOMENTUM // VELOCITY"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.25, 0.85, 1.0, 1.0))
	column.add_child(title)

	speed_label = Label.new()
	speed_label.text = "000.0 u/s"
	speed_label.add_theme_font_size_override("font_size", 28)
	speed_label.add_theme_color_override("font_color", Color(0.92, 0.98, 1.0, 1.0))
	column.add_child(speed_label)

	speed_bar = ProgressBar.new()
	speed_bar.custom_minimum_size = Vector2(190.0, 9.0)
	speed_bar.min_value = 0.0
	speed_bar.max_value = maxf(speedometer_max_speed, 1.0)
	speed_bar.show_percentage = false

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.1, 0.14, 0.18, 1.0)
	bar_bg.set_corner_radius_all(2)
	speed_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.1, 0.85, 1.0, 1.0)
	bar_fill.set_corner_radius_all(2)
	speed_bar.add_theme_stylebox_override("fill", bar_fill)
	column.add_child(speed_bar)

	state_label = Label.new()
	state_label.text = "GROUNDED"
	state_label.add_theme_font_size_override("font_size", 12)
	state_label.add_theme_color_override("font_color", Color(0.65, 0.75, 0.82, 1.0))
	column.add_child(state_label)


func _update_speedometer() -> void:
	if not is_instance_valid(speed_label) or not is_instance_valid(speed_bar) or not is_instance_valid(state_label):
		return

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	speed_label.text = "%05.1f u/s" % horizontal_speed
	speed_bar.max_value = maxf(speedometer_max_speed, 1.0)
	speed_bar.value = horizontal_speed

	if is_wall_running:
		state_label.text = "WALL RUN"
	elif is_sliding:
		state_label.text = "SLIDING"
	elif not is_on_floor():
		state_label.text = "AIRBORNE"
	else:
		state_label.text = "GROUNDED"


func _set_slide_effects(active: bool) -> void:
	if particles:
		particles.emitting = active
		if active:
			particles.amount = maxi(1, max_particle_amount)
