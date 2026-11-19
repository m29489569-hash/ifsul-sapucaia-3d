class_name CampusPerfManager
extends RefCounted

var quality_mode := "auto"
var resolved_quality := "high"
var ft_ema_ms := 16.67
var night_factor := 0.0

var _quality_initialized := false
var _applied_shadow_size := -1
var _positional_atlas_cleared := false
var _auto_warmup := 2.5
var _auto_cooldown := 0.0
var _low_perf_accum := 0.0
var _high_perf_accum := 0.0

var _max_night_lights := 10
var _detail_range_scale := 1.0
var _fps_far_distance := 360.0
var _light_timer := 0.0
var _last_light_cam_pos := Vector3(1e9, 0.0, 1e9)
var _last_is_night := false
var _last_aerial := false
var _night_tween_active := false
var _last_detail_scale := -1.0
var _last_detail_aerial := false
var _bg_hidden := false
var _last_throttle_state := -1
var _vp_active := true
var _interior_timer := 0.0
var _last_interior_cam_pos := Vector3(1e9, 0.0, 1e9)
var _last_interior_aerial := false

func reset_auto_timers(warmup: float = 2.0) -> void:
	_low_perf_accum = 0.0
	_high_perf_accum = 0.0
	_auto_warmup = warmup
	_auto_cooldown = 0.0

func set_background_hidden(hidden: bool, started: bool, paused: bool, modal_open: bool, vp_rid: RID) -> void:
	_bg_hidden = hidden
	update_idle_throttle(started, paused, modal_open, vp_rid)

func notify_night_tween_started() -> void:
	_night_tween_active = true
	_light_timer = 999.0

func notify_night_tween_finished(is_night: bool) -> void:
	_night_tween_active = false
	night_factor = 1.0 if is_night else 0.0
	_last_is_night = is_night
	_light_timer = 999.0

func apply_quality(tier: String, vp: Viewport, env: Environment, sun_light: DirectionalLight3D, builder, is_compat: bool, force: bool = false) -> void:
	var norm_tier := tier if tier in ["low", "medium", "high"] else "high"
	if not force and _quality_initialized and resolved_quality == norm_tier:
		return
	_quality_initialized = true
	resolved_quality = norm_tier
	if vp == null:
		return

	if not _positional_atlas_cleared:
		_positional_atlas_cleared = true
		vp.positional_shadow_atlas_size = 0
		if not OS.has_feature("web"):
			vp.use_occlusion_culling = true

	var vp_rect := vp.get_visible_rect().size
	var pixels := maxf(1.0, vp_rect.x * vp_rect.y)

	match norm_tier:
		"low":
			var low_scale := 0.75
			if pixels > 2200000.0:
				low_scale = clampf(sqrt(750000.0 / pixels), 0.55, 0.75)
			vp.scaling_3d_scale = low_scale
			if not is_compat:
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
				vp.fsr_sharpness = 0.2
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.texture_mipmap_bias = 0.5
			if env:
				env.glow_enabled = false
				env.ssao_enabled = false
			if sun_light:
				sun_light.shadow_enabled = false
			_max_night_lights = 2
			_detail_range_scale = 0.55
			_fps_far_distance = 260.0
			builder.set_vegetation_density(0.35, false)
		"medium":
			var med_scale := 1.0
			if is_compat:
				# On <= 1.4M px screens, 1.0 avoids an extra FBO resolve/blit pass in WebGL2 and keeps text/edges sharp.
				if pixels > 1400000.0:
					med_scale = clampf(sqrt(1200000.0 / pixels), 0.70, 0.94)
			else:
				med_scale = 0.90 if pixels > 1000000.0 else 1.0
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
				vp.fsr_sharpness = 0.2
			vp.scaling_3d_scale = med_scale
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.texture_mipmap_bias = 0.25
			if env:
				env.glow_enabled = not is_compat
				env.ssao_enabled = false
			if sun_light:
				sun_light.shadow_enabled = true
				sun_light.directional_shadow_max_distance = 85.0 if is_compat else 130.0
				sun_light.directional_shadow_fade_start = 0.80
				sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if is_compat else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			if _applied_shadow_size != 1024:
				_applied_shadow_size = 1024
				RenderingServer.directional_shadow_atlas_set_size(1024, true)
			_max_night_lights = 6
			_detail_range_scale = 0.78
			_fps_far_distance = 320.0
			builder.set_vegetation_density(0.75, true)
		_:
			var hi_scale := 1.0
			if is_compat and pixels > 3200000.0:
				hi_scale = clampf(sqrt(2400000.0 / pixels), 0.80, 1.0)
			vp.scaling_3d_scale = hi_scale
			if not is_compat:
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.msaa_3d = Viewport.MSAA_DISABLED if (is_compat and pixels > 2200000.0) else Viewport.MSAA_2X
			vp.texture_mipmap_bias = 0.0
			if env:
				env.glow_enabled = true
				env.ssao_enabled = not is_compat
			if sun_light:
				sun_light.shadow_enabled = true
				sun_light.directional_shadow_max_distance = 105.0 if is_compat else 185.0
				sun_light.directional_shadow_fade_start = 0.82
				sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if is_compat else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			if _applied_shadow_size != 2048:
				_applied_shadow_size = 2048
				RenderingServer.directional_shadow_atlas_set_size(2048, true)
			_max_night_lights = 10
			_detail_range_scale = 1.0
			_fps_far_distance = 380.0
			builder.set_vegetation_density(1.0, true)

	_last_detail_scale = -1.0
	_light_timer = 999.0

