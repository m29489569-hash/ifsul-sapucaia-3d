class_name CampusMinimap
extends Control

class _StaticMapLayer extends Control:
	var owner_map: CampusMinimap
	func _draw() -> void:
		if owner_map != null:
			owner_map._draw_static_layer(self)

var campus_data: Dictionary = {}
var interiors_data: Dictionary = {}
var visited_pois: Dictionary = {}
var current_room: Dictionary = {}
var player_pos: Vector3 = Vector3.ZERO
var player_yaw: float = 0.0
var is_drone: bool = false
var is_expanded: bool = false

var has_target_room: bool = false
var target_room_pos: Vector3 = Vector3.ZERO
var target_room_label: String = ""

var _zoom_factor: float = 0.0
var _target_zoom: float = 0.0
var _pulse_phase: float = 0.0
var _pulse_accum: float = 0.0

var _last_drawn_pos := Vector3(1e9, 0.0, 1e9)
var _last_drawn_yaw := 999.0
var _last_visited_count := -1
var _last_drone := false
var _last_room_id := ""
var _cached_size := Vector2.ZERO

var _cached_streets: Array[PackedVector2Array] = []
var _cached_perim: PackedVector2Array = PackedVector2Array()
var _cached_perim_closed: PackedVector2Array = PackedVector2Array()
var _cached_parking: Array[PackedVector2Array] = []
var _cached_courts: Array[Dictionary] = []
var _cached_buildings: Array[Dictionary] = []
var _cached_pois: Array[Dictionary] = []
var _cached_horta: PackedVector2Array = PackedVector2Array()
var _cached_pond: PackedVector2Array = PackedVector2Array()

var _world_buildings: Array[Dictionary] = []
var _world_rooms: Array[Dictionary] = []
var _world_courtyards: Array[PackedVector2Array] = []
var _world_pois: Array[Dictionary] = []

var _static_layer: _StaticMapLayer
var _arrow_poly := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _arrow_line := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

const MAP_BOUNDS := Rect2(-115.0, -180.0, 220.0, 370.0)
const INDOOR_VIEW_W := 46.0
const INDOOR_VIEW_H := 60.0

func _ready() -> void:
	set_process(false)
	_static_layer = _StaticMapLayer.new()
	_static_layer.owner_map = self
	_static_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_static_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_static_layer.show_behind_parent = true
	add_child(_static_layer)
	resized.connect(_on_resized)
	visibility_changed.connect(_sync_process_state)

func _on_resized() -> void:
	_cached_size = Vector2.ZERO
	if _static_layer:
		_static_layer.queue_redraw()
	queue_redraw()

func set_expanded(expanded: bool) -> void:
	if is_expanded == expanded:
		return
	is_expanded = expanded
	if is_expanded:
		_zoom_factor = 0.0
		_target_zoom = 0.0
	_cached_size = Vector2.ZERO
	if _static_layer:
		_static_layer.queue_redraw()
	queue_redraw()
	_sync_process_state()

func setup(data: Dictionary, interiors: Dictionary = {}) -> void:
	campus_data = data
	interiors_data = interiors
	_last_visited_count = -1
	_cached_size = Vector2.ZERO
	_parse_world_geometry()
	if _static_layer:
		_static_layer.queue_redraw()
	queue_redraw()

func set_target_room(pos: Vector3, label: String = "") -> void:
	has_target_room = true
	target_room_pos = pos
	target_room_label = label
	_pulse_phase = 0.0
	_pulse_accum = 0.0
	_sync_process_state()
	queue_redraw()

func clear_target_room() -> void:
	if not has_target_room:
		return
	has_target_room = false
	target_room_label = ""
	_sync_process_state()
	queue_redraw()

