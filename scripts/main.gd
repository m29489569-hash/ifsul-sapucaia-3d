extends Node3D

const CampusBuilderLib = preload("res://scripts/campus_builder.gd")
const PerfManagerLib = preload("res://scripts/perf_manager.gd")

@onready var world_node: Node3D = $World
@onready var player: CharacterBody3D = $Player
@onready var hud: CanvasLayer = $HUD

var campus_data: Dictionary = {}
var interiors_data: Dictionary = {}
var builder := CampusBuilderLib.new()
var perf := PerfManagerLib.new()
var sun_light: DirectionalLight3D
var world_env: WorldEnvironment
var sky_mat: ProceduralSkyMaterial
var ambient_audio: AudioStreamPlayer

var visited_pois: Dictionary = {}
var current_room: Dictionary = {}
var tour_completed_shown := false
var is_night := false
var is_muted := false
var started := false
var paused := false
var is_compat := false
var roofs_visible := true

var _pois_summary: Array = []
var _telemetry_timer := 0.0
var _room_check_timer := 0.0
var _last_room_check_pos := Vector3(1e9, 0.0, 1e9)
var _js_callbacks: Array = []
var _active_day_night_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_compat = RenderingServer.get_current_rendering_method() == "gl_compatibility" or OS.has_feature("web")
	_ensure_input_map()
	if get_viewport():
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	if OS.has_feature("web"):
		set_process(false)
		hud.set_start_visible(false)
		hud.set_fade_alpha(0.0)
		_read_web_init_prefs()
		call_deferred("_boot_web_staged")
		return
	campus_data = _load_json_dict("res://data/campus.json")
	interiors_data = _load_json_dict("res://data/interiors.json")
	_cache_pois_summary()
	_setup_environment()
	builder.build(world_node, campus_data, interiors_data)
	_setup_audio()
	_setup_player_and_hud()
	_apply_resolved_quality("medium" if is_compat else "high")
	_sync_idle_throttle()
	hud.play_fade_in()

func _read_web_init_prefs() -> void:
	var q_raw: Variant = JavaScriptBridge.eval("(window.__ifsulInitPrefs && window.__ifsulInitPrefs.quality) || localStorage.getItem('ifsul.quality') || 'auto'", false)
	var q_str := String(q_raw).to_lower() if q_raw != null else "auto"
	if q_str in ["auto", "high", "medium", "low"]:
		perf.quality_mode = q_str
	var m_raw: Variant = JavaScriptBridge.eval("Boolean((window.__ifsulInitPrefs && window.__ifsulInitPrefs.muted) ?? (localStorage.getItem('ifsul.muted') === '1'))", false)
	is_muted = bool(m_raw)

func _notify_boot_stage(pct: int, status_text: String) -> void:
	if not OS.has_feature("web"):
		return
	var safe_txt := JSON.stringify(status_text)
	JavaScriptBridge.eval("window.__ifsulShell && window.__ifsulShell.onBootProgress && window.__ifsulShell.onBootProgress(" + str(pct) + ", " + safe_txt + ");", false)

func _warmup_viewport_frame(vp_rid: RID) -> void:
	RenderingServer.viewport_set_active(vp_rid, true)
	await RenderingServer.frame_post_draw
	RenderingServer.viewport_set_active(vp_rid, false)
	await get_tree().process_frame

