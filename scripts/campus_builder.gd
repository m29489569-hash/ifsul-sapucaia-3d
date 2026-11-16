extends RefCounted

const MaterialsLib = preload("res://scripts/materials.gd")

var mats := MaterialsLib.new()
var poi_nodes: Array[Area3D] = []
var night_lights: Array[OmniLight3D] = []
var lamp_mat: StandardMaterial3D
var win_mat: StandardMaterial3D
var building_polys: Array = []
var tree_mmi_list: Array[MultiMeshInstance3D] = []
var full_tree_count: int = 0

func build(root: Node3D, data: Dictionary) -> void:
	poi_nodes.clear()
	night_lights.clear()
	building_polys.clear()
	tree_mmi_list.clear()
	full_tree_count = 0
	lamp_mat = mats.get_material("lamp_glow")
	win_mat = mats.get_material("glass")

	_build_ground(root)
	_build_streets(root, data.get("streets", []))
	_build_campus_pad(root, data.get("perimeter", []))
	_build_perimeter_walls(root, data.get("perimeter", []), data.get("gates", []))
	_build_parking_lots(root, data.get("parking_lots", []))
	_build_paths(root, data.get("footways", []), "concrete", 0.036, Color("#CBC6BC"))
	_build_paths(root, data.get("driveways", []), "asphalt", 0.023, Color("#323539"))
	_build_courts(root, data.get("courts", []))
	_build_buildings(root, data.get("buildings", []))
	_build_landmarks(root, data)
	_build_entrance_signage(root, data)
	_build_vegetation_and_props(root, data)
	_build_pois(root, data.get("pois", []))

func _build_ground(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(560.0, 2.0, 740.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)

	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(560.0, 740.0)
	mi.mesh = plane
	mi.material_override = mats.get_material("grass", Color("#476F38"))
	body.add_child(mi)
	root.add_child(body)

func _build_campus_pad(root: Node3D, perim: Array) -> void:
	var pts := _to_vec2_array(perim)
	if pts.size() < 3:
		return
	var mesh := _extrude_polygon_mesh(pts, 0.015, false)
	var mi := MeshInstance3D.new()
	mi.name = "CampusGroundPad"
	mi.mesh = mesh
	mi.material_override = mats.get_material("grass", Color("#4E803E"))
	root.add_child(mi)

	# Central paved civic courtyard around entrance, admin & auditorium
	var plaza_pts := PackedVector2Array([
		Vector2(-69.5, -2.0), Vector2(18.0, -12.0), Vector2(22.0, 44.0), Vector2(-64.5, 26.5)
	])
	var plaza_mi := MeshInstance3D.new()
	plaza_mi.name = "CentralPlaza"
	plaza_mi.mesh = _extrude_polygon_mesh(plaza_pts, 0.018, false)
	plaza_mi.material_override = mats.get_material("concrete", Color("#C8C3B9"))
	root.add_child(plaza_mi)

	# Inner courtyard tiled floor (05_central_courtyard) + Bloco Adm atrium floor + North soccer pitch lines
	var inner_pts := PackedVector2Array([
		Vector2(-6.0, -7.0), Vector2(28.0, -12.0), Vector2(34.0, 26.0), Vector2(4.0, 22.0)
	])
	var inner_mi := MeshInstance3D.new()
	inner_mi.name = "InnerCourtyardTile"
	inner_mi.mesh = _extrude_polygon_mesh(inner_pts, 0.025, false)
	inner_mi.material_override = mats.get_material("tile", Color("#CFC9BE"))
	root.add_child(inner_mi)

	var line_mat := mats.get_material("line_white")
	_add_court_line(root, Vector3(-10.0, 0.028, -148.0), Vector3(44.0, 0.01, 0.16), line_mat)
	_add_court_line(root, Vector3(-10.0, 0.028, -118.0), Vector3(44.0, 0.01, 0.16), line_mat)
	_add_court_line(root, Vector3(-32.0, 0.028, -133.0), Vector3(0.16, 0.01, 30.0), line_mat)
	_add_court_line(root, Vector3(12.0, 0.028, -133.0), Vector3(0.16, 0.01, 30.0), line_mat)
	_add_court_line(root, Vector3(-10.0, 0.028, -133.0), Vector3(0.16, 0.01, 30.0), line_mat)

func _build_streets(root: Node3D, streets: Array) -> void:
	var road_mat := mats.get_material("asphalt", Color("#323539"))
	var walk_mat := mats.get_material("sidewalk", Color("#BDB9B0"))
	var line_mat := mats.get_material("line_white")
	var st_root := Node3D.new()
	st_root.name = "Streets"
	root.add_child(st_root)

	# Pass 1: all sidewalks below asphalt; Pass 2: all asphalt; Pass 3: dashed centerlines on top
	for s in streets:
		var pts: Array = s.get("points", [])
		var w := float(s.get("width", 8.0))
		_add_polyline_ribbon(st_root, pts, w + 3.2, 0.014, walk_mat, false, 0.4)
	for s in streets:
		var pts: Array = s.get("points", [])
		var w := float(s.get("width", 8.0))
		_add_polyline_ribbon(st_root, pts, w, 0.022, road_mat, false, 0.4)

	# Paved median crossover openings matching real Av. Copacabana intersections
	var slope := 0.160
	var bou_ang := atan2(slope, 1.0)
	var crossover_spans := [
		[-150.0, 9.0],
		[-119.5, 9.0],
		[16.8, 16.0],
		[184.0, 10.0],
	]
	for cs in crossover_spans:
		var cz := float(cs[0])
		var clen := float(cs[1])
		var cx := -80.25 + (cz - 13.0) * slope
		var pad := MeshInstance3D.new()
		var pbox := BoxMesh.new()
		pbox.size = Vector3(14.0, 0.02, clen)
		pad.mesh = pbox
		pad.position = Vector3(cx, 0.022, cz)
		pad.rotation.y = bou_ang
		pad.material_override = road_mat
		st_root.add_child(pad)

	for s in streets:
		var pts: Array = s.get("points", [])
		_add_polyline_ribbon(st_root, pts, 0.16, 0.036, line_mat, true, 0.0)

	# Vegetated central median islands (canteiro central) along Av. Copacabana
	var curb_mat := mats.get_material("wall", Color("#ECEAE4"))
	var grass_mat := mats.get_material("grass", Color("#49873A"))
	var shrub_mats: Array[Material] = [
		mats.get_material("wall", Color("#3A7D2C")),
		mats.get_material("wall", Color("#5B9E3E")),
		mats.get_material("wall", Color("#D94E73")),
		mats.get_material("wall", Color("#EAB308")),
	]
	var curb_w := 4.5
	var grass_w := 3.9
	var curb_r := curb_w * 0.5
	var grass_r := grass_w * 0.5
	var cos_b := cos(bou_ang)
	var sin_b := sin(bou_ang)
	var median_spans := [
		[-142.0, -124.0],
		[-115.0, 9.0],
		[24.5, 176.0],
	]
	for span in median_spans:
		var z0 := float(span[0])
		var z1 := float(span[1])
		var seg_len := (z1 - z0) / cos_b
		var body_len := seg_len - curb_w
		if body_len <= 0.5:
			continue
		var z_mid := (z0 + z1) * 0.5
		var x_mid := -80.25 + (z_mid - 13.0) * slope
		var m_node := Node3D.new()
		m_node.position = Vector3(x_mid, 0.0, z_mid)
		m_node.rotation.y = bou_ang
		st_root.add_child(m_node)

		_add_court_line(m_node, Vector3(0.0, 0.08, 0.0), Vector3(curb_w, 0.16, body_len), curb_mat)
		_add_court_line(m_node, Vector3(0.0, 0.09, 0.0), Vector3(grass_w, 0.18, body_len), grass_mat)

		var end_off := body_len * 0.5
		for sgn in [-1.0, 1.0]:
			var cap_c := MeshInstance3D.new()
			var cc_m := CylinderMesh.new()
			cc_m.top_radius = curb_r; cc_m.bottom_radius = curb_r; cc_m.height = 0.16; cc_m.radial_segments = 16
			cap_c.mesh = cc_m
			cap_c.position = Vector3(0.0, 0.08, sgn * end_off)
			cap_c.material_override = curb_mat
			m_node.add_child(cap_c)

			var cap_g := MeshInstance3D.new()
			var cg_m := CylinderMesh.new()
			cg_m.top_radius = grass_r; cg_m.bottom_radius = grass_r; cg_m.height = 0.18; cg_m.radial_segments = 16
			cap_g.mesh = cg_m
			cap_g.position = Vector3(0.0, 0.09, sgn * end_off)
			cap_g.material_override = grass_mat
			m_node.add_child(cap_g)

		var shrub_n := int((seg_len - 4.0) / 6.0)
		for si in range(shrub_n + 1):
			var sz := -end_off + 1.0 + float(si) * 6.0
			if sz > end_off - 0.5:
				break
			var sh := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.55; sm.height = 0.78; sm.radial_segments = 8; sm.rings = 5
			sh.mesh = sm
			sh.position = Vector3(0.0 if si % 2 == 0 else (0.55 if si % 4 == 1 else -0.55), 0.45, sz)
			var mat_idx := (si % 2) if si % 3 != 2 else (2 if si % 6 == 2 else 3)
			sh.material_override = shrub_mats[mat_idx]
			m_node.add_child(sh)
		var _unused := sin_b

func _build_paths(root: Node3D, paths: Array, mat_key: String, y_height: float, tint: Color) -> void:
	var mat := mats.get_material(mat_key, tint)
	var p_root := Node3D.new()
	p_root.name = "Paths_" + mat_key
	root.add_child(p_root)
	for p in paths:
		_add_polyline_ribbon(p_root, p.get("points", []), float(p.get("width", 2.5)), y_height, mat, false)

func _is_in_copacabana_junction(wp: Vector3) -> bool:
	if wp.x > -42.0:
		return false
	for zj: float in [-150.0, -132.0, -119.5, -80.0, -28.0, 16.8, 185.0]:
		var tol := 9.5 if absf(zj - 16.8) < 1.0 else (6.8 if zj < -140.0 or zj > 180.0 else 5.5)
		if absf(wp.z - zj) < tol:
			return true
	return false

func _add_polyline_ribbon(parent: Node3D, pts: Array, width: float, y: float, mat: Material, dashed: bool, end_pad: float = -1.0) -> void:
	if pts.size() < 2:
		return
	var pad := end_pad if end_pad >= 0.0 else width * 0.35
	for i in range(pts.size() - 1):
		var a := Vector3(float(pts[i][0]), 0.0, float(pts[i][1]))
		var b := Vector3(float(pts[i + 1][0]), 0.0, float(pts[i + 1][1]))
		var seg := b - a
		var length := seg.length()
		if length < 0.2:
			continue
		var angle := atan2(seg.x, seg.z)
		if dashed:
			var step := 4.5
			var n := int(length / step)
			for k in range(n):
				var t := (k + 0.5) / maxf(1.0, float(n))
				var wp := a.lerp(b, t)
				if _is_in_copacabana_junction(wp):
					continue
				var mi := MeshInstance3D.new()
				var q := BoxMesh.new()
				q.size = Vector3(width, 0.012, 2.0)
				mi.mesh = q
				mi.material_override = mat
				mi.position = wp + Vector3(0.0, y, 0.0)
				mi.rotation.y = angle
				parent.add_child(mi)
		else:
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(width, 0.02, length + pad)
			mi.mesh = box
			mi.material_override = mat
			mi.position = (a + b) * 0.5 + Vector3(0.0, y, 0.0)
			mi.rotation.y = angle
			parent.add_child(mi)

func _build_perimeter_walls(root: Node3D, perim: Array, gates: Array) -> void:
	if perim.size() < 3:
		return
	var wall_mat := mats.get_material("concrete", Color("#DDD8CE"))
	var rail_mat := mats.get_material("metal", Color("#2F9E41"))
	var wall_root := Node3D.new()
	wall_root.name = "PerimeterWalls"
	root.add_child(wall_root)

	for i in range(perim.size()):
		var p1 := Vector2(float(perim[i][0]), float(perim[i][1]))
		var nxt: Array = perim[(i + 1) % perim.size()]
		var p2 := Vector2(float(nxt[0]), float(nxt[1]))
		if _is_gate_segment(p1, p2, gates):
			continue
		var diff := p2 - p1
		var length := diff.length()
		if length < 1.0:
			continue
		var is_front := (p1.x < -55.0 and p2.x < -55.0)
		var h := 1.1 if is_front else 2.2
		var body := StaticBody3D.new()
		body.position = Vector3((p1.x + p2.x) * 0.5, h * 0.5, (p1.y + p2.y) * 0.5)
		body.rotation.y = atan2(diff.x, diff.y)
		var col := CollisionShape3D.new()
		var cbox := BoxShape3D.new()
		cbox.size = Vector3(0.32, 2.3, length)
		col.shape = cbox
		body.add_child(col)

		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.28, h, length)
		mi.mesh = mesh
		mi.material_override = wall_mat
		body.add_child(mi)

		if is_front:
			var rail := MeshInstance3D.new()
			var rmesh := BoxMesh.new()
			rmesh.size = Vector3(0.10, 1.0, length)
			rail.mesh = rmesh
			rail.position = Vector3(0.0, h * 0.5 + 0.5, 0.0)
			rail.material_override = rail_mat
			body.add_child(rail)
		wall_root.add_child(body)