func update_state(pos: Vector3, yaw: float, visited: Dictionary, drone: bool, room: Dictionary = {}) -> void:
	player_pos = pos
	player_yaw = yaw
	visited_pois = visited
	is_drone = drone
	current_room = room
	var room_id := String(room.get("id", ""))
	var want_zoom := 1.0 if (not is_expanded and not drone and not room_id.is_empty()) else 0.0
	var zoom_changed := not is_equal_approx(want_zoom, _target_zoom)
	_target_zoom = want_zoom
	if zoom_changed:
		_sync_process_state()

	var move_thresh := 0.08 if _zoom_factor > 0.05 else 0.45
	var moved := Vector2(pos.x - _last_drawn_pos.x, pos.z - _last_drawn_pos.z).length_squared() > move_thresh
	var turned := absf(yaw - _last_drawn_yaw) > 0.045
	if moved or turned or visited.size() != _last_visited_count or drone != _last_drone or room_id != _last_room_id or zoom_changed:
		_last_drawn_pos = pos
		_last_drawn_yaw = yaw
		_last_visited_count = visited.size()
		_last_drone = drone
		_last_room_id = room_id
		queue_redraw()

func _sync_process_state() -> void:
	var zooming := (not is_expanded) and absf(_zoom_factor - _target_zoom) > 0.005
	var pulsing := has_target_room and is_visible_in_tree()
	set_process(zooming or pulsing)

func _process(delta: float) -> void:
	var need_redraw := false
	if not is_expanded and absf(_zoom_factor - _target_zoom) > 0.005:
		var prev_zoom := _zoom_factor
		_zoom_factor = move_toward(_zoom_factor, _target_zoom, delta * 3.8)
		if (prev_zoom <= 0.02) != (_zoom_factor <= 0.02):
			if _static_layer:
				_static_layer.queue_redraw()
		need_redraw = true
	if has_target_room and is_visible_in_tree():
		_pulse_phase = fmod(_pulse_phase + delta * 3.2, TAU)
		_pulse_accum += delta
		if _pulse_accum >= 0.05:
			_pulse_accum = 0.0
			need_redraw = true
	if need_redraw:
		queue_redraw()
	_sync_process_state()

func _parse_world_geometry() -> void:
	_world_buildings.clear()
	_world_rooms.clear()
	_world_courtyards.clear()
	_world_pois.clear()

	for b in campus_data.get("buildings", []):
		var wpoly := PackedVector2Array()
		var cx := 0.0
		var cz := 0.0
		var pts: Array = b.get("polygon", [])
		for p in pts:
			var vx := float(p[0])
			var vz := float(p[1])
			wpoly.append(Vector2(vx, vz))
			cx += vx
			cz += vz
		if wpoly.size() >= 3:
			cx /= float(wpoly.size())
			cz /= float(wpoly.size())
			_world_buildings.append({
				"id": String(b.get("id", "")),
				"sector": String(b.get("sector", "")),
				"short_label": _building_short_label(b),
				"poly": wpoly,
				"center": Vector2(cx, cz),
				"col": _resolve_building_color(b)
			})

	var sectors: Dictionary = interiors_data.get("sectors", {})
	for r in interiors_data.get("rooms", []):
		var c_arr: Array = r.get("center", [0.0, 0.0])
		var s_arr: Array = r.get("size", [4.0, 4.0])
		if c_arr.size() < 2 or s_arr.size() < 2:
			continue
		var cx := float(c_arr[0])
		var cz := float(c_arr[1])
		var rw := float(s_arr[0])
		var rd := float(s_arr[1])
		var rot_deg := float(r.get("rot_deg", 8.7))
		var sec_id := String(r.get("sector", ""))
		var sec_info: Dictionary = sectors.get(sec_id, {}) if sectors.has(sec_id) else {}
		var col_str := String(sec_info.get("color", "#6AA87B"))
		var scol := Color.from_string(col_str, Color("#6AA87B"))
		_world_rooms.append({
			"id": String(r.get("id", "")),
			"code": String(r.get("code", "")),
			"name": String(r.get("name", "")),
			"sector": sec_id,
			"center": Vector2(cx, cz),
			"size": Vector2(rw, rd),
			"poly": _rect_world_poly(cx, cz, rw, rd, rot_deg),
			"col": scol
		})

	for cy in interiors_data.get("courtyards", []):
		var c_arr: Array = cy.get("center", [0.0, 0.0])
		var s_arr: Array = cy.get("size", [6.0, 6.0])
		if c_arr.size() >= 2 and s_arr.size() >= 2:
			var rot_deg := float(cy.get("rot_deg", 8.7))
			_world_courtyards.append(_rect_world_poly(float(c_arr[0]), float(c_arr[1]), float(s_arr[0]), float(s_arr[1]), rot_deg))

	for poi in campus_data.get("pois", []):
		var pos_arr: Array = poi.get("position", [0.0, 0.0, 0.0])
		_world_pois.append({
			"id": String(poi.get("id", "")),
			"title": String(poi.get("title", "")),
			"wx": float(pos_arr[0]),
			"wz": float(pos_arr[2])
		})

