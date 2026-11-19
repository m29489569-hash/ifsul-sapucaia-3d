class_name CampusInteriorBuilder
extends RefCounted

const WALL_THICK := 0.14
const DOOR_HEIGHT := 2.25
const FLOOR_Y := 0.048
const COURTYARD_Y := 0.055
const DOOR_CLEARANCE := 1.5
const WALK_FURN_RANGE := 48.0
const WALK_WALL_RANGE := 78.0
const AERIAL_FURN_RANGE := 105.0
const AERIAL_WALL_RANGE := 175.0

var night_lights: Array[OmniLight3D] = []
var detail_nodes: Array[Dictionary] = []

var _interiors_root: Node3D = null
var _sectors: Dictionary = {}
var _rooms: Array[Dictionary] = []
var _room_lookup: Array[Dictionary] = []
var _sector_lookup: Dictionary = {} # sector_id -> {min_xz, max_xz, indices: Array[int]}
var _courtyard_lookup: Array[Dictionary] = []
var _building_lookup: Array[Dictionary] = []
var _sector_containers: Dictionary = {} # sector_id -> {root, wall_node, furn_node, min_xz, max_xz, wall_vis, furn_vis}
var _last_vis_cam_pos := Vector3(1e9, 0.0, 1e9)
var _last_vis_aerial := false

var _unit_box_mesh: BoxMesh = null
var _unit_cyl_mesh: CylinderMesh = null
var _unit_sphere_mesh: SphereMesh = null
var _ceiling_light_mat: StandardMaterial3D = null
var _glass_mat: StandardMaterial3D = null

func build_interiors(root: Node3D, campus_data: Dictionary, interiors_data: Dictionary, mats: CampusMaterials) -> void:
	cleanup()
	if root == null:
		return

	_interiors_root = Node3D.new()
	_interiors_root.name = "Interiors"
	root.add_child(_interiors_root)

	_ensure_shared_primitives(mats)

	_sectors = interiors_data.get("sectors", {}) as Dictionary
	var raw_rooms: Array = interiors_data.get("rooms", [])
	var courtyards: Array = interiors_data.get("courtyards", [])
	var wayfinding_signs: Array = interiors_data.get("wayfinding_signs", [])
	var buildings: Array = campus_data.get("buildings", [])

	# 1. Build merged interior ceramic tile floors for all walkable buildings
	_build_interior_floors(buildings, mats)

	# 2. Build courtyards (grass overlays + trees + benches)
	_build_courtyards(courtyards, mats)

	# 3. Parse & index rooms, group by sector
	var sector_batches: Dictionary = {} # sector_id -> batch accumulator
	var building_rooms: Dictionary = {} # building_id -> Array[Dictionary]

	for i in range(raw_rooms.size()):
		var raw: Dictionary = raw_rooms[i]
		var enriched := _enrich_room(raw)
		var r_idx := _rooms.size()
		_rooms.append(enriched)
		_index_room_for_lookup(enriched, r_idx)

		var sec_id := String(enriched.get("sector", "geral"))
		if not sector_batches.has(sec_id):
			sector_batches[sec_id] = _new_sector_batch(sec_id)

		var bid := String(enriched.get("building_id", ""))
		if not bid.is_empty():
			if not building_rooms.has(bid):
				building_rooms[bid] = []
			(building_rooms[bid] as Array).append(enriched)

		_build_room_geometry(enriched, sector_batches[sec_id])

	# 4. Flush each sector's batched walls, colliders, plaques, furniture & ceiling lights
	for sec_id in sector_batches.keys():
		_flush_sector_batch(String(sec_id), sector_batches[sec_id], mats)

	# 5. Build hanging corridor wayfinding signs
	_build_wayfinding_signs(wayfinding_signs, mats)

	# 6. Build subtle night interior OmniLight3Ds (1-2 per major walkable building)
	_build_interior_night_lights(buildings, building_rooms)

	# 7. Initial visibility cull around campus entrance
	_last_vis_cam_pos = Vector3(1e9, 0.0, 1e9)
	update_visibility(Vector3(-30.0, 1.6, 5.0), false)

func update_visibility(cam_pos: Vector3, is_aerial: bool = false) -> void:
	if _sector_containers.is_empty():
		return
	if is_aerial == _last_vis_aerial and cam_pos.distance_squared_to(_last_vis_cam_pos) < 4.0:
		return
	_last_vis_cam_pos = cam_pos
	_last_vis_aerial = is_aerial

	var furn_r := AERIAL_FURN_RANGE if is_aerial else WALK_FURN_RANGE
	var wall_r := AERIAL_WALL_RANGE if is_aerial else WALK_WALL_RANGE
	var furn_r_sq := furn_r * furn_r
	var wall_r_sq := wall_r * wall_r

	for sec_id in _sector_containers.keys():
		var sc: Dictionary = _sector_containers[sec_id]
		var min_xz: Vector2 = sc["min_xz"]
		var max_xz: Vector2 = sc["max_xz"]
		var dx := maxf(0.0, maxf(min_xz.x - cam_pos.x, cam_pos.x - max_xz.x))
		var dz := maxf(0.0, maxf(min_xz.y - cam_pos.z, cam_pos.z - max_xz.y))
		var d_sq := dx * dx + dz * dz

		var want_furn := d_sq <= furn_r_sq
		var want_wall := d_sq <= wall_r_sq

		if want_furn != bool(sc["furn_vis"]):
			sc["furn_vis"] = want_furn
			var fn := sc["furn_node"] as Node3D
			if is_instance_valid(fn):
				fn.visible = want_furn
		if want_wall != bool(sc["wall_vis"]):
			sc["wall_vis"] = want_wall
			var wn := sc["wall_node"] as Node3D
			if is_instance_valid(wn):
				wn.visible = want_wall

func find_room_at(world_pos: Vector3) -> Dictionary:
	var wx := world_pos.x
	var wz := world_pos.z

	# 1. Exact room match using sector AABB pre-filter + local rotated rectangle
	for sec_id in _sector_lookup.keys():
		var sl: Dictionary = _sector_lookup[sec_id]
		var mn: Vector2 = sl["min_xz"]
		var mx: Vector2 = sl["max_xz"]
		if wx < mn.x or wx > mx.x or wz < mn.y or wz > mx.y:
			continue
		var indices: Array = sl["indices"]
		for idx_v in indices:
			var entry: Dictionary = _room_lookup[int(idx_v)]
			var dx := wx - float(entry["cx"])
			var dz := wz - float(entry["cz"])
			var cos_r := float(entry["cos_r"])
			var sin_r := float(entry["sin_r"])
			var lx := dx * cos_r - dz * sin_r
			var lz := dx * sin_r + dz * cos_r
			if absf(lx) <= float(entry["hw"]) and absf(lz) <= float(entry["hd"]):
				return (entry["room"] as Dictionary).duplicate(false)

	# 2. Named courtyard match
	for cy in _courtyard_lookup:
		var dx := wx - float(cy["cx"])
		var dz := wz - float(cy["cz"])
		var cos_r := float(cy["cos_r"])
		var sin_r := float(cy["sin_r"])
		var lx := dx * cos_r - dz * sin_r
		var lz := dx * sin_r + dz * cos_r
		if absf(lx) <= float(cy["hw"]) and absf(lz) <= float(cy["hd"]):
			return (cy["info"] as Dictionary).duplicate(false)

	# 3. Walkable building corridor fallback (keeps indoor HUD/minimap stable in hallways)
	var p2 := Vector2(wx, wz)
	for b_entry in _building_lookup:
		var bmin: Vector2 = b_entry["min_xz"]
		var bmax: Vector2 = b_entry["max_xz"]
		if wx < bmin.x or wx > bmax.x or wz < bmin.y or wz > bmax.y:
			continue
		var poly: PackedVector2Array = b_entry["poly"]
		if not Geometry2D.is_point_in_polygon(p2, poly):
			continue
		var inner: PackedVector2Array = b_entry["inner"]
		if inner.size() >= 3 and Geometry2D.is_point_in_polygon(p2, inner):
			continue
		var info := (b_entry["info"] as Dictionary).duplicate(false)
		info["center"] = [wx, wz]
		return info

	return {}

func search_rooms(query: String) -> Array[Dictionary]:
	var q := _normalize_search_text(query)
	var out: Array[Dictionary] = []

	if q.is_empty():
		var sorted_all: Array[Dictionary] = []
		for entry in _room_lookup:
			sorted_all.append(entry)
		sorted_all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var sa := String(a["norm_sector_id"])
			var sb := String(b["norm_sector_id"])
			if sa != sb:
				return sa < sb
			var ca := String(a["norm_code"])
			var cb := String(b["norm_code"])
			if ca != cb:
				return ca < cb
			return String(a["norm_name"]) < String(b["norm_name"])
		)
		for e in sorted_all:
			out.append((e["room"] as Dictionary).duplicate(false))
		return out

	var tokens := q.split(" ", false)
	var scored: Array[Dictionary] = []

	for entry in _room_lookup:
		var n_code := String(entry["norm_code"])
		var n_name := String(entry["norm_name"])
		var n_sec_name := String(entry["norm_sector_name"])
		var n_sec_id := String(entry["norm_sector_id"])
		var n_aliases: Array = entry["norm_aliases"]
		var n_haystack := String(entry["norm_haystack"])

		var tier := 99
		if not n_code.is_empty() and n_code == q:
			tier = 0
		elif n_name == q or n_aliases.has(q):
			tier = 1
		elif not n_code.is_empty() and n_code.begins_with(q):
			tier = 2
		elif n_name.begins_with(q) or _any_begins_with(n_aliases, q):
			tier = 3
		elif (not n_code.is_empty() and n_code.contains(q)) or n_name.contains(q) or _any_contains(n_aliases, q):
			tier = 4
		elif n_sec_id == q or n_sec_name.contains(q):
			tier = 5
		elif tokens.size() > 1:
			var all_ok := true
			for tok in tokens:
				if not n_haystack.contains(tok):
					all_ok = false
					break
			if all_ok:
				tier = 6

		if tier < 99:
			scored.append({
				"tier": tier,
				"code": n_code,
				"name": n_name,
				"room": entry["room"]
			})

	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := int(a["tier"])
		var tb := int(b["tier"])
		if ta != tb:
			return ta < tb
		var ca := String(a["code"])
		var cb := String(b["code"])
		if ca != cb:
			return ca < cb
		return String(a["name"]) < String(b["name"])
	)

	for item in scored:
		out.append((item["room"] as Dictionary).duplicate(false))
	return out

func get_all_rooms() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in _rooms:
		out.append(r.duplicate(false))
	return out

func get_room_world_pos(room: Dictionary) -> Vector3:
	if room.has("center"):
		var c = room["center"]
		if c is Array and c.size() >= 2:
			return Vector3(float(c[0]), FLOOR_Y, float(c[1]))
		if c is Vector2:
			return Vector3(c.x, FLOOR_Y, c.y)
		if c is Vector3:
			return Vector3(c.x, FLOOR_Y, c.z)
	if room.has("pos"):
		var p = room["pos"]
		if p is Array and p.size() >= 3:
			return Vector3(float(p[0]), float(p[1]), float(p[2]))
		if p is Array and p.size() >= 2:
			return Vector3(float(p[0]), FLOOR_Y, float(p[1]))
	return Vector3.ZERO

func cleanup() -> void:
	if is_instance_valid(_interiors_root):
		_interiors_root.queue_free()
	_interiors_root = null
	night_lights.clear()
	detail_nodes.clear()
	_sectors.clear()
	_rooms.clear()
	_room_lookup.clear()
	_sector_lookup.clear()
	_courtyard_lookup.clear()
	_building_lookup.clear()
	_sector_containers.clear()
	_last_vis_cam_pos = Vector3(1e9, 0.0, 1e9)
	_last_vis_aerial = false
	_unit_box_mesh = null
	_unit_cyl_mesh = null
	_unit_sphere_mesh = null
	_ceiling_light_mat = null
	_glass_mat = null

# --- Shared Primitives & Materials ---

func _ensure_shared_primitives(mats: CampusMaterials) -> void:
	if _unit_box_mesh == null:
		_unit_box_mesh = BoxMesh.new()
		_unit_box_mesh.size = Vector3.ONE
	if _unit_cyl_mesh == null:
		_unit_cyl_mesh = CylinderMesh.new()
		_unit_cyl_mesh.top_radius = 0.5
		_unit_cyl_mesh.bottom_radius = 0.5
		_unit_cyl_mesh.height = 1.0
		_unit_cyl_mesh.radial_segments = 10
		_unit_cyl_mesh.rings = 0
	if _unit_sphere_mesh == null:
		_unit_sphere_mesh = SphereMesh.new()
		_unit_sphere_mesh.radius = 0.5
		_unit_sphere_mesh.height = 1.0
		_unit_sphere_mesh.radial_segments = 10
		_unit_sphere_mesh.rings = 5
	if _ceiling_light_mat == null:
		_ceiling_light_mat = mats.get_material("ceiling_lamp")
	if _glass_mat == null:
		_glass_mat = mats.get_material("glass")

# --- Interior Tile Floors & Building Corridor Lookup ---

