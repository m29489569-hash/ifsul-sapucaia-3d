extends Node3D

const CampusBuilderLib = preload("res://scripts/campus_builder.gd")

@onready var world_node: Node3D = $World
@onready var player: CharacterBody3D = $Player
@onready var hud: CanvasLayer = $HUD

var campus_data: Dictionary = {}
var builder := CampusBuilderLib.new()
var sun_light: DirectionalLight3D
var world_env: WorldEnvironment
var sky_mat: ProceduralSkyMaterial
var ambient_audio: AudioStreamPlayer

var visited_pois: Dictionary = {}
var tour_completed_shown := false
var is_night := false
var is_muted := false
var started := false
var paused := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_input_map()
	campus_data = _load_campus_json("res://data/campus.json")
	_setup_environment()
	builder.build(world_node, campus_data)
	_setup_audio()
	_setup_player_and_hud()
	hud.play_fade_in()

func _load_campus_json(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}

func _setup_environment() -> void:
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3B82C4")
	sky_mat.sky_horizon_color = Color("#A8D2F0")
	sky_mat.ground_bottom_color = Color("#2C3B28")
	sky_mat.ground_horizon_color = Color("#8EA38E")

	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.fog_enabled = true
	env.fog_light_color = Color("#C8DCEB")
	env.fog_density = 0.0014
	world_env.environment = env
	add_child(world_env)

	sun_light = DirectionalLight3D.new()
	sun_light.name = "SunLight"
	sun_light.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	sun_light.light_color = Color("#FFF8EB")
	sun_light.light_energy = 1.35
	sun_light.shadow_enabled = true
	sun_light.directional_shadow_max_distance = 130.0
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun_light)

func _setup_audio() -> void:
	ambient_audio = AudioStreamPlayer.new()
	ambient_audio.name = "AmbientAudio"
	ambient_audio.volume_db = -14.0
	var amb_stream := _load_wav_stream("res://assets/audio/ambient_birds_wind.wav", true)
	if amb_stream == null:
		amb_stream = _synth_fallback_wav(true)
	ambient_audio.stream = amb_stream
	add_child(ambient_audio)
	ambient_audio.play()

func _setup_player_and_hud() -> void:
	var sp: Dictionary = campus_data.get("spawn", {})
	var pos_a: Array = sp.get("position", [-55.0, 1.1, 12.0])
	var look_a: Array = sp.get("look_at", [-20.0, 1.8, 8.0])
	player.global_position = Vector3(float(pos_a[0]), float(pos_a[1]), float(pos_a[2]))
	player.look_at_point(Vector3(float(look_a[0]), float(look_a[1]), float(look_a[2])))

	var step_stream := _load_wav_stream("res://assets/audio/footstep.wav", false)
	if step_stream == null:
		step_stream = _synth_fallback_wav(false)
	player.setup_pois(campus_data.get("pois", []), step_stream)
	player.set_gameplay_active(false)

	hud.setup_minimap(campus_data)
	hud.set_muted(is_muted)
	hud.set_day_night(is_night)

	player.nearby_poi_changed.connect(func(p): hud.set_nearby_poi(p))
	player.interact_requested.connect(_on_poi_interacted)
	hud.start_clicked.connect(_start_exploration)
	hud.resume_clicked.connect(_resume_game)
	hud.restart_tour_clicked.connect(_restart_tour)
	hud.free_explore_clicked.connect(_close_modals_and_resume)
	hud.mute_clicked.connect(toggle_mute)
	hud.day_night_clicked.connect(toggle_day_night)
	hud.poi_closed.connect(_on_poi_modal_closed)

func _process(delta: float) -> void:
	for i in range(builder.poi_nodes.size()):
		var beacon := builder.poi_nodes[i].get_node_or_null("Beacon") as Node3D
		if beacon:
			beacon.rotate_y(delta * 1.4)
			beacon.position.y = 2.2 + sin(Time.get_ticks_msec() * 0.003 + i) * 0.18
	hud.update_minimap(player.get_view_position(), player.get_view_yaw(), visited_pois, player.is_drone)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_mute"):
		toggle_mute()
	elif event.is_action_pressed("toggle_day_night") and started:
		toggle_day_night()
	elif event.is_action_pressed("toggle_drone") and started and not hud.is_any_modal_open():
		var d: bool = player.toggle_drone_mode()
		hud.set_drone_mode(d)
	elif event.is_action_pressed("pause") and started:
		if hud.poi_panel.visible:
			hud.poi_panel.visible = false
			_on_poi_modal_closed()
		elif hud.complete_panel.visible:
			hud.complete_panel.visible = false
			_close_modals_and_resume()
		else:
			_toggle_pause()
	elif event.is_action_pressed("interact") and hud.poi_panel.visible:
		hud.poi_panel.visible = false
		_on_poi_modal_closed()

func _start_exploration() -> void:
	started = true
	paused = false
	get_tree().paused = false
	hud.set_start_visible(false)
	player.set_gameplay_active(true)

func _toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused
	hud.set_pause_visible(paused)
	player.set_gameplay_active(not paused)

func _resume_game() -> void:
	paused = false
	get_tree().paused = false
	hud.set_pause_visible(false)
	player.set_gameplay_active(true)

func _close_modals_and_resume() -> void:
	paused = false
	get_tree().paused = false
	hud.set_pause_visible(false)
	player.set_gameplay_active(true)