func _rect_world_poly(cx: float, cz: float, w: float, d: float, rot_deg: float) -> PackedVector2Array:
	var rad := deg_to_rad(rot_deg)
	var c := cos(rad)
	var s := sin(rad)
	var hw := w * 0.5
	var hd := d * 0.5
	var corners: Array[Vector2] = [
		Vector2(-hw, -hd),
		Vector2(hw, -hd),
		Vector2(hw, hd),
		Vector2(-hw, hd)
	]
	var out := PackedVector2Array()
	for pt in corners:
		var wx: float = cx + pt.x * c + pt.y * s
		var wz: float = cz - pt.x * s + pt.y * c
		out.append(Vector2(wx, wz))
	return out

func _resolve_building_color(b: Dictionary) -> Color:
	var map_col := String(b.get("map_color", ""))
	if not map_col.is_empty():
		return Color.from_string(map_col, Color("#D8D4CC"))
	var btype := String(b.get("type", ""))
	match btype:
		"auditorium":
			return Color("#F2DF2F")
		"library":
			return Color("#1EC7C3")
		"social_house":
			return Color("#72C850")
		"academic_cross":
			return Color("#7AC790")
		"admin":
			return Color("#7FA8C9")
		"industrial":
			return Color("#F0A84B")
		_:
			return Color("#D8D4CC")

func _building_short_label(b: Dictionary) -> String:
	var bid := String(b.get("id", ""))
	match bid:
		"bloco_adm":
			return "Setor 100"
		"bloco_ensino_central":
			return "Setor 200"
		"bloco_didatico_leste":
			return "Setor 230 / Cantina"
		"auditorio":
			return "Auditório 504"
		"bloco_labs_industriais":
			return "Setor 300"
		"bloco_engenharia_sul":
			return "Setor 400"
		"bloco_800":
			return "Bloco 800"
		"biblioteca":
			return "Biblioteca"
		"sede_social":
			return "Sede Social"
		"vestiarios_esporte":
			return "Ed. Física"
		"guarita":
			return "Portaria"
		_:
			return ""

func _get_active_bounds() -> Rect2:
	if is_expanded or _zoom_factor <= 0.02:
		return MAP_BOUNDS
	var zoom_rect := Rect2(
		player_pos.x - INDOOR_VIEW_W * 0.5,
		player_pos.z - INDOOR_VIEW_H * 0.5,
		INDOOR_VIEW_W,
		INDOOR_VIEW_H
	)
	var t := smoothstep(0.0, 1.0, _zoom_factor)
	return Rect2(
		MAP_BOUNDS.position.lerp(zoom_rect.position, t),
		MAP_BOUNDS.size.lerp(zoom_rect.size, t)
	)

func _world_to_map_in_bounds(wx: float, wz: float, bounds: Rect2) -> Vector2:
	var pad := 14.0 if is_expanded else 10.0
	var usable := size - Vector2(pad * 2.0, pad * 2.0)
	var sx := usable.x / maxf(1.0, bounds.size.x)
	var sy := usable.y / maxf(1.0, bounds.size.y)
	var sc := minf(sx, sy)
	var offset := (size - bounds.size * sc) * 0.5
	return Vector2(
		offset.x + (wx - bounds.position.x) * sc,
		offset.y + (wz - bounds.position.y) * sc
	)

