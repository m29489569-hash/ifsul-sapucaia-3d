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
var is_compat := false

var quality_mode := "auto"
var resolved_quality := "high"
var ft_ema_ms := 16.67
var _auto_warmup := 2.5
var _auto_cooldown := 0.0
var _low_perf_accum := 0.0
var _high_perf_accum := 0.0
var _telemetry_timer := 0.0
var _js_callbacks: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_compat = RenderingServer.get_current_rendering_method() == "gl_compatibility" or OS.has_feature("web")
	_ensure_input_map()
	campus_data = _load_campus_json("res://data/campus.json")
	_setup_environment()
	builder.build(world_node, campus_data)
	_setup_audio()
	_setup_player_and_hud()
	_apply_resolved_quality("medium" if is_compat else "high")
	if OS.has_feature("web"):
		hud.set_start_visible(false)
		_setup_web_bridge()
		RenderingServer.viewport_set_active(get_viewport().get_viewport_rid(), false)
	hud.play_fade_in()

func _load_campus_json(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}

func _setup_environment() -> void:
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var hdr_res := "res://assets/hdri/sky_1k.hdr"
	var used_hdr := false
	if ResourceLoader.exists(hdr_res):
		var hdr_tex: Resource = ResourceLoader.load(hdr_res)
		if hdr_tex is Texture2D:
			var pmat := PanoramaSkyMaterial.new()
			pmat.panorama = hdr_tex
			sky.sky_material = pmat
			used_hdr = true
	if not used_hdr:
		var hdr_path := ProjectSettings.globalize_path(hdr_res)
		if FileAccess.file_exists(hdr_path):
			var hdr_img := Image.load_from_file(hdr_path)
			if hdr_img != null and not hdr_img.is_empty():
				var pmat := PanoramaSkyMaterial.new()
				pmat.panorama = ImageTexture.create_from_image(hdr_img)
				sky.sky_material = pmat
				used_hdr = true
	if not used_hdr:
		sky_mat = ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color("#3B82C4")
		sky_mat.sky_horizon_color = Color("#A8D2F0")
		sky_mat.ground_bottom_color = Color("#2C3B28")
		sky_mat.ground_horizon_color = Color("#8EA38E")
		sky.sky_material = sky_mat

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.background_energy_multiplier = 1.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.58 if is_compat else 0.55
	env.ssao_enabled = not is_compat
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.28 if is_compat else 0.35
	env.glow_bloom = 0.08 if is_compat else 0.12
	if is_compat:
		env.glow_hdr_threshold = 0.88
	env.fog_enabled = true
	env.fog_light_color = Color("#C8DCEB")
	env.fog_density = 0.00024 if is_compat else 0.00028
	env.fog_sky_affect = 0.25
	world_env.environment = env
	add_child(world_env)

	sun_light = DirectionalLight3D.new()
	sun_light.name = "SunLight"
	sun_light.rotation_degrees = Vector3(-42.0, 48.0, 0.0)
	sun_light.light_color = Color("#FFF6E5")
	sun_light.light_energy = 1.78 if is_compat else 1.55
	sun_light.shadow_enabled = true
	sun_light.directional_shadow_max_distance = 150.0 if is_compat else 190.0
	if is_compat:
		sun_light.shadow_bias = 0.02
		sun_light.shadow_normal_bias = 1.0
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
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
	_update_adaptive_quality(delta)
	if OS.has_feature("web"):
		_telemetry_timer += delta
		if _telemetry_timer >= 0.25:
			_telemetry_timer = 0.0
			_notify_web_shell()

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
	if OS.has_feature("web"):
		RenderingServer.viewport_set_active(get_viewport().get_viewport_rid(), true)
	if ambient_audio and not ambient_audio.playing:
		ambient_audio.play()
	hud.set_start_visible(false)
	hud.set_pause_visible(false)
	player.set_gameplay_active(true)
	_auto_warmup = 2.5
	_notify_web_shell()

func _toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused
	hud.set_pause_visible(paused)
	player.set_gameplay_active(not paused)
	_notify_web_shell()

func _resume_game() -> void:
	paused = false
	get_tree().paused = false
	hud.set_pause_visible(false)
	player.set_gameplay_active(not hud.is_any_modal_open())
	_notify_web_shell()