func _boot_web_staged() -> void:
	var vp_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_active(vp_rid, false)
	hud.visible = false

	_notify_boot_stage(82, "Configurando iluminação e ambiente 3D...")
	await get_tree().process_frame
	campus_data = _load_json_dict("res://data/campus.json")
	interiors_data = _load_json_dict("res://data/interiors.json")
	_cache_pois_summary()
	_setup_environment()
	var sp: Dictionary = campus_data.get("spawn", {})
	var pos_a: Array = sp.get("position", [-55.0, 1.1, 12.0])
	var look_a: Array = sp.get("look_at", [-20.0, 1.8, 8.0])
	player.global_position = Vector3(float(pos_a[0]), float(pos_a[1]), float(pos_a[2]))
	player.look_at_point(Vector3(float(look_a[0]), float(look_a[1]), float(look_a[2])))
	var init_tier := ("medium" if is_compat else "high") if perf.quality_mode == "auto" else perf.quality_mode
	_apply_resolved_quality(init_tier)
	builder.begin_build(world_node)
	await _warmup_viewport_frame(vp_rid)

	_notify_boot_stage(85, "Construindo terreno e vias...")
	await get_tree().process_frame
	builder.build_stage_terrain_base(world_node, campus_data)
	await get_tree().process_frame

	_notify_boot_stage(88, "Finalizando pátios e quadras...")
	await get_tree().process_frame
	builder.build_stage_terrain_details(world_node, campus_data)
	await _warmup_viewport_frame(vp_rid)

	var buildings: Array = campus_data.get("buildings", [])
	var b_total := buildings.size()
	var b_chunk := 5
	for b_start in range(0, b_total, b_chunk):
		var b_end := mini(b_start + b_chunk, b_total)
		var pct := 89 + int(round(4.0 * float(b_end) / maxf(1.0, float(b_total))))
		_notify_boot_stage(pct, "Erguendo blocos (%d/%d)..." % [b_end, b_total])
		await get_tree().process_frame
		builder.build_stage_buildings_range(world_node, campus_data, b_start, b_end)
		if b_start == 0:
			await _warmup_viewport_frame(vp_rid)
		else:
			await get_tree().process_frame

	_notify_boot_stage(94, "Construindo pórticos e marcos...")
	await get_tree().process_frame
	builder.build_stage_landmarks(world_node, campus_data)
	await _warmup_viewport_frame(vp_rid)

	_notify_boot_stage(96, "Construindo interiores e sinalização das salas...")
	await get_tree().process_frame
	builder.build_stage_interiors(world_node, campus_data, interiors_data)
	await _warmup_viewport_frame(vp_rid)

	_notify_boot_stage(97, "Plantando vegetação e mobiliário...")
	await get_tree().process_frame
	builder.build_stage_vegetation(world_node, campus_data)
	await _warmup_viewport_frame(vp_rid)

	_notify_boot_stage(98, "Preparando áudio e interface...")
	await get_tree().process_frame
	builder.build_stage_finalize_props(world_node, campus_data)
	hud.visible = true
	_setup_audio()
	_setup_player_and_hud()
	perf.apply_quality(init_tier, get_viewport(), world_env.environment if world_env else null, sun_light, builder, is_compat, true)
	var master := AudioServer.get_bus_index("Master")
	if master >= 0:
		AudioServer.set_bus_mute(master, is_muted)
	hud.set_muted(is_muted)
	hud.call_deferred("_on_viewport_resized")
	await get_tree().process_frame

	_notify_boot_stage(99, "Finalizando cena 3D...")
	await get_tree().process_frame
	RenderingServer.viewport_set_active(vp_rid, true)
	await RenderingServer.frame_post_draw

	if not started:
		_sync_idle_throttle()
		get_tree().paused = true
	_setup_web_bridge()

func _cache_pois_summary() -> void:
	_pois_summary.clear()
	for p in campus_data.get("pois", []):
		_pois_summary.append({
			"id": String(p.get("id", "")),
			"title": String(p.get("title", "")),
			"position": p.get("position", [0, 0, 0])
		})

func _load_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		return {}
	var parsed = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}