func _build_interior_floors(buildings: Array, mats: CampusMaterials) -> void:
	var tile_st := SurfaceTool.new()
	tile_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_tile_verts := false

	var lawn_st := SurfaceTool.new()
	lawn_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_lawn_verts := false

	for b_v in buildings:
		var b: Dictionary = b_v
		if not bool(b.get("walkable", false)):
			continue
		var poly := _to_vec2_array(b.get("polygon", []))
		if poly.size() < 3:
			continue

		var cw := _ensure_cw_screen(poly)
		var inner := PackedVector2Array()
		if b.has("courtyard_inset"):
			var inset := float(b["courtyard_inset"])
			inner = _compute_inset_polygon(cw, inset)
			for i in range(cw.size()):
				var j := (i + 1) % cw.size()
				var wing := PackedVector2Array([cw[i], cw[j], inner[j], inner[i]])
				if _push_polygon_top(tile_st, wing, FLOOR_Y, 0.24):
					has_tile_verts = true
			if _push_polygon_top(lawn_st, inner, FLOOR_Y - 0.004, 0.14):
				has_lawn_verts = true
		else:
			if _push_polygon_top(tile_st, cw, FLOOR_Y, 0.24):
				has_tile_verts = true

		# Index walkable building for corridor fallback in find_room_at()
		var bmin := Vector2(1e9, 1e9)
		var bmax := Vector2(-1e9, -1e9)
		for p in poly:
			bmin.x = minf(bmin.x, p.x)
			bmin.y = minf(bmin.y, p.y)
			bmax.x = maxf(bmax.x, p.x)
			bmax.y = maxf(bmax.y, p.y)

		var sec_id := String(b.get("sector", ""))
		var sec_info: Dictionary = _sectors.get(sec_id, {})
		var sec_name := String(sec_info.get("name", String(b.get("name", "Setor"))))
		var sec_color := String(sec_info.get("color", String(b.get("map_color", "#58B37B"))))
		var b_name := String(b.get("name", sec_name))
		_building_lookup.append({
			"min_xz": bmin,
			"max_xz": bmax,
			"poly": poly,
			"inner": inner,
			"info": {
				"id": "corridor_" + String(b.get("id", "b")),
				"building_id": String(b.get("id", "")),
				"sector": sec_id,
				"code": "",
				"name": b_name,
				"sector_name": sec_name,
				"sector_color": sec_color,
				"is_corridor": true,
				"aliases": [],
				"preset": "corridor"
			}
		})

	if has_tile_verts:
		tile_st.index()
		tile_st.generate_tangents()
		var mesh := tile_st.commit()
		if mesh != null and mesh.get_surface_count() > 0:
			var mi := MeshInstance3D.new()
			mi.name = "InteriorTileFloors"
			mi.mesh = mesh
			mi.material_override = mats.get_planar_ground_material("interior_floor", Color("#AEAAA2"))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_interiors_root.add_child(mi)

	if has_lawn_verts:
		lawn_st.index()
		lawn_st.generate_tangents()
		var lmesh := lawn_st.commit()
		if lmesh != null and lmesh.get_surface_count() > 0:
			var lmi := MeshInstance3D.new()
			lmi.name = "CourtyardInsetLawns"
			lmi.mesh = lmesh
			lmi.material_override = mats.get_planar_ground_material("grass", Color("#D8ECD0"))
			lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_interiors_root.add_child(lmi)

# --- Courtyards (Grass Lawns + Courtyard Trees & Benches) ---

func _build_courtyards(courtyards: Array, mats: CampusMaterials) -> void:
	if courtyards.is_empty():
		return

	var cy_root := Node3D.new()
	cy_root.name = "InteriorCourtyards"
	_interiors_root.add_child(cy_root)

	var grass_st := SurfaceTool.new()
	grass_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_grass := false

	var prop_boxes: Array = []
	var prop_cyls: Array = []
	var prop_spheres: Array = []

	var curb_col := Color("#D4CFC6")
	var wood_col := Color("#8B5E3C")
	var metal_col := Color("#394047")
	var trunk_col := Color("#5D4331")
	var leaf_cols := [Color("#3D7D35"), Color("#4E8F3E"), Color("#2E6B2B")]
	var shrub_cols := [Color("#4B8E38"), Color("#D95B7A"), Color("#E6B422")]

	for ci in range(courtyards.size()):
		var cy: Dictionary = courtyards[ci]
		var center_a: Array = cy.get("center", [0.0, 0.0])
		var size_a: Array = cy.get("size", [6.0, 6.0])
		if center_a.size() < 2 or size_a.size() < 2:
			continue
		var cx := float(center_a[0])
		var cz := float(center_a[1])
		var w := float(size_a[0])
		var d := float(size_a[1])
		var hw := w * 0.5
		var hd := d * 0.5
		var rot_deg := float(cy.get("rot_deg", 8.7))
		var rot_rad := deg_to_rad(rot_deg)
		var cos_r := cos(rot_rad)
		var sin_r := sin(rot_rad)
		var basis := Basis(Vector3.UP, rot_rad)
		var origin := Vector3(cx, 0.0, cz)

		# Register courtyard for spatial lookup
		var bid := String(cy.get("building_id", ""))
		var sec_id := String(cy.get("sector", "200" if bid == "bloco_ensino_central" else "100"))
		var sec_info: Dictionary = _sectors.get(sec_id, {})
		_courtyard_lookup.append({
			"cx": cx,
			"cz": cz,
			"hw": hw,
			"hd": hd,
			"cos_r": cos_r,
			"sin_r": sin_r,
			"info": {
				"id": String(cy.get("id", "courtyard_%d" % ci)),
				"building_id": bid,
				"sector": sec_id,
				"code": "",
				"name": String(cy.get("name", "Jardim Interno")),
				"sector_name": String(sec_info.get("name", "Jardim Interno")),
				"sector_color": String(sec_info.get("color", "#4EA874")),
				"is_courtyard": true,
				"center": [cx, cz],
				"aliases": [],
				"preset": "courtyard"
			}
		})

		# Grass rectangle polygon
		var corners_local: Array[Vector3] = [
			Vector3(-hw, 0.0, -hd),
			Vector3(hw, 0.0, -hd),
			Vector3(hw, 0.0, hd),
			Vector3(-hw, 0.0, hd)
		]
		var poly := PackedVector2Array()
		for cl in corners_local:
			var wp: Vector3 = origin + basis * cl
			poly.append(Vector2(wp.x, wp.z))
		if _push_polygon_top(grass_st, poly, COURTYARD_Y, 0.16):
			has_grass = true

		# Low decorative curb border (visual only so player never trips)
		var curb_h := 0.09
		var curb_t := 0.16
		prop_boxes.append({"xf": _local_xf(origin, basis, Vector3(0.0, COURTYARD_Y + curb_h * 0.5, -hd + curb_t * 0.5), Vector3(w, curb_h, curb_t)), "col": curb_col})
		prop_boxes.append({"xf": _local_xf(origin, basis, Vector3(0.0, COURTYARD_Y + curb_h * 0.5, hd - curb_t * 0.5), Vector3(w, curb_h, curb_t)), "col": curb_col})
		prop_boxes.append({"xf": _local_xf(origin, basis, Vector3(-hw + curb_t * 0.5, COURTYARD_Y + curb_h * 0.5, 0.0), Vector3(curb_t, curb_h, maxf(0.2, d - curb_t * 2.0))), "col": curb_col})
		prop_boxes.append({"xf": _local_xf(origin, basis, Vector3(hw - curb_t * 0.5, COURTYARD_Y + curb_h * 0.5, 0.0), Vector3(curb_t, curb_h, maxf(0.2, d - curb_t * 2.0))), "col": curb_col})

		# Small stylized courtyard trees
		var tree_spots: Array[Vector2] = []
		if w >= 8.0 and d >= 6.0:
			tree_spots.append(Vector2(-hw * 0.42, -hd * 0.30))
			tree_spots.append(Vector2(hw * 0.42, hd * 0.30))
		elif w >= 5.0 or d >= 5.0:
			tree_spots.append(Vector2(0.0, 0.0))

		for ti in range(tree_spots.size()):
			var tp := tree_spots[ti]
			var th := 2.4 + float((ci + ti) % 2) * 0.5
			prop_cyls.append({"xf": _local_xf(origin, basis, Vector3(tp.x, COURTYARD_Y + th * 0.5, tp.y), Vector3(0.22, th, 0.22)), "col": trunk_col})
			prop_spheres.append({"xf": _local_xf(origin, basis, Vector3(tp.x, COURTYARD_Y + th + 0.55, tp.y), Vector3(1.85, 1.45, 1.85)), "col": leaf_cols[(ci + ti) % leaf_cols.size()]})
			prop_spheres.append({"xf": _local_xf(origin, basis, Vector3(tp.x + 0.45, COURTYARD_Y + th + 0.25, tp.y - 0.35), Vector3(1.15, 1.0, 1.15)), "col": leaf_cols[(ci + ti + 1) % leaf_cols.size()]})

		# Ornamental corner shrubs
		if w >= 4.0 and d >= 4.0:
			var sx := hw - 0.85
			var sz := hd - 0.85
			for si in range(4):
				var lx := sx if (si % 2 == 0) else -sx
				var lz := sz if (si < 2) else -sz
				prop_spheres.append({"xf": _local_xf(origin, basis, Vector3(lx, COURTYARD_Y + 0.36, lz), Vector3(0.75, 0.58, 0.75)), "col": shrub_cols[(ci + si) % shrub_cols.size()]})

		# Courtyard benches
		if w >= 5.5 and d >= 4.5:
			var bench_z := hd - 1.15
			for sgn: float in [-1.0, 1.0]:
				var bz: float = sgn * bench_z
				prop_boxes.append({"xf": _local_xf(origin, basis, Vector3(0.0, COURTYARD_Y + 0.44, bz), Vector3(1.75, 0.08, 0.46)), "col": wood_col})
				prop_boxes.append({"xf": _local_xf(origin, basis, Vector3(-0.68, COURTYARD_Y + 0.22, bz), Vector3(0.08, 0.44, 0.40)), "col": metal_col})
				prop_boxes.append({"xf": _local_xf(origin, basis, Vector3(0.68, COURTYARD_Y + 0.22, bz), Vector3(0.08, 0.44, 0.40)), "col": metal_col})

	if has_grass:
		grass_st.index()
		grass_st.generate_tangents()
		var gmesh := grass_st.commit()
		if gmesh != null and gmesh.get_surface_count() > 0:
			var gmi := MeshInstance3D.new()
			gmi.name = "CourtyardLawns"
			gmi.mesh = gmesh
			gmi.material_override = mats.get_planar_ground_material("grass", Color("#DCEFD4"))
			gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cy_root.add_child(gmi)

	_emit_colored_mm(cy_root, "CourtyardProps", _unit_box_mesh, prop_boxes, mats.get_batch_material("batch_wall"), 85.0)
	_emit_colored_mm(cy_root, "CourtyardTrunks", _unit_cyl_mesh, prop_cyls, mats.get_batch_material("batch_wall"), 85.0)
	_emit_colored_mm(cy_root, "CourtyardFoliage", _unit_sphere_mesh, prop_spheres, mats.get_batch_material("batch_foliage"), 85.0)

# --- Room Enrichment & Indexing ---

func _enrich_room(raw: Dictionary) -> Dictionary:
	var r := raw.duplicate(true)
	var sec_id := String(r.get("sector", "geral"))
	var sec_info: Dictionary = _sectors.get(sec_id, {})
	r["sector"] = sec_id
	r["sector_name"] = String(sec_info.get("name", "Setor " + sec_id))
	r["sector_color"] = String(sec_info.get("color", "#58B37B"))
	if not r.has("code"):
		r["code"] = ""
	if not r.has("aliases"):
		r["aliases"] = []
	if not r.has("open_sides"):
		r["open_sides"] = []
	if not r.has("doors"):
		if r.has("door_side"):
			r["doors"] = [{"side": String(r["door_side"]), "offset": 0.0, "width": 1.4}]
		else:
			r["doors"] = []
	return r

