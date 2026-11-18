class_name CampusMinimap
extends Control

class _StaticMapLayer extends Control:
	var owner_map: CampusMinimap
	func _draw() -> void:
		if owner_map != null:
			owner_map._draw_static_layer(self)

var campus_data: Dictionary = {}
var visited_pois: Dictionary = {}
var player_pos: Vector3 = Vector3.ZERO
var player_yaw: float = 0.0
var is_drone: bool = false

var _last_drawn_pos := Vector3(1e9, 0.0, 1e9)
var _last_drawn_yaw := 999.0
var _last_visited_count := -1
var _last_drone := false
var _cached_size := Vector2.ZERO
var _cached_streets: Array[PackedVector2Array] = []
var _cached_perim: PackedVector2Array = PackedVector2Array()
var _cached_perim_closed: PackedVector2Array = PackedVector2Array()
var _cached_parking: Array[PackedVector2Array] = []
var _cached_courts: Array[Dictionary] = []
var _cached_buildings: Array[Dictionary] = []
var _cached_pois: Array[Dictionary] = []
var _static_layer: _StaticMapLayer
var _arrow_poly := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _arrow_line := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

const MAP_BOUNDS := Rect2(-115.0, -180.0, 220.0, 370.0)

func _ready() -> void:
	_static_layer = _StaticMapLayer.new()
	_static_layer.owner_map = self
	_static_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_static_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_static_layer.show_behind_parent = true
	add_child(_static_layer)
	resized.connect(_on_resized)

func _on_resized() -> void:
	if _static_layer:
		_static_layer.queue_redraw()
	queue_redraw()

func setup(data: Dictionary) -> void:
	campus_data = data
	_last_visited_count = -1
	_cached_size = Vector2.ZERO
	if _static_layer:
		_static_layer.queue_redraw()
	queue_redraw()

func update_state(pos: Vector3, yaw: float, visited: Dictionary, drone: bool) -> void:
	player_pos = pos
	player_yaw = yaw
	visited_pois = visited
	is_drone = drone
	# 1px on the minimap spans ~1.5-2.0m in world space, so 0.45 m^2 (~0.67m) avoids sub-pixel redraws.
	var moved := Vector2(pos.x - _last_drawn_pos.x, pos.z - _last_drawn_pos.z).length_squared() > 0.45
	var turned := absf(yaw - _last_drawn_yaw) > 0.045
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

func _rebuild_cache() -> void:
	_cached_size = size
	_cached_streets.clear()
	_cached_parking.clear()
	_cached_courts.clear()
	_cached_buildings.clear()
	_cached_pois.clear()

	for st in campus_data.get("streets", []):
		var pts := PackedVector2Array()
		for p in st.get("points", []):
			pts.append(_world_to_map(float(p[0]), float(p[1])))
		if pts.size() >= 2:
			_cached_streets.append(pts)

	_cached_perim = PackedVector2Array()
	for p in campus_data.get("perimeter", []):
		_cached_perim.append(_world_to_map(float(p[0]), float(p[1])))
	_cached_perim_closed = PackedVector2Array()
	if _cached_perim.size() >= 3:
		_cached_perim_closed = _cached_perim.duplicate()
		_cached_perim_closed.append(_cached_perim[0])

	for pk in campus_data.get("parking_lots", []):
		var poly := PackedVector2Array()
		for p in pk.get("polygon", []):
			poly.append(_world_to_map(float(p[0]), float(p[1])))
		if poly.size() >= 3:
			_cached_parking.append(poly)

	for c in campus_data.get("courts", []):
		var poly := PackedVector2Array()
		for p in c.get("polygon", []):
			poly.append(_world_to_map(float(p[0]), float(p[1])))
		if poly.size() >= 3:
			var col := Color("#255B8A") if c.get("sport", "") == "multi" else Color("#A34F3A")
			_cached_courts.append({"poly": poly, "col": col})

	for b in campus_data.get("buildings", []):
		var poly := PackedVector2Array()
		for p in b.get("polygon", []):
			poly.append(_world_to_map(float(p[0]), float(p[1])))
		if poly.size() >= 3:
			var bcol := Color("#D8D4CC") if b.get("type", "") != "auditorium" else Color("#C89B96")
			_cached_buildings.append({"poly": poly, "col": bcol})

	for poi in campus_data.get("pois", []):
		var pos_arr: Array = poi.get("position", [0, 0, 0])
		_cached_pois.append({
			"id": String(poi.get("id", "")),
			"mp": _world_to_map(float(pos_arr[0]), float(pos_arr[2]))
		})

func _draw_static_layer(canvas: Control) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.11, 0.10, 0.86), true)
	canvas.draw_rect(Rect2(Vector2.ZERO, size), Color("#2F9E41"), false, 2.0)
	if campus_data.is_empty():
		return
	if _cached_size != size:
		_rebuild_cache()

	for pts in _cached_streets:
		canvas.draw_polyline(pts, Color(0.32, 0.34, 0.37, 0.9), 4.0)

	if _cached_perim.size() >= 3:
		canvas.draw_colored_polygon(_cached_perim, Color(0.20, 0.34, 0.20, 0.65))
		canvas.draw_polyline(_cached_perim_closed, Color("#2F9E41"), 1.6)

	for poly in _cached_parking:
		canvas.draw_colored_polygon(poly, Color(0.28, 0.30, 0.33, 0.85))

	for c in _cached_courts:
		canvas.draw_colored_polygon(c["poly"], c["col"])

	for b in _cached_buildings:
		canvas.draw_colored_polygon(b["poly"], b["col"])

	canvas.draw_string(ThemeDB.fallback_font, Vector2(size.x - 18, 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.95, 0.9))

func _draw() -> void:
	if campus_data.is_empty():
		return
	if _cached_size != size:
		_rebuild_cache()
		if _static_layer:
			_static_layer.queue_redraw()

	for poi in _cached_pois:
		var mp: Vector2 = poi["mp"]
		var is_vis := visited_pois.has(poi["id"])
		var pcol := Color("#2F9E41") if is_vis else Color("#F5C43D")
		draw_circle(mp, 4.5, pcol)
		draw_arc(mp, 5.5, 0.0, TAU, 16, Color.WHITE, 1.2)

	var pp := _world_to_map(player_pos.x, player_pos.z)
	var fwd := Vector2(-sin(player_yaw), -cos(player_yaw)).normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var tip := pp + fwd * 8.0
	var left_pt := pp - fwd * 5.0 - right * 4.5
	var right_pt := pp - fwd * 5.0 + right * 4.5
	_arrow_poly[0] = tip; _arrow_poly[1] = right_pt; _arrow_poly[2] = left_pt
	_arrow_line[0] = tip; _arrow_line[1] = right_pt; _arrow_line[2] = left_pt; _arrow_line[3] = tip
	var arrow_col := Color("#38BDF8") if is_drone else Color("#CD191E")
	draw_colored_polygon(_arrow_poly, arrow_col)
	draw_polyline(_arrow_line, Color.WHITE, 1.2)