func _is_gate_segment(p1: Vector2, p2: Vector2, gates: Array) -> bool:
	var mid := (p1 + p2) * 0.5
	for g in gates:
		var gp1 := Vector2(float(g["p1"][0]), float(g["p1"][1]))
		var gp2 := Vector2(float(g["p2"][0]), float(g["p2"][1]))
		var gmid := (gp1 + gp2) * 0.5
		if mid.distance_to(gmid) < 12.0:
			return true
	return false

func _build_buildings(root: Node3D, buildings: Array) -> void:
	var b_root := Node3D.new()
	b_root.name = "Buildings"
	root.add_child(b_root)

	for b in buildings:
		var poly := _to_vec2_array(b.get("polygon", []))
		if poly.size() < 3:
			continue
		building_polys.append(poly)
		var h := float(b.get("height_m", 4.5))
		var floors := int(b.get("floors", 1))
		var col_wall := Color(b.get("color", "#EAE6DF"))
		var col_trim := Color(b.get("trim_color", "#2F9E41"))
		var b_node := Node3D.new()
		b_node.name = "Bldg_" + String(b.get("id", "b"))
		b_root.add_child(b_node)

		if b.has("courtyard_inset"):
			_build_courtyard_building(b_node, poly, h, float(b["courtyard_inset"]), col_wall, col_trim, b)
		else:
			_add_building_volume(b_node, poly, h, col_wall, col_trim, floors, bool(b.get("has_windows", true)), b)

		var sign_text := String(b.get("sign_text", ""))
		if not sign_text.is_empty():
			_add_building_sign(b_node, poly, h, sign_text, col_trim)

func _build_courtyard_building(parent: Node3D, poly: PackedVector2Array, h: float, inset: float, col_wall: Color, col_trim: Color, b: Dictionary) -> void:
	var c := _poly_centroid(poly)
	var inner := PackedVector2Array()
	for p in poly:
		var dir := (c - p).normalized()
		inner.append(p + dir * inset)
	# Build 4 outer wings cleanly from consecutive edges between outer & inner quad
	for i in range(poly.size()):
		var j := (i + 1) % poly.size()
		var wing := PackedVector2Array([poly[i], poly[j], inner[j], inner[i]])
		_add_building_volume(parent, wing, h, col_wall, col_trim, int(b.get("floors", 2)), true, b)

func _add_building_volume(parent: Node3D, poly: PackedVector2Array, h: float, col_wall: Color, col_trim: Color, floors: int, has_windows: bool, b: Dictionary) -> void:
	var wall_mat := mats.get_material("wall", col_wall)
	var roof_mat := mats.get_material("concrete", Color("#6B6E73"))
	var trim_mat := mats.get_material("ifsul_green") if col_trim == Color("#2F9E41") else (mats.get_material("ifsul_red") if col_trim == Color("#CD191E") else mats.get_material("wall", col_trim))
	var wmat := win_mat
	var btype := String(b.get("type", ""))
	if btype in ["auditorium", "library", "student_center", "workshop"]:
		roof_mat = mats.get_material("wall", Color("#E6E8EC")) if btype != "workshop" else mats.get_material("concrete", Color("#9EA4AB"))

	if btype == "corridor":
		# Open covered walkway on concrete pillars (passable on foot!)
		var canopy := StaticBody3D.new()
		var cmesh := _extrude_polygon_mesh(poly, 0.35, true)
		var cmi := MeshInstance3D.new()
		cmi.mesh = cmesh
		cmi.position.y = h - 0.35
		cmi.material_override = roof_mat
		canopy.add_child(cmi)
		var ccol := CollisionShape3D.new()
		ccol.shape = cmesh.create_trimesh_shape()
		ccol.position.y = h - 0.35
		canopy.add_child(ccol)
		parent.add_child(canopy)
		for v in poly:
			var pmi := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.14; pm.bottom_radius = 0.16; pm.height = h - 0.35
			pmi.mesh = pm
			pmi.position = Vector3(v.x, (h - 0.35) * 0.5, v.y)
			pmi.material_override = mats.get_material("concrete", Color("#DEDAD2"))
			parent.add_child(pmi)
		return

	var body := StaticBody3D.new()
	var mesh := _extrude_polygon_mesh(poly, h, true)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = wall_mat
	body.add_child(mi)

	var col_shape := CollisionShape3D.new()
	col_shape.shape = mesh.create_trimesh_shape()
	body.add_child(col_shape)
	parent.add_child(body)

	# Roof parapet cap + industrial shed skylights & library/student-center octagonal dome (MSS-00.442 / MSS-00.2609)
	var cap := MeshInstance3D.new()
	cap.mesh = _extrude_polygon_mesh(poly, 0.25, false)
	cap.position.y = h
	cap.material_override = roof_mat
	parent.add_child(cap)
	if btype in ["academic", "workshop"] and poly.size() >= 4:
		var c2 := _poly_centroid(poly)
		var rib_mat := mats.get_material("wall", Color("#EBEEF2")) if btype == "workshop" else mats.get_material("metal", Color("#5B6770"))
		var span := 10.5 if btype == "workshop" else 5.5
		for k in range(-3, 4):
			var rc := Vector2(c2.x, c2.y + k * 4.2)
			if not (Geometry2D.is_point_in_polygon(rc + Vector2(-span, 0), poly) and Geometry2D.is_point_in_polygon(rc + Vector2(span, 0), poly)):
				continue
			var rmi := MeshInstance3D.new()
			var rbox := BoxMesh.new()
			rbox.size = Vector3(span * 2.0, 0.35 if btype == "workshop" else 0.16, 1.55)
			rmi.mesh = rbox
			rmi.material_override = rib_mat
			rmi.position = Vector3(rc.x, h + 0.34, rc.y)
			rmi.rotation.y = deg_to_rad(8.7)
			parent.add_child(rmi)
	elif btype in ["library", "student_center"]:
		var c2 := _poly_centroid(poly)
		var dome := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = 2.6; dm.bottom_radius = 4.2; dm.height = 1.4; dm.radial_segments = 8
		dome.mesh = dm
		dome.position = Vector3(c2.x, h + 0.8, c2.y)
		dome.material_override = mats.get_material("wall", Color("#D9E4F0"))
		parent.add_child(dome)

	# Architectural fascia trim + ribbon windows along long outer edges
	var cw := _ensure_cw_screen(poly)
	for i in range(cw.size()):
		var p1 := cw[i]
		var p2 := cw[(i + 1) % cw.size()]
		var edge := p2 - p1
		var len := edge.length()
		if len < 3.5:
			continue
		var mid := (p1 + p2) * 0.5
		var angle := atan2(edge.x, edge.y)
		var out_dir := Vector2(edge.y, -edge.x).normalized()

		# Institutional top fascia band + white structural pilasters on brick walls
		var band := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, 0.52, len)
		band.mesh = bm
		band.material_override = trim_mat
		band.position = Vector3(mid.x + out_dir.x * 0.08, h - 0.32, mid.y + out_dir.y * 0.08)
		band.rotation.y = angle
		parent.add_child(band)

		if btype in ["admin", "academic", "lab", "sports"] and len >= 6.5:
			var pil_count := int(len / 7.0) + 1
			var pil_mat := mats.get_material("wall", Color("#F2F1ED"))
			for pi in range(pil_count):
				var pt := lerpf(-0.46, 0.46, float(pi) / maxf(1.0, float(pil_count - 1)))
				var along_p := edge.normalized() * (pt * len)
				var pil_m := MeshInstance3D.new()
				var pbm := BoxMesh.new()
				pbm.size = Vector3(0.18, h, 0.34)
				pil_m.mesh = pbm
				pil_m.material_override = pil_mat
				pil_m.position = Vector3(mid.x + along_p.x + out_dir.x * 0.09, h * 0.5, mid.y + along_p.y + out_dir.y * 0.09)
				pil_m.rotation.y = angle
				parent.add_child(pil_m)

		# Auditório iconic terracotta wall + clerestory ribbon windows & white portico matching MSS-00.223 / MSS-00.2155
		if String(b.get("type", "")) == "auditorium" and len > 8.0:
			var panel := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.12, h * 0.60, len * 0.88)
			panel.mesh = pm
			panel.material_override = mats.get_material("wall", Color("#BA715C"))
			panel.position = Vector3(mid.x + out_dir.x * 0.07, h * 0.31, mid.y + out_dir.y * 0.07)
			panel.rotation.y = angle
			parent.add_child(panel)

			var clere := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(0.10, 1.05, len * 0.88)
			clere.mesh = cm
			clere.material_override = wmat
			clere.position = Vector3(mid.x + out_dir.x * 0.07, h * 0.72, mid.y + out_dir.y * 0.07)
			clere.rotation.y = angle
			parent.add_child(clere)

			var mull_mat := mats.get_material("metal", Color("#23272A"))
			for m_i in range(9):
				var t := lerpf(-0.42, 0.42, float(m_i) / 8.0)
				var along := edge.normalized() * (t * len)
				var mull := MeshInstance3D.new()
				var mm := BoxMesh.new()
				mm.size = Vector3(0.14, 1.12, 0.10)
				mull.mesh = mm
				mull.material_override = mull_mat
				mull.position = Vector3(mid.x + along.x + out_dir.x * 0.08, h * 0.72, mid.y + along.y + out_dir.y * 0.08)
				mull.rotation.y = angle
				parent.add_child(mull)

		# Floor window strips, vertical mullions, AC split units & 2.1m entrance door on longest facade
		if has_windows:
			var mull_mat2 := mats.get_material("metal", Color("#272B30"))
			var ac_mat := mats.get_material("wall", Color("#F0F2F5"))
			for fl in range(floors):
				var wy := 1.9 + fl * (h / maxf(1.0, float(floors)))
				if wy + 0.8 > h - 0.5:
					continue
				var win := MeshInstance3D.new()
				var wm := BoxMesh.new()
				wm.size = Vector3(0.08, 1.35, len * 0.78)
				win.mesh = wm
				win.material_override = wmat
				win.position = Vector3(mid.x + out_dir.x * 0.06, wy, mid.y + out_dir.y * 0.06)
				win.rotation.y = angle
				parent.add_child(win)
				if len >= 6.0:
					var m_cnt := mini(8, int(len / 3.4))
					for mi_w in range(m_cnt):
						var mt := lerpf(-0.36, 0.36, float(mi_w) / maxf(1.0, float(m_cnt - 1)))
						var along_m := edge.normalized() * (mt * len)
						var mm_w := MeshInstance3D.new()
						var mb_w := BoxMesh.new()
						mb_w.size = Vector3(0.11, 1.38, 0.08)
						mm_w.mesh = mb_w
						mm_w.material_override = mull_mat2
						mm_w.position = Vector3(mid.x + along_m.x + out_dir.x * 0.07, wy, mid.y + along_m.y + out_dir.y * 0.07)
						mm_w.rotation.y = angle
						parent.add_child(mm_w)
				if fl == 1 and len >= 10.0:
					for ac_t: float in [-0.24, 0.24]:
						var along_ac: Vector2 = edge.normalized() * (ac_t * len)
						var ac := MeshInstance3D.new()
						var acb := BoxMesh.new()
						acb.size = Vector3(0.26, 0.45, 0.68)
						ac.mesh = acb
						ac.material_override = ac_mat
						ac.position = Vector3(mid.x + along_ac.x + out_dir.x * 0.14, wy - 0.92, mid.y + along_ac.y + out_dir.y * 0.14)
						ac.rotation.y = angle
						parent.add_child(ac)

		if i == 0 and len >= 5.0 and String(b.get("type", "")) != "corridor":
			var door := MeshInstance3D.new()
			var dm := BoxMesh.new()
			dm.size = Vector3(0.14, 2.1, 2.4) # 2.1m door scale anchor
			door.mesh = dm
			door.material_override = mats.get_material("metal", Color("#223228"))
			door.position = Vector3(mid.x + out_dir.x * 0.09, 1.05, mid.y + out_dir.y * 0.09)
			door.rotation.y = angle
			parent.add_child(door)