func _index_room_for_lookup(room: Dictionary, r_idx: int) -> void:
	var center_a: Array = room.get("center", [0.0, 0.0])
	var size_a: Array = room.get("size", [4.0, 4.0])
	var cx := float(center_a[0]) if center_a.size() >= 1 else 0.0
	var cz := float(center_a[1]) if center_a.size() >= 2 else 0.0
	var hw := (float(size_a[0]) if size_a.size() >= 1 else 4.0) * 0.5
	var hd := (float(size_a[1]) if size_a.size() >= 2 else 4.0) * 0.5
	var rot_rad := deg_to_rad(float(room.get("rot_deg", 8.7)))
	var cos_r := cos(rot_rad)
	var sin_r := sin(rot_rad)

	var ext_x := absf(hw * cos_r) + absf(hd * sin_r)
	var ext_z := absf(hw * sin_r) + absf(hd * cos_r)

	var sec_id := String(room.get("sector", "geral"))
	if not _sector_lookup.has(sec_id):
		_sector_lookup[sec_id] = {
			"min_xz": Vector2(cx - ext_x, cz - ext_z),
			"max_xz": Vector2(cx + ext_x, cz + ext_z),
			"indices": []
		}
	else:
		var sl: Dictionary = _sector_lookup[sec_id]
		var mn: Vector2 = sl["min_xz"]
		var mx: Vector2 = sl["max_xz"]
		sl["min_xz"] = Vector2(minf(mn.x, cx - ext_x), minf(mn.y, cz - ext_z))
		sl["max_xz"] = Vector2(maxf(mx.x, cx + ext_x), maxf(mx.y, cz + ext_z))
	(_sector_lookup[sec_id]["indices"] as Array).append(r_idx)

	var n_code := _normalize_search_text(String(room.get("code", "")))
	var n_name := _normalize_search_text(String(room.get("name", "")))
	var n_sec_name := _normalize_search_text(String(room.get("sector_name", "")))
	var n_sec_id := _normalize_search_text(sec_id)
	var n_aliases: Array[String] = []
	var alias_parts := PackedStringArray()
	for al in room.get("aliases", []):
		var na := _normalize_search_text(String(al))
		if not na.is_empty():
			n_aliases.append(na)
			alias_parts.append(na)
	var haystack := "%s %s %s %s %s" % [n_code, n_name, " ".join(alias_parts), n_sec_name, n_sec_id]

	_room_lookup.append({
		"cx": cx,
		"cz": cz,
		"hw": hw,
		"hd": hd,
		"cos_r": cos_r,
		"sin_r": sin_r,
		"room": room,
		"norm_code": n_code,
		"norm_name": n_name,
		"norm_aliases": n_aliases,
		"norm_sector_name": n_sec_name,
		"norm_sector_id": n_sec_id,
		"norm_haystack": haystack
	})

# --- Per-Sector Batching ---

func _new_sector_batch(sec_id: String) -> Dictionary:
	return {
		"sector": sec_id,
		"min_xz": Vector2(1e9, 1e9),
		"max_xz": Vector2(-1e9, -1e9),
		"wall_boxes": [],
		"glass_boxes": [],
		"colliders": [], # Array of {pos: Vector3, size: Vector3, rot_y: float}
		"furn_boxes": [],
		"furn_cyls": [],
		"light_xfs": [],
		"plaques": [] # Array of {pos: Vector3, rot_y: float, text: String, double_sided: bool}
	}

func _expand_batch_bounds(batch: Dictionary, cx: float, cz: float, hw: float, hd: float, cos_r: float, sin_r: float) -> void:
	var ex := absf(hw * cos_r) + absf(hd * sin_r) + 1.0
	var ez := absf(hw * sin_r) + absf(hd * cos_r) + 1.0
	var mn: Vector2 = batch["min_xz"]
	var mx: Vector2 = batch["max_xz"]
	batch["min_xz"] = Vector2(minf(mn.x, cx - ex), minf(mn.y, cz - ez))
	batch["max_xz"] = Vector2(maxf(mx.x, cx + ex), maxf(mx.y, cz + ez))

func _build_room_geometry(room: Dictionary, batch: Dictionary) -> void:
	var center_a: Array = room.get("center", [0.0, 0.0])
	var size_a: Array = room.get("size", [4.0, 4.0])
	if center_a.size() < 2 or size_a.size() < 2:
		return
	var cx := float(center_a[0])
	var cz := float(center_a[1])
	var w := maxf(1.0, float(size_a[0]))
	var d := maxf(1.0, float(size_a[1]))
	var hw := w * 0.5
	var hd := d * 0.5
	var rot_deg := float(room.get("rot_deg", 8.7))
	var rot_rad := deg_to_rad(rot_deg)
	var ceil_h := clampf(float(room.get("ceiling_h", 3.4)), 2.6, 6.2)
	var basis := Basis(Vector3.UP, rot_rad)
	var origin := Vector3(cx, 0.0, cz)

	_expand_batch_bounds(batch, cx, cz, hw, hd, cos(rot_rad), sin(rot_rad))

	var open_sides: Dictionary = {}
	for s in room.get("open_sides", []):
		open_sides[String(s).to_lower()] = true

	var glass_sides: Dictionary = {}
	for s in room.get("glass_sides", []):
		glass_sides[String(s).to_lower()] = true

	# Organize doors by side and record door zones for furniture clearance
	var doors_by_side: Dictionary = {"north": [], "south": [], "east": [], "west": []}
	var door_zones: Array[Dictionary] = []
	var raw_doors: Array = room.get("doors", [])
	for dv in raw_doors:
		if not (dv is Dictionary):
			continue
		var side := String(dv.get("side", "south")).to_lower()
		if not doors_by_side.has(side):
			continue
		var side_len := w if (side == "north" or side == "south") else d
		var dw := maxf(1.25, float(dv.get("width", 1.4)))
		dw = minf(dw, maxf(1.2, side_len - 0.28))
		var max_off := maxf(0.0, side_len * 0.5 - dw * 0.5 - 0.14)
		var off := clampf(float(dv.get("offset", 0.0)), -max_off, max_off)
		(doors_by_side[side] as Array).append({"offset": off, "width": dw})

		# Clearance rectangle in local room XZ extending DOOR_CLEARANCE inward
		var zc := _make_door_clearance_rect(side, off, dw, hw, hd)
		door_zones.append(zc)

	# 1. Partition walls with doorway cutouts, frames, baseboards, and solid-only colliders
	var wall_col := Color("#EFECE6")
	var base_col := Color("#4C5259")
	var frame_col := Color("#2B3238")
	var sec_col := Color(String(room.get("sector_color", "#58B37B")))
	var door_h := minf(DOOR_HEIGHT, ceil_h - 0.35)

	var wall_boxes: Array = batch["wall_boxes"]
	var glass_boxes: Array = batch["glass_boxes"]
	var colliders: Array = batch["colliders"]

	var sides_order: Array[String] = ["north", "south", "west", "east"]
	for side in sides_order:
		if open_sides.has(side):
			continue
		var is_ns: bool = (side == "north" or side == "south")
		var half_len := hw if is_ns else hd
		var trim_lo := 0.0
		var trim_hi := 0.0
		if not is_ns:
			# Avoid corner z-fighting with north/south walls where those exist
			if not open_sides.has("north"):
				trim_lo = WALL_THICK
			if not open_sides.has("south"):
				trim_hi = WALL_THICK
		var seg_min := -half_len + trim_lo
		var seg_max := half_len - trim_hi
		if seg_max - seg_min < 0.10:
			continue

		var is_glass := glass_sides.has(side)
		var s_doors: Array = doors_by_side[side]

		# Merge door intervals along this wall
		var intervals: Array[Vector2] = []
		for d_item in s_doors:
			var doff := float(d_item["offset"])
			var dhw := float(d_item["width"]) * 0.5
			var a := clampf(doff - dhw, seg_min, seg_max)
			var b := clampf(doff + dhw, seg_min, seg_max)
			if b - a >= 0.4:
				intervals.append(Vector2(a, b))
		intervals.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var merged: Array[Vector2] = []
		for iv in intervals:
			if merged.is_empty() or iv.x > merged[merged.size() - 1].y + 0.05:
				merged.append(iv)
			else:
				merged[merged.size() - 1].y = maxf(merged[merged.size() - 1].y, iv.y)

		# Solid segments between door openings
		var cursor := seg_min
		var solid_segs: Array[Vector2] = []
		for iv in merged:
			if iv.x - cursor >= 0.06:
				solid_segs.append(Vector2(cursor, iv.x))
			cursor = maxf(cursor, iv.y)
		if seg_max - cursor >= 0.06:
			solid_segs.append(Vector2(cursor, seg_max))

		# Emit solid wall segments + baseboards + BoxShape3D colliders
		for seg in solid_segs:
			var slen := seg.y - seg.x
			var smid := (seg.x + seg.y) * 0.5
			var wall_h := ceil_h - FLOOR_Y
			if is_glass and slen >= 0.6:
				# Courtyard-facing glazed wall: low wall + reflective glass + upper transom
				var sill_h := 0.92
				var glass_h := maxf(0.5, minf(1.55, ceil_h - sill_h - 0.45))
				var top_y0 := FLOOR_Y + sill_h + glass_h
				var top_h := maxf(0.15, ceil_h - top_y0)
				_push_wall_box(wall_boxes, origin, basis, side, hw, hd, smid, FLOOR_Y + sill_h * 0.5, slen, sill_h, WALL_THICK, wall_col)
				_push_wall_box(glass_boxes, origin, basis, side, hw, hd, smid, FLOOR_Y + sill_h + glass_h * 0.5, slen, glass_h, 0.05, Color.WHITE)
				_push_wall_box(wall_boxes, origin, basis, side, hw, hd, smid, top_y0 + top_h * 0.5, slen, top_h, WALL_THICK, wall_col)
				_push_wall_box(wall_boxes, origin, basis, side, hw, hd, smid, FLOOR_Y + sill_h, slen, 0.05, WALL_THICK + 0.02, frame_col)
				_push_wall_box(wall_boxes, origin, basis, side, hw, hd, smid, top_y0, slen, 0.05, WALL_THICK + 0.02, frame_col)
			else:
				_push_wall_box(wall_boxes, origin, basis, side, hw, hd, smid, FLOOR_Y + wall_h * 0.5, slen, wall_h, WALL_THICK, wall_col)
			# Dark baseboard
			_push_wall_box(wall_boxes, origin, basis, side, hw, hd, smid, FLOOR_Y + 0.06, slen, 0.12, WALL_THICK + 0.016, base_col)
			# Physics collider (only on solid segments >= 0.12m, NEVER across doorways)
			if slen >= 0.12:
				_push_wall_collider(colliders, origin, basis, rot_rad, side, hw, hd, smid, slen, ceil_h)

		# Emit doorway lintels + dark jambs (visual only, zero collider blocking doorway!)
		for iv in merged:
			var dlen := iv.y - iv.x
			var dmid := (iv.x + iv.y) * 0.5
			var lintel_h := maxf(0.12, ceil_h - door_h)
			_push_wall_box(wall_boxes, origin, basis, side, hw, hd, dmid, door_h + lintel_h * 0.5, dlen, lintel_h, WALL_THICK, wall_col)
			# Jambs and top head frame
			var jt := 0.055
			var jd := WALL_THICK + 0.03
			_push_wall_box(wall_boxes, origin, basis, side, hw, hd, iv.x + jt * 0.5, FLOOR_Y + (door_h - FLOOR_Y) * 0.5, jt, door_h - FLOOR_Y, jd, frame_col)
			_push_wall_box(wall_boxes, origin, basis, side, hw, hd, iv.y - jt * 0.5, FLOOR_Y + (door_h - FLOOR_Y) * 0.5, jt, door_h - FLOOR_Y, jd, frame_col)
			_push_wall_box(wall_boxes, origin, basis, side, hw, hd, dmid, door_h - 0.03, dlen, 0.06, jd, frame_col)

	# 2. Door plaques (above primary door, or hanging near center if room has no doors)
	_build_room_plaque(room, origin, basis, rot_rad, hw, hd, ceil_h, door_h, doors_by_side, open_sides, sec_col, batch)

	# 3. Ceiling emissive light strips
	_build_ceiling_lights(origin, basis, w, d, ceil_h, batch["light_xfs"])

	# 4. Furniture preset (with door clearance & wall inset)
	_build_room_furniture(room, origin, basis, w, d, ceil_h, open_sides, doors_by_side, door_zones, batch)

# --- Wall Positioning Helpers ---

func _wall_local_pos(side: String, hw: float, hd: float, along: float, y: float, out_offset: float = 0.0) -> Vector3:
	var inset := WALL_THICK * 0.5
	match side:
		"north":
			return Vector3(along, y, -hd + inset - out_offset)
		"south":
			return Vector3(along, y, hd - inset + out_offset)
		"west":
			return Vector3(-hw + inset - out_offset, y, along)
		_:
			return Vector3(hw - inset + out_offset, y, along)

func _push_wall_box(target: Array, origin: Vector3, basis: Basis, side: String, hw: float, hd: float, along: float, y: float, slen: float, sh: float, sthick: float, col: Color) -> void:
	var lpos := _wall_local_pos(side, hw, hd, along, y)
	var sz := Vector3(slen, sh, sthick) if (side == "north" or side == "south") else Vector3(sthick, sh, slen)
	target.append({"xf": _local_xf(origin, basis, lpos, sz), "col": col})

func _push_wall_collider(colliders: Array, origin: Vector3, basis: Basis, rot_rad: float, side: String, hw: float, hd: float, along: float, slen: float, ceil_h: float) -> void:
	var lpos := _wall_local_pos(side, hw, hd, along, ceil_h * 0.5)
	var wpos := origin + basis * lpos
	var sz := Vector3(slen, ceil_h, WALL_THICK) if (side == "north" or side == "south") else Vector3(WALL_THICK, ceil_h, slen)
	colliders.append({"pos": wpos, "size": sz, "rot_y": rot_rad})

# --- Door Plaques ---