func _close_modals_and_resume() -> void:
	paused = false
	get_tree().paused = false
	hud.set_pause_visible(false)
	player.set_gameplay_active(true)
	_notify_web_shell()

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
	_notify_web_shell()

func _on_poi_modal_closed() -> void:
	var total: int = campus_data.get("pois", []).size()
	if visited_pois.size() >= total and not tour_completed_shown:
		tour_completed_shown = true
		hud.show_complete_modal()
	else:
		player.set_gameplay_active(true)
	_notify_web_shell()

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
	set_muted(not is_muted)

func set_muted(muted: bool) -> void:
	is_muted = muted
	var master := AudioServer.get_bus_index("Master")
	if master >= 0:
		AudioServer.set_bus_mute(master, is_muted)
	hud.set_muted(is_muted)
	_notify_web_shell()

func toggle_day_night() -> void:
	is_night = not is_night
	hud.set_day_night(is_night)
	var tw := create_tween().set_parallel(true)
	if is_night:
		tw.tween_property(sun_light, "rotation_degrees:x", -15.0, 1.6)
		tw.tween_property(sun_light, "light_energy", 0.22, 1.6)
		tw.tween_property(sun_light, "light_color", Color("#7094D4"), 1.6)
		if sky_mat:
			tw.tween_property(sky_mat, "sky_top_color", Color("#090D1A"), 1.6)
			tw.tween_property(sky_mat, "sky_horizon_color", Color("#1A243B"), 1.6)
		tw.tween_property(world_env.environment, "background_energy_multiplier", 0.12, 1.6)
		tw.tween_property(world_env.environment, "ambient_light_energy", 0.24, 1.6)
		tw.tween_property(world_env.environment, "fog_light_color", Color("#141D2E"), 1.6)
		if builder.lamp_mat:
			tw.tween_property(builder.lamp_mat, "emission_energy_multiplier", 4.5, 1.6)
		if builder.win_mat:
			tw.tween_property(builder.win_mat, "emission_energy_multiplier", 1.35, 1.6)
		for l in builder.night_lights:
			tw.tween_property(l, "light_energy", 6.5, 1.6)
	else:
		tw.tween_property(sun_light, "rotation_degrees:x", -42.0, 1.6)
		tw.tween_property(sun_light, "light_energy", 1.78 if is_compat else 1.55, 1.6)
		tw.tween_property(sun_light, "light_color", Color("#FFF6E5"), 1.6)
		if sky_mat:
			tw.tween_property(sky_mat, "sky_top_color", Color("#3B82C4"), 1.6)
			tw.tween_property(sky_mat, "sky_horizon_color", Color("#A8D2F0"), 1.6)
		tw.tween_property(world_env.environment, "background_energy_multiplier", 1.05, 1.6)
		tw.tween_property(world_env.environment, "ambient_light_energy", 0.58 if is_compat else 0.55, 1.6)
		tw.tween_property(world_env.environment, "fog_light_color", Color("#C8DCEB"), 1.6)
		if builder.lamp_mat:
			tw.tween_property(builder.lamp_mat, "emission_energy_multiplier", 0.0, 1.6)
		if builder.win_mat:
			tw.tween_property(builder.win_mat, "emission_energy_multiplier", 0.0, 1.6)
		for l in builder.night_lights:
			tw.tween_property(l, "light_energy", 0.0, 1.6)

func _load_wav_stream(res_path: String, loop: bool) -> AudioStream:
	if ResourceLoader.exists(res_path):
		var res: Resource = ResourceLoader.load(res_path)
		if res is AudioStreamWAV:
			var wav_res := (res as AudioStreamWAV).duplicate() as AudioStreamWAV
			if loop:
				wav_res.loop_mode = AudioStreamWAV.LOOP_FORWARD
				var bps := (2 if wav_res.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if wav_res.stereo else 1)
				wav_res.loop_end = int(wav_res.data.size() / maxf(1.0, float(bps)))
			return wav_res
		elif res is AudioStream:
			return res
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

func set_quality_mode(mode: String) -> void:
	var norm := mode.to_lower()
	if not (norm in ["auto", "high", "medium", "low"]):
		norm = "auto"
	quality_mode = norm
	_low_perf_accum = 0.0
	_high_perf_accum = 0.0
	_auto_warmup = 2.0
	_auto_cooldown = 0.0
	if quality_mode == "auto":
		_apply_resolved_quality("medium" if is_compat else "high")
	else:
		_apply_resolved_quality(quality_mode)
	_notify_web_shell()