func _setup_environment() -> void:
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3B82C4")
	sky_mat.sky_horizon_color = Color("#A8D2F0")
	sky_mat.ground_bottom_color = Color("#2C3B28")
	sky_mat.ground_horizon_color = Color("#8EA38E")
	var used_hdr := false
	if not is_compat:
		var hdr_res := "res://assets/hdri/sky_1k.hdr"
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
		sky.sky_material = sky_mat
	if is_compat:
		sky.radiance_size = Sky.RADIANCE_SIZE_64
		sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.background_energy_multiplier = 1.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	if is_compat:
		# Avoid sky cubemap glReadPixels GPU stalls on WebGL2
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("#C4D7E8")
		env.ambient_light_sky_contribution = 0.0
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.58 if is_compat else 0.55
	env.ssao_enabled = not is_compat
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.15
	env.glow_enabled = not is_compat
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
	sun_light.directional_shadow_max_distance = 85.0 if is_compat else 190.0
	if is_compat:
		sun_light.shadow_bias = 0.03
		sun_light.shadow_normal_bias = 0.28
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if is_compat else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
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
	if not OS.has_feature("web"):
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

	hud.setup_minimap(campus_data, interiors_data)
	hud.set_room_search_provider(Callable(self, "search_rooms"))
	hud.set_muted(is_muted)
	hud.set_day_night(is_night)
	hud.set_drone_mode(player.is_drone, roofs_visible)

	player.nearby_poi_changed.connect(func(p): hud.set_nearby_poi(p))
	player.interact_requested.connect(_on_poi_interacted)
	hud.start_clicked.connect(_start_exploration)
	hud.resume_clicked.connect(_resume_game)
	hud.restart_tour_clicked.connect(_restart_tour)
	hud.free_explore_clicked.connect(_close_modals_and_resume)
	hud.mute_clicked.connect(toggle_mute)
	hud.day_night_clicked.connect(toggle_day_night)
	hud.poi_closed.connect(_on_poi_modal_closed)
	hud.room_search_selected.connect(_on_room_search_selected)
	hud.room_search_drone_requested.connect(_on_room_search_drone_requested)
	hud.room_search_cleared.connect(_on_room_search_cleared)
	hud.search_opened.connect(_on_search_opened)
	hud.search_closed.connect(_on_search_closed)
	hud.map_toggle_requested.connect(_toggle_expanded_map)
	_refresh_current_room(true)

func _process(delta: float) -> void:
	var ticks := Time.get_ticks_msec() * 0.003
	var beacons := builder.poi_beacons
	for i in range(beacons.size()):
		var beacon := beacons[i]
		if is_instance_valid(beacon):
			beacon.rotate_y(delta * 1.4)
			beacon.position.y = 2.2 + sin(ticks + i) * 0.18

	_room_check_timer += delta
	if _room_check_timer >= 0.15:
		_room_check_timer = 0.0
		_refresh_current_room(false)

	hud.update_minimap(player.get_view_position(), player.get_view_yaw(), visited_pois, player.is_drone, current_room)
	var vp := get_viewport()
	var env := world_env.environment if world_env else null
	var modal_open: bool = hud.is_any_modal_open() if hud else false
	perf.update_adaptive_quality(delta, started, paused, modal_open, vp, env, sun_light, builder, is_compat)
	perf.update_runtime_systems(delta, vp, builder, is_night, player)
	if OS.has_feature("web"):
		_telemetry_timer += delta
		if _telemetry_timer >= 0.25:
			_telemetry_timer = 0.0
			_notify_web_shell()

func _input(event: InputEvent) -> void:
	if not started:
		return
	if event.is_action_pressed("pause") and hud.is_room_search_open():
		hud.close_room_search()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and hud.is_expanded_map_open():
		_toggle_expanded_map()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_map") and not paused and not hud.is_room_search_open():
		if not hud.poi_panel.visible and not hud.complete_panel.visible and not hud.start_panel.visible:
			_toggle_expanded_map()
			get_viewport().set_input_as_handled()
			return

func _unhandled_input(event: InputEvent) -> void:
	if hud.is_room_search_open():
		if event.is_action_pressed("pause"):
			hud.close_room_search()
		return
	if hud.is_expanded_map_open():
		if event.is_action_pressed("pause") or event.is_action_pressed("toggle_map"):
			_toggle_expanded_map()
		return

	if event.is_action_pressed("toggle_mute"):
		toggle_mute()
	elif event.is_action_pressed("toggle_day_night") and started:
		toggle_day_night()
	elif event.is_action_pressed("search_rooms") and started and not paused and not hud.is_any_modal_open():
		hud.open_room_search()
	elif event.is_action_pressed("toggle_drone") and started and not hud.is_any_modal_open():
		var d: bool = player.toggle_drone_mode()
		if not d:
			set_roofs_visible(true)
		else:
			hud.set_drone_mode(true, roofs_visible)
		_refresh_current_room(true)
		_notify_web_shell()
	elif event.is_action_pressed("toggle_roofs") and started and player.is_drone and not hud.is_any_modal_open():
		var cur_roofs: bool = bool(builder.get("roofs_visible")) if builder.get("roofs_visible") != null else roofs_visible
		set_roofs_visible(not cur_roofs)
		_notify_web_shell()
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