func _add_building_sign(parent: Node3D, poly: PackedVector2Array, h: float, text: String, trim_col: Color) -> void:
	var c := _poly_centroid(poly)
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 46
	lbl.pixel_size = 0.0095
	lbl.modulate = Color.WHITE
	lbl.outline_modulate = trim_col.darkened(0.55)
	lbl.outline_size = 10
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = false
	lbl.position = Vector3(c.x, h + 1.15, c.y)
	parent.add_child(lbl)

	if text == "BIBLIOTECA":
		var plaque := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(4.2, 0.85, 0.14)
		plaque.mesh = pm
		plaque.material_override = mats.get_material("ifsul_green")
		plaque.position = Vector3(20.6, 3.05, -78.8)
		plaque.rotation.y = deg_to_rad(-52.0)
		parent.add_child(plaque)
		var flbl := Label3D.new()
		flbl.text = "BIBLIOTECA • IFSul"
		flbl.font_size = 42
		flbl.pixel_size = 0.008
		flbl.double_sided = false
		flbl.modulate = Color.WHITE
		flbl.position = Vector3(0.0, 0.0, 0.09)
		plaque.add_child(flbl)

func _build_courts(root: Node3D, courts: Array) -> void:
	var c_root := Node3D.new()
	c_root.name = "SportsCourts"
	root.add_child(c_root)
	var line_mat := mats.get_material("line_white")
	var gym_roof_mat := StandardMaterial3D.new()
	gym_roof_mat.albedo_color = Color("#DCE1E6")
	gym_roof_mat.metallic = 0.35
	gym_roof_mat.roughness = 0.42
	var blue_truss_mat := StandardMaterial3D.new()
	blue_truss_mat.albedo_color = Color("#1D63B8")
	blue_truss_mat.metallic = 0.45
	blue_truss_mat.roughness = 0.38
	var fence_mat := StandardMaterial3D.new()
	fence_mat.albedo_color = Color(0.75, 0.80, 0.85, 0.24)
	fence_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fence_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var curb_mat := mats.get_material("wall", Color("#EAE8E2"))

	for c in courts:
		var center: Array = c.get("center", [0, 0])
		var sz: Array = c.get("size", [20, 40])
		var rot := deg_to_rad(float(c.get("rot_deg", 0.0)))
		var w := float(sz[0])
		var d := float(sz[1])
		var node := Node3D.new()
		node.name = "Court_" + String(c.get("id", "c"))
		node.position = Vector3(float(center[0]), 0.0, float(center[1]))
		node.rotation.y = rot
		c_root.add_child(node)

		# Outer border + inner playing court
		var border_mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, 0.04, d)
		border_mi.mesh = bm
		border_mi.position.y = 0.02
		border_mi.material_override = mats.get_material("court_red", Color(c.get("border_color", "#B85D43")))
		node.add_child(border_mi)

		var play_mi := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(w * 0.84, 0.05, d * 0.86)
		play_mi.mesh = pm
		play_mi.position.y = 0.028
		play_mi.material_override = mats.get_material("court_blue", Color(c.get("surface_color", "#255B8A")))
		node.add_child(play_mi)

		# Court painted markings (perimeter + center line + center circle)
		var pw := w * 0.80
		var pd := d * 0.82
		_add_court_line(node, Vector3(0, 0.058, pd * 0.5), Vector3(pw, 0.01, 0.14), line_mat)
		_add_court_line(node, Vector3(0, 0.058, -pd * 0.5), Vector3(pw, 0.01, 0.14), line_mat)
		_add_court_line(node, Vector3(pw * 0.5, 0.058, 0), Vector3(0.14, 0.01, pd), line_mat)
		_add_court_line(node, Vector3(-pw * 0.5, 0.058, 0), Vector3(0.14, 0.01, pd), line_mat)
		if String(c.get("sport", "")) == "multi":
			_add_court_line(node, Vector3(0, 0.058, 0), Vector3(pw, 0.01, 0.14), line_mat)
			var ring := MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = 2.85
			tor.outer_radius = 3.0
			ring.mesh = tor
			ring.position = Vector3(0, 0.055, 0)
			ring.scale = Vector3(1.0, 0.15, 1.0)
			ring.material_override = line_mat
			node.add_child(ring)
			# Futsal goals & basketball hoops
			var goal_mat := mats.get_material("metal", Color("#F0F2F5"))
			var hoop_mat := mats.get_material("ifsul_red")
			for end_s: float in [-1.0, 1.0]:
				var gz: float = end_s * (pd * 0.48)
				_add_court_line(node, Vector3(-1.5, 1.05, gz), Vector3(0.10, 2.1, 0.10), goal_mat)
				_add_court_line(node, Vector3(1.5, 1.05, gz), Vector3(0.10, 2.1, 0.10), goal_mat)
				_add_court_line(node, Vector3(0.0, 2.1, gz), Vector3(3.1, 0.10, 0.10), goal_mat)
				_add_court_line(node, Vector3(0.0, 3.05, gz - end_s * 0.6), Vector3(1.8, 1.1, 0.08), line_mat)
				_add_court_line(node, Vector3(0.0, 2.75, gz - end_s * 0.85), Vector3(0.45, 0.06, 0.45), hoop_mat)
		elif String(c.get("sport", "")) == "volleyball":
			var post_mat := mats.get_material("metal", Color("#E2E8F0"))
			_add_court_line(node, Vector3(0, 1.25, -pd * 0.52), Vector3(0.12, 2.5, 0.12), post_mat)
			_add_court_line(node, Vector3(0, 1.25, pd * 0.52), Vector3(0.12, 2.5, 0.12), post_mat)
			_add_court_line(node, Vector3(0, 2.0, 0), Vector3(0.04, 0.95, pd * 1.02), mats.get_material("glass"))
			# Perimeter wire fence & posts on Volleyball court (MSS-00.2485)
			for f_side in [-1.0, 1.0]:
				_add_court_line(node, Vector3(0.0, 1.6, f_side * (d * 0.52)), Vector3(w, 3.2, 0.04), fence_mat)
			_add_court_line(node, Vector3(-w * 0.52, 1.6, 0.0), Vector3(0.04, 3.2, d), fence_mat)

		# Covered gymnasium blue steel trusses, silver roof, curb & wire fence (MSS-00.446 / MSS-00.2607)
		if bool(c.get("covered", false)):
			var roof_h := 8.0
			for sx: float in [-w * 0.48, w * 0.48]:
				for i in range(6):
					var pz := lerpf(-d * 0.46, d * 0.46, float(i) / 5.0)
					var pbody := StaticBody3D.new()
					pbody.position = Vector3(sx, roof_h * 0.5, pz)
					var pc := CollisionShape3D.new()
					var pbox := BoxShape3D.new()
					pbox.size = Vector3(0.42, roof_h, 0.42)
					pc.shape = pbox
					pbody.add_child(pc)
					# Twin vertical blue steel truss legs
					for sub_z in [-0.18, 0.18]:
						var pmi := MeshInstance3D.new()
						var pmesh := BoxMesh.new()
						pmesh.size = Vector3(0.32, roof_h, 0.14)
						pmi.mesh = pmesh
						pmi.position.z = sub_z
						pmi.material_override = blue_truss_mat
						pbody.add_child(pmi)
					node.add_child(pbody)
				# Longitudinal blue eaves truss girder
				_add_court_line(node, Vector3(sx, roof_h - 0.3, 0.0), Vector3(0.28, 0.65, d * 0.96), blue_truss_mat)
				# Low white concrete curb + wire mesh fence along sides (leaving gap near POI on east side)
				_add_court_line(node, Vector3(sx, 0.3, 0.0), Vector3(0.26, 0.6, d * 0.96), curb_mat)
				if sx < 0.0:
					_add_court_line(node, Vector3(sx, 2.4, 0.0), Vector3(0.04, 3.6, d * 0.96), fence_mat)
				else:
					_add_court_line(node, Vector3(sx, 2.4, -d * 0.25), Vector3(0.04, 3.6, d * 0.44), fence_mat)
					_add_court_line(node, Vector3(sx, 2.4, d * 0.30), Vector3(0.04, 3.6, d * 0.36), fence_mat)

			# Transverse blue roof trusses + pitched bright silver metal roof panels
			for i in range(6):
				var pz := lerpf(-d * 0.46, d * 0.46, float(i) / 5.0)
				_add_court_line(node, Vector3(0.0, roof_h - 0.18, pz), Vector3(w * 0.94, 0.48, 0.18), blue_truss_mat)
			for side: float in [-1.0, 1.0]:
				var rmi := MeshInstance3D.new()
				var rbox := BoxMesh.new()
				rbox.size = Vector3(w * 0.54, 0.22, d + 1.5)
				rmi.mesh = rbox
				rmi.material_override = gym_roof_mat
				rmi.position = Vector3(side * w * 0.25, roof_h + 1.05, 0.0)
				rmi.rotation.z = -side * deg_to_rad(11.0)
				node.add_child(rmi)
			# South & North blue fence + white entrance portico frame (MSS-00.446)
			_add_court_line(node, Vector3(0.0, 0.3, d * 0.49), Vector3(w * 0.96, 0.6, 0.26), curb_mat)
			_add_court_line(node, Vector3(0.0, 2.4, d * 0.49), Vector3(w * 0.96, 3.6, 0.04), fence_mat)
			_add_court_line(node, Vector3(-w * 0.54, 2.0, -d * 0.45), Vector3(3.4, 3.8, 0.45), curb_mat)

