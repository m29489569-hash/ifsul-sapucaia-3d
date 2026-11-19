extends CanvasLayer

const MinimapView = preload("res://scripts/minimap.gd")
const MaterialsLib = preload("res://scripts/materials.gd")

signal start_clicked
signal resume_clicked
signal restart_tour_clicked
signal free_explore_clicked
signal mute_clicked
signal day_night_clicked
signal poi_closed
signal room_search_selected(room: Dictionary)
signal room_search_drone_requested(room: Dictionary)
signal room_search_cleared
signal search_opened
signal search_closed
signal map_toggle_requested

var minimap: CampusMinimap
var expanded_minimap: CampusMinimap
var start_panel: Control
var pause_panel: Control
var poi_panel: PanelContainer
var complete_panel: PanelContainer
var complete_title_lbl: Label
var search_overlay: Control
var search_panel: PanelContainer
var search_input: LineEdit
var search_count_lbl: Label
var search_list: VBoxContainer
var clear_target_btn: Button
var map_overlay: Control
var map_panel: PanelContainer
var map_body: HBoxContainer
var map_legend_box: PanelContainer
var map_legend_list: VBoxContainer
var map_target_box: VBoxContainer
var map_target_lbl: Label
var map_clear_btn: Button

var top_bar: HBoxContainer
var left_flow: HFlowContainer
var brand_lbl: Label
var logo_rect: TextureRect
var room_box: PanelContainer
var room_lbl: Label
var hint_box: PanelContainer
var hint_lbl: Label
var prompt_lbl: Label
var tour_lbl: Label
var mode_lbl: Label
var search_btn: Button
var time_btn: Button
var mute_btn: Button
var fade_rect: ColorRect
var fade_tween: Tween
var poi_title: Label
var poi_sub: Label
var poi_desc: RichTextLabel
var total_pois := 8
var _modal_specs: Array[Dictionary] = []
var _interiors_data: Dictionary = {}
var _search_provider: Callable = Callable()
var _last_search_results: Array[Dictionary] = []
var _has_target_room := false

func _ready() -> void:
	_build_ui()
	if get_viewport():
		get_viewport().size_changed.connect(_on_viewport_resized)
	call_deferred("_on_viewport_resized")