func _refresh_current_room(force: bool = false) -> void:
	if player == null:
		return
	if player.is_drone:
		if not current_room.is_empty():
			current_room = {}
			hud.set_current_room({})
		return
	var pos := player.global_position
	if not force and pos.distance_squared_to(_last_room_check_pos) < 0.04:
		return
	_last_room_check_pos = pos
	var found: Dictionary = builder.find_room_at(pos) if builder.has_method("find_room_at") else {}
	if String(found.get("id", "")) != String(current_room.get("id", "")):
		current_room = found
		hud.set_current_room(current_room)

func search_rooms(query: String) -> Array[Dictionary]:
	if builder.has_method("search_rooms"):
		return builder.search_rooms(query)
	var out: Array[Dictionary] = []
	var q := query.strip_edges().to_lower()
	for r in interiors_data.get("rooms", []):
		if r is Dictionary:
			if q.is_empty():
				out.append(r)
			else:
				var hay := ("%s %s %s" % [String(r.get("code", "")), String(r.get("name", "")), String(r.get("sector", ""))]).to_lower()
				if hay.contains(q):
					out.append(r)
	return out

func set_roofs_visible(vis: bool) -> void:
	roofs_visible = vis
	if builder.has_method("set_roofs_visible"):
		builder.set_roofs_visible(vis)
	if hud:
		hud.set_drone_mode(player.is_drone if player else false, roofs_visible)

func _get_room_world_pos(room: Dictionary) -> Vector3:
	if builder.has_method("get_room_world_pos"):
		return builder.call("get_room_world_pos", room)
	var ib: Variant = builder.get("interior_builder")
	if ib != null and ib.has_method("get_room_world_pos"):
		return ib.call("get_room_world_pos", room)
	var c: Array = room.get("center", [0.0, 0.0])
	if c.size() >= 2:
		return Vector3(float(c[0]), 0.0, float(c[1]))
	return Vector3.ZERO

func _format_room_label(room: Dictionary) -> String:
	var code := String(room.get("code", ""))
	var rname := String(room.get("name", ""))
	if not code.is_empty() and not rname.is_empty():
		return "%s • %s" % [code, rname]
	return rname if not rname.is_empty() else code

func _on_search_opened() -> void:
	player.set_gameplay_active(false)
	_sync_idle_throttle()
	_notify_web_shell()

func _on_search_closed() -> void:
	player.set_gameplay_active(started and not paused and not hud.is_any_modal_open())
	_sync_idle_throttle()
	_notify_web_shell()

func _on_room_search_selected(room: Dictionary) -> void:
	var pos := _get_room_world_pos(room)
	var label := _format_room_label(room)
	hud.set_target_room(pos, label)
	if builder.has_method("set_room_beacon"):
		builder.set_room_beacon(pos, label)
	if player.is_drone:
		player.move_drone_to_target(pos)
	player.set_gameplay_active(started and not paused and not hud.is_any_modal_open())
	_sync_idle_throttle()
	_notify_web_shell()

func _on_room_search_drone_requested(room: Dictionary) -> void:
	var pos := _get_room_world_pos(room)
	var label := _format_room_label(room)
	hud.set_target_room(pos, label)
	if builder.has_method("set_room_beacon"):
		builder.set_room_beacon(pos, label)
	player.move_drone_to_target(pos)
	hud.set_drone_mode(true, roofs_visible)
	_refresh_current_room(true)
	player.set_gameplay_active(started and not paused and not hud.is_any_modal_open())
	_sync_idle_throttle()
	_notify_web_shell()

func _on_room_search_cleared() -> void:
	hud.clear_target_room()
	if builder.has_method("clear_room_beacon"):
		builder.clear_room_beacon()