func _build_room_plaque(room: Dictionary, origin: Vector3, basis: Basis, rot_rad: float, hw: float, hd: float, ceil_h: float, door_h: float, doors_by_side: Dictionary, open_sides: Dictionary, sec_col: Color, batch: Dictionary) -> void:
	var code := String(room.get("code", "")).strip_edges()
	var rname := String(room.get("name", "")).strip_edges()
	if code.is_empty() and rname.is_empty():
		return

	var plaque_text := rname
	if not code.is_empty():
		if rname.is_empty():
			plaque_text = code
		elif not rname.to_lower().begins_with(code.to_lower()):
			plaque_text = "%s • %s" % [code, rname]

	if plaque_text.length() > 34:
		plaque_text = plaque_text.substr(0, 33) + "…"

	var plate_w := clampf(float(plaque_text.length()) * 0.056 + 0.34, 0.72, 1.85)
	var plate_h := 0.25
	var plate_bg := Color("#1E252D")
	var wall_boxes: Array = batch["wall_boxes"]
	var plaques: Array = batch["plaques"]

	# Pick primary door (up to 2 doors for very large halls)
	var placed := 0
	for side in ["south", "north", "west", "east"]:
		if open_sides.has(side):
			continue
		var s_doors: Array = doors_by_side[side]
		if s_doors.is_empty():
			continue
		var d0: Dictionary = s_doors[0]
		var off := float(d0["offset"])
		var py := clampf(door_h + 0.22, 2.15, ceil_h - 0.18)
		var out_off := WALL_THICK * 0.5 + 0.025
		var lpos := _wall_local_pos(side, hw, hd, off, py, out_off)
		var side_yaw := _side_outward_yaw(side)
		var lbasis := Basis(Vector3.UP, side_yaw)
		var wpos := origin + basis * lpos
		var wbasis := basis * lbasis

		# Backing plate + sector accent strip on left
		wall_boxes.append({"xf": Transform3D(wbasis * Basis.from_scale(Vector3(plate_w, plate_h, 0.026)), wpos), "col": plate_bg})
		var stripe_pos := wpos + wbasis * Vector3(-plate_w * 0.5 + 0.045, 0.0, 0.005)
		wall_boxes.append({"xf": Transform3D(wbasis * Basis.from_scale(Vector3(0.08, plate_h, 0.032)), stripe_pos), "col": sec_col})

		var lbl_pos := wpos + wbasis * Vector3(0.035, 0.0, 0.018)
		plaques.append({
			"pos": lbl_pos,
			"rot_y": rot_rad + side_yaw,
			"text": plaque_text,
			"double_sided": false,
			"max_w": plate_w - 0.16
		})
		placed += 1
		if placed >= 1 and (hw * 2.0 < 12.0 and hd * 2.0 < 12.0):
			break
		if placed >= 2:
			break

	# If room has no doors (open reception/hall/lounge), hang plaque cleanly overhead
	if placed == 0:
		var py := minf(2.70, ceil_h - 0.35)
		var lpos := Vector3(0.0, py, 0.0)
		var yaw := 0.0
		if open_sides.has("south"):
			lpos.z = hd - 0.45
			yaw = 0.0
		elif open_sides.has("north"):
			lpos.z = -hd + 0.45
			yaw = PI
		elif open_sides.has("west"):
			lpos.x = -hw + 0.45
			yaw = -PI * 0.5
		elif open_sides.has("east"):
			lpos.x = hw - 0.45
			yaw = PI * 0.5

		var lbasis := Basis(Vector3.UP, yaw)
		var wpos := origin + basis * lpos
		var wbasis := basis * lbasis
		wall_boxes.append({"xf": Transform3D(wbasis * Basis.from_scale(Vector3(plate_w, plate_h, 0.035)), wpos), "col": plate_bg})
		var stripe_pos := wpos + wbasis * Vector3(0.0, -plate_h * 0.5 + 0.025, 0.0)
		wall_boxes.append({"xf": Transform3D(wbasis * Basis.from_scale(Vector3(plate_w, 0.045, 0.042)), stripe_pos), "col": sec_col})
		# Thin ceiling hangers
		var rod_h := maxf(0.1, ceil_h - (py + plate_h * 0.5))
		for sgn in [-1.0, 1.0]:
			var rpos := wpos + wbasis * Vector3(sgn * (plate_w * 0.38), plate_h * 0.5 + rod_h * 0.5, 0.0)
			wall_boxes.append({"xf": Transform3D(wbasis * Basis.from_scale(Vector3(0.025, rod_h, 0.025)), rpos), "col": Color("#2E343B")})

		plaques.append({
			"pos": wpos + wbasis * Vector3(0.0, 0.01, 0.024),
			"rot_y": rot_rad + yaw,
			"text": plaque_text,
			"double_sided": false,
			"max_w": plate_w - 0.12
		})
		plaques.append({
			"pos": wpos + wbasis * Vector3(0.0, 0.01, -0.024),
			"rot_y": rot_rad + yaw + PI,
			"text": plaque_text,
			"double_sided": false,
			"max_w": plate_w - 0.12
		})

func _side_outward_yaw(side: String) -> float:
	match side:
		"south":
			return 0.0
		"north":
			return PI
		"east":
			return PI * 0.5
		"west":
			return -PI * 0.5
		_:
			return 0.0

# --- Ceiling Light Strips ---

func _build_ceiling_lights(origin: Vector3, basis: Basis, w: float, d: float, ceil_h: float, light_xfs: Array) -> void:
	var ly := ceil_h - 0.05
	var nx := clampi(int(floor(w / 4.2)), 1, 4)
	var nz := clampi(int(floor(d / 4.2)), 1, 4)
	var along_x := w >= d
	var strip_sz := Vector3(1.15, 0.035, 0.22) if along_x else Vector3(0.22, 0.035, 1.15)
	for ix in range(nx):
		var tx := (float(ix) + 0.5) / float(nx) - 0.5
		var lx := tx * maxf(0.0, w - 1.4)
		for iz in range(nz):
			var tz := (float(iz) + 0.5) / float(nz) - 0.5
			var lz := tz * maxf(0.0, d - 1.4)
			light_xfs.append(_local_xf(origin, basis, Vector3(lx, ly, lz), strip_sz))

# --- Door Clearance Check ---

func _make_door_clearance_rect(side: String, offset: float, width: float, hw: float, hd: float) -> Dictionary:
	var pad := width * 0.5 + 0.38
	match side:
		"north":
			return {"min_x": offset - pad, "max_x": offset + pad, "min_z": -hd, "max_z": -hd + DOOR_CLEARANCE + 0.15}
		"south":
			return {"min_x": offset - pad, "max_x": offset + pad, "min_z": hd - DOOR_CLEARANCE - 0.15, "max_z": hd}
		"west":
			return {"min_x": -hw, "max_x": -hw + DOOR_CLEARANCE + 0.15, "min_z": offset - pad, "max_z": offset + pad}
		_:
			return {"min_x": hw - DOOR_CLEARANCE - 0.15, "max_x": hw, "min_z": offset - pad, "max_z": offset + pad}

func _is_clear_of_doors(door_zones: Array[Dictionary], lx: float, lz: float, half_x: float, half_z: float) -> bool:
	for dz in door_zones:
		if (lx + half_x) > float(dz["min_x"]) and (lx - half_x) < float(dz["max_x"]) and (lz + half_z) > float(dz["min_z"]) and (lz - half_z) < float(dz["max_z"]):
			return false
	return true

func _pick_front_side(open_sides: Dictionary, doors_by_side: Dictionary, w: float, d: float) -> String:
	var primary_door := ""
	for s in ["south", "north", "west", "east"]:
		if not (doors_by_side[s] as Array).is_empty():
			primary_door = s
			break
	var opp_map := {"south": "north", "north": "south", "west": "east", "east": "west"}
	if not primary_door.is_empty():
		var opp := String(opp_map[primary_door])
		if not open_sides.has(opp) and (doors_by_side[opp] as Array).is_empty():
			return opp
	var best_side := ""
	var best_len := -1.0
	for s in ["north", "south", "west", "east"]:
		if open_sides.has(s) or not (doors_by_side[s] as Array).is_empty():
			continue
		var slen := w if (s == "north" or s == "south") else d
		if slen > best_len:
			best_len = slen
			best_side = s
	if not best_side.is_empty():
		return best_side
	return "north"

# Transform a point in a front-oriented sub-frame (where -Z is front_side) back to room local XZ
func _front_to_room_xz(front_side: String, fx: float, fz: float) -> Vector2:
	match front_side:
		"north":
			return Vector2(fx, fz)
		"south":
			return Vector2(-fx, -fz)
		"east":
			return Vector2(-fz, fx)
		"west":
			return Vector2(fz, -fx)
		_:
			return Vector2(fx, fz)

func _front_yaw(front_side: String) -> float:
	match front_side:
		"north":
			return 0.0
		"south":
			return PI
		"east":
			return -PI * 0.5
		"west":
			return PI * 0.5
		_:
			return 0.0

func _front_dims(front_side: String, w: float, d: float) -> Vector2:
	if front_side == "east" or front_side == "west":
		return Vector2(d, w)
	return Vector2(w, d)

# --- Furniture Preset Dispatcher ---

func _build_room_furniture(room: Dictionary, origin: Vector3, basis: Basis, w: float, d: float, ceil_h: float, open_sides: Dictionary, doors_by_side: Dictionary, door_zones: Array[Dictionary], batch: Dictionary) -> void:
	var preset := String(room.get("preset", "admin")).to_lower()
	var n_name := _normalize_search_text(String(room.get("name", "")))
	var front_side := _pick_front_side(open_sides, doors_by_side, w, d)
	var f_dims := _front_dims(front_side, w, d)
	var fw := f_dims.x
	var fd := f_dims.y
	var f_basis := basis * Basis(Vector3.UP, _front_yaw(front_side))

	# Helper closure-like context dictionary passed to preset builders
	var ctx := {
		"origin": origin,
		"basis": basis,
		"f_basis": f_basis,
		"front_side": front_side,
		"w": w,
		"d": d,
		"fw": fw,
		"fd": fd,
		"ceil_h": ceil_h,
		"door_zones": door_zones,
		"open_sides": open_sides,
		"doors_by_side": doors_by_side,
		"boxes": batch["furn_boxes"],
		"cyls": batch["furn_cyls"],
		"name_norm": n_name
	}

	match preset:
		"classroom":
			_furn_classroom(ctx)
		"computer_lab":
			_furn_computer_lab(ctx)
		"industrial_lab":
			_furn_industrial_lab(ctx)
		"admin", "office", "meeting", "health":
			_furn_admin(ctx, preset)
		"reception":
			_furn_reception(ctx)
		"auditorium":
			_furn_auditorium(ctx)
		"canteen":
			_furn_canteen(ctx)
		"library":
			_furn_library(ctx)
		"student_org", "lounge", "convivencia":
			_furn_student_org(ctx)
		"restroom":
			_furn_restroom(ctx)
		"gym":
			_furn_gym(ctx)
		"social":
			_furn_social(ctx)
		"garage", "storage", "maintenance":
			_furn_garage(ctx, preset)
		"stair", "stairs":
			_furn_stair(ctx)
		"gallery":
			_furn_gallery(ctx)
		"corridor", "open", "hall":
			pass
		_:
			_furn_admin(ctx, "admin")

# --- Furniture Placement Helpers ---

func _f_clear(ctx: Dictionary, fx: float, fz: float, hx: float, hz: float) -> bool:
	var fside := String(ctx["front_side"])
	var rpos := _front_to_room_xz(fside, fx, fz)
	var rhx := hx if (fside == "north" or fside == "south") else hz
	var rhz := hz if (fside == "north" or fside == "south") else hx
	var hw := float(ctx["w"]) * 0.5 - 0.18
	var hd := float(ctx["d"]) * 0.5 - 0.18
	if absf(rpos.x) + rhx > hw or absf(rpos.y) + rhz > hd:
		return false
	return _is_clear_of_doors(ctx["door_zones"], rpos.x, rpos.y, rhx, rhz)

func _f_box(ctx: Dictionary, lpos: Vector3, sz: Vector3, col: Color, yaw: float = 0.0) -> void:
	var fb: Basis = ctx["f_basis"]
	var org: Vector3 = ctx["origin"]
	var b := (fb * Basis(Vector3.UP, yaw)) if not is_zero_approx(yaw) else fb
	var xf := Transform3D(b * Basis.from_scale(sz), org + fb * Vector3(lpos.x, FLOOR_Y + lpos.y, lpos.z))
	(ctx["boxes"] as Array).append({"xf": xf, "col": col})

func _f_cyl(ctx: Dictionary, lpos: Vector3, sz: Vector3, col: Color) -> void:
	var fb: Basis = ctx["f_basis"]
	var org: Vector3 = ctx["origin"]
	var xf := Transform3D(fb * Basis.from_scale(sz), org + fb * Vector3(lpos.x, FLOOR_Y + lpos.y, lpos.z))
	(ctx["cyls"] as Array).append({"xf": xf, "col": col})

func _add_board_on_front(ctx: Dictionary, is_chalkboard: bool = true) -> void:
	var fw := float(ctx["fw"])
	var fd := float(ctx["fd"])
	var bw := clampf(fw * 0.56, 1.4, 3.6)
	var bz := -fd * 0.5 + WALL_THICK + 0.04
	var surface_col := Color("#1E4D32") if is_chalkboard else Color("#F3F6F9")
	_f_box(ctx, Vector3(0.0, 1.52, bz), Vector3(bw + 0.08, 1.18, 0.04), Color("#9AA3AD"))
	_f_box(ctx, Vector3(0.0, 1.52, bz + 0.015), Vector3(bw, 1.10, 0.03), surface_col)
	_f_box(ctx, Vector3(0.0, 0.94, bz + 0.06), Vector3(bw, 0.04, 0.09), Color("#7F8A94"))