func _apply_resolved_quality(tier: String) -> void:
	resolved_quality = tier
	var vp := get_viewport()
	if vp == null:
		return
	var env := world_env.environment if world_env else null
	match tier:
		"low":
			vp.scaling_3d_scale = 0.72
			vp.msaa_3d = Viewport.MSAA_DISABLED
			if env:
				env.glow_enabled = false
			if sun_light:
				sun_light.shadow_enabled = false
			builder.set_vegetation_density(0.35)
		"medium":
			vp.scaling_3d_scale = 0.90
			vp.msaa_3d = Viewport.MSAA_DISABLED
			if env:
				env.glow_enabled = not is_compat
			if sun_light:
				sun_light.shadow_enabled = true
				sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			RenderingServer.directional_shadow_atlas_set_size(1024, true)
			builder.set_vegetation_density(0.75)
		_:
			resolved_quality = "high"
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X
			if env:
				env.glow_enabled = true
			if sun_light:
				sun_light.shadow_enabled = true
				sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if is_compat else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			builder.set_vegetation_density(1.0)

func _update_adaptive_quality(delta: float) -> void:
	if not started or paused or hud.is_any_modal_open():
		return
	var frame_ms := clampf(delta * 1000.0, 1.0, 200.0)
	ft_ema_ms = lerpf(ft_ema_ms, frame_ms, 0.12)
	if quality_mode != "auto":
		return
	if _auto_warmup > 0.0:
		_auto_warmup -= delta
		return
	if _auto_cooldown > 0.0:
		_auto_cooldown -= delta
	if ft_ema_ms > 20.5:
		_low_perf_accum += delta
		_high_perf_accum = 0.0
		if _low_perf_accum >= 1.5 and _auto_cooldown <= 0.0:
			if resolved_quality == "high":
				_apply_resolved_quality("medium")
				_auto_cooldown = 6.0
			elif resolved_quality == "medium":
				_apply_resolved_quality("low")
				_auto_cooldown = 6.0
			_low_perf_accum = 0.0
	elif ft_ema_ms < 12.5:
		_high_perf_accum += delta
		_low_perf_accum = 0.0
		if _high_perf_accum >= 4.0 and _auto_cooldown <= 0.0:
			if resolved_quality == "low":
				_apply_resolved_quality("medium")
				_auto_cooldown = 10.0
			elif resolved_quality == "medium":
				_apply_resolved_quality("high")
				_auto_cooldown = 10.0
			_high_perf_accum = 0.0
	else:
		_low_perf_accum = maxf(0.0, _low_perf_accum - delta * 0.5)
		_high_perf_accum = maxf(0.0, _high_perf_accum - delta * 0.5)

func _build_state_dict() -> Dictionary:
	var pos: Vector3 = player.get_view_position() if player else Vector3.ZERO
	var pois_summary: Array = []
	for p in campus_data.get("pois", []):
		pois_summary.append({
			"id": String(p.get("id", "")),
			"title": String(p.get("title", "")),
			"position": p.get("position", [0, 0, 0])
		})
	return {
		"fps": int(round(Engine.get_frames_per_second())),
		"frametimeMs": snappedf(ft_ema_ms, 0.01),
		"quality": quality_mode,
		"resolvedQuality": resolved_quality,
		"muted": is_muted,
		"paused": paused,
		"started": started,
		"isNight": is_night,
		"isDrone": player.is_drone if player else false,
		"modalOpen": hud.is_any_modal_open() if hud else false,
		"poiModalVisible": hud.poi_panel.visible if hud else false,
		"completeVisible": hud.complete_panel.visible if hud else false,
		"pauseVisible": hud.pause_panel.visible if hud else false,
		"visitedCount": visited_pois.size(),
		"totalPois": campus_data.get("pois", []).size(),
		"visitedIds": visited_pois.keys(),
		"tourText": hud.tour_lbl.text if hud else "",
		"position": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)],
		"yaw": snappedf(player.get_view_yaw() if player else 0.0, 0.001),
		"pois": pois_summary,
		"renderer": RenderingServer.get_current_rendering_method()
	}

func _notify_web_shell() -> void:
	if not OS.has_feature("web"):
		return
	var payload := JSON.stringify(_build_state_dict())
	JavaScriptBridge.eval("window.__ifsulShell && window.__ifsulShell.onGodotState(" + payload + ");", false)