func _toggle_expanded_map() -> void:
	var next_open: bool = not hud.is_expanded_map_open()
	hud.set_expanded_map_visible(next_open)
	if next_open:
		hud.update_minimap(player.get_view_position(), player.get_view_yaw(), visited_pois, player.is_drone, current_room)
		player.set_gameplay_active(false)
	else:
		player.set_gameplay_active(started and not paused and not hud.is_any_modal_open())
	_sync_idle_throttle()
	_notify_web_shell()

func _start_exploration() -> void:
	started = true
	paused = false
	get_tree().paused = false
	set_process(true)
	if ambient_audio and not ambient_audio.playing:
		ambient_audio.call_deferred("play")
	hud.set_start_visible(false)
	hud.set_pause_visible(false)
	player.set_gameplay_active(true)
	perf.reset_auto_timers(1.0)
	_sync_idle_throttle()
	_notify_web_shell()

func _toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused
	hud.set_pause_visible(paused)
	player.set_gameplay_active(not paused and not hud.is_any_modal_open())
	_sync_idle_throttle()
	_notify_web_shell()

func _resume_game() -> void:
	paused = false
	get_tree().paused = false
	hud.set_pause_visible(false)
	player.set_gameplay_active(not hud.is_any_modal_open())
	_sync_idle_throttle()
	_notify_web_shell()

func _close_modals_and_resume() -> void:
	paused = false
	get_tree().paused = false
	hud.set_pause_visible(false)
	hud.set_expanded_map_visible(false)
	if hud.is_room_search_open():
		hud.search_overlay.visible = false
		hud.search_input.release_focus()
	player.set_gameplay_active(true)
	_sync_idle_throttle()
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
	_sync_idle_throttle()
	_notify_web_shell()

func _on_poi_modal_closed() -> void:
	var total: int = campus_data.get("pois", []).size()
	if visited_pois.size() >= total and not tour_completed_shown:
		tour_completed_shown = true
		hud.show_complete_modal()
	else:
		player.set_gameplay_active(true)
	_sync_idle_throttle()
	_notify_web_shell()

func _restart_tour() -> void:
	visited_pois.clear()
	tour_completed_shown = false
	_refresh_poi_visuals()
	hud.set_tour_progress(0, campus_data.get("pois", []).size())
	_on_room_search_cleared()
	var sp: Dictionary = campus_data.get("spawn", {})
	var pos_a: Array = sp.get("position", [-55.0, 1.1, 12.0])
	var look_a: Array = sp.get("look_at", [-20.0, 1.8, 8.0])
	if player.is_drone:
		player.toggle_drone_mode()
	set_roofs_visible(true)
	player.teleport_to(Vector3(float(pos_a[0]), float(pos_a[1]), float(pos_a[2])))
	player.look_at_point(Vector3(float(look_a[0]), float(look_a[1]), float(look_a[2])))
	_refresh_current_room(true)
	_close_modals_and_resume()