func _add_chair(ctx: Dictionary, fx: float, fz: float, seat_col: Color, yaw: float = 0.0) -> void:
	var frame := Color("#2D3238")
	var fb: Basis = ctx["f_basis"]
	var org: Vector3 = ctx["origin"]
	var rb := fb * Basis(Vector3.UP, yaw)
	var base_p := org + fb * Vector3(fx, FLOOR_Y, fz)
	var boxes: Array = ctx["boxes"]
	boxes.append({"xf": Transform3D(rb * Basis.from_scale(Vector3(0.42, 0.05, 0.40)), base_p + rb * Vector3(0.0, 0.44, 0.0)), "col": seat_col})
	boxes.append({"xf": Transform3D(rb * Basis.from_scale(Vector3(0.42, 0.36, 0.05)), base_p + rb * Vector3(0.0, 0.64, 0.18)), "col": seat_col})
	boxes.append({"xf": Transform3D(rb * Basis.from_scale(Vector3(0.38, 0.42, 0.05)), base_p + rb * Vector3(0.0, 0.21, 0.15)), "col": frame})
	boxes.append({"xf": Transform3D(rb * Basis.from_scale(Vector3(0.38, 0.42, 0.05)), base_p + rb * Vector3(0.0, 0.21, -0.15)), "col": frame})

func _add_desk(ctx: Dictionary, fx: float, fz: float, dw: float, dd: float, top_col: Color, yaw: float = 0.0) -> void:
	var leg_col := Color("#394048")
	var fb: Basis = ctx["f_basis"]
	var org: Vector3 = ctx["origin"]
	var rb := fb * Basis(Vector3.UP, yaw)
	var base_p := org + fb * Vector3(fx, FLOOR_Y, fz)
	var boxes: Array = ctx["boxes"]
	boxes.append({"xf": Transform3D(rb * Basis.from_scale(Vector3(dw, 0.05, dd)), base_p + rb * Vector3(0.0, 0.74, 0.0)), "col": top_col})
	var lx := dw * 0.5 - 0.05
	boxes.append({"xf": Transform3D(rb * Basis.from_scale(Vector3(0.05, 0.72, dd - 0.06)), base_p + rb * Vector3(-lx, 0.36, 0.0)), "col": leg_col})
	boxes.append({"xf": Transform3D(rb * Basis.from_scale(Vector3(0.05, 0.72, dd - 0.06)), base_p + rb * Vector3(lx, 0.36, 0.0)), "col": leg_col})

func _add_monitor(ctx: Dictionary, fx: float, fz: float, yaw: float = 0.0) -> void:
	var fb: Basis = ctx["f_basis"]
	var org: Vector3 = ctx["origin"]
	var rb := fb * Basis(Vector3.UP, yaw)
	var base_p := org + fb * Vector3(fx, FLOOR_Y + 0.77, fz)
	var boxes: Array = ctx["boxes"]
	boxes.append({"xf": Transform3D(rb * Basis.from_scale(Vector3(0.16, 0.03, 0.14)), base_p + rb * Vector3(0.0, 0.015, 0.0)), "col": Color("#22272E")})
	boxes.append({"xf": Transform3D(rb * Basis.from_scale(Vector3(0.05, 0.14, 0.04)), base_p + rb * Vector3(0.0, 0.09, -0.02)), "col": Color("#2A3038")})
	boxes.append({"xf": Transform3D(rb * Basis.from_scale(Vector3(0.50, 0.32, 0.035)), base_p + rb * Vector3(0.0, 0.28, 0.0)), "col": Color("#191D23")})
	boxes.append({"xf": Transform3D(rb * Basis.from_scale(Vector3(0.45, 0.27, 0.012)), base_p + rb * Vector3(0.0, 0.28, 0.018)), "col": Color("#2E5070")})

# --- Preset Implementations ---

func _furn_classroom(ctx: Dictionary) -> void:
	var fw := float(ctx["fw"])
	var fd := float(ctx["fd"])
	_add_board_on_front(ctx, true)

	# Teacher desk & chair near front-left or front-center
	var tz := -fd * 0.5 + 1.25
	var tx := clampf(-fw * 0.24, -fw * 0.5 + 1.0, fw * 0.5 - 1.0)
	if _f_clear(ctx, tx, tz, 0.72, 0.45):
		_add_desk(ctx, tx, tz, 1.28, 0.64, Color("#C39768"))
		_add_chair(ctx, tx, tz - 0.42, Color("#2A3D4F"), PI)

	# Auto-scaled rows of student desks + chairs
	var z_start := -fd * 0.5 + 2.35
	var z_end := fd * 0.5 - 0.85
	var x_span := fw - 1.5
	var cols := clampi(int(floor(x_span / 1.22)), 1, 5)
	var rows := clampi(int(floor((z_end - z_start) / 1.25)) + 1, 1, 5)
	if z_end < z_start:
		rows = 0

	var desk_col := Color("#D8BA8B")
	var seat_col := Color("#2F7D3E")
	for r in range(rows):
		var z := z_start + float(r) * 1.22
		if z > z_end:
			break
		for c in range(cols):
			var t := (float(c) + 0.5) / float(cols) - 0.5
			var x := t * maxf(0.0, x_span - 0.6)
			if _f_clear(ctx, x, z, 0.42, 0.52):
				_add_desk(ctx, x, z, 0.68, 0.48, desk_col)
				_add_chair(ctx, x, z + 0.36, seat_col, 0.0)

func _furn_computer_lab(ctx: Dictionary) -> void:
	var fw := float(ctx["fw"])
	var fd := float(ctx["fd"])
	_add_board_on_front(ctx, false)

	var bench_col := Color("#D7DCE2")
	var chair_col := Color("#232931")
	var pc_col := Color("#2B313A")

	# Rows of long computer lab benches with monitors and chairs
	var z_start := -fd * 0.5 + 1.85
	var z_end := fd * 0.5 - 0.95
	var row_step := 1.55
	var rows := clampi(int(floor((z_end - z_start) / row_step)) + 1, 1, 4)
	if z_end < z_start:
		rows = 1
		z_start = 0.0

	var usable_w := maxf(1.2, fw - 1.6)
	var seats_per_row := clampi(int(floor(usable_w / 1.10)), 1, 6)

	for r in range(rows):
		var z := z_start + float(r) * row_step
		if z > z_end + 0.15:
			break
		for s in range(seats_per_row):
			var t := (float(s) + 0.5) / float(seats_per_row) - 0.5
			var x := t * maxf(0.0, usable_w - 0.8)
			if not _f_clear(ctx, x, z, 0.54, 0.58):
				continue
			_add_desk(ctx, x, z, 1.02, 0.62, bench_col)
			_add_monitor(ctx, x, z - 0.10, 0.0)
			# Keyboard + PC tower
			_f_box(ctx, Vector3(x, 0.78, z + 0.14), Vector3(0.38, 0.02, 0.13), Color("#252A30"))
			_f_box(ctx, Vector3(x + 0.36, 0.24, z - 0.05), Vector3(0.18, 0.42, 0.38), pc_col)
			_add_chair(ctx, x, z + 0.42, chair_col, 0.0)

func _furn_industrial_lab(ctx: Dictionary) -> void:
	var fw := float(ctx["fw"])
	var fd := float(ctx["fd"])
	var n_name := String(ctx["name_norm"])
	var is_chem := n_name.contains("quimic") or n_name.contains("lcq") or n_name.contains("bio") or n_name.contains("reciclag")

	if is_chem:
		# Chemistry / Bio / LCQ lab: fume hoods on front wall + dark slate island benches + glassware
		var hood_count := clampi(int(floor((fw - 1.6) / 2.2)), 1, 3)
		var hz := -fd * 0.5 + 0.65
		for hi in range(hood_count):
			var t := (float(hi) + 0.5) / float(hood_count) - 0.5
			var hx := t * maxf(0.0, fw - 2.4)
			if _f_clear(ctx, hx, hz, 0.85, 0.55):
				_f_box(ctx, Vector3(hx, 0.45, hz), Vector3(1.55, 0.90, 0.78), Color("#D8DEE4"))
				_f_box(ctx, Vector3(hx, 1.48, hz - 0.06), Vector3(1.55, 1.15, 0.66), Color("#E6EAEE"))
				_f_box(ctx, Vector3(hx, 1.38, hz + 0.28), Vector3(1.32, 0.78, 0.04), Color("#3E657D"))

		# Island slate benches
		var z_start := -fd * 0.5 + 2.4
		var z_end := fd * 0.5 - 1.2
		var rows := clampi(int(floor((z_end - z_start) / 2.4)) + 1, 1, 3)
		var bw := clampf(fw - 2.6, 1.8, 5.2)
		var flask_cols := [Color("#3B82F6"), Color("#10B981"), Color("#F59E0B"), Color("#EF4444")]
		for r in range(rows):
			var bz := z_start + float(r) * 2.35
			if bz > z_end:
				break
			if _f_clear(ctx, 0.0, bz, bw * 0.5, 0.62):
				_f_box(ctx, Vector3(0.0, 0.43, bz), Vector3(bw - 0.1, 0.86, 1.05), Color("#DCE1E6"))
				_f_box(ctx, Vector3(0.0, 0.89, bz), Vector3(bw, 0.06, 1.16), Color("#2B323A"))
				_f_box(ctx, Vector3(0.0, 1.22, bz), Vector3(bw * 0.82, 0.05, 0.24), Color("#9AA5B1"))
				var n_fl := clampi(int(bw * 1.4), 2, 7)
				for fi in range(n_fl):
					var ft := (float(fi) + 0.5) / float(n_fl) - 0.5
					_f_cyl(ctx, Vector3(ft * (bw * 0.72), 1.35, bz), Vector3(0.11, 0.22, 0.11), flask_cols[(r + fi) % flask_cols.size()])
		# Yellow safety shower post
		if _f_clear(ctx, fw * 0.5 - 0.65, -fd * 0.5 + 0.75, 0.35, 0.35):
			_f_cyl(ctx, Vector3(fw * 0.5 - 0.65, 1.15, -fd * 0.5 + 0.75), Vector3(0.10, 2.30, 0.10), Color("#EAB308"))
	else:
		# Mechanical / CNC / Plastics / Innovation workshop
		var safety_yellow := Color("#EAB308")
		var mach_body := Color("#CFD6DD")
		var mach_accent := Color("#32536E")
		var bench_top := Color("#B98956")

		# Heavy machinery stations (CNC enclosures / injection molders)
		var m_cols := clampi(int(floor((fw - 1.8) / 3.4)), 1, 4)
		var m_rows := clampi(int(floor((fd - 2.0) / 3.6)), 1, 3)
		for mr in range(m_rows):
			var tz := (float(mr) + 0.5) / float(m_rows) - 0.5
			var mz := tz * maxf(0.0, fd - 3.2)
			for mc in range(m_cols):
				var tx := (float(mc) + 0.5) / float(m_cols) - 0.5
				var mx := tx * maxf(0.0, fw - 3.0)
				if not _f_clear(ctx, mx, mz, 1.15, 0.95):
					continue
				if (mr + mc) % 2 == 0:
					# Stylized CNC / Injection Machine with safety yellow base stripe
					_f_box(ctx, Vector3(mx, 0.012, mz), Vector3(2.25, 0.015, 1.65), safety_yellow)
					_f_box(ctx, Vector3(mx, 0.92, mz), Vector3(1.85, 1.84, 1.20), mach_body)
					_f_box(ctx, Vector3(mx, 1.52, mz + 0.61), Vector3(1.86, 0.36, 0.04), mach_accent)
					_f_box(ctx, Vector3(mx - 0.25, 1.05, mz + 0.61), Vector3(0.75, 0.55, 0.04), Color("#25394A"))
					_f_box(ctx, Vector3(mx + 0.58, 1.12, mz + 0.63), Vector3(0.32, 0.42, 0.06), Color("#1E242B"))
					_f_box(ctx, Vector3(mx, 0.14, mz + 0.61), Vector3(1.86, 0.10, 0.04), safety_yellow)
				else:
					# Heavy technical workbench with tool cabinet + vise
					_f_box(ctx, Vector3(mx, 0.42, mz), Vector3(1.90, 0.84, 0.85), Color("#4A545E"))
					_f_box(ctx, Vector3(mx, 0.88, mz), Vector3(2.00, 0.08, 0.94), bench_top)
					_f_box(ctx, Vector3(mx - 0.65, 1.00, mz + 0.25), Vector3(0.24, 0.18, 0.28), Color("#2E6A9E"))
					_f_box(ctx, Vector3(mx + 0.55, 1.04, mz - 0.15), Vector3(0.45, 0.24, 0.26), Color("#CD191E"))

