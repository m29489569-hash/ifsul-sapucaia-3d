extends CharacterBody3D

signal interact_requested(poi_data: Dictionary)
signal nearby_poi_changed(poi_data: Dictionary)

const WALK_SPEED := 5.6
const SPRINT_SPEED := 9.8
const JUMP_VELOCITY := 5.0
const GRAVITY := 14.0
const DRONE_BASE_SPEED := 18.0
const MOUSE_SENS := 0.0022

@onready var head: Node3D = $Head
@onready var fps_cam: Camera3D = $Head/Camera3D
@onready var drone_cam: Camera3D = $DroneCam
@onready var footstep_audio: AudioStreamPlayer = $FootstepAudio

var active_gameplay := false
var is_drone := false
var drone_yaw := 0.0
var drone_pitch := -0.45
var step_timer := 0.0
var current_poi: Dictionary = {}
var pois: Array = []
var _poi_xz := PackedVector2Array()
var _last_poi_pos := Vector3(1e9, 0.0, 1e9)
var _last_poi_drone := false

func _ready() -> void:
	set_physics_process(false)
	# Smooth navigation through 1.2m-2.6m interior doorways and ceramic floor transitions
	floor_snap_length = 0.14
	floor_max_angle = deg_to_rad(46.0)
	wall_min_slide_angle = 0.08
	safe_margin = 0.02
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col and col.shape is CapsuleShape3D:
		var cap := (col.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
		cap.radius = minf(cap.radius, 0.30)
		col.shape = cap

func setup_pois(poi_list: Array, footstep_stream: AudioStream) -> void:
	pois = poi_list
	_poi_xz.resize(pois.size())
	for i in range(pois.size()):
		var a: Array = pois[i].get("position", [0, 0, 0])
		_poi_xz[i] = Vector2(float(a[0]), float(a[2]))
	_last_poi_pos = Vector3(1e9, 0.0, 1e9)
	if footstep_stream != null:
		footstep_audio.stream = footstep_stream

func set_gameplay_active(enabled: bool) -> void:
	active_gameplay = enabled
	set_physics_process(enabled)
	if enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func look_at_point(target: Vector3) -> void:
	var flat_dir := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if flat_dir.length() > 0.1:
		rotation.y = atan2(-flat_dir.x, -flat_dir.z)
		head.rotation.x = 0.0

func teleport_to(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	_update_nearest_poi(true)

func toggle_drone_mode() -> bool:
	is_drone = not is_drone
	if is_drone:
		var start_y := maxf(global_position.y + 20.0, 20.0)
		drone_cam.global_position = Vector3(
			clampf(global_position.x, -220.0, 220.0),
			clampf(start_y, 8.0, 160.0),
			clampf(global_position.z + 12.0, -280.0, 280.0)
		)
		drone_yaw = rotation.y
		drone_pitch = -0.58
		drone_cam.rotation = Vector3(drone_pitch, drone_yaw, 0.0)
		drone_cam.fov = 68.0
		drone_cam.current = true
		fps_cam.current = false
	else:
		fps_cam.current = true
		drone_cam.current = false
	_update_nearest_poi(true)
	return is_drone

func move_drone_to_target(world_pos: Vector3) -> void:
	if not is_drone:
		toggle_drone_mode()
	drone_cam.global_position = Vector3(
		clampf(world_pos.x, -220.0, 220.0),
		clampf(maxf(world_pos.y + 26.0, 26.0), 10.0, 160.0),
		clampf(world_pos.z + 14.0, -280.0, 280.0)
	)
	drone_yaw = 0.0
	drone_pitch = -1.04
	drone_cam.rotation = Vector3(drone_pitch, drone_yaw, 0.0)
	drone_cam.fov = 64.0
	_update_nearest_poi(true)

func get_view_position() -> Vector3:
	return drone_cam.global_position if is_drone else global_position

func get_view_yaw() -> float:
	return drone_yaw if is_drone else rotation.y

func _unhandled_input(event: InputEvent) -> void:
	if not active_gameplay:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if is_drone:
			drone_yaw -= event.relative.x * MOUSE_SENS
			drone_pitch = clampf(drone_pitch - event.relative.y * MOUSE_SENS, -1.45, 1.35)
			drone_cam.rotation = Vector3(drone_pitch, drone_yaw, 0.0)
		else:
			rotate_y(-event.relative.x * MOUSE_SENS)
			head.rotation.x = clampf(head.rotation.x - event.relative.y * MOUSE_SENS, -1.35, 1.35)
	elif event is InputEventMouseButton and is_drone and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			drone_cam.fov = clampf(drone_cam.fov - 4.0, 26.0, 95.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			drone_cam.fov = clampf(drone_cam.fov + 4.0, 26.0, 95.0)
	elif event.is_action_pressed("interact") and not current_poi.is_empty():
		interact_requested.emit(current_poi)

func _physics_process(delta: float) -> void:
	if not active_gameplay:
		return
	if is_drone:
		_process_drone(delta)
	else:
		_process_walk(delta)
	_update_nearest_poi()

func _process_walk(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	var input_vec := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis := global_transform.basis
	var move_dir := (basis.z * input_vec.y + basis.x * input_vec.x)
	move_dir.y = 0.0
	if move_dir.length_squared() > 0.000001:
		move_dir = move_dir.normalized()

	var spd := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	velocity.x = move_dir.x * spd
	velocity.z = move_dir.z * spd
	move_and_slide()

	if is_on_floor() and move_dir.length_squared() > 0.01:
		step_timer -= delta * (1.55 if Input.is_action_pressed("sprint") else 1.0)
		if step_timer <= 0.0:
			step_timer = 0.44
			if footstep_audio.stream != null and not footstep_audio.playing:
				footstep_audio.pitch_scale = randf_range(0.92, 1.08)
				footstep_audio.play()
	else:
		step_timer = 0.08

func _process_drone(delta: float) -> void:
	var input_vec := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var d_basis := drone_cam.global_transform.basis
	var move := d_basis.z * input_vec.y + d_basis.x * input_vec.x
	if Input.is_action_pressed("jump"):
		move.y += 1.0
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C):
		move.y -= 1.0
	if move.length_squared() > 0.000001:
		move = move.normalized()
	var spd := DRONE_BASE_SPEED * (2.0 if Input.is_action_pressed("sprint") else 1.0)
	drone_cam.global_position += move * spd * delta
	drone_cam.global_position.x = clampf(drone_cam.global_position.x, -220.0, 220.0)
	drone_cam.global_position.z = clampf(drone_cam.global_position.z, -280.0, 280.0)
	drone_cam.global_position.y = clampf(drone_cam.global_position.y, 1.5, 160.0)

func _update_nearest_poi(force: bool = false) -> void:
	var ref_pos := get_view_position()
	if not force and is_drone == _last_poi_drone and Vector2(ref_pos.x - _last_poi_pos.x, ref_pos.z - _last_poi_pos.z).length_squared() < 0.02:
		return
	_last_poi_pos = ref_pos
	_last_poi_drone = is_drone

	var ref_xz := Vector2(ref_pos.x, ref_pos.z)
	var best: Dictionary = {}
	var best_dist_sq := (14.0 * 14.0) if is_drone else (6.5 * 6.5)
	for i in range(_poi_xz.size()):
		var d_sq := ref_xz.distance_squared_to(_poi_xz[i])
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = pois[i]
	if best.get("id", "") != current_poi.get("id", ""):
		current_poi = best
		nearby_poi_changed.emit(current_poi)