func _get_scale_in_bounds(bounds: Rect2) -> float:
	var pad := 14.0 if is_expanded else 10.0
	var usable := size - Vector2(pad * 2.0, pad * 2.0)
	return minf(usable.x / maxf(1.0, bounds.size.x), usable.y / maxf(1.0, bounds.size.y))

func _world_to_map(wx: float, wz: float) -> Vector2:
	return _world_to_map_in_bounds(wx, wz, _get_active_bounds())

func _poly_to_map(wpoly: PackedVector2Array, bounds: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(wpoly.size())
	for i in range(wpoly.size()):
		out[i] = _world_to_map_in_bounds(wpoly[i].x, wpoly[i].y, bounds)
	return out

func _close_poly(poly: PackedVector2Array) -> PackedVector2Array:
	var closed := poly.duplicate()
	if closed.size() >= 2:
		closed.append(closed[0])
	return closed

func _rebuild_cache() -> void:
	_cached_size = size
	_cached_streets.clear()
	_cached_parking.clear()
	_cached_courts.clear()
	_cached_buildings.clear()
	_cached_pois.clear()
	_cached_horta = PackedVector2Array()
	_cached_pond = PackedVector2Array()

	for st in campus_data.get("streets", []):
		var pts := PackedVector2Array()
		for p in st.get("points", []):
			pts.append(_world_to_map_in_bounds(float(p[0]), float(p[1]), MAP_BOUNDS))
		if pts.size() >= 2:
			_cached_streets.append(pts)

	_cached_perim = PackedVector2Array()
	for p in campus_data.get("perimeter", []):
		_cached_perim.append(_world_to_map_in_bounds(float(p[0]), float(p[1]), MAP_BOUNDS))
	_cached_perim_closed = _close_poly(_cached_perim) if _cached_perim.size() >= 3 else PackedVector2Array()

	for pk in campus_data.get("parking_lots", []):
		var poly := PackedVector2Array()
		for p in pk.get("polygon", []):
			poly.append(_world_to_map_in_bounds(float(p[0]), float(p[1]), MAP_BOUNDS))
		if poly.size() >= 3:
			_cached_parking.append(poly)

	for c in campus_data.get("courts", []):
		var poly := PackedVector2Array()
		for p in c.get("polygon", []):
			poly.append(_world_to_map_in_bounds(float(p[0]), float(p[1]), MAP_BOUNDS))
		if poly.size() >= 3:
			var sp := String(c.get("sport", ""))
			var col := Color("#A34F3A")
			if sp == "multi":
				col = Color("#255B8A")
			elif sp == "outdoor_multi" or sp == "outdoor":
				col = Color("#3B78A6")
			elif sp.contains("sand") or sp.contains("volley"):
				col = Color("#C28A52")
			_cached_courts.append({"poly": poly, "closed": _close_poly(poly), "col": col})

	var lms: Dictionary = campus_data.get("landmarks", {})
	if lms.has("horta") and lms["horta"] is Dictionary:
		var h: Dictionary = lms["horta"]
		if h.has("polygon") and h["polygon"] is Array:
			for p in h["polygon"]:
				_cached_horta.append(_world_to_map_in_bounds(float(p[0]), float(p[1]), MAP_BOUNDS))
		elif h.has("center") and h.has("size"):
			var hc: Array = h["center"]
			var hs: Array = h["size"]
			var wpoly := _rect_world_poly(float(hc[0]), float(hc[1]), float(hs[0]), float(hs[1]), float(h.get("rot_deg", 8.7)))
			_cached_horta = _poly_to_map(wpoly, MAP_BOUNDS)

	if lms.has("southern_pond") and lms["southern_pond"] is Dictionary:
		var pond: Dictionary = lms["southern_pond"]
		if pond.has("polygon") and pond["polygon"] is Array:
			for p in pond["polygon"]:
				_cached_pond.append(_world_to_map_in_bounds(float(p[0]), float(p[1]), MAP_BOUNDS))
		elif pond.has("center"):
			var pc: Array = pond["center"]
			var rx := float(pond.get("rx", pond.get("radius", 9.0)))
			var rz := float(pond.get("rz", pond.get("radius", 6.5)))
			for i in range(16):
				var ang := TAU * float(i) / 16.0
				_cached_pond.append(_world_to_map_in_bounds(float(pc[0]) + cos(ang) * rx, float(pc[1]) + sin(ang) * rz, MAP_BOUNDS))

	for wb in _world_buildings:
		var poly := _poly_to_map(wb["poly"], MAP_BOUNDS)
		if poly.size() >= 3:
			_cached_buildings.append({
				"poly": poly,
				"closed": _close_poly(poly),
				"col": wb["col"],
				"center": _world_to_map_in_bounds(wb["center"].x, wb["center"].y, MAP_BOUNDS),
				"short_label": wb["short_label"]
			})

	for wp in _world_pois:
		_cached_pois.append({
			"id": wp["id"],
			"mp": _world_to_map_in_bounds(wp["wx"], wp["wz"], MAP_BOUNDS)
		})

func _draw_static_layer(canvas: Control) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.10, 0.09, 0.92), true)
	canvas.draw_rect(Rect2(Vector2.ZERO, size), Color("#2F9E41"), false, 2.0)
	if campus_data.is_empty():
		return
	# When compact minimap is zoomed indoors, _draw() renders the dynamic zoomed map
	if not is_expanded and _zoom_factor > 0.02:
		return
	if _cached_size != size:
		_rebuild_cache()

	for pts in _cached_streets:
		canvas.draw_polyline(pts, Color(0.32, 0.34, 0.37, 0.9), 5.5 if is_expanded else 3.8)

	if _cached_perim.size() >= 3:
		canvas.draw_colored_polygon(_cached_perim, Color(0.18, 0.31, 0.19, 0.65))
		canvas.draw_polyline(_cached_perim_closed, Color("#2F9E41"), 2.0 if is_expanded else 1.5)

	for poly in _cached_parking:
		canvas.draw_colored_polygon(poly, Color(0.28, 0.30, 0.33, 0.85))

	if _cached_pond.size() >= 3:
		canvas.draw_colored_polygon(_cached_pond, Color("#2B7FA8"))
		canvas.draw_polyline(_close_poly(_cached_pond), Color("#7DD3FC"), 1.2)

	if _cached_horta.size() >= 3:
		canvas.draw_colored_polygon(_cached_horta, Color("#3B6E2A"))
		canvas.draw_polyline(_close_poly(_cached_horta), Color("#86EFAC"), 1.2)

	for c in _cached_courts:
		canvas.draw_colored_polygon(c["poly"], c["col"])
		canvas.draw_polyline(c["closed"], Color(0.95, 0.98, 1.0, 0.55), 1.0)

	var border_w := 1.6 if is_expanded else 1.1
	for b in _cached_buildings:
		canvas.draw_colored_polygon(b["poly"], b["col"])
		canvas.draw_polyline(b["closed"], Color(0.06, 0.09, 0.08, 0.90), border_w)

	if is_expanded:
		_draw_expanded_details(canvas)

	var font := ThemeDB.fallback_font
	if font:
		canvas.draw_string(font, Vector2(size.x - 20, 18), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13 if is_expanded else 11, Color(0.92, 0.97, 0.92))

