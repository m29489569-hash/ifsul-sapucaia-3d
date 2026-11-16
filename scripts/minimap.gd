class_name CampusMinimap
extends Control

var campus_data: Dictionary = {}
var visited_pois: Dictionary = {}
var player_pos: Vector3 = Vector3.ZERO
var player_yaw: float = 0.0
var is_drone: bool = false
var _last_drawn_pos := Vector3(1e9, 0.0, 1e9)
var _last_drawn_yaw := 999.0
var _last_visited_count := -1
var _last_drone := false

const MAP_BOUNDS := Rect2(-115.0, -180.0, 220.0, 370.0)

func setup(data: Dictionary) -> void:
	campus_data = data
	_last_visited_count = -1
	queue_redraw()

func update_state(pos: Vector3, yaw: float, visited: Dictionary, drone: bool) -> void:
	player_pos = pos
	player_yaw = yaw
	visited_pois = visited
	is_drone = drone
	var moved := Vector2(pos.x - _last_drawn_pos.x, pos.z - _last_drawn_pos.z).length_squared() > 0.06
	var turned := absf(yaw - _last_drawn_yaw) > 0.02
	if moved or turned or visited.size() != _last_visited_count or drone != _last_drone:
		_last_drawn_pos = pos
		_last_drawn_yaw = yaw
		_last_visited_count = visited.size()
		_last_drone = drone
		queue_redraw()

func _world_to_map(wx: float, wz: float) -> Vector2:
	var pad := 10.0
	var usable := size - Vector2(pad * 2.0, pad * 2.0)
	var sx := usable.x / MAP_BOUNDS.size.x
	var sy := usable.y / MAP_BOUNDS.size.y
	var scale := minf(sx, sy)
	var offset := (size - MAP_BOUNDS.size * scale) * 0.5
	return Vector2(
		offset.x + (wx - MAP_BOUNDS.position.x) * scale,
		offset.y + (wz - MAP_BOUNDS.position.y) * scale
	)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.11, 0.10, 0.86), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color("#2F9E41"), false, 2.0)
	if campus_data.is_empty():
		return

	# Streets
	for st in campus_data.get("streets", []):
		var pts: PackedVector2Array = PackedVector2Array()
		for p in st.get("points", []):
			pts.append(_world_to_map(float(p[0]), float(p[1])))
		if pts.size() >= 2:
			draw_polyline(pts, Color(0.32, 0.34, 0.37, 0.9), 4.0)

	# Campus perimeter
	var perim_pts := PackedVector2Array()
	for p in campus_data.get("perimeter", []):
		perim_pts.append(_world_to_map(float(p[0]), float(p[1])))
	if perim_pts.size() >= 3:
		draw_colored_polygon(perim_pts, Color(0.20, 0.34, 0.20, 0.65))
		var closed := perim_pts.duplicate()
		closed.append(perim_pts[0])
		draw_polyline(closed, Color("#2F9E41"), 1.6)

	# Parking lots
	for pk in campus_data.get("parking_lots", []):
		var poly := PackedVector2Array()
		for p in pk.get("polygon", []):
			poly.append(_world_to_map(float(p[0]), float(p[1])))
		if poly.size() >= 3:
			draw_colored_polygon(poly, Color(0.28, 0.30, 0.33, 0.85))

	# Courts
	for c in campus_data.get("courts", []):
		var poly := PackedVector2Array()
		for p in c.get("polygon", []):
			poly.append(_world_to_map(float(p[0]), float(p[1])))
		if poly.size() >= 3:
			var col := Color("#255B8A") if c.get("sport", "") == "multi" else Color("#A34F3A")
			draw_colored_polygon(poly, col)

	# Buildings
	for b in campus_data.get("buildings", []):
		var poly := PackedVector2Array()
		for p in b.get("polygon", []):
			poly.append(_world_to_map(float(p[0]), float(p[1])))
		if poly.size() >= 3:
			var bcol := Color("#D8D4CC") if b.get("type", "") != "auditorium" else Color("#C89B96")
			draw_colored_polygon(poly, bcol)

	# POIs
	for poi in campus_data.get("pois", []):
		var pos_arr: Array = poi.get("position", [0, 0, 0])
		var mp := _world_to_map(float(pos_arr[0]), float(pos_arr[2]))
		var is_vis := visited_pois.has(poi.get("id", ""))
		var pcol := Color("#2F9E41") if is_vis else Color("#F5C43D")
		draw_circle(mp, 4.5, pcol)
		draw_arc(mp, 5.5, 0.0, TAU, 16, Color.WHITE, 1.2)

	# Player / Drone arrow
	var pp := _world_to_map(player_pos.x, player_pos.z)
	var fwd := Vector2(-sin(player_yaw), -cos(player_yaw)).normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var tip := pp + fwd * 8.0
	var left_pt := pp - fwd * 5.0 - right * 4.5
	var right_pt := pp - fwd * 5.0 + right * 4.5
	var arrow_col := Color("#38BDF8") if is_drone else Color("#CD191E")
	draw_colored_polygon(PackedVector2Array([tip, right_pt, left_pt]), arrow_col)
	draw_polyline(PackedVector2Array([tip, right_pt, left_pt, tip]), Color.WHITE, 1.2)

	# Compass N
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 18, 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.95, 0.9))
