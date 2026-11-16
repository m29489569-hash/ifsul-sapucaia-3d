extends SceneTree

func _init() -> void:
	call_deferred("_run_qa")

func _run_qa() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	assert(packed != null, "Falha ao carregar res://scenes/main.tscn")
	var main := packed.instantiate()
	root.add_child(main)

	await process_frame
	await physics_frame
	await physics_frame

	# 1. Verify world & MultiMeshes & Buildings
	var world := main.get_node("World") as Node3D
	var bldgs := world.get_node("Buildings")
	var props := world.get_node("PropsMultiMesh")
	assert(bldgs.get_child_count() == 16, "Esperado 16 edificios, obtido %d" % bldgs.get_child_count())
	var mm_count := 0
	for ch in props.get_children():
		if ch is MultiMeshInstance3D:
			mm_count += 1
	assert(mm_count >= 6, "Esperado >= 6 MultiMeshInstance3D, obtido %d" % mm_count)

	# 2. Verify spawn has zero collision overlap & stands on floor
	var player := main.get_node("Player") as CharacterBody3D
	player.move_and_slide()
	assert(player.global_position.y >= 0.0, "Player caiu abaixo do terreno")
	var space: PhysicsDirectSpaceState3D = (main as Node3D).get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.70
	q.shape = cap
	q.transform = Transform3D(Basis(), player.global_position + Vector3(0, 0.92, 0))
	q.collision_mask = 1
	var hits: Array[Dictionary] = space.intersect_shape(q, 4)
	for h in hits:
		assert(h["collider"].name == "GroundBody", "Spawn colidindo com %s" % h["collider"].name)

	# 3. Verify all 6 POIs reachable on foot (no solid collider inside POI body) and complete tour + reset
	assert(main.builder.poi_nodes.size() == 6, "Esperado 6 POIs")
	main._start_exploration()
	for poi_area in main.builder.poi_nodes:
		var ppos: Vector3 = poi_area.global_position
		q.transform = Transform3D(Basis(), ppos + Vector3(0, 1.0, 0))
		var phits: Array[Dictionary] = space.intersect_shape(q, 4)
		for h in phits:
			assert(h["collider"].name == "GroundBody", "POI %s obstruido por %s" % [poi_area.name, h["collider"].name])
		var pdata: Dictionary = poi_area.get_meta("poi_data")
		assert(String(pdata.get("description", "")).length() > 40, "Descricao vazia no POI %s" % poi_area.name)
		main._on_poi_interacted(pdata)
		main.hud.poi_panel.visible = false
		main._on_poi_modal_closed()

	assert(main.visited_pois.size() == 6, "Tour deveria estar em 6/6")
	assert(main.hud.complete_panel.visible, "Modal de conclusao deveria aparecer em 6/6")
	assert(main.hud.tour_lbl.text == "Tour do Campus 6/6", "Texto HUD inesperado: %s" % main.hud.tour_lbl.text)

	# 4. Restart tour
	main._restart_tour()
	assert(main.visited_pois.size() == 0, "Restart nao zerou POIs")
	assert(main.hud.tour_lbl.text == "Tour do Campus 0/6", "Restart nao atualizou HUD")

	# 5. Drone, Day/Night, Mute, Pause, Resize
	var d1: bool = player.toggle_drone_mode()
	assert(d1 and player.drone_cam.current, "Drone nao ativou")
	var d2: bool = player.toggle_drone_mode()
	assert((not d2) and player.fps_cam.current, "FPS nao retornou")

	main.toggle_day_night()
	assert(main.is_night, "Ciclo noite falhou")
	main.toggle_day_night()
	assert(not main.is_night, "Ciclo dia falhou")

	main.toggle_mute()
	assert(main.is_muted and main.hud.mute_btn.text.contains("MUDO"), "Mudo falhou")
	main.toggle_mute()
	assert((not main.is_muted) and main.hud.mute_btn.text.contains("ON"), "Desmutar falhou")

	main._toggle_pause()
	assert(main.paused and main.hud.pause_panel.visible, "Pause falhou")
	main._resume_game()
	assert((not main.paused) and (not main.hud.pause_panel.visible), "Retomar falhou")

	root.size = Vector2i(1600, 900)
	await process_frame
	assert(main.hud.minimap.size.x > 100.0, "Minimapa invalido apos resize")

	print("QA_PASS: 16 edificios, MultiMesh ok, 6 POIs acessiveis, tour 6/6 + reinicio, drone/dia-noite/mudo/pause/resize OK")
	quit(0)