func _build_ui() -> void:
	# Subtle edge vignette
	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.color = Color(0, 0, 0, 0.10)
	add_child(vig)

	# Crosshair
	var cross := ColorRect.new()
	cross.size = Vector2(5, 5)
	cross.color = Color(1, 1, 1, 0.72)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.offset_left = -2.5; cross.offset_top = -2.5
	cross.offset_right = 2.5; cross.offset_bottom = 2.5
	add_child(cross)

	# Top HUD bar (left wraps cleanly via HFlowContainer; right stays anchored for [G] Salas + [N] Dia + web chips)
	top_bar = HBoxContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 16; top_bar.offset_top = 14
	top_bar.offset_right = -16; top_bar.offset_bottom = 54
	top_bar.add_theme_constant_override("separation", 10)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_bar)

	left_flow = HFlowContainer.new()
	left_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_flow.add_theme_constant_override("h_separation", 8)
	left_flow.add_theme_constant_override("v_separation", 6)
	left_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(left_flow)

	var brand_box := _make_pill_panel(Color(0.08, 0.14, 0.10, 0.90), Color("#2F9E41"))
	var brand_row := HBoxContainer.new()
	brand_row.add_theme_constant_override("separation", 8)
	logo_rect = TextureRect.new()
	logo_rect.texture = MaterialsLib.create_ifsul_logo_texture(64)
	logo_rect.custom_minimum_size = Vector2(22, 22)
	logo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand_row.add_child(logo_rect)
	brand_lbl = Label.new()
	brand_lbl.text = "IFSul • Sapucaia do Sul"
	brand_lbl.add_theme_font_size_override("font_size", 15)
	brand_row.add_child(brand_lbl)
	brand_box.add_child(brand_row)
	left_flow.add_child(brand_box)

	var tour_box := _make_pill_panel(Color(0.08, 0.14, 0.10, 0.88), Color("#2F9E41"))
	tour_lbl = Label.new()
	tour_lbl.text = "Tour do Campus 0/%d" % total_pois
	tour_lbl.add_theme_font_size_override("font_size", 15)
	tour_box.add_child(tour_lbl)
	left_flow.add_child(tour_box)

	var mode_box := _make_pill_panel(Color(0.09, 0.12, 0.15, 0.85), Color("#64748B"))
	mode_lbl = Label.new()
	mode_lbl.text = "[F] Modo: A pé"
	mode_lbl.add_theme_font_size_override("font_size", 14)
	mode_box.add_child(mode_lbl)
	left_flow.add_child(mode_box)

	room_box = _make_pill_panel(Color(0.06, 0.13, 0.16, 0.92), Color("#38BDF8"))
	room_lbl = Label.new()
	room_lbl.text = ""
	room_lbl.add_theme_font_size_override("font_size", 14)
	room_lbl.modulate = Color("#E0F2FE")
	room_box.add_child(room_lbl)
	room_box.visible = false
	left_flow.add_child(room_box)

	var right_actions := HBoxContainer.new()
	right_actions.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	right_actions.add_theme_constant_override("separation", 8)
	top_bar.add_child(right_actions)

	search_btn = Button.new()
	search_btn.text = "[G] Salas"
	search_btn.focus_mode = Control.FOCUS_NONE
	_style_hud_button(search_btn, Color("#38BDF8"))
	search_btn.pressed.connect(func():
		if not is_any_modal_open():
			open_room_search()
	)
	right_actions.add_child(search_btn)

	time_btn = Button.new()
	time_btn.text = "[N] Dia"
	time_btn.focus_mode = Control.FOCUS_NONE
	_style_hud_button(time_btn, Color("#2F9E41"))
	time_btn.pressed.connect(func(): day_night_clicked.emit())
	right_actions.add_child(time_btn)

	mute_btn = Button.new()
	mute_btn.text = "[M] Som: ON"
	mute_btn.focus_mode = Control.FOCUS_NONE
	_style_hud_button(mute_btn, Color("#2F9E41"))
	mute_btn.pressed.connect(func(): mute_clicked.emit())
	if OS.has_feature("web"):
		mute_btn.visible = false
	right_actions.add_child(mute_btn)

	# Bottom controls hint pill
	hint_box = _make_pill_panel(Color(0.06, 0.10, 0.08, 0.86), Color(0.18, 0.50, 0.28, 0.85))
	hint_box.anchor_left = 0.0; hint_box.anchor_right = 0.0
	hint_box.anchor_top = 1.0; hint_box.anchor_bottom = 1.0
	hint_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_box.offset_left = 16; hint_box.offset_bottom = -16; hint_box.offset_top = -16
	hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_lbl = Label.new()
	hint_lbl.text = "WASD Mover | E Interagir | G Buscar Sala | Tab Mapa | F Drone (T Teto) | N Dia/Noite | Esc Pausa"
	hint_lbl.add_theme_font_size_override("font_size", 12)
	hint_lbl.modulate = Color(0.95, 0.98, 0.95, 0.95)
	hint_box.add_child(hint_lbl)
	add_child(hint_box)

	# Minimap (bottom right)
	minimap = MinimapView.new()
	minimap.clip_contents = true
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap.offset_left = -210; minimap.offset_top = -270
	minimap.offset_right = -16; minimap.offset_bottom = -16
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(minimap)

	# Interact prompt
	prompt_lbl = Label.new()
	prompt_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_lbl.offset_left = -260; prompt_lbl.offset_right = 260
	prompt_lbl.offset_top = -120; prompt_lbl.offset_bottom = -84
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_lbl.add_theme_font_size_override("font_size", 18)
	prompt_lbl.modulate = Color("#FFFBE6")
	prompt_lbl.visible = false
	add_child(prompt_lbl)

	# POI Info Card Modal
	poi_panel = _make_modal_panel(560, 320, Color("#2F9E41"))
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	poi_panel.add_child(pv)
	poi_title = Label.new()
	poi_title.add_theme_font_size_override("font_size", 21)
	poi_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(poi_title)
	poi_sub = Label.new()
	poi_sub.add_theme_font_size_override("font_size", 14)
	poi_sub.modulate = Color("#86EFAC")
	poi_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(poi_sub)
	poi_desc = RichTextLabel.new()
	poi_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	poi_desc.fit_content = false
	pv.add_child(poi_desc)
	var pbtn := Button.new()
	pbtn.text = "Continuar Exploração [E / Esc]"
	pbtn.pressed.connect(func():
		poi_panel.visible = false
		poi_closed.emit()
	)
	pv.add_child(pbtn)
	poi_panel.visible = false
	add_child(poi_panel)

	# Tour Complete Modal
	complete_panel = _make_modal_panel(480, 250, Color("#2F9E41"))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 12)
	complete_panel.add_child(cv)
	complete_title_lbl = Label.new()
	complete_title_lbl.text = "Tour do Câmpus Concluído! (%d/%d)" % [total_pois, total_pois]
	complete_title_lbl.add_theme_font_size_override("font_size", 22)
	complete_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(complete_title_lbl)
	var cd := Label.new()
	cd.text = "Você explorou todos os pontos históricos, acadêmicos, laboratoriais e esportivos do IFSul — Câmpus Sapucaia do Sul."
	cd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(cd)
	var ch := HBoxContainer.new()
	ch.alignment = BoxContainer.ALIGNMENT_CENTER
	ch.add_theme_constant_override("separation", 14)
	var btn_free := Button.new()
	btn_free.text = "Explorar livremente"
	btn_free.pressed.connect(func():
		complete_panel.visible = false
		free_explore_clicked.emit()
	)
	var btn_rst := Button.new()
	btn_rst.text = "Reiniciar tour"
	btn_rst.pressed.connect(func():
		complete_panel.visible = false
		restart_tour_clicked.emit()
	)
	ch.add_child(btn_free); ch.add_child(btn_rst)
	cv.add_child(ch)
	complete_panel.visible = false
	add_child(complete_panel)

	# Room Search Modal ([G])
	_build_room_search_modal()

	# Expanded Map Overlay ([Tab])
	_build_expanded_map_overlay()

	# Pause Overlay
	pause_panel = _make_backdrop_overlay()
	var pm := _make_modal_panel(360, 220, Color("#2F9E41"))
	pause_panel.add_child(pm)
	var pmv := VBoxContainer.new()
	pmv.add_theme_constant_override("separation", 12)
	pm.add_child(pmv)
	var pl := Label.new()
	pl.text = "Pausa"
	pl.add_theme_font_size_override("font_size", 24)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pmv.add_child(pl)
	var b_res := Button.new()
	b_res.text = "Retomar [Esc]"
	b_res.pressed.connect(func(): resume_clicked.emit())
	var b_rst2 := Button.new()
	b_rst2.text = "Reiniciar tour"
	b_rst2.pressed.connect(func(): restart_tour_clicked.emit())
	pmv.add_child(b_res); pmv.add_child(b_rst2)
	pause_panel.visible = false
	add_child(pause_panel)

	# Start Overlay
	start_panel = _make_backdrop_overlay()
	var sm := _make_modal_panel(560, 310, Color("#2F9E41"))
	start_panel.add_child(sm)
	var smv := VBoxContainer.new()
	smv.add_theme_constant_override("separation", 14)
	smv.alignment = BoxContainer.ALIGNMENT_CENTER
	sm.add_child(smv)
	var st_title := Label.new()
	st_title.text = "IFSul — Câmpus Sapucaia do Sul"
	st_title.add_theme_font_size_override("font_size", 26)
	st_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	smv.add_child(st_title)
	var st_sub := Label.new()
	st_sub.text = "Av. Copacabana, 100 • Piratini • Sapucaia do Sul (RS)\nExplore os blocos, salas internas, laboratórios, biblioteca e quadras em 3D."
	st_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	smv.add_child(st_sub)
	var b_start := Button.new()
	b_start.text = "Explorar"
	b_start.custom_minimum_size = Vector2(200, 44)
	b_start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b_start.pressed.connect(func(): start_clicked.emit())
	smv.add_child(b_start)
	add_child(start_panel)

	# Fade-in overlay
	fade_rect = ColorRect.new()
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.color = Color(0, 0, 0, 1.0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade_rect)