func _draw_expanded_details(canvas: Control) -> void:
	var font := ThemeDB.fallback_font
	var sc := _get_scale_in_bounds(MAP_BOUNDS)

	for cy in _world_courtyards:
		var mpoly := _poly_to_map(cy, MAP_BOUNDS)
		if mpoly.size() >= 3:
			canvas.draw_colored_polygon(mpoly, Color(0.22, 0.44, 0.24, 0.92))
			canvas.draw_polyline(_close_poly(mpoly), Color("#86EFAC"), 1.0)

	for r in _world_rooms:
		var mpoly := _poly_to_map(r["poly"], MAP_BOUNDS)
		if mpoly.size() < 3:
			continue
		var fill_col: Color = r["col"]
		fill_col.a = 0.28
		canvas.draw_colored_polygon(mpoly, fill_col)
		canvas.draw_polyline(_close_poly(mpoly), Color(0.07, 0.10, 0.09, 0.72), 1.0)
		var code := String(r["code"])
		if font and not code.is_empty():
			var rsz: Vector2 = r["size"]
			var px_min := minf(rsz.x, rsz.y) * sc
			if px_min >= 11.5:
				var fsize := clampi(int(px_min * 0.42), 8, 11)
				var center_mp := _world_to_map_in_bounds(r["center"].x, r["center"].y, MAP_BOUNDS)
				var tw := font.get_string_size(code, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
				canvas.draw_string(font, center_mp + Vector2(-tw * 0.5, fsize * 0.35), code, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.05, 0.08, 0.07, 0.95))

	if font:
		for b in _cached_buildings:
			var lbl := String(b["short_label"])
			if lbl.is_empty():
				continue
			var fsize := 11
			var tsz := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
			var pos: Vector2 = b["center"] - Vector2(tsz.x * 0.5, -tsz.y * 0.3)
			var bg := Rect2(pos.x - 4.0, pos.y - tsz.y + 1.0, tsz.x + 8.0, tsz.y + 4.0)
			canvas.draw_rect(bg, Color(0.04, 0.07, 0.06, 0.76), true)
			canvas.draw_string(font, pos, lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.96, 0.99, 0.96))