func _add_court_line(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = sz
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)

func _build_parking_lots(root: Node3D, lots: Array) -> void:
	var p_root := Node3D.new()
	p_root.name = "ParkingLots"
	root.add_child(p_root)
	var asp := mats.get_material("asphalt", Color("#393C41"))
	var paver_asp := mats.get_material("concrete", Color("#8F8B85"))
	var line_mat := mats.get_material("line_white")
	var yellow_line_mat := mats.get_material("wall", Color("#EAB308"))

	for lot in lots:
		var is_front := (String(lot.get("id", "")) == "estacionamento_principal")
		var poly := _to_vec2_array(lot.get("polygon", []))
		if poly.size() >= 3:
			var mi := MeshInstance3D.new()
			mi.mesh = _extrude_polygon_mesh(poly, 0.03, false)
			mi.material_override = paver_asp if is_front else asp
			p_root.add_child(mi)

		# 2.5m x 5.0m parking bay markings (yellow in front lot per MSS-00.223)
		for row in lot.get("bay_rows", []):
			var start := Vector2(float(row["start"][0]), float(row["start"][1]))
			var count := int(row.get("count", 6))
			var step := float(row.get("step", 2.6))
			var ang := deg_to_rad(float(row.get("angle_deg", 8.7)))
			var dir := Vector2(cos(ang), -sin(ang))
			var bay_fwd := Vector2(sin(ang), cos(ang))
			for i in range(count + 1):
				var p := start + dir * (i * step) + bay_fwd * 2.5
				var lmi := MeshInstance3D.new()
				var lb := BoxMesh.new()
				lb.size = Vector3(0.12, 0.01, 5.0)
				lmi.mesh = lb
				lmi.material_override = yellow_line_mat if is_front else line_mat
				lmi.position = Vector3(p.x, 0.036, p.y)
				lmi.rotation.y = ang
				p_root.add_child(lmi)