func _build_room_search_modal() -> void:
	search_overlay = _make_backdrop_overlay()
	search_panel = _make_modal_panel(640, 470, Color("#38BDF8"))
	search_overlay.add_child(search_panel)

	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 10)
	search_panel.add_child(sv)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Buscador de Salas e Ambientes"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	search_count_lbl = Label.new()
	search_count_lbl.text = ""
	search_count_lbl.add_theme_font_size_override("font_size", 13)
	search_count_lbl.modulate = Color("#94A3B8")
	header.add_child(search_count_lbl)
	sv.add_child(header)

	search_input = LineEdit.new()
	search_input.placeholder_text = "Buscar por código, nome ou apelido (ex: 223A, CORAC, 807, Antiga Sala 1)..."
	search_input.clear_button_enabled = true
	search_input.custom_minimum_size = Vector2(0, 36)
	search_input.text_changed.connect(_on_search_text_changed)
	search_input.text_submitted.connect(_on_search_submitted)
	sv.add_child(search_input)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(scroll)

	search_list = VBoxContainer.new()
	search_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_list.add_theme_constant_override("separation", 6)
	scroll.add_child(search_list)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	clear_target_btn = Button.new()
	clear_target_btn.text = "Limpar marcador"
	clear_target_btn.disabled = true
	clear_target_btn.pressed.connect(func():
		room_search_cleared.emit()
	)
	footer.add_child(clear_target_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var btn_close := Button.new()
	btn_close.text = "Fechar [Esc]"
	btn_close.pressed.connect(func(): close_room_search())
	footer.add_child(btn_close)
	sv.add_child(footer)

	search_overlay.visible = false
	add_child(search_overlay)

func _build_expanded_map_overlay() -> void:
	map_overlay = _make_backdrop_overlay()
	map_panel = _make_modal_panel(880, 600, Color("#2F9E41"))
	map_overlay.add_child(map_panel)

	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)
	map_panel.add_child(mv)

	var mheader := HBoxContainer.new()
	mheader.add_theme_constant_override("separation", 10)
	var mtitle := Label.new()
	mtitle.text = "Mapa das Salas — IFSul Câmpus Sapucaia do Sul"
	mtitle.add_theme_font_size_override("font_size", 19)
	mtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mheader.add_child(mtitle)

	var mclose := Button.new()
	mclose.text = "Fechar [Tab / Esc]"
	mclose.focus_mode = Control.FOCUS_NONE
	mclose.pressed.connect(func(): map_toggle_requested.emit())
	mheader.add_child(mclose)
	mv.add_child(mheader)

	map_body = HBoxContainer.new()
	map_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_body.add_theme_constant_override("separation", 12)
	mv.add_child(map_body)

	expanded_minimap = MinimapView.new()
	expanded_minimap.is_expanded = true
	expanded_minimap.clip_contents = true
	expanded_minimap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	expanded_minimap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	expanded_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_body.add_child(expanded_minimap)

	map_legend_box = _make_pill_panel(Color(0.06, 0.09, 0.08, 0.92), Color(0.20, 0.44, 0.28, 0.85))
	map_legend_box.custom_minimum_size = Vector2(210, 0)
	map_legend_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_body.add_child(map_legend_box)

	var lscroll := ScrollContainer.new()
	lscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	map_legend_box.add_child(lscroll)

	map_legend_list = VBoxContainer.new()
	map_legend_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_legend_list.add_theme_constant_override("separation", 7)
	lscroll.add_child(map_legend_list)

	map_target_box = VBoxContainer.new()
	map_target_box.add_theme_constant_override("separation", 6)
	map_target_lbl = Label.new()
	map_target_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_target_lbl.add_theme_font_size_override("font_size", 12)
	map_target_lbl.modulate = Color("#7DD3FC")
	map_target_box.add_child(map_target_lbl)
	map_clear_btn = Button.new()
	map_clear_btn.text = "Limpar marcador"
	map_clear_btn.focus_mode = Control.FOCUS_NONE
	map_clear_btn.pressed.connect(func(): room_search_cleared.emit())
	map_target_box.add_child(map_clear_btn)
	map_target_box.visible = false

	_rebuild_map_legend()

	map_overlay.visible = false
	add_child(map_overlay)