func _on_poi_interacted(poi: Dictionary) -> void:
	var pid := String(poi.get("id", ""))
	if pid.is_empty():
		return
	visited_pois[pid] = true
	_refresh_poi_visuals()
	var total: int = campus_data.get("pois", []).size()
	hud.set_tour_progress(visited_pois.size(), total)
	player.set_gameplay_active(false)
	hud.show_poi_card(poi)

func _on_poi_modal_closed() -> void:
	var total: int = campus_data.get("pois", []).size()
	if visited_pois.size() >= total and not tour_completed_shown:
		tour_completed_shown = true
		hud.show_complete_modal()
	else:
		player.set_gameplay_active(true)

func _restart_tour() -> void:
	visited_pois.clear()
	tour_completed_shown = false
	_refresh_poi_visuals()
	hud.set_tour_progress(0, campus_data.get("pois", []).size())
	var sp: Dictionary = campus_data.get("spawn", {})
	var pos_a: Array = sp.get("position", [-55.0, 1.1, 12.0])
	var look_a: Array = sp.get("look_at", [-20.0, 1.8, 8.0])
	if player.is_drone:
		hud.set_drone_mode(player.toggle_drone_mode())
	player.global_position = Vector3(float(pos_a[0]), float(pos_a[1]), float(pos_a[2]))
	player.look_at_point(Vector3(float(look_a[0]), float(look_a[1]), float(look_a[2])))
	_close_modals_and_resume()

func _refresh_poi_visuals() -> void:
	for area in builder.poi_nodes:
		var is_vis := visited_pois.has(area.name)
		var beacon := area.get_node_or_null("Beacon") as MeshInstance3D
		if beacon and beacon.material_override is StandardMaterial3D:
			var bmat := beacon.material_override as StandardMaterial3D
			var col := Color("#2F9E41") if is_vis else Color("#F5C43D")
			bmat.albedo_color = col
			bmat.emission = col

func toggle_mute() -> void:
	is_muted = not is_muted
	var master := AudioServer.get_bus_index("Master")
	if master >= 0:
		AudioServer.set_bus_mute(master, is_muted)
	hud.set_muted(is_muted)

func toggle_day_night() -> void:
	is_night = not is_night
	hud.set_day_night(is_night)
	var tw := create_tween().set_parallel(true)
	if is_night:
		tw.tween_property(sun_light, "rotation_degrees:x", -15.0, 1.6)
		tw.tween_property(sun_light, "light_energy", 0.16, 1.6)
		tw.tween_property(sun_light, "light_color", Color("#7094D4"), 1.6)
		tw.tween_property(sky_mat, "sky_top_color", Color("#090D1A"), 1.6)
		tw.tween_property(sky_mat, "sky_horizon_color", Color("#1A243B"), 1.6)
		tw.tween_property(world_env.environment, "ambient_light_energy", 0.22, 1.6)
		tw.tween_property(world_env.environment, "fog_light_color", Color("#141D2E"), 1.6)
		if builder.lamp_mat:
			tw.tween_property(builder.lamp_mat, "emission_energy_multiplier", 3.5, 1.6)
		for l in builder.night_lights:
			tw.tween_property(l, "light_energy", 3.2, 1.6)
	else:
		tw.tween_property(sun_light, "rotation_degrees:x", -48.0, 1.6)
		tw.tween_property(sun_light, "light_energy", 1.35, 1.6)
		tw.tween_property(sun_light, "light_color", Color("#FFF8EB"), 1.6)
		tw.tween_property(sky_mat, "sky_top_color", Color("#3B82C4"), 1.6)
		tw.tween_property(sky_mat, "sky_horizon_color", Color("#A8D2F0"), 1.6)
		tw.tween_property(world_env.environment, "ambient_light_energy", 0.45, 1.6)
		tw.tween_property(world_env.environment, "fog_light_color", Color("#C8DCEB"), 1.6)
		if builder.lamp_mat:
			tw.tween_property(builder.lamp_mat, "emission_energy_multiplier", 0.0, 1.6)
		for l in builder.night_lights:
			tw.tween_property(l, "light_energy", 0.0, 1.6)

func _load_wav_stream(res_path: String, loop: bool) -> AudioStreamWAV:
	var abs_path := ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return null
	var bytes := FileAccess.get_file_as_bytes(abs_path)
	if bytes.size() <= 44:
		return null
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	wav.data = bytes.slice(44)
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = int(wav.data.size() / 2.0)
	return wav

func _synth_fallback_wav(loop: bool) -> AudioStreamWAV:
	var sr := 22050
	var count := sr * (2 if loop else 0) + (0 if loop else int(sr * 0.12))
	var buf := PackedByteArray()
	buf.resize(count * 2)
	for i in range(count):
		var t := float(i) / float(sr)
		var sample := sin(TAU * 420.0 * t) * 0.04 if loop else sin(TAU * 130.0 * t) * exp(-t * 30.0) * 0.4
		buf.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.data = buf
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = count
	return wav

func _ensure_input_map() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT],
		"jump": [KEY_SPACE],
		"interact": [KEY_E],
		"toggle_drone": [KEY_F],
		"toggle_day_night": [KEY_N],
		"toggle_mute": [KEY_M],
		"pause": [KEY_ESCAPE]
	}
	for action in keys.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if InputMap.action_get_events(action).is_empty():
			for kc in keys[action]:
				var ev := InputEventKey.new()
				ev.physical_keycode = kc
				InputMap.action_add_event(action, ev)

func _exit_tree() -> void:
	builder.poi_nodes.clear()
	builder.night_lights.clear()
	builder.mats.cache.clear()