func _build_landmarks(root: Node3D, data: Dictionary) -> void:
	var lm: Dictionary = data.get("landmarks", {})
	var wt: Dictionary = lm.get("water_tower", {})
	if not wt.is_empty():
		var pos_a: Array = wt["position"]
		var h := float(wt.get("height", 16.5))
		var r := float(wt.get("radius", 1.85))
		var body := StaticBody3D.new()
		body.name = "WaterTower"
		body.position = Vector3(float(pos_a[0]), h * 0.5, float(pos_a[2]))
		var col := CollisionShape3D.new()
		var cs := CylinderShape3D.new()
		cs.radius = r
		cs.height = h
		col.shape = cs
		body.add_child(col)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = h
		mi.mesh = cm
		mi.material_override = mats.get_material("wall", Color("#F0EEE9"))
		body.add_child(mi)
		# Metallic maintenance cage ladder along east side of water tower (MSS-00.223)
		var lad := MeshInstance3D.new()
		var lbox := BoxMesh.new()
		lbox.size = Vector3(0.55, h * 0.92, 0.55)
		lad.mesh = lbox
		lad.position = Vector3(r + 0.28, 0.0, 0.0)
		lad.material_override = mats.get_material("metal", Color("#CBD5E1"))
		body.add_child(lad)
		# Red/white mast atop water tower (matching MSS-00.266 photo)
		for seg in range(4):
			var mast := MeshInstance3D.new()
			var mm := CylinderMesh.new()
			mm.top_radius = 0.07
			mm.bottom_radius = 0.09
			mm.height = 1.8
			mast.mesh = mm
			mast.position.y = h * 0.5 + 0.9 + seg * 1.8
			mast.material_override = mats.get_material("ifsul_red") if seg % 2 == 0 else mats.get_material("line_white")
			body.add_child(mast)
		root.add_child(body)

	# White colonnade walkway + "Profissionais para o mundo." fascia & Auditório 3D IFSul Relief Logo + Portico (MSS-00.223)
	var col_node := Node3D.new()
	col_node.name = "ColonnadeAndAuditorioPortico"
	root.add_child(col_node)
	var white_mat := mats.get_material("wall", Color("#F3F2EE"))
	var c_start := Vector3(-31.5, 0.0, -7.2)
	var c_end := Vector3(-8.5, 0.0, 5.2)
	var c_vec := c_end - c_start
	var c_len := c_vec.length()
	var c_ang := atan2(c_vec.x, c_vec.z)
	var beam := MeshInstance3D.new()
	var bm_col := BoxMesh.new()
	bm_col.size = Vector3(2.4, 0.72, c_len)
	beam.mesh = bm_col
	beam.material_override = white_mat
	beam.position = (c_start + c_end) * 0.5 + Vector3(0.0, 3.65, 0.0)
	beam.rotation.y = c_ang
	col_node.add_child(beam)
	for ci in range(7):
		var cp := c_start.lerp(c_end, float(ci) / 6.0)
		var pil := MeshInstance3D.new()
		var pm_c := BoxMesh.new()
		pm_c.size = Vector3(0.35, 3.4, 0.35)
		pil.mesh = pm_c
		pil.material_override = white_mat
		pil.position = cp + Vector3(0.0, 1.7, 0.0)
		col_node.add_child(pil)
	var motto := Label3D.new()
	motto.text = "Educação Pública e Gratuita: Profissionais para o mundo."
	motto.font_size = 34
	motto.pixel_size = 0.0085
	motto.double_sided = false
	motto.modulate = Color("#1F3524")
	motto.position = (c_start + c_end) * 0.5 + Vector3(-1.25, 3.65, 0.65)
	motto.rotation.y = c_ang - PI * 0.5
	col_node.add_child(motto)

	# Auditório Pedro Kaizer West-facing Front Portico + Giant 3D Relief IFSul Logo + Mural (MSS-00.223)
	var aud_front := Node3D.new()
	aud_front.name = "AuditorioFrontPortico"
	aud_front.position = Vector3(-22.8, 0.0, 21.8)
	aud_front.rotation.y = deg_to_rad(-8.5)
	col_node.add_child(aud_front)

	# Open white portico canopy extending west over plaza edge
	var port_roof := MeshInstance3D.new()
	var prm := BoxMesh.new()
	prm.size = Vector3(6.8, 0.55, 13.5)
	port_roof.mesh = prm
	port_roof.material_override = white_mat
	port_roof.position = Vector3(-3.2, 6.25, 1.5)
	aud_front.add_child(port_roof)
	for pz in [-4.5, 7.6]:
		var pcol_m := MeshInstance3D.new()
		var pcm := BoxMesh.new()
		pcm.size = Vector3(0.55, 6.1, 0.55)
		pcol_m.mesh = pcm
		pcol_m.material_override = white_mat
		pcol_m.position = Vector3(-6.1, 3.05, pz)
		aud_front.add_child(pcol_m)

	# Giant 3D Relief IFSul Logo mounted on the west Auditório wall (x=-0.1, z=1.5..5.5)
	var relief_cells := [[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [0, 2], [1, 2], [2, 2], [0, 3], [1, 3]]
	for rc in relief_cells:
		var rmi := MeshInstance3D.new()
		if rc[0] == 0 and rc[1] == 0:
			var rcm := CylinderMesh.new()
			rcm.top_radius = 0.28; rcm.bottom_radius = 0.28; rcm.height = 0.16
			rmi.mesh = rcm
			rmi.rotation.z = PI * 0.5
			rmi.material_override = mats.get_material("ifsul_red")
		else:
			var rbm := BoxMesh.new()
			rbm.size = Vector3(0.16, 0.52, 0.52)
			rmi.mesh = rbm
			rmi.material_override = mats.get_material("ifsul_green")
		rmi.position = Vector3(-0.75, 5.1 - float(rc[1]) * 0.62, 1.5 + float(rc[0]) * 0.62)
		aud_front.add_child(rmi)
	var aud_logo_txt := Label3D.new()
	aud_logo_txt.text = "INSTITUTO FEDERAL\nSUL-RIO-GRANDENSE\nCâmpus Sapucaia do Sul"
	aud_logo_txt.font_size = 38
	aud_logo_txt.pixel_size = 0.0085
	aud_logo_txt.double_sided = false
	aud_logo_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	aud_logo_txt.modulate = Color("#1D2E20")
	aud_logo_txt.position = Vector3(-0.78, 3.85, 3.4)
	aud_logo_txt.rotation.y = -PI * 0.5
	aud_front.add_child(aud_logo_txt)

	# Student colorful mural on north-facing terrace wall of Auditório (visible from FlagPlaza!)
	var mural_bg := MeshInstance3D.new()
	var mbox := BoxMesh.new()
	mbox.size = Vector3(4.6, 2.2, 0.14)
	mural_bg.mesh = mbox
	mural_bg.material_override = mats.get_material("wall", Color("#F4F0E8"))
	mural_bg.position = Vector3(5.8, 2.3, -8.2)
	mural_bg.rotation.y = deg_to_rad(-16.0)
	aud_front.add_child(mural_bg)
	var mural_cols := [Color("#E11D48"), Color("#F59E0B"), Color("#2563EB"), Color("#16A34A"), Color("#9333EA")]
	for mi_c in range(5):
		var mp := MeshInstance3D.new()
		var mpb := BoxMesh.new()
		mpb.size = Vector3(0.75, 1.7, 0.04)
		mp.mesh = mpb
		mp.material_override = mats.get_material("wall", mural_cols[mi_c])
		mp.position = Vector3(-1.6 + mi_c * 0.8, 0.0, 0.08)
		mural_bg.add_child(mp)

	# Flagpoles + raised planter matching MSS-00.2155 reference photo
	var fp: Dictionary = lm.get("flag_plaza", {})
	if not fp.is_empty():
		var fpos: Array = fp["position"]
		var f_root := Node3D.new()
		f_root.name = "FlagPlaza"
		f_root.position = Vector3(float(fpos[0]), 0.0, float(fpos[2]))
		f_root.rotation.y = deg_to_rad(float(fp.get("rot_deg", 8.7)))
		root.add_child(f_root)

		var planter := StaticBody3D.new()
		var pcol := CollisionShape3D.new()
		var pbox := BoxShape3D.new()
		pbox.size = Vector3(7.0, 0.45, 2.6)
		pcol.shape = pbox
		pcol.position.y = 0.225
		planter.add_child(pcol)
		var pmi := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(7.0, 0.45, 2.6)
		pmi.mesh = pm
		pmi.position.y = 0.225
		pmi.material_override = mats.get_material("concrete", Color("#CBC6BC"))
		planter.add_child(pmi)
		# Flowers on raised planter (matching MSS-00.2155)
		var frng := RandomNumberGenerator.new()
		frng.seed = 2155
		for fx in range(12):
			var fl := MeshInstance3D.new()
			var fs := SphereMesh.new()
			fs.radius = 0.24
			fs.height = 0.36
			fl.mesh = fs
			fl.position = Vector3(-2.9 + fx * 0.52, 0.55, frng.randf_range(-0.7, 0.7))
			fl.material_override = mats.get_material("wall", Color("#DB4B7A") if fx % 2 == 0 else Color("#4C8E3B"))
			planter.add_child(fl)
		f_root.add_child(planter)

		var flag_colors := [Color("#009B3A"), Color("#D92525"), Color("#2F9E41"), Color("#1E55A0")]
		for i in range(4):
			var pole := MeshInstance3D.new()
			var cym := CylinderMesh.new()
			cym.top_radius = 0.05
			cym.bottom_radius = 0.07
			cym.height = 7.5
			pole.mesh = cym
			pole.position = Vector3(-2.4 + i * 1.6, 3.8, 0.0)
			pole.material_override = mats.get_material("metal", Color("#D8DCE0"))
			f_root.add_child(pole)

			var flag := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(1.15, 0.72, 0.04)
			flag.mesh = fm
			flag.position = Vector3(-2.4 + i * 1.6 + 0.6, 7.0, 0.0)
			flag.material_override = mats.get_material("wall", flag_colors[i])
			f_root.add_child(flag)

func _build_entrance_signage(root: Node3D, data: Dictionary) -> void:
	var sign_node := Node3D.new()
	sign_node.name = "EntranceSignage"
	sign_node.position = Vector3(-64.2, 0.0, 2.2)
	sign_node.rotation.y = deg_to_rad(8.7)
	root.add_child(sign_node)

	# Yellow entrance curb + open metal gate wings + iconic green payphones (MSS-00.266)
	var gate_root := Node3D.new()
	gate_root.position = Vector3(-63.2, 0.0, 17.5)
	gate_root.rotation.y = deg_to_rad(8.7)
	root.add_child(gate_root)
	var gate_mat := mats.get_material("metal", Color("#D8DCE0"))
	for gz in [-1.5, 7.2]:
		var wing := MeshInstance3D.new()
		var wm := BoxMesh.new()
		wm.size = Vector3(3.2, 1.9, 0.08)
		wing.mesh = wm
		wing.position = Vector3(1.6, 0.95, gz)
		wing.material_override = gate_mat
		gate_root.add_child(wing)
	var yellow_curb_mat := mats.get_material("wall", Color("#E8B923"))
	for c_spec in [[-8.0, 8.0], [8.8, 7.5]]:
		var curb := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(0.24, 0.15, float(c_spec[1]))
		curb.mesh = cb
		curb.position = Vector3(-2.2, 0.08, float(c_spec[0]))
		curb.material_override = yellow_curb_mat
		gate_root.add_child(curb)
	for oz in [-7.6, -6.5]:
		var orelhao := MeshInstance3D.new()
		var om := SphereMesh.new()
		om.radius = 0.36
		om.height = 0.8
		orelhao.mesh = om
		orelhao.position = Vector3(-1.2, 1.65, oz)
		orelhao.material_override = mats.get_material("ifsul_green")
		gate_root.add_child(orelhao)
		var opost := MeshInstance3D.new()
		var opm := CylinderMesh.new()
		opm.top_radius = 0.04; opm.bottom_radius = 0.05; opm.height = 1.6
		opost.mesh = opm
		opost.position = Vector3(-1.2, 0.8, oz)
		opost.material_override = gate_mat
		gate_root.add_child(opost)

	# White zebra crosswalks: 1) Gate entrance throat, 2) Av. Copacabana carriageways at median tip (z = 10.6)
	var cw_mat := mats.get_material("line_white")
	for cwi in range(7):
		_add_court_line(gate_root, Vector3(-2.0, 0.038, -2.7 + cwi * 0.9), Vector3(2.8, 0.012, 0.45), cw_mat)

	var bou_cw := Node3D.new()
	bou_cw.name = "CopacabanaCrosswalk"
	bou_cw.rotation.y = atan2(0.160, 1.0)
	var cw_z := 10.6
	bou_cw.position = Vector3(-80.25 + (cw_z - 13.0) * 0.160, 0.0, cw_z)
	root.add_child(bou_cw)
	for lane_x: float in [-6.15, 6.15]:
		for bi in range(7):
			var lx := lane_x - 2.85 + float(bi) * 0.95
			_add_court_line(bou_cw, Vector3(lx, 0.038, 0.0), Vector3(0.44, 0.012, 2.5), cw_mat)

	# Bicycle rack behind Guarita with parked bikes (MSS-00.444 / MSS-00.223)
	var bike_rack := Node3D.new()
	bike_rack.position = Vector3(-54.8, 0.0, 12.6)
	bike_rack.rotation.y = deg_to_rad(8.7)
	root.add_child(bike_rack)
	var dark_met := mats.get_material("metal", Color("#1F2937"))
	_add_court_line(bike_rack, Vector3(0.0, 0.25, 0.0), Vector3(0.10, 0.5, 4.4), dark_met)
	for bi in range(5):
		var bz := -1.6 + bi * 0.8
		for wx in [-0.45, 0.45]:
			var wmi := MeshInstance3D.new()
			var wtor := TorusMesh.new()
			wtor.inner_radius = 0.22; wtor.outer_radius = 0.28
			wmi.mesh = wtor
			wmi.position = Vector3(wx, 0.30, bz)
			wmi.rotation.x = PI * 0.5
			wmi.material_override = dark_met
			bike_rack.add_child(wmi)
		_add_court_line(bike_rack, Vector3(0.0, 0.62, bz), Vector3(0.95, 0.06, 0.05), mats.get_material("ifsul_red") if bi % 2 == 0 else mats.get_material("ifsul_green"))

	# Hedged green lawn with 3D topiary "IFSul" letters in front of Bloco Administrativo (MSS-00.442 / MSS-00.444)
	var topiary := Node3D.new()
	topiary.name = "TopiaryIFSul"
	topiary.position = Vector3(-47.5, 0.0, -5.0)
	topiary.rotation.y = deg_to_rad(9.5)
	root.add_child(topiary)
	var lawn_mat := mats.get_material("grass", Color("#4B8B3B"))
	var hedge_mat := mats.get_material("wall", Color("#7CB342"))
	var top_mat := mats.get_material("wall", Color("#A4C639"))
	_add_court_line(topiary, Vector3(0.0, 0.04, 0.0), Vector3(17.5, 0.06, 4.6), lawn_mat)
	_add_court_line(topiary, Vector3(0.0, 0.22, -2.2), Vector3(17.8, 0.38, 0.42), hedge_mat)
	_add_court_line(topiary, Vector3(0.0, 0.22, 2.2), Vector3(17.8, 0.38, 0.42), hedge_mat)
	_add_court_line(topiary, Vector3(-8.7, 0.22, 0.0), Vector3(0.42, 0.38, 4.4), hedge_mat)
	_add_court_line(topiary, Vector3(8.7, 0.22, 0.0), Vector3(0.42, 0.38, 4.4), hedge_mat)
	var top_lbl := Label3D.new()
	top_lbl.text = "IFSul"
	top_lbl.font_size = 160
	top_lbl.pixel_size = 0.022
	top_lbl.double_sided = false
	top_lbl.modulate = Color("#C5E14B")
	top_lbl.outline_modulate = Color("#2F6B28")
	top_lbl.outline_size = 12
	top_lbl.position = Vector3(0.0, 0.16, 0.0)
	top_lbl.rotation.x = -PI * 0.5
	topiary.add_child(top_lbl)
	# Subtle 3D hedge blocks forming I-F-S-u-l relief for ground view visibility
	for hx in [-5.4, -2.7, 0.0, 2.7, 5.4]:
		_add_court_line(topiary, Vector3(hx, 0.20, 0.0), Vector3(1.6, 0.28, 2.2), top_mat)

	# Southern Pond with island, 4 white birdhouses & parking bollards (MSS-00.1912 / MSS-00.442)
	var pond_node := Node3D.new()
	pond_node.name = "SouthernPond"
	pond_node.position = Vector3(-24.0, 0.0, 81.0)
	pond_node.rotation.y = deg_to_rad(8.7)
	root.add_child(pond_node)
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color("#2D5F5B")
	water_mat.roughness = 0.08
	water_mat.metallic = 0.30
	var pond_mi := MeshInstance3D.new()
	var pond_m := CylinderMesh.new()
	pond_m.top_radius = 6.5; pond_m.bottom_radius = 6.5; pond_m.height = 0.05
	pond_mi.mesh = pond_m
	pond_mi.scale = Vector3(1.9, 1.0, 1.0)
	pond_mi.position.y = 0.03
	pond_mi.material_override = water_mat
	pond_node.add_child(pond_mi)
	var isl_mi := MeshInstance3D.new()
	var isl_m := CylinderMesh.new()
	isl_m.top_radius = 2.8; isl_m.bottom_radius = 3.2; isl_m.height = 0.28
	isl_mi.mesh = isl_m
	isl_mi.scale = Vector3(1.7, 1.0, 0.9)
	isl_mi.position = Vector3(1.5, 0.14, 0.0)
	isl_mi.material_override = lawn_mat
	pond_node.add_child(isl_mi)
	var bh_mat := mats.get_material("wall", Color("#F3F2EE"))
	for bh_i in range(4):
		var bx := -1.8 + bh_i * 1.4
		_add_court_line(pond_node, Vector3(1.5 + bx, 0.52, 0.0), Vector3(0.08, 0.55, 0.08), mats.get_material("trunk"))
		_add_court_line(pond_node, Vector3(1.5 + bx, 0.85, 0.0), Vector3(0.45, 0.42, 0.45), bh_mat)
	for bol_i in range(16):
		var bp := Vector3(-24.0 + bol_i * 2.8, 0.32, -11.5)
		_add_court_line(pond_node, bp, Vector3(0.16, 0.64, 0.16), bh_mat)

	# Water tower Agave & Purple Foliage Garden (MSS-00.2360) + North Admin Garden (MSS-00.406)
	var agave_bed := Node3D.new()
	agave_bed.position = Vector3(-18.5, 0.0, -3.5)
	root.add_child(agave_bed)
	_add_court_line(agave_bed, Vector3(0.0, 0.05, 0.0), Vector3(4.6, 0.06, 2.8), mats.get_material("concrete", Color("#CFC3B4")))
	var purple_mat := mats.get_material("wall", Color("#6B2D5C"))
	var agave_mat := mats.get_material("wall", Color("#4D8C7A"))
	for ai in range(6):
		_add_court_line(agave_bed, Vector3(-1.8 + ai * 0.72, 0.18, 0.9), Vector3(0.65, 0.24, 0.65), purple_mat)
		_add_court_line(agave_bed, Vector3(-1.8 + ai * 0.72, 0.18, -0.9), Vector3(0.65, 0.24, 0.65), purple_mat)
	for ax in [-1.1, 0.2, 1.3]:
		var ag := MeshInstance3D.new()
		var agm := CylinderMesh.new()
		agm.top_radius = 0.55; agm.bottom_radius = 0.14; agm.height = 0.75; agm.radial_segments = 6
		ag.mesh = agm
		ag.position = Vector3(ax, 0.42, 0.0)
		ag.material_override = agave_mat
		agave_bed.add_child(ag)

	var north_g := Node3D.new()
	north_g.position = Vector3(-48.0, 0.0, -49.5)
	north_g.rotation.y = deg_to_rad(8.7)
	root.add_child(north_g)
	_add_court_line(north_g, Vector3(0.0, 0.18, 0.0), Vector3(14.0, 0.30, 0.45), hedge_mat)
	_add_court_line(north_g, Vector3(0.0, 0.18, 4.0), Vector3(14.0, 0.30, 0.45), hedge_mat)
	_add_court_line(north_g, Vector3(-7.0, 0.18, 2.0), Vector3(0.45, 0.30, 4.0), hedge_mat)
	_add_court_line(north_g, Vector3(7.0, 0.18, 2.0), Vector3(0.45, 0.30, 4.0), hedge_mat)

	# Totem monument at main gate
	var totem_body := StaticBody3D.new()
	var tcol := CollisionShape3D.new()
	var tbox := BoxShape3D.new()
	tbox.size = Vector3(0.45, 3.4, 6.4)
	tcol.shape = tbox
	tcol.position.y = 1.7
	totem_body.add_child(tcol)

	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.42, 3.4, 6.4)
	base.mesh = bm
	base.position.y = 1.7
	base.material_override = mats.get_material("wall", Color("#F4F4F2"))
	totem_body.add_child(base)

	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.46, 0.45, 6.44)
	stripe.mesh = sm
	stripe.position.y = 3.15
	stripe.material_override = mats.get_material("ifsul_green")
	totem_body.add_child(stripe)

	# Official IFSul Logo panel on both sides of totem
	var logo_mat := StandardMaterial3D.new()
	logo_mat.albedo_texture = MaterialsLib.create_ifsul_logo_texture(256)
	logo_mat.roughness = 0.4
	for side in [-1.0, 1.0]:
		var logo_mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.25, 1.25)
		logo_mi.mesh = qm
		logo_mi.material_override = logo_mat
		logo_mi.position = Vector3(side * 0.23, 1.75, 2.05 * side)
		logo_mi.rotation.y = -PI * 0.5 if side < 0 else PI * 0.5
		totem_body.add_child(logo_mi)

		var title := Label3D.new()
		title.text = "IFSul — Câmpus Sapucaia do Sul\nINSTITUTO FEDERAL Sul-rio-grandense\nAv. Copacabana, 100"
		title.font_size = 34
		title.pixel_size = 0.0046
		title.double_sided = false
		title.modulate = Color("#16381D")
		title.position = Vector3(side * 0.23, 1.8, -0.7 * side)
		title.rotation.y = -PI * 0.5 if side < 0 else PI * 0.5
		totem_body.add_child(title)

	sign_node.add_child(totem_body)