func _rebuild_map_legend() -> void:
	if map_legend_list == null:
		return
	for ch in map_legend_list.get_children():
		if ch != map_target_box:
			map_legend_list.remove_child(ch)
			ch.queue_free()
	if map_target_box.get_parent() == map_legend_list:
		map_legend_list.remove_child(map_target_box)

	var sec_hdr := Label.new()
	sec_hdr.text = "Legenda de Setores"
	sec_hdr.add_theme_font_size_override("font_size", 14)
	sec_hdr.modulate = Color("#86EFAC")
	map_legend_list.add_child(sec_hdr)

	var sectors: Dictionary = _interiors_data.get("sectors", {})
	var entries: Array[Dictionary] = []
	if not sectors.is_empty():
		var keys := sectors.keys()
		keys.sort()
		for k in keys:
			var info: Variant = sectors[k]
			if info is Dictionary:
				entries.append({
					"label": String(info.get("name", "Setor " + String(k))),
					"color": Color.from_string(String(info.get("color", "#6AA87B")), Color("#6AA87B"))
				})
	else:
		entries = [
			{"label": "Setor 100 — Admin/Saúde", "color": Color("#7FA8C9")},
			{"label": "Setor 200 — Ensino/Labs", "color": Color("#58B37B")},
			{"label": "Setor 300 — Plásticos/Quím.", "color": Color("#F0A84B")},
			{"label": "Setor 400 — Mecânica/CNC", "color": Color("#E8983C")},
			{"label": "Auditório 504", "color": Color("#F2DF2F")},
			{"label": "Bloco 800 (801–812)", "color": Color("#7AC790")},
			{"label": "Biblioteca", "color": Color("#1EC7C3")},
			{"label": "Sede Social", "color": Color("#72C850")},
			{"label": "Educação Física", "color": Color("#6EE09B")}
		]

	for e in entries:
		map_legend_list.add_child(_make_legend_row(e["color"], e["label"]))

	var sep := HSeparator.new()
	map_legend_list.add_child(sep)

	var mk_hdr := Label.new()
	mk_hdr.text = "Marcadores"
	mk_hdr.add_theme_font_size_override("font_size", 13)
	mk_hdr.modulate = Color("#CBD5E1")
	map_legend_list.add_child(mk_hdr)

	map_legend_list.add_child(_make_legend_row(Color("#CD191E"), "Você (a pé)"))
	map_legend_list.add_child(_make_legend_row(Color("#38BDF8"), "Drone / Sala marcada"))
	map_legend_list.add_child(_make_legend_row(Color("#F5C43D"), "Marco do Tour (POI)"))
	map_legend_list.add_child(_make_legend_row(Color("#2F9E41"), "Marco visitado"))

	var sep2 := HSeparator.new()
	map_legend_list.add_child(sep2)
	map_legend_list.add_child(map_target_box)