func _furn_reception(ctx: Dictionary) -> void:
	var fw := float(ctx["fw"])
	var fd := float(ctx["fd"])
	var cw := clampf(fw * 0.52, 1.8, 4.4)
	var cz := -fd * 0.12
	if _f_clear(ctx, 0.0, cz, cw * 0.5, 0.55):
		_f_box(ctx, Vector3(0.0, 0.52, cz), Vector3(cw, 1.04, 0.72), Color("#E6E2DA"))
		_f_box(ctx, Vector3(0.0, 0.52, cz + 0.37), Vector3(cw, 0.88, 0.04), Color("#2F9E41"))
		_f_box(ctx, Vector3(0.0, 1.06, cz), Vector3(cw + 0.08, 0.06, 0.80), Color("#C69B6D"))
		_add_monitor(ctx, -cw * 0.22, cz - 0.08, 0.0)
		if cw >= 2.8:
			_add_monitor(ctx, cw * 0.22, cz - 0.08, 0.0)
		_add_chair(ctx, 0.0, cz - 0.62, Color("#242B33"), PI)

	# Visitor waiting bench on opposite side
	var bz := fd * 0.32
	if _f_clear(ctx, 0.0, bz, 0.95, 0.35):
		_f_box(ctx, Vector3(0.0, 0.44, bz), Vector3(1.80, 0.09, 0.48), Color("#2F4858"))
		_f_box(ctx, Vector3(0.0, 0.72, bz + 0.20), Vector3(1.80, 0.42, 0.07), Color("#2F4858"))
		_f_box(ctx, Vector3(-0.72, 0.22, bz), Vector3(0.08, 0.44, 0.40), Color("#3A414A"))
		_f_box(ctx, Vector3(0.72, 0.22, bz), Vector3(0.08, 0.44, 0.40), Color("#3A414A"))

func _furn_admin(ctx: Dictionary, preset: String) -> void:
	var fw := float(ctx["fw"])
	var fd := float(ctx["fd"])
	var n_name := String(ctx["name_norm"])

	if n_name.contains("recepcao") or n_name.contains("corac") or n_name.contains("atendimento"):
		_furn_reception(ctx)
		return

	if preset == "meeting" or n_name.contains("reunio"):
		# Conference table + chairs + display screen
		var tw := clampf(fw * 0.56, 1.8, 4.4)
		var td := clampf(fd * 0.38, 1.0, 1.8)
		if _f_clear(ctx, 0.0, 0.0, tw * 0.5, td * 0.5):
			_add_desk(ctx, 0.0, 0.0, tw, td, Color("#7D5436"))
			var n_ch := clampi(int(floor(tw / 0.85)), 2, 5)
			for ci in range(n_ch):
				var ct := (float(ci) + 0.5) / float(n_ch) - 0.5
				var cx := ct * (tw - 0.45)
				if _f_clear(ctx, cx, -td * 0.5 - 0.35, 0.25, 0.25):
					_add_chair(ctx, cx, -td * 0.5 - 0.35, Color("#293845"), PI)
				if _f_clear(ctx, cx, td * 0.5 + 0.35, 0.25, 0.25):
					_add_chair(ctx, cx, td * 0.5 + 0.35, Color("#293845"), 0.0)
		_add_board_on_front(ctx, false)
		return

	if preset == "health" or n_name.contains("saude") or n_name.contains("psicolog"):
		# Consultation desk + exam couch or lounge sofa
		var dx := -fw * 0.20
		var dz := -fd * 0.15
		if _f_clear(ctx, dx, dz, 0.72, 0.52):
			_add_desk(ctx, dx, dz, 1.35, 0.68, Color("#DFD9CE"))
			_add_monitor(ctx, dx + 0.15, dz - 0.12, 0.0)
			_add_chair(ctx, dx, dz - 0.48, Color("#2B5C78"), PI)
			_add_chair(ctx, dx, dz + 0.48, Color("#2F7D3E"), 0.0)
		var ex := fw * 0.25
		if _f_clear(ctx, ex, -fd * 0.10, 0.55, 0.95):
			_f_box(ctx, Vector3(ex, 0.35, -fd * 0.10), Vector3(0.80, 0.58, 1.85), Color("#F0F4F8"))
			_f_box(ctx, Vector3(ex, 0.68, -fd * 0.10), Vector3(0.82, 0.12, 1.88), Color("#3B82A6"))
		return

	# Standard administrative office: desks with monitors + filing cabinets along front wall
	var cab_n := clampi(int(floor((fw - 1.2) / 1.4)), 1, 4)
	var cab_z := -fd * 0.5 + 0.42
	for ci in range(cab_n):
		var ct := (float(ci) + 0.5) / float(cab_n) - 0.5
		var cx := ct * maxf(0.0, fw - 1.8)
		if _f_clear(ctx, cx, cab_z, 0.42, 0.30):
			_f_box(ctx, Vector3(cx, 0.90, cab_z), Vector3(0.78, 1.80, 0.46), Color("#8E98A3"))
			_f_box(ctx, Vector3(cx, 0.90, cab_z + 0.235), Vector3(0.70, 1.66, 0.02), Color("#A5AEB8"))

	var cols := clampi(int(floor((fw - 1.2) / 1.9)), 1, 3)
	var rows := clampi(int(floor((fd - 2.0) / 2.0)), 1, 2)
	for r in range(rows):
		var tz := (float(r) + 0.5) / float(rows) - 0.5
		var dz := tz * maxf(0.0, fd - 2.6) + 0.35
		for c in range(cols):
			var tx := (float(c) + 0.5) / float(cols) - 0.5
			var dx := tx * maxf(0.0, fw - 2.2)
			if _f_clear(ctx, dx, dz, 0.72, 0.58):
				_add_desk(ctx, dx, dz, 1.32, 0.66, Color("#CBB192"))
				_add_monitor(ctx, dx - 0.12, dz - 0.10, 0.0)
				_add_chair(ctx, dx, dz + 0.44, Color("#27303A"), 0.0)

func _furn_auditorium(ctx: Dictionary) -> void:
	var fw := float(ctx["fw"])
	var fd := float(ctx["fd"])
	var stage_d := clampf(fd * 0.22, 2.2, 4.4)
	var stage_w := maxf(2.4, fw - 0.8)
	var stage_z := -fd * 0.5 + stage_d * 0.5 + 0.15

	# Raised wooden stage + lectern + wide projection screen
	if _f_clear(ctx, 0.0, stage_z, stage_w * 0.5, stage_d * 0.5):
		_f_box(ctx, Vector3(0.0, 0.26, stage_z), Vector3(stage_w, 0.52, stage_d), Color("#7D5436"))
		# Lectern on stage right
		var lx := minf(stage_w * 0.30, 2.2)
		_f_box(ctx, Vector3(lx, 0.98, stage_z + stage_d * 0.25), Vector3(0.58, 0.94, 0.48), Color("#463120"))
		_f_box(ctx, Vector3(lx, 1.04, stage_z + stage_d * 0.25 + 0.25), Vector3(0.46, 0.36, 0.04), Color("#2F9E41"))
	# Wide projection screen on front wall
	var scr_w := clampf(fw * 0.58, 2.6, 7.2)
	var scr_z := -fd * 0.5 + WALL_THICK + 0.05
	_f_box(ctx, Vector3(0.0, 2.35, scr_z), Vector3(scr_w + 0.16, 2.26, 0.05), Color("#1A1E24"))
	_f_box(ctx, Vector3(0.0, 2.35, scr_z + 0.025), Vector3(scr_w, 2.10, 0.03), Color("#F4F6F8"))

	# Rows of plush auditorium seats split by a generous 1.6m center walking aisle
	var z_start := -fd * 0.5 + stage_d + 1.55
	var z_end := fd * 0.5 - 1.15
	var row_step := 1.05
	var rows := clampi(int(floor((z_end - z_start) / row_step)) + 1, 1, 14)
	if z_end < z_start:
		rows = 0

	var half_aisle := 0.85
	var seat_col_a := Color("#B8262C") # IFSul accent red
	var seat_col_b := Color("#2A7A3A") # IFSul accent green
	var arm_col := Color("#23272D")

	for r in range(rows):
		var rz := z_start + float(r) * row_step
		if rz > z_end:
			break
		var seat_c := seat_col_a if (r % 4 != 0) else seat_col_b
		var side_w := fw * 0.5 - half_aisle - 0.65
		var per_side := clampi(int(floor(side_w / 0.68)), 1, 8)
		for side_sgn: float in [-1.0, 1.0]:
			for si in range(per_side):
				var sx: float = side_sgn * (half_aisle + 0.42 + float(si) * 0.66)
				if not _f_clear(ctx, sx, rz, 0.32, 0.36):
					continue
				_f_box(ctx, Vector3(sx, 0.42, rz), Vector3(0.54, 0.12, 0.46), seat_c)
				_f_box(ctx, Vector3(sx, 0.72, rz + 0.20), Vector3(0.54, 0.54, 0.10), seat_c)
				_f_box(ctx, Vector3(sx, 0.20, rz), Vector3(0.46, 0.40, 0.10), arm_col)

func _furn_canteen(ctx: Dictionary) -> void:
	var fw := float(ctx["fw"])
	var fd := float(ctx["fd"])

	# Service counter + pastry display case along front wall
	var cw := clampf(fw * 0.68, 2.2, 7.5)
	var cz := -fd * 0.5 + 1.15
	if _f_clear(ctx, 0.0, cz, cw * 0.5, 0.52):
		_f_box(ctx, Vector3(0.0, 0.48, cz), Vector3(cw, 0.96, 0.76), Color("#EAE5DC"))
		_f_box(ctx, Vector3(0.0, 0.48, cz + 0.39), Vector3(cw, 0.78, 0.04), Color("#2F9E41"))
		_f_box(ctx, Vector3(0.0, 0.99, cz), Vector3(cw + 0.08, 0.06, 0.84), Color("#C99B68"))
		# Display case
		_f_box(ctx, Vector3(-cw * 0.24, 1.24, cz + 0.08), Vector3(minf(1.5, cw * 0.35), 0.44, 0.52), Color("#9EC4DB"))
		# Menu board on back wall
		_f_box(ctx, Vector3(0.0, 1.85, -fd * 0.5 + WALL_THICK + 0.05), Vector3(minf(3.2, cw * 0.6), 0.85, 0.04), Color("#1E2832"))

	# Dining tables + colorful stools
	var z_start := -fd * 0.5 + 2.8
	var z_end := fd * 0.5 - 1.0
	var cols := clampi(int(floor((fw - 1.6) / 2.2)), 1, 5)
	var rows := clampi(int(floor((z_end - z_start) / 2.1)) + 1, 1, 4)
	if z_end < z_start:
		rows = 1
		z_start = 0.25

	var stool_cols: Array[Color] = [Color("#2F9E41"), Color("#D97706"), Color("#3B5E7A")]
	for r in range(rows):
		var tz := z_start + float(r) * 2.05
		if tz > z_end + 0.1:
			break
		for c in range(cols):
			var tx := ((float(c) + 0.5) / float(cols) - 0.5) * maxf(0.0, fw - 2.4)
			if not _f_clear(ctx, tx, tz, 0.72, 0.68):
				continue
			_add_desk(ctx, tx, tz, 1.15, 0.72, Color("#D6B284"))
			var sc: Color = stool_cols[(r + c) % stool_cols.size()]
			for sx_off: float in [-0.32, 0.32]:
				for sz_off: float in [-0.52, 0.52]:
					_f_cyl(ctx, Vector3(tx + sx_off, 0.23, tz + sz_off), Vector3(0.08, 0.44, 0.08), Color("#363D45"))
					_f_cyl(ctx, Vector3(tx + sx_off, 0.47, tz + sz_off), Vector3(0.32, 0.06, 0.32), sc)

func _furn_library(ctx: Dictionary) -> void:
	var fw := float(ctx["fw"])
	var fd := float(ctx["fd"])
	var n_name := String(ctx["name_norm"])
	var wood_shelf := Color("#7C5638")
	var book_cols: Array[Color] = [Color("#B9382C"), Color("#2A6F97"), Color("#2F855A"), Color("#D49B2A"), Color("#5B4B8A"), Color("#D96B27")]

	# Central circulation counter if large or named atendimento/central/biblioteca
	var is_central := (fw >= 6.5 and fd >= 6.5) or n_name.contains("central") or n_name.contains("balcao")
	if is_central and _f_clear(ctx, 0.0, -fd * 0.22, 1.4, 0.55):
		_f_box(ctx, Vector3(0.0, 0.50, -fd * 0.22), Vector3(2.6, 1.00, 0.75), Color("#8B5E3C"))
		_f_box(ctx, Vector3(0.0, 0.50, -fd * 0.22 + 0.38), Vector3(2.6, 0.24, 0.04), Color("#1EC7C3"))
		_add_monitor(ctx, 0.0, -fd * 0.22, 0.0)

	# Rows of double-sided bookshelves filled with colored book blocks
	var shelf_w := clampf(fw * 0.34, 1.4, 3.2)
	var cols := 2 if fw >= 5.2 else 1
	var z_start := -fd * 0.5 + (2.6 if is_central else 1.2)
	var z_end := fd * 0.5 - 1.3
	var rows := clampi(int(floor((z_end - z_start) / 1.9)) + 1, 1, 5)
	if z_end < z_start:
		rows = 1
		z_start = 0.0

	for r in range(rows):
		var sz := z_start + float(r) * 1.85
		if sz > z_end + 0.2:
			break
		for c in range(cols):
			var sx := 0.0 if cols == 1 else ((-1.0 if c == 0 else 1.0) * maxf(1.2, fw * 0.24))
			if not _f_clear(ctx, sx, sz, shelf_w * 0.5 + 0.1, 0.34):
				continue
			# Bookshelf outer frame
			_f_box(ctx, Vector3(sx, 1.02, sz), Vector3(shelf_w, 2.04, 0.44), wood_shelf)
			# 4 tiers of colorful book clusters on both sides
			for tier in range(4):
				var by := 0.32 + float(tier) * 0.45
				for seg in range(3):
					var seg_w := (shelf_w - 0.20) / 3.0
					var bx := sx - (shelf_w - 0.20) * 0.5 + (float(seg) + 0.5) * seg_w
					var bcol: Color = book_cols[(r * 5 + c * 3 + tier * 2 + seg) % book_cols.size()]
					_f_box(ctx, Vector3(bx, by, sz), Vector3(seg_w - 0.05, 0.30, 0.48), bcol)

	# Reading/study table near the back if space allows
	var study_z := fd * 0.5 - 1.05
	if _f_clear(ctx, 0.0, study_z, 0.95, 0.55):
		_add_desk(ctx, 0.0, study_z, 1.75, 0.84, Color("#C9A172"))
		_add_chair(ctx, -0.45, study_z - 0.52, Color("#1E7B78"), PI)
		_add_chair(ctx, 0.45, study_z - 0.52, Color("#1E7B78"), PI)