func _build_vegetation_and_props(root: Node3D, data: Dictionary) -> void:
	var props_root := Node3D.new()
	props_root.name = "PropsMultiMesh"
	root.add_child(props_root)

	# 1. Trees via MultiMeshInstance3D
	var tree_positions := _collect_tree_positions(data)
	var trunk_mm := MultiMesh.new()
	trunk_mm.transform_format = MultiMesh.TRANSFORM_3D
	var t_cyl := CylinderMesh.new()
	t_cyl.top_radius = 0.18
	t_cyl.bottom_radius = 0.28
	t_cyl.height = 3.2
	trunk_mm.mesh = t_cyl
	trunk_mm.instance_count = tree_positions.size()

	var crown_mm := MultiMesh.new()
	crown_mm.transform_format = MultiMesh.TRANSFORM_3D
	crown_mm.use_colors = true
	var c_sph := SphereMesh.new()
	c_sph.radius = 2.1
	c_sph.height = 3.2
	c_sph.radial_segments = 10
	c_sph.rings = 6
	crown_mm.mesh = c_sph
	crown_mm.instance_count = tree_positions.size()

	var crown2_mm := MultiMesh.new()
	crown2_mm.transform_format = MultiMesh.TRANSFORM_3D
	crown2_mm.use_colors = true
	crown2_mm.mesh = c_sph
	crown2_mm.instance_count = tree_positions.size()

	var rng := RandomNumberGenerator.new()
	rng.seed = 1996
	for i in range(tree_positions.size()):
		var p: Vector2 = tree_positions[i]
		var sc := rng.randf_range(0.78, 1.45)
		var is_araucaria := (i % 9 == 0)
		if is_araucaria:
			trunk_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(sc * 0.7, sc * 2.4, sc * 0.7)), Vector3(p.x, 3.8 * sc, p.y)))
			crown_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(sc * 1.45, sc * 0.42, sc * 1.45)), Vector3(p.x, 7.6 * sc, p.y)))
			crown2_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(sc * 0.95, sc * 0.30, sc * 0.95)), Vector3(p.x, 8.2 * sc, p.y)))
			crown_mm.set_instance_color(i, Color("#295A27"))
			crown2_mm.set_instance_color(i, Color("#33692E"))
		else:
			trunk_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(sc, sc, sc)), Vector3(p.x, 1.6 * sc, p.y)))
			crown_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(sc, sc * 0.92, sc)), Vector3(p.x, 3.6 * sc, p.y)))
			var ox := rng.randf_range(-0.9, 0.9) * sc
			var oz := rng.randf_range(-0.9, 0.9) * sc
			crown2_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(sc * 0.78, sc * 0.75, sc * 0.78)), Vector3(p.x + ox, 4.7 * sc, p.y + oz)))
			var roll := rng.randf()
			var col := Color("#3D7A32") if roll < 0.72 else (Color("#E0B028") if roll < 0.86 else Color("#6E54A3"))
			crown_mm.set_instance_color(i, col)
			crown2_mm.set_instance_color(i, col.lightened(0.08))

	var trunk_mmi := MultiMeshInstance3D.new()
	trunk_mmi.multimesh = trunk_mm
	trunk_mmi.material_override = mats.get_material("trunk")
	props_root.add_child(trunk_mmi)

	var crown_mmi := MultiMeshInstance3D.new()
	crown_mmi.multimesh = crown_mm
	var fmat := mats.get_material("foliage", Color.WHITE)
	fmat.vertex_color_use_as_albedo = true
	crown_mmi.material_override = fmat
	props_root.add_child(crown_mmi)

	var crown2_mmi := MultiMeshInstance3D.new()
	crown2_mmi.multimesh = crown2_mm
	crown2_mmi.material_override = fmat
	props_root.add_child(crown2_mmi)

	full_tree_count = tree_positions.size()
	tree_mmi_list = [trunk_mmi, crown_mmi, crown2_mmi]

	# 2. Light poles via MultiMeshInstance3D + key OmniLight3D night lights
	var pole_pts := [
		Vector2(-75, -100), Vector2(-70, -40), Vector2(-64, 15), Vector2(-56, 60), Vector2(-50, 110),
		Vector2(-48, -10), Vector2(-24, -10), Vector2(-10, 6), Vector2(14, -42), Vector2(14, -84),
		Vector2(-38, -72), Vector2(-4, 60), Vector2(-18, 95), Vector2(36, 18), Vector2(20, 74)
	]
	var pole_mm := MultiMesh.new()
	pole_mm.transform_format = MultiMesh.TRANSFORM_3D
	var pm := CylinderMesh.new()
	pm.top_radius = 0.08
	pm.bottom_radius = 0.12
	pm.height = 6.2
	pole_mm.mesh = pm
	pole_mm.instance_count = pole_pts.size()

	var head_mm := MultiMesh.new()
	head_mm.transform_format = MultiMesh.TRANSFORM_3D
	var hm := BoxMesh.new()
	hm.size = Vector3(0.55, 0.16, 0.35)
	head_mm.mesh = hm
	head_mm.instance_count = pole_pts.size()

	for i in range(pole_pts.size()):
		var p: Vector2 = pole_pts[i]
		pole_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x, 3.1, p.y)))
		head_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x + 0.2, 6.2, p.y)))
		if i % 2 == 0 or i <= 4:
			var light := OmniLight3D.new()
			light.position = Vector3(p.x + 0.2, 5.9, p.y)
			light.light_color = Color("#FFD794")
			light.light_energy = 0.0
			light.omni_range = 34.0
			light.shadow_enabled = false
			props_root.add_child(light)
			night_lights.append(light)

	# Sports courts, main plaza, Auditório portico & southern pond night floodlights
	for fp in [Vector3(-60.0, 7.2, -84.0), Vector3(-23.0, 7.5, -105.0), Vector3(-22.0, 9.0, 4.0), Vector3(-28.0, 5.2, 22.0), Vector3(-24.0, 6.0, 82.0)]:
		var fl := OmniLight3D.new()
		fl.position = fp
		fl.light_color = Color("#FFF0D6")
		fl.light_energy = 0.0
		fl.omni_range = 42.0
		fl.shadow_enabled = false
		props_root.add_child(fl)
		night_lights.append(fl)

	var pole_mmi := MultiMeshInstance3D.new()
	pole_mmi.multimesh = pole_mm
	pole_mmi.material_override = mats.get_material("metal", Color("#7B8187"))
	props_root.add_child(pole_mmi)

	var head_mmi := MultiMeshInstance3D.new()
	head_mmi.multimesh = head_mm
	head_mmi.material_override = lamp_mat
	props_root.add_child(head_mmi)

	# 3. Campus green benches & trash bins via MultiMesh
	var bench_pts := [
		Vector2(-24.5, 11.0), Vector2(-21.5, 14.8), Vector2(-18.5, 11.2),
		Vector2(-46.0, 5.5), Vector2(-32.0, -4.0), Vector2(12.0, -76.0),
		Vector2(-10.0, 92.0), Vector2(-42.0, -56.0), Vector2(14.0, 4.0),
		Vector2(18.0, 11.0), Vector2(-48.0, -24.0)
	]
	var bench_mm := MultiMesh.new()
	bench_mm.transform_format = MultiMesh.TRANSFORM_3D
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(1.6, 0.55, 0.55)
	bench_mm.mesh = bmesh
	bench_mm.instance_count = bench_pts.size()

	var bin_mm := MultiMesh.new()
	bin_mm.transform_format = MultiMesh.TRANSFORM_3D
	var tbin := CylinderMesh.new()
	tbin.top_radius = 0.22
	tbin.bottom_radius = 0.18
	tbin.height = 0.85
	bin_mm.mesh = tbin
	bin_mm.instance_count = bench_pts.size()

	for i in range(bench_pts.size()):
		var p: Vector2 = bench_pts[i]
		bench_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x, 0.28, p.y)))
		bin_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x + 1.3, 0.43, p.y)))

	var bench_mmi := MultiMeshInstance3D.new()
	bench_mmi.multimesh = bench_mm
	bench_mmi.material_override = mats.get_material("ifsul_green")
	props_root.add_child(bench_mmi)

	var bin_mmi := MultiMeshInstance3D.new()
	bin_mmi.multimesh = bin_mm
	bin_mmi.material_override = mats.get_material("metal", Color("#2B3036"))
	props_root.add_child(bin_mmi)

	# 4. Parked cars in both parking lots via MultiMeshInstance3D
	var car_xforms: Array[Transform3D] = []
	for lot in data.get("parking_lots", []):
		for row in lot.get("bay_rows", []):
			var start := Vector2(float(row["start"][0]), float(row["start"][1]))
			var step := float(row.get("step", 2.6))
			var ang := deg_to_rad(float(row.get("angle_deg", 8.7)))
			var dir := Vector2(cos(ang), -sin(ang))
			var bay_fwd := Vector2(sin(ang), cos(ang))
			for idx in row.get("car_indices", []):
				var p := start + dir * ((float(idx) + 0.5) * step) + bay_fwd * 2.5
				car_xforms.append(Transform3D(Basis(Vector3.UP, ang), Vector3(p.x, 0.65, p.y)))

	if car_xforms.size() > 0:
		var car_mm := MultiMesh.new()
		car_mm.transform_format = MultiMesh.TRANSFORM_3D
		car_mm.use_colors = true
		var car_mesh := BoxMesh.new()
		car_mesh.size = Vector3(1.82, 0.62, 4.15)
		car_mm.mesh = car_mesh
		car_mm.instance_count = car_xforms.size()

		var cab_mm := MultiMesh.new()
		cab_mm.transform_format = MultiMesh.TRANSFORM_3D
		var cab_mesh := BoxMesh.new()
		cab_mesh.size = Vector3(1.52, 0.56, 2.05)
		cab_mm.mesh = cab_mesh
		cab_mm.instance_count = car_xforms.size()

		var wheel_mm := MultiMesh.new()
		wheel_mm.transform_format = MultiMesh.TRANSFORM_3D
		var w_mesh := CylinderMesh.new()
		w_mesh.top_radius = 0.30; w_mesh.bottom_radius = 0.30; w_mesh.height = 0.22
		wheel_mm.mesh = w_mesh
		wheel_mm.instance_count = car_xforms.size() * 4

		var car_palette := [Color("#E2E8F0"), Color("#4B5563"), Color("#1D4ED8"), Color("#B91C1C"), Color("#CBD5E1"), Color("#1E293B")]
		var wheel_offsets := [Vector3(-0.88, -0.22, -1.25), Vector3(0.88, -0.22, -1.25), Vector3(-0.88, -0.22, 1.25), Vector3(0.88, -0.22, 1.25)]
		for i in range(car_xforms.size()):
			var xf := car_xforms[i]
			xf.origin.y = 0.52
			car_mm.set_instance_transform(i, xf)
			car_mm.set_instance_color(i, car_palette[i % car_palette.size()])
			cab_mm.set_instance_transform(i, xf * Transform3D(Basis(), Vector3(0.0, 0.56, -0.15)))
			for wi in range(4):
				var wxf := xf * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), wheel_offsets[wi])
				wheel_mm.set_instance_transform(i * 4 + wi, wxf)

		var car_mmi := MultiMeshInstance3D.new()
		car_mmi.multimesh = car_mm
		var cmat := StandardMaterial3D.new()
		cmat.vertex_color_use_as_albedo = true
		cmat.metallic = 0.35
		cmat.roughness = 0.22
		car_mmi.material_override = cmat
		props_root.add_child(car_mmi)

		var cab_mmi := MultiMeshInstance3D.new()
		cab_mmi.multimesh = cab_mm
		var cab_mat := StandardMaterial3D.new()
		cab_mat.albedo_color = Color("#1E293B")
		cab_mat.metallic = 0.2
		cab_mat.roughness = 0.12
		cab_mmi.material_override = cab_mat
		props_root.add_child(cab_mmi)

		var wheel_mmi := MultiMeshInstance3D.new()
		wheel_mmi.multimesh = wheel_mm
		wheel_mmi.material_override = mats.get_material("asphalt", Color("#18181B"))
		props_root.add_child(wheel_mmi)

	# 5. Sapucaia do Sul surrounding neighborhood houses via MultiMesh
	var house_pts: Array[Vector2] = []
	var hrng := RandomNumberGenerator.new()
	hrng.seed = 93216
	# West residential blocks across Av. Copacabana (aligned parallel to Pista Oeste)
	for row_z: float in [-110.0, -92.0, -52.0, -34.0, -2.0, 12.0, 48.0, 68.0, 98.0, 122.0]:
		var x_west_base := -86.5 + (row_z - 13.0) * 0.160 - 13.5
		for col_i in range(5):
			var col_x := x_west_base - float(col_i) * 17.5
			house_pts.append(Vector2(col_x + hrng.randf_range(-2.2, 2.2), row_z + hrng.randf_range(-2.0, 2.0)))
	# North & South neighborhood blocks
	for col_x in [-85.0, -64.0, -42.0, -20.0, 2.0, 24.0, 46.0]:
		house_pts.append(Vector2(col_x, -188.0 + hrng.randf_range(-4.0, 4.0)))
		house_pts.append(Vector2(col_x, -210.0 + hrng.randf_range(-4.0, 4.0)))
	for col_x in [-25.0, 0.0, 25.0, 52.0, 78.0]:
		house_pts.append(Vector2(col_x, 198.0 + hrng.randf_range(-5.0, 5.0)))

	if house_pts.size() > 0:
		var hw_mm := MultiMesh.new()
		hw_mm.transform_format = MultiMesh.TRANSFORM_3D
		hw_mm.use_colors = true
		var hwm := BoxMesh.new()
		hwm.size = Vector3(9.5, 3.6, 8.0)
		hw_mm.mesh = hwm
		hw_mm.instance_count = house_pts.size()

		var hr_mm := MultiMesh.new()
		hr_mm.transform_format = MultiMesh.TRANSFORM_3D
		var hrm := BoxMesh.new()
		hrm.size = Vector3(10.2, 0.9, 8.6)
		hr_mm.mesh = hrm
		hr_mm.instance_count = house_pts.size()

		var hpal := [Color("#E6DFD3"), Color("#DED8CE"), Color("#D5DFD8"), Color("#E8DCC8")]
		for i in range(house_pts.size()):
			var hp: Vector2 = house_pts[i]
			var ang := deg_to_rad(8.7 + hrng.randf_range(-2.0, 2.0))
			hw_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, ang), Vector3(hp.x, 1.8, hp.y)))
			hw_mm.set_instance_color(i, hpal[i % hpal.size()])
			hr_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, ang), Vector3(hp.x, 4.0, hp.y)))

		var hw_mmi := MultiMeshInstance3D.new()
		hw_mmi.multimesh = hw_mm
		var hwmat := mats.get_material("wall", Color.WHITE)
		hwmat.vertex_color_use_as_albedo = true
		hw_mmi.material_override = hwmat
		props_root.add_child(hw_mmi)

		var hr_mmi := MultiMeshInstance3D.new()
		hr_mmi.multimesh = hr_mm
		hr_mmi.material_override = mats.get_material("wall", Color("#9C523B"))
		props_root.add_child(hr_mmi)