func _make_legend_row(col: Color, txt: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var sw := ColorRect.new()
	sw.color = col
	sw.custom_minimum_size = Vector2(13, 13)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sw)
	var lbl := Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	return row

func play_fade_in() -> void:
	fade_rect.color.a = 1.0
	if fade_tween:
		fade_tween.kill()
	fade_tween = create_tween()
	fade_tween.tween_property(fade_rect, "color:a", 0.0, 0.85)

func set_fade_alpha(a: float) -> void:
	if fade_tween:
		fade_tween.kill()
	if fade_rect:
		fade_rect.color.a = a

func setup_minimap(data: Dictionary, interiors: Dictionary = {}) -> void:
	_interiors_data = interiors
	total_pois = maxi(1, data.get("pois", []).size())
	minimap.setup(data, interiors)
	if expanded_minimap:
		expanded_minimap.setup(data, interiors)
	_rebuild_map_legend()
	set_tour_progress(0, total_pois)
	_sync_complete_title()

func set_room_search_provider(cb: Callable) -> void:
	_search_provider = cb

func _sync_complete_title() -> void:
	if complete_title_lbl:
		complete_title_lbl.text = "Tour do Câmpus Concluído! (%d/%d)" % [total_pois, total_pois]

func set_tour_progress(visited: int, total: int) -> void:
	total_pois = maxi(1, total)
	tour_lbl.text = "Tour do Campus %d/%d" % [visited, total_pois]
	_sync_complete_title()

func set_drone_mode(drone: bool, roofs_visible: bool = true) -> void:
	if drone:
		mode_lbl.text = "[F] Modo: Drone | [T] Teto: %s" % ("ON" if roofs_visible else "OFF")
	else:
		mode_lbl.text = "[F] Modo: A pé"

func set_day_night(is_night: bool) -> void:
	time_btn.text = "[N] Noite" if is_night else "[N] Dia"

func set_muted(muted: bool) -> void:
	mute_btn.text = "[M] Som: MUDO" if muted else "[M] Som: ON"

func set_current_room(room: Dictionary) -> void:
	if room_box == null or room_lbl == null:
		return
	if room.is_empty():
		room_box.visible = false
		return
	var sec := String(room.get("sector", ""))
	var sec_prefix := _sector_short_label(sec)
	var code := String(room.get("code", ""))
	var rname := String(room.get("name", ""))
	var room_desc := ""
	if not code.is_empty() and not rname.is_empty():
		room_desc = "%s %s" % [code, rname]
	elif not rname.is_empty():
		room_desc = rname
	else:
		room_desc = code
	if not sec_prefix.is_empty() and sec_prefix.to_lower() != room_desc.to_lower():
		room_lbl.text = "📍 %s • %s" % [sec_prefix, room_desc]
	else:
		room_lbl.text = "📍 %s" % room_desc

	var col_str := String(room.get("sector_color", ""))
	if col_str.is_empty():
		var sectors: Dictionary = _interiors_data.get("sectors", {})
		if sectors.has(sec) and sectors[sec] is Dictionary:
			col_str = String(sectors[sec].get("color", "#38BDF8"))
	var sb := room_box.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		sb.border_color = Color.from_string(col_str, Color("#38BDF8"))
	room_box.visible = true

func _sector_short_label(sec: String) -> String:
	match sec:
		"100", "200", "230", "300", "400":
			return "Setor " + sec
		"500":
			return "Auditório"
		"800":
			return "Bloco 800"
		"biblioteca":
			return "Biblioteca"
		"social":
			return "Sede Social"
		"esportes":
			return "Ed. Física"
		_:
			return sec

func set_target_room(pos: Vector3, label: String = "") -> void:
	_has_target_room = true
	if minimap:
		minimap.set_target_room(pos, label)
	if expanded_minimap:
		expanded_minimap.set_target_room(pos, label)
	if clear_target_btn:
		clear_target_btn.disabled = false
	if map_target_box and map_target_lbl:
		map_target_lbl.text = "Marcador ativo:\n%s" % label
		map_target_box.visible = true