func _refresh_poi_visuals() -> void:
	for i in range(builder.poi_nodes.size()):
		var area := builder.poi_nodes[i]
		var is_vis := visited_pois.has(area.name)
		var beacon := (builder.poi_beacons[i] if i < builder.poi_beacons.size() else null) as MeshInstance3D
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
	if _active_day_night_tween and _active_day_night_tween.is_valid():
		_active_day_night_tween.kill()
	perf.notify_night_tween_started()
	var tw := create_tween().set_parallel(true)
	_active_day_night_tween = tw
	if is_night:
		tw.tween_property(sun_light, "rotation_degrees:x", -15.0, 1.6)
		tw.tween_property(sun_light, "light_energy", 0.22, 1.6)
		tw.tween_property(sun_light, "light_color", Color("#7094D4"), 1.6)
		if sky_mat:
			tw.tween_property(sky_mat, "sky_top_color", Color("#090D1A"), 1.6)
			tw.tween_property(sky_mat, "sky_horizon_color", Color("#1A243B"), 1.6)
		tw.tween_property(world_env.environment, "background_energy_multiplier", 0.12, 1.6)
		tw.tween_property(world_env.environment, "ambient_light_energy", 0.24, 1.6)
		if is_compat:
			tw.tween_property(world_env.environment, "ambient_light_color", Color("#1A243B"), 1.6)
		tw.tween_property(world_env.environment, "fog_light_color", Color("#141D2E"), 1.6)
		if builder.lamp_mat:
			tw.tween_property(builder.lamp_mat, "emission_energy_multiplier", 4.5, 1.6)
		if builder.win_mat:
			tw.tween_property(builder.win_mat, "emission_energy_multiplier", 1.35, 1.6)
		tw.tween_property(perf, "night_factor", 1.0, 1.6)
	else:
		tw.tween_property(sun_light, "rotation_degrees:x", -42.0, 1.6)
		tw.tween_property(sun_light, "light_energy", 1.78 if is_compat else 1.55, 1.6)
		tw.tween_property(sun_light, "light_color", Color("#FFF6E5"), 1.6)
		if sky_mat:
			tw.tween_property(sky_mat, "sky_top_color", Color("#3B82C4"), 1.6)
			tw.tween_property(sky_mat, "sky_horizon_color", Color("#A8D2F0"), 1.6)
		tw.tween_property(world_env.environment, "background_energy_multiplier", 1.05, 1.6)
		tw.tween_property(world_env.environment, "ambient_light_energy", 0.58 if is_compat else 0.55, 1.6)
		if is_compat:
			tw.tween_property(world_env.environment, "ambient_light_color", Color("#C4D7E8"), 1.6)
		tw.tween_property(world_env.environment, "fog_light_color", Color("#C8DCEB"), 1.6)
		if builder.lamp_mat:
			tw.tween_property(builder.lamp_mat, "emission_energy_multiplier", 0.0, 1.6)
		if builder.win_mat:
			tw.tween_property(builder.win_mat, "emission_energy_multiplier", 0.0, 1.6)
		tw.tween_property(perf, "night_factor", 0.0, 1.6)
	tw.chain().tween_callback(func():
		perf.notify_night_tween_finished(is_night)
		perf.update_runtime_systems(0.0, get_viewport(), builder, is_night, player)
	)

func _load_wav_stream(res_path: String, loop: bool) -> AudioStream:
	if ResourceLoader.exists(res_path):
		var res: Resource = ResourceLoader.load(res_path)
		if res is AudioStreamWAV:
			var wav_res := res as AudioStreamWAV
			if loop and wav_res.loop_mode != AudioStreamWAV.LOOP_FORWARD:
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
		"search_rooms": [KEY_G],
		"toggle_map": [KEY_TAB],
		"toggle_roofs": [KEY_T],
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

func _sync_idle_throttle() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var modal_open: bool = hud.is_any_modal_open() if hud else false
	perf.update_idle_throttle(started, paused, modal_open, vp.get_viewport_rid())

func _on_viewport_size_changed() -> void:
	var vp := get_viewport()
	if vp == null or world_env == null:
		return
	var env := world_env.environment
	perf.apply_quality(perf.resolved_quality, vp, env, sun_light, builder, is_compat, true)

func set_quality_mode(mode: String) -> void:
	var norm := mode.to_lower()
	if not (norm in ["auto", "high", "medium", "low"]):
		norm = "auto"
	perf.quality_mode = norm
	perf.reset_auto_timers(2.0)
	if perf.quality_mode == "auto":
		_apply_resolved_quality("medium" if is_compat else "high")
	else:
		_apply_resolved_quality(perf.quality_mode)
	_notify_web_shell()

func _apply_resolved_quality(tier: String) -> void:
	var vp := get_viewport()
	var env := world_env.environment if world_env else null
	perf.apply_quality(tier, vp, env, sun_light, builder, is_compat)

