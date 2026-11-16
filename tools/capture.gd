extends SceneTree

func _init() -> void:
	call_deferred("_run_capture")

func _parse_iter_arg() -> String:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--iter" and i + 1 < args.size():
			return args[i + 1]
	return "iter-00"

func _apply_time_instant(main: Node3D, is_night: bool) -> void:
	main.is_night = is_night
	main.hud.set_day_night(is_night)
	if is_night:
		main.sun_light.rotation_degrees.x = -15.0
		main.sun_light.light_energy = 0.18
		main.sun_light.light_color = Color("#7094D4")
		main.sky_mat.sky_top_color = Color("#090D1A")
		main.sky_mat.sky_horizon_color = Color("#1A243B")
		main.world_env.environment.ambient_light_energy = 0.24
		main.world_env.environment.fog_light_color = Color("#141D2E")
		if main.builder.lamp_mat:
			main.builder.lamp_mat.emission_energy_multiplier = 3.5
		for l in main.builder.night_lights:
			l.light_energy = 3.2
	else:
		main.sun_light.rotation_degrees.x = -48.0
		main.sun_light.light_energy = 1.35
		main.sun_light.light_color = Color("#FFF8EB")
		main.sky_mat.sky_top_color = Color("#3B82C4")
		main.sky_mat.sky_horizon_color = Color("#A8D2F0")
		main.world_env.environment.ambient_light_energy = 0.45
		main.world_env.environment.fog_light_color = Color("#C8DCEB")
		if main.builder.lamp_mat:
			main.builder.lamp_mat.emission_energy_multiplier = 0.0
		for l in main.builder.night_lights:
			l.light_energy = 0.0

func _run_capture() -> void:
	var iter_name := _parse_iter_arg()
	var out_dir := ProjectSettings.globalize_path("res://shots/" + iter_name)
	DirAccess.make_dir_recursive_absolute(out_dir)

	var packed := load("res://scenes/main.tscn") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)

	for _i in range(4):
		await process_frame

	main._start_exploration()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main.hud.fade_rect.color.a = 0.0

	var cap_cam := Camera3D.new()
	cap_cam.far = 650.0
	main.add_child(cap_cam)

	var shots_txt := FileAccess.get_file_as_string("res://data/shots.json")
	var shots_cfg: Dictionary = JSON.parse_string(shots_txt)
	var shots: Array = shots_cfg.get("shots", [])
	var shot_metrics: Array = []
	var total_ms := 0.0

	for s in shots:
		var sid := String(s["id"])
		var is_night := bool(s.get("night", false))
		_apply_time_instant(main, is_night)
		main.hud.visible = bool(s.get("hud", false))

		if sid == "01_spawn_hud":
			main.player.fps_cam.current = true
			cap_cam.current = false
		else:
			var p: Array = s["pos"]
			var la: Array = s["look_at"]
			cap_cam.fov = float(s.get("fov", 60.0))
			cap_cam.look_at_from_position(
				Vector3(float(p[0]), float(p[1]), float(p[2])),
				Vector3(float(la[0]), float(la[1]), float(la[2])),
				Vector3.UP
			)
			cap_cam.current = true

		var t0 := Time.get_ticks_usec()
		for _f in range(10):
			await process_frame
		await RenderingServer.frame_post_draw
		var t1 := Time.get_ticks_usec()
		var avg_shot_ms := float(t1 - t0) / 10000.0
		total_ms += avg_shot_ms
		shot_metrics.append({"id": sid, "avg_frametime_ms": snappedf(avg_shot_ms, 0.01)})

		var img := root.get_texture().get_image()
		if img != null and not img.is_empty():
			img.save_png(out_dir.path_join(sid + ".png"))

	var meta := {
		"iter": iter_name,
		"render_method": "native_forward_plus",
		"resolution": "1280x720",
		"fixed_fps": 60,
		"avg_frametime_ms": snappedf(total_ms / maxf(1.0, float(shots.size())), 0.01),
		"shots": shot_metrics
	}
	var mf := FileAccess.open(out_dir.path_join("meta.json"), FileAccess.WRITE)
	mf.store_string(JSON.stringify(meta, "  "))
	mf.close()
	print("CAPTURE_DONE:", iter_name, " avg_ms=", meta["avg_frametime_ms"])
	quit(0)