func clear_target_room() -> void:
	_has_target_room = false
	if minimap:
		minimap.clear_target_room()
	if expanded_minimap:
		expanded_minimap.clear_target_room()
	if clear_target_btn:
		clear_target_btn.disabled = true
	if map_target_box:
		map_target_box.visible = false

func open_room_search() -> void:
	if map_overlay and map_overlay.visible:
		map_overlay.visible = false
	search_overlay.visible = true
	_refresh_search_results(search_input.text)
	search_input.grab_focus()
	search_input.select_all()
	search_opened.emit()

func close_room_search() -> void:
	if not search_overlay.visible:
		return
	search_overlay.visible = false
	search_input.release_focus()
	search_closed.emit()

func is_room_search_open() -> bool:
	return search_overlay != null and search_overlay.visible

func set_expanded_map_visible(v: bool) -> void:
	if v and search_overlay and search_overlay.visible:
		search_overlay.visible = false
		search_input.release_focus()
	map_overlay.visible = v
	if v and expanded_minimap:
		expanded_minimap.queue_redraw()

func is_expanded_map_open() -> bool:
	return map_overlay != null and map_overlay.visible

func _on_search_text_changed(new_text: String) -> void:
	_refresh_search_results(new_text)

func _on_search_submitted(_text: String) -> void:
	if not _last_search_results.is_empty():
		var first_room := _last_search_results[0]
		search_overlay.visible = false
		search_input.release_focus()
		room_search_selected.emit(first_room)

func _query_rooms(query: String) -> Array[Dictionary]:
	if _search_provider.is_valid():
		var res: Variant = _search_provider.call(query)
		if res is Array:
			var typed: Array[Dictionary] = []
			for item in res:
				if item is Dictionary:
					typed.append(item)
			return typed
	# Fallback accent-insensitive filter over _interiors_data.rooms
	var q := _norm_text(query.strip_edges())
	var out: Array[Dictionary] = []
	for r in _interiors_data.get("rooms", []):
		if not (r is Dictionary):
			continue
		if q.is_empty():
			out.append(r)
			continue
		var al_strs := PackedStringArray()
		for a in r.get("aliases", []):
			al_strs.append(String(a))
		var hay := _norm_text("%s %s %s %s" % [
			String(r.get("code", "")),
			String(r.get("name", "")),
			String(r.get("sector", "")),
			" ".join(al_strs)
		])
		if hay.contains(q):
			out.append(r)
	return out

func _norm_text(s: String) -> String:
	var out := s.to_lower()
	const REPL := {
		"á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a",
		"é": "e", "è": "e", "ê": "e", "ë": "e",
		"í": "i", "ì": "i", "î": "i", "ï": "i",
		"ó": "o", "ò": "o", "ô": "o", "õ": "o", "ö": "o",
		"ú": "u", "ù": "u", "û": "u", "ü": "u",
		"ç": "c"
	}
	for k in REPL.keys():
		out = out.replace(k, REPL[k])
	return out

func _refresh_search_results(query: String) -> void:
	if search_list == null:
		return
	for ch in search_list.get_children():
		ch.queue_free()

	_last_search_results = _query_rooms(query)
	var total := _last_search_results.size()
	var shown := mini(total, 45)
	if search_count_lbl:
		search_count_lbl.text = "%d resultado%s" % [total, "" if total == 1 else "s"]

	if total == 0:
		var empty_lbl := Label.new()
		empty_lbl.text = "Nenhuma sala encontrada para \"%s\"." % query
		empty_lbl.modulate = Color("#94A3B8")
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		search_list.add_child(empty_lbl)
		return

	var sectors: Dictionary = _interiors_data.get("sectors", {})
	for i in range(shown):
		var room := _last_search_results[i]
		search_list.add_child(_build_room_result_row(room, sectors))

	if total > shown:
		var more_lbl := Label.new()
		more_lbl.text = "... e mais %d salas. Digite para refinar a busca." % (total - shown)
		more_lbl.add_theme_font_size_override("font_size", 12)
		more_lbl.modulate = Color("#94A3B8")
		more_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		search_list.add_child(more_lbl)