func _collect_tree_positions(data: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 2008
	# Central inner courtyard & Bloco Adm atrium trees
	for cp in [Vector2(14.5, 6.0), Vector2(18.5, 13.0), Vector2(10.5, 13.5), Vector2(-48.5, -24.5)]:
		out.append(cp)
	# Eastern woodland forest belt across Rua Palestina (matching satellite_esri_campus.jpg)
	for _i in range(145):
		var px := rng.randf_range(92.0, 190.0)
		var pz := rng.randf_range(-160.0, 120.0)
		out.append(Vector2(px, pz))
	# Southern green park & eastern woodland edge (matching satellite dense canopy)
	for _i in range(110):
		var px := rng.randf_range(-52.0, 72.0)
		var pz := rng.randf_range(68.0, 152.0)
		if _is_tree_clear(Vector2(px, pz), data):
			out.append(Vector2(px, pz))
	# Northern green lawn east of quadra
	for _i in range(28):
		var px := rng.randf_range(-40.0, 38.0)
		var pz := rng.randf_range(-155.0, -115.0)
		if _is_tree_clear(Vector2(px, pz), data):
			out.append(Vector2(px, pz))
	# Avenue Copacabana central median boulevard trees (inside vegetated median islands)
	for mz: float in [-138.0, -128.0, -110.0, -96.0, -82.0, -68.0, -54.0, -40.0, -26.0, -12.0, 2.0, 30.0, 46.0, 62.0, 78.0, 94.0, 110.0, 126.0, 144.0, 162.0]:
		var mx := -80.25 + (mz - 13.0) * 0.160
		var cand := Vector2(mx, mz)
		if _is_tree_clear(cand, data):
			out.append(cand)
	return out

func _is_tree_clear(p: Vector2, data: Dictionary) -> bool:
	for bpoly in building_polys:
		if Geometry2D.is_point_in_polygon(p, bpoly):
			return false
		for v in bpoly:
			if p.distance_to(v) < 5.0:
				return false
	for c in data.get("courts", []):
		if Geometry2D.is_point_in_polygon(p, _to_vec2_array(c.get("polygon", []))):
			return false
	for pk in data.get("parking_lots", []):
		if Geometry2D.is_point_in_polygon(p, _to_vec2_array(pk.get("polygon", []))):
			return false
	for poi in data.get("pois", []):
		var arr: Array = poi.get("position", [0, 0, 0])
		if p.distance_to(Vector2(float(arr[0]), float(arr[2]))) < 5.0:
			return false
	return true

func set_vegetation_density(ratio: float) -> void:
	if full_tree_count <= 0:
		return
	var target := clampi(int(round(float(full_tree_count) * ratio)), 1, full_tree_count)
	for mmi in tree_mmi_list:
		if is_instance_valid(mmi) and mmi.multimesh != null:
			mmi.multimesh.visible_instance_count = target if target < full_tree_count else -1

func _build_pois(root: Node3D, pois: Array) -> void:
	var p_root := Node3D.new()
	p_root.name = "POIs"
	root.add_child(p_root)

	for i in range(pois.size()):
		var p: Dictionary = pois[i]
		var pos_a: Array = p.get("position", [0, 0, 0])
		var pos := Vector3(float(pos_a[0]), float(pos_a[1]), float(pos_a[2]))
		var area := Area3D.new()
		area.name = String(p.get("id", "poi_%d" % i))
		area.position = pos
		area.set_meta("poi_data", p)
		area.collision_layer = 4
		area.collision_mask = 2

		var col := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 4.2
		col.shape = sph
		col.position.y = 1.2
		area.add_child(col)

		# Pedestal ring + floating diamond marker
		var ring := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 1.15
		tm.bottom_radius = 1.25
		tm.height = 0.08
		ring.mesh = tm
		ring.position.y = 0.05
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color("#2F9E41")
		rmat.emission_enabled = true
		rmat.emission = Color("#2F9E41")
		rmat.emission_energy_multiplier = 0.8
		ring.material_override = rmat
		ring.name = "Ring"
		area.add_child(ring)

		var marker := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 0.7, 0.7)
		marker.mesh = bm
		marker.position.y = 2.2
		marker.rotation = Vector3(deg_to_rad(45), deg_to_rad(45), 0)
		var mmat := StandardMaterial3D.new()
		mmat.albedo_color = Color("#F5C43D")
		mmat.emission_enabled = true
		mmat.emission = Color("#F5C43D")
		mmat.emission_energy_multiplier = 1.2
		marker.material_override = mmat
		marker.name = "Beacon"
		area.add_child(marker)

		var lbl := Label3D.new()
		lbl.text = "%d. %s\n[E] Explorar" % [i + 1, String(p.get("title", ""))]
		lbl.position.y = 2.95
		lbl.font_size = 28
		lbl.pixel_size = 0.0048
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.visibility_range_end = 30.0
		lbl.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		lbl.modulate = Color("#FFFBE6")
		lbl.outline_modulate = Color(0.05, 0.1, 0.06)
		lbl.outline_size = 6
		area.add_child(lbl)

		p_root.add_child(area)
		poi_nodes.append(area)