func _draw_zoomed_indoor_world(bounds: Rect2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.10, 0.09, 0.94), true)
	var sc := _get_scale_in_bounds(bounds)
	var font := ThemeDB.fallback_font
	var active_room_id := String(current_room.get("id", ""))

	for wb in _world_buildings:
		var mpoly := _poly_to_map(wb["poly"], bounds)
		if mpoly.size() >= 3:
			var bcol: Color = wb["col"]
			bcol = bcol.darkened(0.28)
			draw_colored_polygon(mpoly, bcol)
			draw_polyline(_close_poly(mpoly), Color(0.06, 0.09, 0.08, 0.95), 1.8)

	for cy in _world_courtyards:
		var mpoly := _poly_to_map(cy, bounds)
		if mpoly.size() >= 3:
			draw_colored_polygon(mpoly, Color(0.22, 0.44, 0.24, 0.92))
			draw_polyline(_close_poly(mpoly), Color("#86EFAC"), 1.2)

	for r in _world_rooms:
		var mpoly := _poly_to_map(r["poly"], bounds)
		if mpoly.size() < 3:
			continue
		var is_cur := (not active_room_id.is_empty()) and String(r["id"]) == active_room_id
		var fill_col: Color = r["col"]
		if is_cur:
			fill_col = fill_col.lightened(0.25)
			fill_col.a = 0.88
		else:
			fill_col.a = 0.58
		draw_colored_polygon(mpoly, fill_col)
		var border_col := Color("#FFFFFF") if is_cur else Color(0.07, 0.10, 0.09, 0.88)
		draw_polyline(_close_poly(mpoly), border_col, 2.0 if is_cur else 1.2)

		var code := String(r["code"])
		if code.is_empty():
			code = String(r["name"]).substr(0, 8)
		if font and not code.is_empty():
			var rsz: Vector2 = r["size"]
			if minf(rsz.x, rsz.y) * sc >= 13.0:
				var fsize := clampi(int(minf(rsz.x, rsz.y) * sc * 0.34), 8, 12)
				var center_mp := _world_to_map_in_bounds(r["center"].x, r["center"].y, bounds)
				var tw := font.get_string_size(code, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
				draw_string(font, center_mp + Vector2(-tw * 0.5, fsize * 0.35), code, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.04, 0.07, 0.06, 0.96))

	if font:
		draw_rect(Rect2(6, 6, 66, 16), Color(0.04, 0.08, 0.07, 0.84), true)
		draw_string(font, Vector2(10, 18), "INDOOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#7DD3FC"))
		draw_string(font, Vector2(size.x - 18, 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.92, 0.97, 0.92))

	draw_rect(Rect2(Vector2.ZERO, size), Color("#38BDF8"), false, 2.0)