func _build_room_result_row(room: Dictionary, sectors: Dictionary) -> PanelContainer:
	var sec := String(room.get("sector", ""))
	var sec_col := Color("#38BDF8")
	if room.has("sector_color"):
		sec_col = Color.from_string(String(room["sector_color"]), sec_col)
	elif sectors.has(sec) and sectors[sec] is Dictionary:
		sec_col = Color.from_string(String(sectors[sec].get("color", "#38BDF8")), sec_col)

	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.16, 0.14, 0.92)
	sb.border_color = Color(sec_col.r, sec_col.g, sec_col.b, 0.55)
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10; sb.content_margin_right = 8
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
	pc.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	pc.add_child(row)

	var code := String(room.get("code", ""))
	var rname := String(room.get("name", ""))
	var aliases: Array = room.get("aliases", [])
	var sec_tag := _sector_short_label(sec)
	var line := "[%s] " % sec_tag if not sec_tag.is_empty() else ""
	if not code.is_empty() and not rname.is_empty():
		line += "%s — %s" % [code, rname]
	else:
		line += rname if not rname.is_empty() else code
	if not aliases.is_empty():
		var al_strs := PackedStringArray()
		for a in aliases:
			al_strs.append(String(a))
		line += " (%s)" % ", ".join(al_strs)

	var main_btn := Button.new()
	main_btn.text = line
	main_btn.flat = true
	main_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	main_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_btn.clip_text = true
	main_btn.add_theme_font_size_override("font_size", 13)
	main_btn.pressed.connect(func():
		search_overlay.visible = false
		search_input.release_focus()
		room_search_selected.emit(room)
	)
	row.add_child(main_btn)

	var loc_btn := Button.new()
	loc_btn.text = "Localizar"
	loc_btn.add_theme_font_size_override("font_size", 12)
	loc_btn.pressed.connect(func():
		search_overlay.visible = false
		search_input.release_focus()
		room_search_selected.emit(room)
	)
	row.add_child(loc_btn)

	var drone_btn := Button.new()
	drone_btn.text = "Ir (Drone)"
	drone_btn.add_theme_font_size_override("font_size", 12)
	drone_btn.pressed.connect(func():
		search_overlay.visible = false
		search_input.release_focus()
		room_search_drone_requested.emit(room)
	)
	row.add_child(drone_btn)

	return pc

func set_nearby_poi(poi: Dictionary) -> void:
	if poi.is_empty():
		prompt_lbl.visible = false
	else:
		prompt_lbl.text = "[E] Examinar: %s" % String(poi.get("title", ""))
		prompt_lbl.visible = true

func show_poi_card(poi: Dictionary) -> void:
	poi_title.text = String(poi.get("title", ""))
	poi_sub.text = String(poi.get("subtitle", ""))
	poi_desc.text = String(poi.get("description", ""))
	poi_panel.visible = true

func show_complete_modal() -> void:
	_sync_complete_title()
	complete_panel.visible = true

func set_start_visible(v: bool) -> void:
	start_panel.visible = v

func set_pause_visible(v: bool) -> void:
	pause_panel.visible = v

func is_any_modal_open() -> bool:
	return (
		start_panel.visible
		or pause_panel.visible
		or poi_panel.visible
		or complete_panel.visible
		or (search_overlay != null and search_overlay.visible)
		or (map_overlay != null and map_overlay.visible)
	)

func update_minimap(pos: Vector3, yaw: float, visited: Dictionary, drone: bool, room: Dictionary = {}) -> void:
	minimap.update_state(pos, yaw, visited, drone, room)
	if expanded_minimap and map_overlay and map_overlay.visible:
		expanded_minimap.update_state(pos, yaw, visited, drone, room)

func _make_pill_panel(bg: Color, border: Color) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12; sb.content_margin_right = 12
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
	pc.add_theme_stylebox_override("panel", sb)
	return pc

func _make_modal_panel(w: int, h: int, border: Color) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.offset_left = -w * 0.5; pc.offset_right = w * 0.5
	pc.offset_top = -h * 0.5; pc.offset_bottom = h * 0.5
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.12, 0.09, 0.95)
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 20; sb.content_margin_right = 20
	sb.content_margin_top = 16; sb.content_margin_bottom = 16
	pc.add_theme_stylebox_override("panel", sb)
	_modal_specs.append({"panel": pc, "max_w": float(w), "max_h": float(h)})
	return pc

func _style_hud_button(btn: Button, border: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.14, 0.10, 0.90)
	normal.border_color = border
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 12; normal.content_margin_right = 12
	normal.content_margin_top = 6; normal.content_margin_bottom = 6
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.12, 0.22, 0.15, 0.95)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.06, 0.11, 0.08, 0.95)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_font_size_override("font_size", 14)