func _furn_student_org(ctx: Dictionary) -> void:
	var fw := float(ctx["fw"])
	var fd := float(ctx["fd"])

	# Cork bulletin board on front wall
	var bw := clampf(fw * 0.45, 1.2, 2.6)
	var bz := -fd * 0.5 + WALL_THICK + 0.04
	_f_box(ctx, Vector3(0.0, 1.50, bz), Vector3(bw + 0.08, 1.05, 0.04), Color("#6E4B2E"))
	_f_box(ctx, Vector3(0.0, 1.50, bz + 0.015), Vector3(bw, 0.96, 0.03), Color("#BC8954"))
	_f_box(ctx, Vector3(-bw * 0.25, 1.58, bz + 0.035), Vector3(0.28, 0.36, 0.01), Color("#F8FAFC"))
	_f_box(ctx, Vector3(bw * 0.15, 1.45, bz + 0.035), Vector3(0.32, 0.26, 0.01), Color("#FEF08A"))

	# Lounge sofas + central coffee/meeting table
	var sofa_col := Color("#2E6F40")
	var sofa_alt := Color("#355978")
	var sx := minf(fw * 0.28, 2.1)
	if _f_clear(ctx, -sx, 0.0, 0.52, 0.95):
		_f_box(ctx, Vector3(-sx, 0.26, 0.0), Vector3(0.76, 0.44, 1.75), sofa_col)
		_f_box(ctx, Vector3(-sx - 0.32, 0.62, 0.0), Vector3(0.16, 0.48, 1.75), sofa_col)
	if _f_clear(ctx, sx, 0.0, 0.52, 0.95):
		_f_box(ctx, Vector3(sx, 0.26, 0.0), Vector3(0.76, 0.44, 1.75), sofa_alt)
		_f_box(ctx, Vector3(sx + 0.32, 0.62, 0.0), Vector3(0.16, 0.48, 1.75), sofa_alt)
	if _f_clear(ctx, 0.0, 0.0, 0.55, 0.65):
		_add_desk(ctx, 0.0, 0.0, 0.95, 1.15, Color("#C69C6D"))

func _furn_restroom(ctx: Dictionary) -> void:
	var fw := float(ctx["fw"])
	var fd := float(ctx["fd"])
	var div_col := Color("#D0D6DC")
	var ceramic := Color("#F4F6F8")

	# Row of stall dividers along front wall
	var stalls := clampi(int(floor((fw - 0.8) / 1.15)), 1, 5)
	var stall_d := minf(1.35, fd * 0.38)
	var sz := -fd * 0.5 + stall_d * 0.5 + 0.12
	for si in range(stalls):
		var t := (float(si) + 0.5) / float(stalls) - 0.5
		var sx := t * maxf(0.0, fw - 1.2)
		if _f_clear(ctx, sx, sz, 0.45, stall_d * 0.5):
			_f_box(ctx, Vector3(sx + 0.52, 1.08, sz), Vector3(0.05, 1.85, stall_d), div_col)
			_f_box(ctx, Vector3(sx, 0.26, -fd * 0.5 + 0.42), Vector3(0.38, 0.44, 0.52), ceramic)

	# Sink counter + mirror along opposite or side wall
	var sink_z := fd * 0.5 - 0.45
	var sink_w := clampf(fw * 0.55, 1.0, 3.6)
	if _f_clear(ctx, 0.0, sink_z, sink_w * 0.5, 0.35):
		_f_box(ctx, Vector3(0.0, 0.42, sink_z), Vector3(sink_w, 0.82, 0.52), Color("#C5CCD4"))
		_f_box(ctx, Vector3(0.0, 1.48, fd * 0.5 - WALL_THICK - 0.03), Vector3(sink_w * 0.9, 0.88, 0.03), Color("#8AB2C8"))

func _furn_gym(ctx: Dictionary) -> void:
	var fw := float(ctx["fw"])
	var fd := float(ctx["fd"])
	# Dark rubberized workout mat area
	if _f_clear(ctx, 0.0, 0.0, fw * 0.34, fd * 0.34):
		_f_box(ctx, Vector3(0.0, 0.01, 0.0), Vector3(fw * 0.66, 0.02, fd * 0.66), Color("#2A3038"))

	# Weight benches & squat/dumbbell racks
	var cols := clampi(int(floor((fw - 1.6) / 2.2)), 1, 4)
	for c in range(cols):
		var tx := ((float(c) + 0.5) / float(cols) - 0.5) * maxf(0.0, fw - 2.4)
		if _f_clear(ctx, tx, -fd * 0.12, 0.55, 0.80):
			_f_box(ctx, Vector3(tx, 0.46, -fd * 0.12), Vector3(0.38, 0.10, 1.25), Color("#CD191E"))
			_f_box(ctx, Vector3(tx, 0.23, -fd * 0.12), Vector3(0.30, 0.44, 0.95), Color("#232830"))
			# Barbell rack uprights + horizontal barbell with weight plates
			_f_box(ctx, Vector3(tx - 0.48, 0.72, -fd * 0.12 - 0.45), Vector3(0.07, 1.44, 0.07), Color("#4A5568"))
			_f_box(ctx, Vector3(tx + 0.48, 0.72, -fd * 0.12 - 0.45), Vector3(0.07, 1.44, 0.07), Color("#4A5568"))
			_f_box(ctx, Vector3(tx, 1.12, -fd * 0.12 - 0.45), Vector3(1.52, 0.05, 0.05), Color("#9AA3AD"))
			_f_box(ctx, Vector3(tx - 0.68, 1.12, -fd * 0.12 - 0.45), Vector3(0.08, 0.34, 0.34), Color("#1F242B"))
			_f_box(ctx, Vector3(tx + 0.68, 1.12, -fd * 0.12 - 0.45), Vector3(0.08, 0.34, 0.34), Color("#1F242B"))

func _furn_social(ctx: Dictionary) -> void:
	var fw := float(ctx["fw"])
	var fd := float(ctx["fd"])
	# Kitchen / barbecue grill counter along front wall
	var kw := clampf(fw * 0.62, 2.0, 5.4)
	var kz := -fd * 0.5 + 0.58
	if _f_clear(ctx, 0.0, kz, kw * 0.5, 0.45):
		_f_box(ctx, Vector3(0.0, 0.44, kz), Vector3(kw, 0.88, 0.70), Color("#D6D0C6"))
		_f_box(ctx, Vector3(-kw * 0.30, 1.35, kz - 0.05), Vector3(1.10, 1.95, 0.68), Color("#A8533E")) # Churrasqueira brick chimney
		_f_box(ctx, Vector3(-kw * 0.30, 1.05, kz + 0.24), Vector3(0.76, 0.56, 0.18), Color("#262220"))

	# Banquet tables + chairs
	var cols := clampi(int(floor((fw - 1.6) / 2.6)), 1, 3)
	for c in range(cols):
		var tx := ((float(c) + 0.5) / float(cols) - 0.5) * maxf(0.0, fw - 2.8)
		if _f_clear(ctx, tx, fd * 0.12, 0.95, 0.75):
			_add_desk(ctx, tx, fd * 0.12, 1.75, 0.85, Color("#C39360"))
			_add_chair(ctx, tx - 0.45, fd * 0.12 + 0.56, Color("#2F7D3E"), 0.0)
			_add_chair(ctx, tx + 0.45, fd * 0.12 + 0.56, Color("#2F7D3E"), 0.0)
			_add_chair(ctx, tx - 0.45, fd * 0.12 - 0.56, Color("#2F7D3E"), PI)
			_add_chair(ctx, tx + 0.45, fd * 0.12 - 0.56, Color("#2F7D3E"), PI)

func _furn_garage(ctx: Dictionary, preset: String) -> void:
	var fw := float(ctx["fw"])
	var fd := float(ctx["fd"])
	# Storage shelving racks along front wall
	var racks := clampi(int(floor((fw - 1.2) / 1.8)), 1, 4)
	var rz := -fd * 0.5 + 0.55
	for ri in range(racks):
		var tx := ((float(ri) + 0.5) / float(racks) - 0.5) * maxf(0.0, fw - 2.0)
		if _f_clear(ctx, tx, rz, 0.78, 0.35):
			_f_box(ctx, Vector3(tx - 0.68, 1.05, rz), Vector3(0.08, 2.10, 0.56), Color("#4A5568"))
			_f_box(ctx, Vector3(tx + 0.68, 1.05, rz), Vector3(0.08, 2.10, 0.56), Color("#4A5568"))
			for tier in range(3):
				var sy := 0.45 + float(tier) * 0.65
				_f_box(ctx, Vector3(tx, sy, rz), Vector3(1.42, 0.06, 0.56), Color("#D97706"))
				_f_box(ctx, Vector3(tx - 0.25, sy + 0.22, rz), Vector3(0.42, 0.36, 0.42), Color("#C49A6C"))
				_f_box(ctx, Vector3(tx + 0.26, sy + 0.19, rz), Vector3(0.38, 0.30, 0.38), Color("#B3885A"))

	# Institutional utility vehicle if garage & spacious enough
	if preset == "garage" and fw >= 4.2 and fd >= 4.8 and _f_clear(ctx, 0.0, 0.35, 1.15, 2.15):
		_f_box(ctx, Vector3(0.0, 0.75, 0.35), Vector3(1.85, 0.82, 3.90), Color("#F0F2F5"))
		_f_box(ctx, Vector3(0.0, 1.42, 0.05), Vector3(1.70, 0.68, 2.10), Color("#F0F2F5"))
		_f_box(ctx, Vector3(0.0, 0.76, 0.35), Vector3(1.88, 0.18, 3.80), Color("#2F9E41"))
		_f_box(ctx, Vector3(0.0, 1.42, 0.05), Vector3(1.74, 0.44, 1.85), Color("#2F495E"))
		for wx in [-0.90, 0.90]:
			for wz in [-0.95, 1.45]:
				_f_box(ctx, Vector3(wx, 0.34, wz), Vector3(0.24, 0.66, 0.66), Color("#1C1F24"))

func _furn_stair(ctx: Dictionary) -> void:
	var fw := float(ctx["fw"])
	var fd := float(ctx["fd"])
	var sw := clampf(fw * 0.60, 1.2, 2.6)
	var steps := 10
	var run := clampf(fd * 0.65, 2.4, 4.2)
	var step_d := run / float(steps)
	for i in range(steps):
		var sh := 0.18 * float(i + 1)
		var sz := -run * 0.5 + (float(i) + 0.5) * step_d
		if _f_clear(ctx, 0.0, sz, sw * 0.5, step_d * 0.5):
			_f_box(ctx, Vector3(0.0, sh * 0.5, sz), Vector3(sw, sh, step_d), Color("#CFC9BE"))

func _furn_gallery(ctx: Dictionary) -> void:
	var fw := float(ctx["fw"])
	var fd := float(ctx["fd"])
	var art_cols := [Color("#D94E4E"), Color("#2E86AB"), Color("#E6A732"), Color("#2F9E41")]
	var n_art := clampi(int(floor((fw - 1.2) / 1.8)), 1, 4)
	var az := -fd * 0.5 + WALL_THICK + 0.04
	for ai in range(n_art):
		var ax := ((float(ai) + 0.5) / float(n_art) - 0.5) * maxf(0.0, fw - 2.0)
		_f_box(ctx, Vector3(ax, 1.55, az), Vector3(1.10, 0.85, 0.04), Color("#2B2F36"))
		_f_box(ctx, Vector3(ax, 1.55, az + 0.02), Vector3(0.96, 0.72, 0.02), art_cols[ai % art_cols.size()])
	if _f_clear(ctx, 0.0, 0.0, 0.95, 0.35):
		_f_box(ctx, Vector3(0.0, 0.44, 0.0), Vector3(1.80, 0.10, 0.55), Color("#8B5E3C"))
		_f_box(ctx, Vector3(-0.72, 0.22, 0.0), Vector3(0.08, 0.44, 0.44), Color("#2C333B"))
		_f_box(ctx, Vector3(0.72, 0.22, 0.0), Vector3(0.08, 0.44, 0.44), Color("#2C333B"))