func _draw() -> void:
	if campus_data.is_empty():
		return
	if _cached_size != size:
		_rebuild_cache()
		if _static_layer:
			_static_layer.queue_redraw()

	var bounds := _get_active_bounds()
	var zoomed := (not is_expanded) and (_zoom_factor > 0.02)
	if zoomed:
		_draw_zoomed_indoor_world(bounds)

	# POIs
	var poi_r := 5.5 if is_expanded else 4.2
	for wp in _world_pois:
		var mp := _world_to_map_in_bounds(wp["wx"], wp["wz"], bounds)
		if mp.x < -8.0 or mp.x > size.x + 8.0 or mp.y < -8.0 or mp.y > size.y + 8.0:
			continue
		var is_vis := visited_pois.has(wp["id"])
		var pcol := Color("#2F9E41") if is_vis else Color("#F5C43D")
		draw_circle(mp, poi_r, pcol)
		draw_arc(mp, poi_r + 1.0, 0.0, TAU, 16, Color.WHITE, 1.2)

	# Pulsing target room marker
	if has_target_room:
		var tp := _world_to_map_in_bounds(target_room_pos.x, target_room_pos.z, bounds)
		var clamped_tp := Vector2(clampf(tp.x, 10.0, size.x - 10.0), clampf(tp.y, 10.0, size.y - 10.0))
		var pulse := 0.5 + 0.5 * sin(_pulse_phase)
		var ring_r := (9.0 if is_expanded else 6.5) + pulse * (9.0 if is_expanded else 6.0)
		var ring_col := Color("#38BDF8")
		ring_col.a = 0.95 - pulse * 0.55
		draw_arc(clamped_tp, ring_r, 0.0, TAU, 24, ring_col, 2.2)
		draw_arc(clamped_tp, ring_r * 0.65, 0.0, TAU, 20, Color(0.96, 0.77, 0.24, 0.90), 1.6)
		draw_circle(clamped_tp, 4.5 if is_expanded else 3.6, Color("#F5C43D"))
		draw_arc(clamped_tp, 5.2 if is_expanded else 4.2, 0.0, TAU, 16, Color("#0B1410"), 1.3)
		var font := ThemeDB.fallback_font
		if font and not target_room_label.is_empty():
			var fsize := 11 if is_expanded else 9
			var short_lbl := target_room_label if is_expanded else target_room_label.substr(0, 18)
			var tsz := font.get_string_size(short_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
			var lx := clampf(clamped_tp.x - tsz.x * 0.5, 6.0, maxf(6.0, size.x - tsz.x - 10.0))
			var ly := clampf(clamped_tp.y - 12.0, tsz.y + 6.0, size.y - 8.0)
			draw_rect(Rect2(lx - 4.0, ly - tsz.y, tsz.x + 8.0, tsz.y + 4.0), Color(0.05, 0.11, 0.14, 0.90), true)
			draw_rect(Rect2(lx - 4.0, ly - tsz.y, tsz.x + 8.0, tsz.y + 4.0), Color("#38BDF8"), false, 1.0)
			draw_string(font, Vector2(lx, ly), short_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color("#E0F2FE"))

	# Player / Drone direction arrow
	var pp := _world_to_map_in_bounds(player_pos.x, player_pos.z, bounds)
	var fwd := Vector2(-sin(player_yaw), -cos(player_yaw)).normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var arrow_scale := 1.25 if is_expanded else 1.0
	var tip := pp + fwd * (8.0 * arrow_scale)
	var left_pt := pp - fwd * (5.0 * arrow_scale) - right * (4.5 * arrow_scale)
	var right_pt := pp - fwd * (5.0 * arrow_scale) + right * (4.5 * arrow_scale)
	_arrow_poly[0] = tip; _arrow_poly[1] = right_pt; _arrow_poly[2] = left_pt
	_arrow_line[0] = tip; _arrow_line[1] = right_pt; _arrow_line[2] = left_pt; _arrow_line[3] = tip
	var arrow_col := Color("#38BDF8") if is_drone else Color("#CD191E")
	draw_colored_polygon(_arrow_poly, arrow_col)
	draw_polyline(_arrow_line, Color.WHITE, 1.4 if is_expanded else 1.2)