func _on_viewport_resized() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size := vp.get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return

	var w_ratio := clampf(vp_size.x / 1280.0, 0.68, 1.15)
	var margin := clampf(roundf(vp_size.x * 0.012), 10.0, 18.0)

	if top_bar:
		top_bar.offset_left = margin
		top_bar.offset_top = margin
		top_bar.offset_right = -margin

	var pill_font := int(roundf(clampf(13.0 * w_ratio + 2.0, 12.0, 16.0)))
	var sub_font := int(roundf(clampf(12.0 * w_ratio + 2.0, 11.0, 15.0)))
	var hint_font := int(roundf(clampf(10.0 * w_ratio + 2.0, 10.0, 13.0)))

	if brand_lbl:
		brand_lbl.add_theme_font_size_override("font_size", pill_font)
	if tour_lbl:
		tour_lbl.add_theme_font_size_override("font_size", pill_font)
	if mode_lbl:
		mode_lbl.add_theme_font_size_override("font_size", sub_font)
	if room_lbl:
		room_lbl.add_theme_font_size_override("font_size", sub_font)
	if search_btn:
		search_btn.add_theme_font_size_override("font_size", sub_font)
	if time_btn:
		time_btn.add_theme_font_size_override("font_size", sub_font)
	if mute_btn:
		mute_btn.add_theme_font_size_override("font_size", sub_font)
	if logo_rect:
		var logo_sz := roundf(clampf(20.0 * w_ratio + 2.0, 16.0, 24.0))
		logo_rect.custom_minimum_size = Vector2(logo_sz, logo_sz)

	var map_w := clampf(roundf(vp_size.x * 0.155), 112.0, 194.0)
	var map_h := minf(roundf(map_w * 1.31), vp_size.y * 0.36)
	if minimap:
		minimap.offset_left = -(map_w + margin)
		minimap.offset_top = -(map_h + margin)
		minimap.offset_right = -margin
		minimap.offset_bottom = -margin

	if map_legend_box:
		map_legend_box.custom_minimum_size.x = 168.0 if vp_size.x < 920.0 else 210.0

	if hint_box and hint_lbl:
		hint_lbl.add_theme_font_size_override("font_size", hint_font)
		var max_hint_w := maxf(160.0, vp_size.x - map_w - margin * 3.0)
		if vp_size.x < 860.0:
			hint_lbl.text = "WASD Mover | E Interagir | G Salas | Tab Mapa | F Drone | N Dia/Noite | Esc Pausa"
		else:
			hint_lbl.text = "WASD Mover | E Interagir | G Buscar Sala | Tab Mapa | F Drone (T Teto) | N Dia/Noite | Esc Pausa"
		if max_hint_w < 680.0:
			hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint_lbl.custom_minimum_size.x = maxf(140.0, max_hint_w - 28.0)
		else:
			hint_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
			hint_lbl.custom_minimum_size.x = 0.0
		hint_box.offset_left = margin
		hint_box.offset_bottom = -margin
		hint_box.offset_top = -margin

	if prompt_lbl:
		var prompt_half := minf(260.0, vp_size.x * 0.44)
		prompt_lbl.offset_left = -prompt_half
		prompt_lbl.offset_right = prompt_half
		prompt_lbl.offset_top = -(margin + 96.0)
		prompt_lbl.offset_bottom = -(margin + 60.0)
		prompt_lbl.add_theme_font_size_override("font_size", int(roundf(clampf(16.0 * w_ratio + 2.0, 14.0, 19.0))))

	for spec in _modal_specs:
		var pc := spec["panel"] as PanelContainer
		if not is_instance_valid(pc):
			continue
		var mw := minf(float(spec["max_w"]), maxf(260.0, vp_size.x - 28.0))
		var mh := minf(float(spec["max_h"]), maxf(180.0, vp_size.y - 28.0))
		pc.offset_left = -mw * 0.5; pc.offset_right = mw * 0.5
		pc.offset_top = -mh * 0.5; pc.offset_bottom = mh * 0.5

	if OS.has_feature("web"):
		call_deferred("_emit_web_hud_metrics")

func _emit_web_hud_metrics() -> void:
	if not OS.has_feature("web") or time_btn == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size := vp.get_visible_rect().size
	if vp_size.y <= 0.0:
		return
	var rect := time_btn.get_global_rect()
	var top_ratio := clampf(rect.end.y / vp_size.y, 0.04, 0.25)
	var sub_font := float(time_btn.get_theme_font_size("font_size"))
	var font_ratio := clampf(sub_font / vp_size.y, 0.012, 0.03)
	JavaScriptBridge.eval("window.__ifsulShell && window.__ifsulShell.onHudMetrics && window.__ifsulShell.onHudMetrics({topRatio:" + str(snappedf(top_ratio, 0.0001)) + ",fontRatio:" + str(snappedf(font_ratio, 0.0001)) + "});", false)

func _make_backdrop_overlay() -> ColorRect:
	var cr := ColorRect.new()
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.color = Color(0.03, 0.05, 0.04, 0.65)
	return cr