func _setup_web_bridge() -> void:
	var win: Variant = JavaScriptBridge.get_interface("window")
	if win == null:
		return
	var host: Variant = JavaScriptBridge.create_object("Object")
	var add_cb := func(target: Variant, prop: String, fn: Callable) -> void:
		var cb := JavaScriptBridge.create_callback(fn)
		_js_callbacks.append(cb)
		target[prop] = cb

	add_cb.call(host, "start", func(_args):
		if not started:
			_start_exploration()
		elif paused:
			_resume_game()
	)
	add_cb.call(host, "setQuality", func(args):
		if args.size() > 0:
			set_quality_mode(String(args[0]))
	)
	add_cb.call(host, "setMuted", func(args):
		if args.size() > 0:
			set_muted(bool(args[0]))
	)
	add_cb.call(host, "toggleMute", func(_args):
		toggle_mute()
	)
	add_cb.call(host, "setPaused", func(args):
		var want_pause := bool(args[0]) if args.size() > 0 else true
		if want_pause and started and not paused and not hud.is_any_modal_open():
			_toggle_pause()
		elif not want_pause and paused:
			_resume_game()
	)
	add_cb.call(host, "togglePause", func(_args):
		if started and not hud.poi_panel.visible and not hud.complete_panel.visible:
			_toggle_pause()
	)
	add_cb.call(host, "restartTour", func(_args):
		_restart_tour()
	)
	add_cb.call(host, "getStateJson", func(_args):
		return JSON.stringify(_build_state_dict())
	)
	win["__ifsulGodot"] = host

	var is_test := bool(JavaScriptBridge.eval("new URLSearchParams(location.search).get('test') === '1'", false))
	if is_test:
		var test_api: Variant = JavaScriptBridge.create_object("Object")
		add_cb.call(test_api, "getStateJson", func(_args):
			return JSON.stringify(_build_state_dict())
		)
		add_cb.call(test_api, "teleport", func(args):
			if args.size() >= 3 and player:
				player.global_position = Vector3(float(args[0]), float(args[1]), float(args[2]))
				player.velocity = Vector3.ZERO
				player._update_nearest_poi()
				_notify_web_shell()
		)
		add_cb.call(test_api, "interact", func(_args):
			if player:
				player._update_nearest_poi()
				if not player.current_poi.is_empty():
					_on_poi_interacted(player.current_poi)
					return true
			return false
		)
		add_cb.call(test_api, "closePoiModal", func(_args):
			if hud.poi_panel.visible:
				hud.poi_panel.visible = false
				_on_poi_modal_closed()
				return true
			return false
		)
		add_cb.call(test_api, "closeCompleteModal", func(_args):
			if hud.complete_panel.visible:
				hud.complete_panel.visible = false
				_close_modals_and_resume()
				return true
			return false
		)
		add_cb.call(test_api, "setQuality", func(args):
			if args.size() > 0:
				set_quality_mode(String(args[0]))
		)
		add_cb.call(test_api, "toggleMute", func(_args):
			toggle_mute()
		)
		add_cb.call(test_api, "togglePause", func(_args):
			if started:
				_toggle_pause()
		)
		add_cb.call(test_api, "resume", func(_args):
			_resume_game()
		)
		add_cb.call(test_api, "toggleDayNight", func(_args):
			toggle_day_night()
			_notify_web_shell()
		)
		add_cb.call(test_api, "toggleDrone", func(_args):
			var d: bool = player.toggle_drone_mode()
			hud.set_drone_mode(d)
			_notify_web_shell()
			return d
		)
		add_cb.call(test_api, "restartTour", func(_args):
			_restart_tour()
			_notify_web_shell()
		)
		win["__ifsulRaw"] = test_api
		JavaScriptBridge.eval("window.__ifsulShell && window.__ifsulShell.exposeTestHook && window.__ifsulShell.exposeTestHook();", false)

	JavaScriptBridge.eval("window.__ifsulShell && window.__ifsulShell.onGodotReady && window.__ifsulShell.onGodotReady();", false)
	_notify_web_shell()

func _exit_tree() -> void:
	_js_callbacks.clear()
	builder.tree_mmi_list.clear()
	builder.poi_nodes.clear()
	builder.night_lights.clear()
	builder.mats.cache.clear()
	builder.mats._noise_cache.clear()