func update_adaptive_quality(delta: float, started: bool, paused: bool, modal_open: bool, vp: Viewport, env: Environment, sun_light: DirectionalLight3D, builder, is_compat: bool) -> void:
	if not started or paused or modal_open or _bg_hidden:
		return
	# Reject frame spikes caused by browser tab switches or window resizing
	if delta > 0.25:
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
				apply_quality("medium", vp, env, sun_light, builder, is_compat)
				_auto_cooldown = 6.0
			elif resolved_quality == "medium":
				apply_quality("low", vp, env, sun_light, builder, is_compat)
				_auto_cooldown = 6.0
			_low_perf_accum = 0.0
	elif ft_ema_ms < 12.5:
		_high_perf_accum += delta
		_low_perf_accum = 0.0
		if _high_perf_accum >= 4.0 and _auto_cooldown <= 0.0:
			if resolved_quality == "low":
				apply_quality("medium", vp, env, sun_light, builder, is_compat)
				_auto_cooldown = 10.0
			elif resolved_quality == "medium":
				apply_quality("high", vp, env, sun_light, builder, is_compat)
				_auto_cooldown = 10.0
			_high_perf_accum = 0.0
	else:
		_low_perf_accum = maxf(0.0, _low_perf_accum - delta * 0.5)
		_high_perf_accum = maxf(0.0, _high_perf_accum - delta * 0.5)