# --- Flush Sector Batches into Scene Tree ---

func _flush_sector_batch(sec_id: String, batch: Dictionary, mats: CampusMaterials) -> void:
	var sec_root := Node3D.new()
	sec_root.name = "Sector_" + sec_id
	_interiors_root.add_child(sec_root)

	var wall_node := Node3D.new()
	wall_node.name = "Walls"
	sec_root.add_child(wall_node)

	var furn_node := Node3D.new()
	furn_node.name = "Furniture"
	sec_root.add_child(furn_node)

	# 1. Batched partition walls, baseboards, door frames, plaque backings
	_emit_colored_mm(wall_node, "PartitionWallsMM", _unit_box_mesh, batch["wall_boxes"], mats.get_batch_material("batch_wall"), 0.0)
	_emit_plain_mm(wall_node, "GlassPartitionsMM", _unit_box_mesh, _extract_xfs(batch["glass_boxes"]), _glass_mat, 0.0)

	# 2. Single StaticBody3D per sector holding all solid wall segment BoxShape3Ds
	var colliders: Array = batch["colliders"]
	if not colliders.is_empty():
		var body := StaticBody3D.new()
		body.name = "WallColliders"
		body.collision_layer = 1
		body.collision_mask = 0
		for col_d in colliders:
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = col_d["size"]
			cs.shape = box
			cs.position = col_d["pos"]
			cs.rotation.y = float(col_d["rot_y"])
			body.add_child(cs)
		sec_root.add_child(body)

	# 3. Batched furniture & ceiling lights (ZERO shadows, toggled by update_visibility via exact AABB distance)
	_emit_colored_mm(furn_node, "FurnitureBoxesMM", _unit_box_mesh, batch["furn_boxes"], mats.get_batch_material("batch_wall"), 0.0)
	_emit_colored_mm(furn_node, "FurnitureCylsMM", _unit_cyl_mesh, batch["furn_cyls"], mats.get_batch_material("batch_wall"), 0.0)
	_emit_plain_mm(furn_node, "CeilingLightsMM", _unit_box_mesh, batch["light_xfs"], _ceiling_light_mat, 0.0)

	# 4. Crisp door plaques (Label3D with 18m fade range)
	var plaques: Array = batch["plaques"]
	for pi in range(plaques.size()):
		var pd: Dictionary = plaques[pi]
		var lbl := Label3D.new()
		lbl.text = String(pd["text"])
		lbl.position = pd["pos"]
		lbl.rotation.y = float(pd["rot_y"])
		lbl.font_size = 26
		lbl.pixel_size = 0.0036 if String(pd["text"]).length() > 22 else 0.0040
		lbl.double_sided = bool(pd["double_sided"])
		lbl.modulate = Color("#F8FAFC")
		lbl.outline_modulate = Color("#0D131A")
		lbl.outline_size = 5
		lbl.visibility_range_end = 18.0
		lbl.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		furn_node.add_child(lbl)
		detail_nodes.append({"node": lbl, "base_range": 18.0})

	_sector_containers[sec_id] = {
		"root": sec_root,
		"wall_node": wall_node,
		"furn_node": furn_node,
		"min_xz": batch["min_xz"],
		"max_xz": batch["max_xz"],
		"wall_vis": true,
		"furn_vis": true
	}

# --- Hanging Corridor Wayfinding Signs ---

func _build_wayfinding_signs(signs: Array, mats: CampusMaterials) -> void:
	if signs.is_empty():
		return
	var s_root := Node3D.new()
	s_root.name = "WayfindingSigns"
	_interiors_root.add_child(s_root)

	var sign_boxes: Array = []
	var board_bg := Color("#163824")
	var accent_col := Color("#2F9E41")
	var rod_col := Color("#2D343C")

	for si in range(signs.size()):
		var sd: Dictionary = signs[si]
		var pos_a: Array = sd.get("pos", [0.0, 0.0])
		if pos_a.size() < 2:
			continue
		var txt := String(sd.get("text", "")).strip_edges()
		if txt.is_empty():
			continue
		var rot_rad := deg_to_rad(float(sd.get("rot_deg", 8.7)))
		var basis := Basis(Vector3.UP, rot_rad)
		var y := float(sd.get("y", 2.82))
		var wpos := Vector3(float(pos_a[0]), y, float(pos_a[1]))

		var bw := clampf(float(txt.length()) * 0.072 + 0.55, 1.35, 3.4)
		var bh := 0.36
		sign_boxes.append({"xf": Transform3D(basis * Basis.from_scale(Vector3(bw, bh, 0.05)), wpos), "col": board_bg})
		sign_boxes.append({"xf": Transform3D(basis * Basis.from_scale(Vector3(bw, 0.055, 0.056)), wpos + Vector3(0.0, -bh * 0.5 + 0.025, 0.0)), "col": accent_col})
		for sgn in [-1.0, 1.0]:
			var rpos := wpos + basis * Vector3(sgn * (bw * 0.38), bh * 0.5 + 0.42, 0.0)
			sign_boxes.append({"xf": Transform3D(basis * Basis.from_scale(Vector3(0.03, 0.84, 0.03)), rpos), "col": rod_col})

		# Front & back labels so sign reads cleanly from both sides of corridor
		for face in [0, 1]:
			var lbl := Label3D.new()
			lbl.text = txt
			var dz := 0.032 if face == 0 else -0.032
			lbl.position = wpos + basis * Vector3(0.0, 0.015, dz)
			lbl.rotation.y = rot_rad + (0.0 if face == 0 else PI)
			lbl.font_size = 30
			lbl.pixel_size = 0.0042 if txt.length() <= 26 else 0.0036
			lbl.double_sided = false
			lbl.modulate = Color("#FFFDF5")
			lbl.outline_modulate = Color("#081A0E")
			lbl.outline_size = 5
			lbl.visibility_range_end = 28.0
			lbl.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			s_root.add_child(lbl)
			detail_nodes.append({"node": lbl, "base_range": 28.0})

	_emit_colored_mm(s_root, "WayfindingBoardsMM", _unit_box_mesh, sign_boxes, mats.get_batch_material("batch_wall"), 0.0)

# --- Subtle Interior Night Lights ---

func _build_interior_night_lights(buildings: Array, building_rooms: Dictionary) -> void:
	var lights_root := Node3D.new()
	lights_root.name = "InteriorNightLights"
	_interiors_root.add_child(lights_root)

	for b_v in buildings:
		var b: Dictionary = b_v
		if not bool(b.get("walkable", false)):
			continue
		var btype := String(b.get("type", ""))
		if btype == "corridor":
			continue
		var poly := _to_vec2_array(b.get("polygon", []))
		if poly.size() < 3:
			continue
		var bid := String(b.get("id", "b"))
		var h := minf(float(b.get("height_m", 4.6)) - 0.9, 3.8)
		var b_rooms: Array = building_rooms.get(bid, [])

		# Place 1 light at building centroid (or 2 split across large elongated blocks)
		var bmin := Vector2(1e9, 1e9)
		var bmax := Vector2(-1e9, -1e9)
		for p in poly:
			bmin.x = minf(bmin.x, p.x); bmin.y = minf(bmin.y, p.y)
			bmax.x = maxf(bmax.x, p.x); bmax.y = maxf(bmax.y, p.y)
		var span_x := bmax.x - bmin.x
		var span_z := bmax.y - bmin.y
		var c := _poly_centroid(poly)

		var spots: Array[Vector2] = []
		if b.has("courtyard_inset"):
			# Place 2 lights on opposite wings instead of open courtyard center
			spots.append(Vector2(c.x - span_x * 0.32, c.y))
			spots.append(Vector2(c.x + span_x * 0.32, c.y))
		elif maxf(span_x, span_z) >= 34.0 and b_rooms.size() >= 6:
			if span_x >= span_z:
				spots.append(Vector2(c.x - span_x * 0.24, c.y))
				spots.append(Vector2(c.x + span_x * 0.24, c.y))
			else:
				spots.append(Vector2(c.x, c.y - span_z * 0.24))
				spots.append(Vector2(c.x, c.y + span_z * 0.24))
		else:
			spots.append(c)

		for si in range(spots.size()):
			var sp := spots[si]
			var light := OmniLight3D.new()
			light.name = "IntLight_%s_%d" % [bid, si]
			light.position = Vector3(sp.x, h, sp.y)
			light.light_color = Color("#FFF4DE")
			light.light_energy = 0.0
			light.omni_range = 18.0
			light.omni_attenuation = 1.4
			light.shadow_enabled = false
			light.visible = false
			light.distance_fade_enabled = true
			light.distance_fade_begin = 36.0
			light.distance_fade_length = 14.0
			lights_root.add_child(light)
			night_lights.append(light)

# --- MultiMesh & SurfaceTool Utilities ---

func _emit_colored_mm(parent: Node3D, node_name: String, mesh: Mesh, items: Array, mat: Material, vis_range: float) -> void:
	if items.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in range(items.size()):
		mm.set_instance_transform(i, items[i]["xf"])
		mm.set_instance_color(i, items[i]["col"])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_range > 0.0:
		mmi.visibility_range_end = vis_range
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		detail_nodes.append({"node": mmi, "base_range": vis_range})
	parent.add_child(mmi)

func _emit_plain_mm(parent: Node3D, node_name: String, mesh: Mesh, xfs: Array, mat: Material, vis_range: float) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in range(xfs.size()):
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_range > 0.0:
		mmi.visibility_range_end = vis_range
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		detail_nodes.append({"node": mmi, "base_range": vis_range})
	parent.add_child(mmi)

func _extract_xfs(items: Array) -> Array:
	var out: Array = []
	for it in items:
		out.append(it["xf"])
	return out

func _local_xf(origin: Vector3, basis: Basis, lpos: Vector3, sz: Vector3) -> Transform3D:
	return Transform3D(basis * Basis.from_scale(sz), origin + basis * lpos)

func _to_vec2_array(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(arr.size())
	for i in range(arr.size()):
		var p = arr[i]
		out[i] = Vector2(float(p[0]), float(p[1]))
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
	if area < 0.0:
		copy.reverse()
	return copy

func _compute_inset_polygon(cw: PackedVector2Array, inset: float) -> PackedVector2Array:
	var n := cw.size()
	var out := PackedVector2Array()
	out.resize(n)
	for i in range(n):
		var prev := cw[(i - 1 + n) % n]
		var curr := cw[i]
		var nxt := cw[(i + 1) % n]
		var e0 := (curr - prev).normalized()
		var e1 := (nxt - curr).normalized()
		var n0 := Vector2(-e0.y, e0.x)
		var n1 := Vector2(-e1.y, e1.x)
		var bis := n0 + n1
		var off: Vector2
		if bis.length_squared() < 0.0004:
			off = n1 * inset
		else:
			var bis_dir := bis.normalized()
			var denom := maxf(0.45, bis_dir.dot(n1))
			off = bis_dir * minf(inset / denom, inset * 2.2)
		out[i] = curr + off
	return out

func _push_polygon_top(st: SurfaceTool, poly: PackedVector2Array, y: float, uv_scale: float) -> bool:
	if poly.size() < 3:
		return false
	var cw := _ensure_cw_screen(poly)
	var tris := Geometry2D.triangulate_polygon(cw)
	if tris.is_empty():
		return false
	for i in range(0, tris.size(), 3):
		var a := Vector3(cw[tris[i]].x, y, cw[tris[i]].y)
		var b := Vector3(cw[tris[i + 1]].x, y, cw[tris[i + 1]].y)
		var c := Vector3(cw[tris[i + 2]].x, y, cw[tris[i + 2]].y)
		if (b - a).cross(c - a).y > 0.0:
			var tmp := b
			b = c
			c = tmp
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(a.x, a.z) * uv_scale)
		st.add_vertex(a)
		st.set_uv(Vector2(b.x, b.z) * uv_scale)
		st.add_vertex(b)
		st.set_uv(Vector2(c.x, c.z) * uv_scale)
		st.add_vertex(c)
	return true

# --- Text Normalization & Search Helpers ---

func _normalize_search_text(text: String) -> String:
	var s := text.strip_edges().to_lower()
	if s.is_empty():
		return ""
	var repl := {
		"á": "a", "à": "a", "â": "a", "ã": "a", "ä": "a",
		"é": "e", "è": "e", "ê": "e", "ë": "e",
		"í": "i", "ì": "i", "î": "i", "ï": "i",
		"ó": "o", "ò": "o", "ô": "o", "õ": "o", "ö": "o",
		"ú": "u", "ù": "u", "û": "u", "ü": "u",
		"ç": "c", "ñ": "n",
		"•": " ", "—": " ", "–": " ", "-": " ", "/": " ", ".": " ", ",": " ", "(": " ", ")": " "
	}
	for k in repl.keys():
		if s.contains(k):
			s = s.replace(k, String(repl[k]))
	# Collapse repeated whitespace
	var parts := s.split(" ", false)
	return " ".join(parts)

func _any_begins_with(arr: Array, q: String) -> bool:
	for s in arr:
		if String(s).begins_with(q):
			return true
	return false

func _any_contains(arr: Array, q: String) -> bool:
	for s in arr:
		if String(s).contains(q):
			return true
	return false
