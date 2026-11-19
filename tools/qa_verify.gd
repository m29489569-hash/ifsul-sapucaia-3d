extends SceneTree

func _init() -> void:
	call_deferred("_run_qa")

func _has_match_code(results: Array[Dictionary], expected_code: String) -> bool:
	for r in results:
		if String(r.get("code", "")).to_upper() == expected_code.to_upper():
			return true
	return false

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
	cap.radius = 0.28
	cap.height = 1.70
	q.shape = cap
	q.transform = Transform3D(Basis(), player.global_position + Vector3(0, 0.92, 0))
	q.collision_mask = 1
	var hits: Array[Dictionary] = space.intersect_shape(q, 4)
	for h in hits:
		assert(h["collider"].name == "GroundBody", "Spawn colidindo com %s" % h["collider"].name)

	# 3. Verify all 8 POIs reachable on foot (no solid collider inside POI body) and complete tour + reset
	assert(main.builder.poi_nodes.size() == 8, "Esperado 8 POIs, obtido %d" % main.builder.poi_nodes.size())
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

	assert(main.visited_pois.size() == 8, "Tour deveria estar em 8/8, obtido %d" % main.visited_pois.size())
	assert(main.hud.complete_panel.visible, "Modal de conclusao deveria aparecer em 8/8")
	assert(main.hud.tour_lbl.text == "Tour do Campus 8/8", "Texto HUD inesperado: %s" % main.hud.tour_lbl.text)
	assert(main.hud.complete_title_lbl.text.contains("8/8"), "Titulo de conclusao deveria conter 8/8: %s" % main.hud.complete_title_lbl.text)

	# 4. Restart tour
	main._restart_tour()
	assert(main.visited_pois.size() == 0, "Restart nao zerou POIs")
	assert(main.hud.tour_lbl.text == "Tour do Campus 0/8", "Restart nao atualizou HUD: %s" % main.hud.tour_lbl.text)

	# 5. Walkable interiors: zero solid collider overlap + find_room_at() accuracy
	var interior_samples: Array[Dictionary] = [
		{"label": "Recepcao", "pos": Vector3(-13.4, 0.0, -3.5), "sector": "200", "code": "REC"},
		{"label": "Setor 100 corridor", "pos": Vector3(-46.2, 0.0, -13.5), "sector": "100", "code": ""},
		{"label": "Setor 200 corridor", "pos": Vector3(-4.0, 0.0, -20.9), "sector": "200", "code": ""},
		{"label": "CORAC", "pos": Vector3(-8.81, 0.0, -14.43), "sector": "200", "code": "203"},
		{"label": "Antiga Sala 1", "pos": Vector3(-3.38, 0.0, -14.72), "sector": "200", "code": "205"},
		{"label": "Cantina", "pos": Vector3(34.37, 0.0, 24.2), "sector": "230", "code": "CANT"},
		{"label": "Auditorio 504", "pos": Vector3(-7.5, 0.0, 26.8), "sector": "500", "code": "504"},
		{"label": "Bloco 800 / 807", "pos": Vector3(33.8, 0.0, -82.4), "sector": "800", "code": "807"},
		{"label": "Biblioteca Sul B15", "pos": Vector3(-19.1, 0.0, 122.0), "sector": "biblioteca", "code": "BIB"},
		{"label": "Setor 300 Plasticos", "pos": Vector3(30.5, 0.0, -29.88), "sector": "300", "code": "301"},
		{"label": "Setor 400 Mecanica", "pos": Vector3(61.29, 0.0, 43.91), "sector": "400", "code": "400"}
	]
	for sample in interior_samples:
		var spos: Vector3 = sample["pos"]
		q.transform = Transform3D(Basis(), spos + Vector3(0, 1.0, 0))
		var ihits: Array[Dictionary] = space.intersect_shape(q, 6)
		for h in ihits:
			assert(h["collider"].name == "GroundBody", "Interior %s (%s) obstruido por %s" % [sample["label"], str(spos), h["collider"].name])
		var found: Dictionary = main.builder.find_room_at(spos)
		assert(not found.is_empty(), "find_room_at() retornou vazio em %s (%s)" % [sample["label"], str(spos)])
		assert(String(found.get("sector", "")) == String(sample["sector"]), "Setor inesperado em %s: esperado %s, obtido %s" % [sample["label"], sample["sector"], String(found.get("sector", ""))])
		var expected_code := String(sample["code"])
		if not expected_code.is_empty():
			assert(String(found.get("code", "")) == expected_code, "Codigo inesperado em %s: esperado %s, obtido %s" % [sample["label"], expected_code, String(found.get("code", ""))])

	var outdoor_room: Dictionary = main.builder.find_room_at(Vector3(-55.0, 0.0, 12.0))
	assert(outdoor_room.is_empty(), "find_room_at() deveria retornar vazio no spawn externo, obteve %s" % str(outdoor_room))

	# 6. Verify search_rooms() queries (aliases, codes, accents, sectors)
	var m_antiga: Array[Dictionary] = main.builder.search_rooms("Antiga Sala 1")
	assert(not m_antiga.is_empty() and _has_match_code(m_antiga, "205"), "search_rooms('Antiga Sala 1') falhou: %s" % str(m_antiga))
	var m_807: Array[Dictionary] = main.builder.search_rooms("807")
	assert(not m_807.is_empty() and _has_match_code(m_807, "807"), "search_rooms('807') falhou: %s" % str(m_807))
	var m_corac: Array[Dictionary] = main.builder.search_rooms("CORAC")
	assert(not m_corac.is_empty() and _has_match_code(m_corac, "203"), "search_rooms('CORAC') falhou: %s" % str(m_corac))
	var m_bib: Array[Dictionary] = main.builder.search_rooms("Biblioteca")
	assert(not m_bib.is_empty() and _has_match_code(m_bib, "BIB"), "search_rooms('Biblioteca') falhou: %s" % str(m_bib))

	# 7. Drone, Roof-Cut X-ray, Day/Night, Mute, Pause, Resize
	var d1: bool = player.toggle_drone_mode()
	assert(d1 and player.drone_cam.current, "Drone nao ativou")

	assert(main.builder.roof_nodes.size() > 0, "roof_nodes deveria conter os tetos dos blocos navegaveis")
	main.set_roofs_visible(false)
	assert(not main.builder.roofs_visible and not main.roofs_visible, "set_roofs_visible(false) falhou")
	for rn in main.builder.roof_nodes:
		if is_instance_valid(rn):
			assert(not rn.visible, "Roof node %s deveria estar oculto" % rn.name)
	main.set_roofs_visible(true)
	assert(main.builder.roofs_visible and main.roofs_visible, "set_roofs_visible(true) falhou")
	for rn in main.builder.roof_nodes:
		if is_instance_valid(rn):
			assert(rn.visible, "Roof node %s deveria estar visivel" % rn.name)

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

	# 8. Verify optimization systems (batches, merged roads, occluders, light culling, quality scaling, minimap static layer)
	var streets := world.get_node("Streets")
	assert(streets.get_node_or_null("MergedSidewalks") != null, "MergedSidewalks ausente")
	assert(streets.get_node_or_null("MergedAsphalt") != null, "MergedAsphalt ausente")
	assert(streets.get_node_or_null("MergedFootways") != null, "MergedFootways ausente")
	assert(world.get_node_or_null("StaticBatches") != null, "StaticBatches ausente")
	assert(world.get_node_or_null("Interiors") != null, "Interiors node ausente")
	assert(main.builder.detail_nodes.size() > 0, "detail_nodes vazio")
	assert(root.use_occlusion_culling, "Occlusion culling deve estar ativo")
	assert(root.positional_shadow_atlas_size == 0, "Positional shadow atlas deve ser 0")
	assert(main.hud.minimap._static_layer != null, "Minimapa deve ter camada estatica separada")

	var occ_count := 0
	for bnode in bldgs.get_children():
		for sub in bnode.get_children():
			if sub is StaticBody3D:
				for gc in sub.get_children():
					if gc is OccluderInstance3D:
						occ_count += 1
	assert(occ_count >= 1, "Esperado >= 1 OccluderInstance3D nos edificios solidos (guarita), obtido %d" % occ_count)

	# Verify quality tiers & night light culler budget
	main.set_quality_mode("low")
	main.is_night = true
	main.perf.notify_night_tween_finished(true)
	main.perf.update_runtime_systems(0.5, root, main.builder, true, player)
	var low_lights := 0
	for l in main.builder.night_lights:
		if l.visible:
			low_lights += 1
	assert(low_lights <= 2, "Low quality deve limitar luzes noturnas a <= 2, obteve %d" % low_lights)

	main.set_quality_mode("medium")
	main.perf.update_runtime_systems(0.5, root, main.builder, true, player)
	var med_lights := 0
	for l in main.builder.night_lights:
		if l.visible:
			med_lights += 1
	assert(med_lights <= 6, "Medium quality deve limitar luzes noturnas a <= 6, obteve %d" % med_lights)

	main.set_quality_mode("high")
	main.perf.update_runtime_systems(0.5, root, main.builder, true, player)
	var hi_lights := 0
	for l in main.builder.night_lights:
		if l.visible:
			hi_lights += 1
	assert(hi_lights <= 10, "High quality deve limitar luzes noturnas a <= 10, obteve %d" % hi_lights)
	main.is_night = false
	main.perf.notify_night_tween_finished(false)
	main.perf.update_runtime_systems(0.5, root, main.builder, false, player)

	# Verify spike rejection on adaptive quality
	main.set_quality_mode("auto")
	var pre_q: String = main.perf.resolved_quality
	main.perf.update_adaptive_quality(2.5, true, false, false, root, main.world_env.environment, main.sun_light, main.builder, main.is_compat)
	assert(main.perf.resolved_quality == pre_q, "Delta spike de tab switch nao deve rebaixar qualidade")

	print("QA_PASS: 16 edificios, MultiMesh ok, 8 POIs acessiveis, tour 8/8 + reinicio, 11 interiores livres + find_room_at/search_rooms, roof-cut, drone/dia-noite/mudo/pause/resize + otimizacoes OK (occ=%d, roofs=%d)" % [occ_count, main.builder.roof_nodes.size()])
	quit(0)