func update_runtime_systems(delta: float, vp: Viewport, builder, is_night: bool, player) -> void:
	if vp == null or builder == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	var cam_pos := cam.global_position
	var is_aerial: bool = (cam_pos.y > 14.0) or (player != null and bool(player.is_drone))

	# 1. Detail visibility range & FPS camera far clip
	if not is_equal_approx(_detail_range_scale, _last_detail_scale) or is_aerial != _last_detail_aerial:
		_last_detail_scale = _detail_range_scale
		_last_detail_aerial = is_aerial
		var mult := _detail_range_scale * (1.85 if is_aerial else 1.0)
		builder.apply_detail_range_scale(mult)
		if player != null and player.fps_cam != null:
			player.fps_cam.far = _fps_far_distance

	# 1b. Interior sector proximity culling (active both day and night, throttled)
	_interior_timer += delta
	var int_moved_sq := cam_pos.distance_squared_to(_last_interior_cam_pos)
	if _interior_timer >= 0.25 or int_moved_sq > 6.25 or is_aerial != _last_interior_aerial:
		_interior_timer = 0.0
		_last_interior_cam_pos = cam_pos
		_last_interior_aerial = is_aerial
		if builder.has_method("update_interior_visibility"):
			builder.update_interior_visibility(cam_pos, is_aerial)

	# 2. Snap night_factor when external tools (e.g. capture.gd) toggle is_night without tweening
	if not _night_tween_active and is_night != _last_is_night:
		_last_is_night = is_night
		night_factor = 1.0 if is_night else 0.0
		_light_timer = 999.0

	# 3. Dynamic Night Light Culler (bounds active OmniLight3Ds to top N nearest to camera/focus)
	var lights_active := is_night or night_factor > 0.001
	if not lights_active:
		if _last_is_night or _night_tween_active:
			for l in builder.night_lights:
				if is_instance_valid(l) and l.visible:
					l.light_energy = 0.0
					l.visible = false
			_last_is_night = false
		return

	_light_timer += delta
	var moved_sq := cam_pos.distance_squared_to(_last_light_cam_pos)
	if _night_tween_active or _light_timer >= 0.16 or moved_sq > 9.0 or is_aerial != _last_aerial:
		_light_timer = 0.0
		_last_light_cam_pos = cam_pos
		_last_aerial = is_aerial
		_cull_night_lights(builder.night_lights, cam_pos, is_aerial)

func _cull_night_lights(lights: Array[OmniLight3D], cam_pos: Vector3, is_aerial: bool) -> void:
	var n := lights.size()
	if n == 0:
		return
	var focus := Vector3(cam_pos.x, 2.0, cam_pos.z - 28.0) if cam_pos.y > 40.0 else cam_pos
	var max_dist_sq := 140.0 * 140.0 if not is_aerial else 360.0 * 360.0
	var scored: Array[Dictionary] = []
	for i in range(n):
		var l := lights[i]
		if not is_instance_valid(l):
			continue
		var d_sq := l.global_position.distance_squared_to(focus)
		# Give landmark floodlights slight priority in aerial views so courts, plaza, and pond remain lit
		var weight := 0.55 if (cam_pos.y > 40.0 and bool(l.get_meta("is_floodlight", false))) else 1.0
		scored.append({"idx": i, "score": d_sq * weight, "d_sq": d_sq})

	scored.sort_custom(func(a, b): return float(a["score"]) < float(b["score"]))
	var cap := _max_night_lights
	var target_e := 6.5 * night_factor
	var use_fade := cam_pos.y <= 25.0
	for rank in range(scored.size()):
		var item := scored[rank]
		var l := lights[int(item["idx"])]
		var enable := rank < cap and float(item["d_sq"]) <= max_dist_sq and target_e > 0.01
		if enable:
			if l.distance_fade_enabled != use_fade:
				l.distance_fade_enabled = use_fade
			if not l.visible:
				l.visible = true
			l.light_energy = target_e
		else:
			if l.visible:
				l.light_energy = 0.0
				l.visible = false

func update_idle_throttle(started: bool, paused: bool, modal_open: bool, vp_rid: RID) -> void:
	var state := 0
	if _bg_hidden:
		state = 3
	elif not started:
		state = 1
	elif paused or modal_open:
		state = 2
	if state == _last_throttle_state:
		return
	_last_throttle_state = state
	var want_active := true
	match state:
		3:
			want_active = false
			Engine.max_fps = 5
		1:
			if OS.has_feature("web"):
				want_active = false
			Engine.max_fps = 20
		2:
			want_active = true
			Engine.max_fps = 24
		_:
			want_active = true
			Engine.max_fps = 0
	if want_active != _vp_active:
		_vp_active = want_active
		RenderingServer.viewport_set_active(vp_rid, want_active)