func _to_vec2_array(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out

func _poly_centroid(poly: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return sum / maxf(1.0, float(poly.size()))

func _ensure_cw_screen(poly: PackedVector2Array) -> PackedVector2Array:
	var area := 0.0
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	var copy := poly.duplicate()
	if area < 0.0: # keep clockwise in XZ screen so outward normal is (edge.y, -edge.x)
		copy.reverse()
	return copy

func _extrude_polygon_mesh(poly: PackedVector2Array, height: float, include_walls: bool) -> ArrayMesh:
	var cw := _ensure_cw_screen(poly)
	var tris := Geometry2D.triangulate_polygon(cw)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Top cap (+Y normal; Godot front-face is CW, so (b-a)x(c-a).y < 0)
	for i in range(0, tris.size(), 3):
		var a := Vector3(cw[tris[i]].x, height, cw[tris[i]].y)
		var b := Vector3(cw[tris[i + 1]].x, height, cw[tris[i + 1]].y)
		var c := Vector3(cw[tris[i + 2]].x, height, cw[tris[i + 2]].y)
		if (b - a).cross(c - a).y > 0.0:
			var tmp := b
			b = c
			c = tmp
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(a.x, a.z) * 0.15)
		st.add_vertex(a)
		st.set_uv(Vector2(b.x, b.z) * 0.15)
		st.add_vertex(b)
		st.set_uv(Vector2(c.x, c.z) * 0.15)
		st.add_vertex(c)

	if include_walls:
		for i in range(cw.size()):
			var p0 := cw[i]
			var p1 := cw[(i + 1) % cw.size()]
			var edge := p1 - p0
			var len := edge.length()
			if len < 0.01:
				continue
			var n := Vector3(edge.y, 0.0, -edge.x).normalized()
			var v0 := Vector3(p0.x, 0.0, p0.y)
			var v1 := Vector3(p1.x, 0.0, p1.y)
			var v2 := Vector3(p1.x, height, p1.y)
			var v3 := Vector3(p0.x, height, p0.y)
			# Ensure CW front-face aligns with outward normal n ((v1-v0)x(v2-v0).dot(n) < 0)
			var tri_n := (v1 - v0).cross(v2 - v0)
			st.set_normal(n)
			if tri_n.dot(n) <= 0.0:
				_push_quad(st, v0, v1, v2, v3, len, height)
			else:
				_push_quad(st, v1, v0, v3, v2, len, height)

	st.generate_tangents()
	return st.commit()

func _push_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, w: float, h: float) -> void:
	var u0 := Vector2(0, 0)
	var u1 := Vector2(w * 0.25, 0)
	var u2 := Vector2(w * 0.25, h * 0.25)
	var u3 := Vector2(0, h * 0.25)
	st.set_uv(u0); st.add_vertex(v0)
	st.set_uv(u1); st.add_vertex(v1)
	st.set_uv(u2); st.add_vertex(v2)
	st.set_uv(u0); st.add_vertex(v0)
	st.set_uv(u2); st.add_vertex(v2)
	st.set_uv(u3); st.add_vertex(v3)