func _build_state_dict() -> Dictionary:
	var pos: Vector3 = player.get_view_position() if player else Vector3.ZERO
	if _pois_summary.is_empty() and not campus_data.is_empty():
		_cache_pois_summary()
	return {
		"fps": int(round(Engine.get_frames_per_second())),
		"frametimeMs": snappedf(perf.ft_ema_ms, 0.01),
		"quality": perf.quality_mode,
		"resolvedQuality": perf.resolved_quality,
		"muted": is_muted,
		"paused": paused,
		"started": started,
		"isNight": is_night,
		"isDrone": player.is_drone if player else false,
		"roofsVisible": roofs_visible,
		"currentRoom": current_room,
		"modalOpen": hud.is_any_modal_open() if hud else false,
		"poiModalVisible": hud.poi_panel.visible if hud else false,
		"completeVisible": hud.complete_panel.visible if hud else false,
		"pauseVisible": hud.pause_panel.visible if hud else false,
		"searchVisible": hud.is_room_search_open() if hud else false,
		"mapVisible": hud.is_expanded_map_open() if hud else false,
		"visitedCount": visited_pois.size(),
		"totalPois": _pois_summary.size(),
		"visitedIds": visited_pois.keys(),
		"tourText": hud.tour_lbl.text if hud else "",
		"position": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)],
		"yaw": snappedf(player.get_view_yaw() if player else 0.0, 0.001),
		"pois": _pois_summary,
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
		if started and not hud.poi_panel.visible and not hud.complete_panel.visible and not hud.is_room_search_open() and not hud.is_expanded_map_open():
			_toggle_pause()
	)
	add_cb.call(host, "restartTour", func(_args):
		_restart_tour()
	)
	add_cb.call(host, "setBackgroundHidden", func(args):
		var hidden := bool(args[0]) if args.size() > 0 else false
		var vp := get_viewport()
		if vp != null:
			var modal_open: bool = hud.is_any_modal_open() if hud else false
			perf.set_background_hidden(hidden, started, paused, modal_open, vp.get_viewport_rid())
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
				player.teleport_to(Vector3(float(args[0]), float(args[1]), float(args[2])))
				_refresh_current_room(true)
				_notify_web_shell()
		)
		add_cb.call(test_api, "interact", func(_args):
			if player:
				player._update_nearest_poi(true)
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
			if not d:
				set_roofs_visible(true)
			else:
				hud.set_drone_mode(true, roofs_visible)
			_refresh_current_room(true)
			_notify_web_shell()
			return d
		)
		add_cb.call(test_api, "restartTour", func(_args):
			_restart_tour()
			_notify_web_shell()
		)
		add_cb.call(test_api, "refreshCurrentRoom", func(_args):
			_refresh_current_room(true)
			JavaScriptBridge.eval("window.__ifsulLastRoom = " + JSON.stringify(current_room) + ";", false)
			_notify_web_shell()
		)
		add_cb.call(test_api, "searchRoom", func(args):
			var q := String(args[0]) if args.size() > 0 else ""
			var matches := search_rooms(q)
			JavaScriptBridge.eval("window.__ifsulLastSearch = " + JSON.stringify(matches) + ";", false)
		)
		add_cb.call(test_api, "setRoofsVisible", func(args):
			var vis := bool(args[0]) if args.size() > 0 else true
			set_roofs_visible(vis)
			_notify_web_shell()
		)
		win["__ifsulRaw"] = test_api
		JavaScriptBridge.eval("window.__ifsulShell && window.__ifsulShell.exposeTestHook && window.__ifsulShell.exposeTestHook();", false)
		JavaScriptBridge.eval("""
			if (window.__ifsul && window.__ifsulRaw) {
				window.__ifsul.getCurrentRoom = function() {
					window.__ifsulRaw.refreshCurrentRoom();
					return window.__ifsulLastRoom || {};
				};
				window.__ifsul.searchRoom = function(q) {
					window.__ifsulRaw.searchRoom(String(q || ''));
					return window.__ifsulLastSearch || [];
				};
				window.__ifsul.setRoofsVisible = function(v) {
					window.__ifsulRaw.setRoofsVisible(Boolean(v));
				};
			}
		""", false)

	JavaScriptBridge.eval("window.__ifsulShell && window.__ifsulShell.onGodotReady && window.__ifsulShell.onGodotReady();", false)
	_notify_web_shell()

func _exit_tree() -> void:
	Engine.max_fps = 0
	if _active_day_night_tween and _active_day_night_tween.is_valid():
		_active_day_night_tween.kill()
	if ambient_audio:
		ambient_audio.stop()
		ambient_audio.stream = null
	if player and player.footstep_audio:
		player.footstep_audio.stop()
		player.footstep_audio.stream = null
	_js_callbacks.clear()
	builder.cleanup()
