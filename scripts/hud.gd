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

var minimap: Control
var start_panel: Control
var pause_panel: Control
var poi_panel: PanelContainer
var complete_panel: PanelContainer
var top_bar: HBoxContainer
var left_flow: HFlowContainer
var brand_lbl: Label
var logo_rect: TextureRect
var hint_box: PanelContainer
var hint_lbl: Label
var prompt_lbl: Label
var tour_lbl: Label
var mode_lbl: Label
var time_btn: Button
var mute_btn: Button
var fade_rect: ColorRect
var fade_tween: Tween
var poi_title: Label
var poi_sub: Label
var poi_desc: RichTextLabel
var total_pois := 6
var _modal_specs: Array[Dictionary] = []

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

	# Top HUD bar (left wraps cleanly via HFlowContainer; right stays anchored for [N] Dia + web chips)
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
	tour_lbl.text = "Tour do Campus 0/6"
	tour_lbl.add_theme_font_size_override("font_size", 15)
	tour_box.add_child(tour_lbl)
	left_flow.add_child(tour_box)

	var mode_box := _make_pill_panel(Color(0.09, 0.12, 0.15, 0.85), Color("#64748B"))
	mode_lbl = Label.new()
	mode_lbl.text = "[F] Modo: A pé"
	mode_lbl.add_theme_font_size_override("font_size", 14)
	mode_box.add_child(mode_lbl)
	left_flow.add_child(mode_box)

	var right_actions := HBoxContainer.new()
	right_actions.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	right_actions.add_theme_constant_override("separation", 8)
	top_bar.add_child(right_actions)

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
	hint_lbl.text = "WASD Mover | Shift Correr | Espaço Pular | E Interagir | F Drone (Scroll Zoom) | N Dia/Noite | M Som | Esc Pausa"
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
	var ct := Label.new()
	ct.text = "Tour do Câmpus Concluído! (6/6)"
	ct.add_theme_font_size_override("font_size", 22)
	ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(ct)
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
	st_sub.text = "Av. Copacabana, 100 • Piratini • Sapucaia do Sul (RS)\nExplore os blocos, laboratórios, biblioteca, quadras e história real do câmpus em 3D."
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

func setup_minimap(data: Dictionary) -> void:
	total_pois = maxi(1, data.get("pois", []).size())
	minimap.setup(data)
	set_tour_progress(0, total_pois)

func set_tour_progress(visited: int, total: int) -> void:
	tour_lbl.text = "Tour do Campus %d/%d" % [visited, total]

func set_drone_mode(drone: bool) -> void:
	mode_lbl.text = "[F] Modo: Drone Livre" if drone else "[F] Modo: A pé"

func set_day_night(is_night: bool) -> void:
	time_btn.text = "[N] Noite" if is_night else "[N] Dia"

func set_muted(muted: bool) -> void:
	mute_btn.text = "[M] Som: MUDO" if muted else "[M] Som: ON"

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
	complete_panel.visible = true

func set_start_visible(v: bool) -> void:
	start_panel.visible = v

func set_pause_visible(v: bool) -> void:
	pause_panel.visible = v

func is_any_modal_open() -> bool:
	return start_panel.visible or pause_panel.visible or poi_panel.visible or complete_panel.visible

func update_minimap(pos: Vector3, yaw: float, visited: Dictionary, drone: bool) -> void:
	minimap.update_state(pos, yaw, visited, drone)

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
	sb.content_margin_left = 22; sb.content_margin_right = 22
	sb.content_margin_top = 18; sb.content_margin_bottom = 18
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

	if hint_box and hint_lbl:
		hint_lbl.add_theme_font_size_override("font_size", hint_font)
		var max_hint_w := maxf(160.0, vp_size.x - map_w - margin * 3.0)
		if vp_size.x < 780.0:
			hint_lbl.text = "WASD Mover | E Interagir | F Drone | N Dia/Noite | Esc Pausa"
		else:
			hint_lbl.text = "WASD Mover | Shift Correr | Espaço Pular | E Interagir | F Drone (Scroll Zoom) | N Dia/Noite | M Som | Esc Pausa"
		if max_hint_w < 640.0:
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
