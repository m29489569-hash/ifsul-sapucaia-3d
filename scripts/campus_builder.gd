extends RefCounted

const MaterialsLib = preload("res://scripts/materials.gd")
const InteriorBuilderLib = preload("res://scripts/interior_builder.gd")

var mats := MaterialsLib.new()
var interior_builder = null
var roof_nodes: Array[Node3D] = []
var roofs_visible: bool = true
var _room_beacon: Node3D = null
var _courtyard_inners: Array[PackedVector2Array] = []
var poi_nodes: Array[Area3D] = []
var poi_beacons: Array[Node3D] = []
var night_lights: Array[OmniLight3D] = []
var lamp_mat: StandardMaterial3D
var win_mat: StandardMaterial3D
var building_polys: Array = []
var tree_mmi_list: Array[MultiMeshInstance3D] = []
var _tree_entries: Array[Dictionary] = []
var full_tree_count: int = 0
var detail_nodes: Array[Dictionary] = []

var _build_root: Node3D = null
var _colored_batches: Dictionary = {}
var _plain_batches: Dictionary = {}
var _sphere_batches: Dictionary = {}
var _cyl_batches: Dictionary = {}
var _torus_batches: Dictionary = {}
var _unit_box_mesh: BoxMesh = null
var _unit_sphere_mesh: SphereMesh = null
var _unit_cyl_mesh: CylinderMesh = null
var _unit_torus_mesh: TorusMesh = null
var _road_st: SurfaceTool = null
var _walk_st: SurfaceTool = null
var _foot_st: SurfaceTool = null

func build(root: Node3D, data: Dictionary, interiors_data: Dictionary = {}) -> void:
	begin_build(root)
	build_stage_terrain(root, data)
	build_stage_structures(root, data)
	build_stage_interiors(root, data, interiors_data)
	build_stage_props(root, data)

func begin_build(root: Node3D) -> void:
	clear_room_beacon()
	if interior_builder != null:
		interior_builder.cleanup()
		interior_builder = null
	_build_root = root
	_colored_batches.clear()
	_plain_batches.clear()
	_sphere_batches.clear()
	_cyl_batches.clear()
	_torus_batches.clear()
	roof_nodes.clear()
	roofs_visible = true
	_courtyard_inners.clear()
	poi_nodes.clear()
	poi_beacons.clear()
	night_lights.clear()
	building_polys.clear()
	tree_mmi_list.clear()
	_tree_entries.clear()
	detail_nodes.clear()
	full_tree_count = 0
	lamp_mat = mats.get_material("lamp_glow")
	win_mat = mats.get_material("glass")

func build_stage_terrain(root: Node3D, data: Dictionary) -> void:
	build_stage_terrain_base(root, data)
	build_stage_terrain_details(root, data)

func build_stage_terrain_base(root: Node3D, data: Dictionary) -> void:
	_build_ground(root)
	_begin_ribbon_builders()
	_build_streets(root, data.get("streets", []))
	_build_campus_pad(root, data.get("perimeter", []))
	_build_perimeter_walls(root, data.get("perimeter", []), data.get("gates", []))

func build_stage_terrain_details(root: Node3D, data: Dictionary) -> void:
	_build_parking_lots(root, data.get("parking_lots", []))
	_build_paths(data.get("footways", []), false, 0.046)
	_build_paths(data.get("driveways", []), true, 0.033)
	_flush_ribbon_builders(root)
	_build_courts(root, data.get("courts", []))

func build_stage_structures(root: Node3D, data: Dictionary) -> void:
	var buildings: Array = data.get("buildings", [])
	build_stage_buildings_range(root, data, 0, buildings.size())
	build_stage_landmarks(root, data)

func build_stage_buildings_range(root: Node3D, data: Dictionary, start_idx: int, end_idx: int) -> void:
	_build_buildings_slice(root, data.get("buildings", []), start_idx, end_idx)

func build_stage_landmarks(root: Node3D, data: Dictionary) -> void:
	_build_landmarks(root, data)
	_build_entrance_signage(root, data)

func build_stage_interiors(root: Node3D, data: Dictionary, interiors_data: Dictionary) -> void:
	if interiors_data.is_empty():
		return
	interior_builder = InteriorBuilderLib.new()
	interior_builder.build_interiors(root, data, interiors_data, mats)
	for l in interior_builder.night_lights:
		night_lights.append(l)
	for dn in interior_builder.detail_nodes:
		detail_nodes.append(dn)

func build_stage_props(root: Node3D, data: Dictionary) -> void:
	build_stage_vegetation(root, data)
	build_stage_finalize_props(root, data)

func build_stage_vegetation(root: Node3D, data: Dictionary) -> void:
	_build_vegetation_and_props(root, data)

func build_stage_finalize_props(root: Node3D, data: Dictionary) -> void:
	_build_pois(root, data.get("pois", []))
	_flush_static_batches(root)

func set_roofs_visible(vis: bool) -> void:
	roofs_visible = vis
	for rn in roof_nodes:
		if is_instance_valid(rn):
			rn.visible = vis

func update_interior_visibility(cam_pos: Vector3, is_aerial: bool = false) -> void:
	if interior_builder != null:
		interior_builder.update_visibility(cam_pos, is_aerial)

func find_room_at(world_pos: Vector3) -> Dictionary:
	if interior_builder != null:
		return interior_builder.find_room_at(world_pos)
	return {}

func search_rooms(query: String) -> Array[Dictionary]:
	if interior_builder != null:
		return interior_builder.search_rooms(query)
	return []

func get_all_rooms() -> Array[Dictionary]:
	if interior_builder != null:
		return interior_builder.get_all_rooms()
	return []

func get_room_world_pos(room: Dictionary) -> Vector3:
	if interior_builder != null:
		return interior_builder.get_room_world_pos(room)
	var c: Array = room.get("center", [0.0, 0.0])
	return Vector3(float(c[0]), 0.0, float(c[1]))

func set_room_beacon(world_pos: Vector3, label_text: String) -> void:
	clear_room_beacon()
	if _build_root == null or not is_instance_valid(_build_root):
		return
	var beacon := Node3D.new()
	beacon.name = "RoomNavigationBeacon"
	beacon.position = Vector3(world_pos.x, 0.0, world_pos.z)

	var ring := MeshInstance3D.new()
	ring.mesh = _make_cylinder_mesh(0.85, 0.95, 0.06, 20)
	ring.position.y = 0.09
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color("#1EC7C3")
	rmat.emission_enabled = true
	rmat.emission = Color("#1EC7C3")
	rmat.emission_energy_multiplier = 1.4
	rmat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	ring.material_override = rmat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.add_child(ring)

	var beam := MeshInstance3D.new()
	beam.mesh = _make_cylinder_mesh(0.16, 0.24, 16.0, 12)
	beam.position.y = 8.1
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.12, 0.78, 0.76, 0.34)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.emission_enabled = true
	bmat.emission = Color("#1EC7C3")
	bmat.emission_energy_multiplier = 1.2
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = bmat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.add_child(beam)

	var diamond := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(0.45, 0.45, 0.45)
	diamond.mesh = dm
	diamond.position.y = 1.95
	diamond.rotation = Vector3(deg_to_rad(45.0), deg_to_rad(45.0), 0.0)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color("#F5C43D")
	dmat.emission_enabled = true
	dmat.emission = Color("#F5C43D")
	dmat.emission_energy_multiplier = 1.4
	diamond.material_override = dmat
	diamond.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.add_child(diamond)

	var lbl_in := Label3D.new()
	lbl_in.text = label_text
	lbl_in.position.y = 2.65
	lbl_in.font_size = 32
	lbl_in.pixel_size = 0.0055
	lbl_in.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl_in.no_depth_test = true
	lbl_in.visibility_range_end = 42.0
	lbl_in.modulate = Color("#FFFBE6")
	lbl_in.outline_modulate = Color("#0F3B3A")
	lbl_in.outline_size = 6
	beacon.add_child(lbl_in)

	var lbl_top := Label3D.new()
	lbl_top.text = label_text
	lbl_top.position.y = 11.5
	lbl_top.font_size = 32
	lbl_top.pixel_size = 0.0125
	lbl_top.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl_top.no_depth_test = true
	lbl_top.visibility_range_end = 260.0
	lbl_top.modulate = Color("#A7F3D0")
	lbl_top.outline_modulate = Color("#0A2928")
	lbl_top.outline_size = 6
	beacon.add_child(lbl_top)

	_build_root.add_child(beacon)
	_room_beacon = beacon

func clear_room_beacon() -> void:
	if is_instance_valid(_room_beacon):
		_room_beacon.queue_free()
	_room_beacon = null

# --- Optimized Primitive Builders ---

func _make_cylinder_mesh(top_r: float, bottom_r: float, height: float, radial_segments: int = 12) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = height
	m.radial_segments = radial_segments
	m.rings = 0
	return m

func _make_sphere_mesh(radius: float, height: float, radial_segments: int = 10, rings: int = 5) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = radial_segments
	m.rings = rings
	return m

func _make_torus_mesh(inner_r: float, outer_r: float, rings: int = 16, ring_segments: int = 6) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner_r
	m.outer_radius = outer_r
	m.rings = rings
	m.ring_segments = ring_segments
	return m

# --- Batching & Spatial Chunking ---

func _to_world_xf(parent: Node3D, pos: Vector3, sz: Vector3, rot: Vector3) -> Transform3D:
	var local_basis := (Basis.from_euler(rot) if rot != Vector3.ZERO else Basis.IDENTITY) * Basis.from_scale(sz)
	var xf := Transform3D(local_basis, pos)
	var cur: Node3D = parent
	while cur != null and cur != _build_root:
		xf = cur.transform * xf
		cur = cur.get_parent() as Node3D
	return xf

func _push_colored_batch_item(batches: Dictionary, parent: Node3D, pos: Vector3, sz: Vector3, rot: Vector3, bucket: String, col: Color, cast_shadow: bool, detail_tier: int) -> void:
	var norm_bucket := "batch_wall" if (bucket == "batch_line" or bucket == "batch_concrete") else bucket
	var xf := _to_world_xf(parent, pos, sz, rot)
	var key := "%s|%d|%d" % [norm_bucket, 1 if cast_shadow else 0, detail_tier]
	if not batches.has(key):
		batches[key] = {
			"bucket": norm_bucket,
			"shadow": cast_shadow,
			"detail": detail_tier,
			"items": []
		}
	(batches[key]["items"] as Array).append({"xf": xf, "col": col})

func _add_colored_box(parent: Node3D, pos: Vector3, sz: Vector3, rot: Vector3, bucket: String, col: Color, cast_shadow: bool = false, detail_tier: int = 0) -> void:
	_push_colored_batch_item(_colored_batches, parent, pos, sz, rot, bucket, col, cast_shadow, detail_tier)

func _add_static_box(parent: Node3D, pos: Vector3, sz: Vector3, rot: Vector3, mat: Material, cast_shadow: bool = false, detail_tier: int = 0) -> void:
	var xf := _to_world_xf(parent, pos, sz, rot)
	var key := "%d|%d|%d" % [mat.get_instance_id(), 1 if cast_shadow else 0, detail_tier]
	if not _plain_batches.has(key):
		_plain_batches[key] = {
			"mat": mat,
			"shadow": cast_shadow,
			"detail": detail_tier,
			"items": []
		}
	(_plain_batches[key]["items"] as Array).append(xf)

func _add_colored_sphere(parent: Node3D, pos: Vector3, sz: Vector3, bucket: String, col: Color, cast_shadow: bool = false, detail_tier: int = 0, rot: Vector3 = Vector3.ZERO) -> void:
	_push_colored_batch_item(_sphere_batches, parent, pos, sz, rot, bucket, col, cast_shadow, detail_tier)

func _add_colored_cylinder(parent: Node3D, pos: Vector3, sz: Vector3, rot: Vector3, bucket: String, col: Color, cast_shadow: bool = false, detail_tier: int = 0) -> void:
	_push_colored_batch_item(_cyl_batches, parent, pos, sz, rot, bucket, col, cast_shadow, detail_tier)

func _add_colored_torus(parent: Node3D, pos: Vector3, sz: Vector3, rot: Vector3, bucket: String, col: Color, detail_tier: int = 1) -> void:
	var xf := _to_world_xf(parent, pos, sz, rot)
	var key := "%s|%d" % [bucket, detail_tier]
	if not _torus_batches.has(key):
		_torus_batches[key] = {
			"bucket": bucket,
			"detail": detail_tier,
			"items": []
		}
	(_torus_batches[key]["items"] as Array).append({"xf": xf, "col": col})

func _emit_colored_multimesh(batch_root: Node3D, mesh: Mesh, items: Array, mat: Material, cast_shadow: bool, detail_tier: int, chunk_threshold: int = 48) -> void:
	if items.is_empty():
		return
	var groups: Array[Array] = []
	if items.size() >= 150:
		var buckets: Array[Array] = [[], [], [], []]
		for it in items:
			var p: Vector3 = (it["xf"] as Transform3D).origin
			var qidx := (0 if p.x < 0.0 else 1) + (0 if p.z < 0.0 else 2)
			buckets[qidx].append(it)
		for b in buckets:
			if not b.is_empty():
				groups.append(b)
	elif items.size() >= chunk_threshold:
		var halves: Array[Array] = [[], []]
		for it in items:
			var p: Vector3 = (it["xf"] as Transform3D).origin
			halves[0 if p.z < 0.0 else 1].append(it)
		for b in halves:
			if not b.is_empty():
				groups.append(b)
	else:
		groups.append(items)

	for g in groups:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = g.size()
		for i in range(g.size()):
			mm.set_instance_transform(i, g[i]["xf"])
			mm.set_instance_color(i, g[i]["col"])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if detail_tier > 0:
			var base_r := 135.0 if detail_tier == 1 else 190.0
			mmi.visibility_range_end = base_r
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			detail_nodes.append({"node": mmi, "base_range": base_r})
		batch_root.add_child(mmi)

func _emit_plain_multimesh(batch_root: Node3D, mesh: Mesh, items: Array, mat: Material, cast_shadow: bool, detail_tier: int, chunk_threshold: int = 48) -> void:
	if items.is_empty():
		return
	var groups: Array[Array] = []
	if items.size() >= chunk_threshold:
		var halves: Array[Array] = [[], []]
		for xf in items:
			var p: Vector3 = (xf as Transform3D).origin
			halves[0 if p.z < 0.0 else 1].append(xf)
		for b in halves:
			if not b.is_empty():
				groups.append(b)
	else:
		groups.append(items)

	for g in groups:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = g.size()
		for i in range(g.size()):
			mm.set_instance_transform(i, g[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if detail_tier > 0:
			var base_r := 135.0 if detail_tier == 1 else 190.0
			mmi.visibility_range_end = base_r
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			detail_nodes.append({"node": mmi, "base_range": base_r})
		batch_root.add_child(mmi)

func _flush_static_batches(root: Node3D) -> void:
	if _colored_batches.is_empty() and _plain_batches.is_empty() and _sphere_batches.is_empty() and _cyl_batches.is_empty() and _torus_batches.is_empty():
		return
	var batch_root := Node3D.new()
	batch_root.name = "StaticBatches"
	root.add_child(batch_root)

	if not _colored_batches.is_empty() or not _plain_batches.is_empty():
		if _unit_box_mesh == null:
			_unit_box_mesh = BoxMesh.new()
			_unit_box_mesh.size = Vector3.ONE
		for key in _colored_batches.keys():
			var b: Dictionary = _colored_batches[key]
			var mat := mats.get_batch_material(String(b["bucket"]))
			_emit_colored_multimesh(batch_root, _unit_box_mesh, b["items"], mat, bool(b["shadow"]), int(b["detail"]))
		for key in _plain_batches.keys():
			var b: Dictionary = _plain_batches[key]
			_emit_plain_multimesh(batch_root, _unit_box_mesh, b["items"], b["mat"], bool(b["shadow"]), int(b["detail"]))

	if not _sphere_batches.is_empty():
		if _unit_sphere_mesh == null:
			_unit_sphere_mesh = _make_sphere_mesh(0.5, 1.0, 10, 5)
		for key in _sphere_batches.keys():
			var b: Dictionary = _sphere_batches[key]
			var mat := mats.get_batch_material(String(b["bucket"]))
			_emit_colored_multimesh(batch_root, _unit_sphere_mesh, b["items"], mat, bool(b["shadow"]), int(b["detail"]), 9999)

	if not _cyl_batches.is_empty():
		if _unit_cyl_mesh == null:
			_unit_cyl_mesh = _make_cylinder_mesh(0.5, 0.5, 1.0, 10)
		for key in _cyl_batches.keys():
			var b: Dictionary = _cyl_batches[key]
			var mat := mats.get_batch_material(String(b["bucket"]))
			_emit_colored_multimesh(batch_root, _unit_cyl_mesh, b["items"], mat, bool(b["shadow"]), int(b["detail"]), 9999)

	if not _torus_batches.is_empty():
		if _unit_torus_mesh == null:
			_unit_torus_mesh = _make_torus_mesh(0.78, 1.0, 14, 6)
		for key in _torus_batches.keys():
			var b: Dictionary = _torus_batches[key]
			var mat := mats.get_batch_material(String(b["bucket"]))
			_emit_colored_multimesh(batch_root, _unit_torus_mesh, b["items"], mat, false, int(b["detail"]), 9999)

	_colored_batches.clear()
	_plain_batches.clear()
	_sphere_batches.clear()
	_cyl_batches.clear()
	_torus_batches.clear()

# --- Merged World-UV Ground & Ribbon Mesh Builders ---

func _begin_ribbon_builders() -> void:
	_walk_st = SurfaceTool.new()
	_walk_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_road_st = SurfaceTool.new()
	_road_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_foot_st = SurfaceTool.new()
	_foot_st.begin(Mesh.PRIMITIVE_TRIANGLES)

func _push_world_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	# Ensure CW winding facing +Y
	if (v1 - v0).cross(v2 - v0).y > 0.0:
		var tmp := v1
		v1 = v3
		v3 = tmp
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(v0.x, v0.z) * 0.14)
	st.add_vertex(v0)
	st.set_uv(Vector2(v1.x, v1.z) * 0.14)
	st.add_vertex(v1)
	st.set_uv(Vector2(v2.x, v2.z) * 0.14)
	st.add_vertex(v2)
	st.set_uv(Vector2(v0.x, v0.z) * 0.14)
	st.add_vertex(v0)
	st.set_uv(Vector2(v2.x, v2.z) * 0.14)
	st.add_vertex(v2)
	st.set_uv(Vector2(v3.x, v3.z) * 0.14)
	st.add_vertex(v3)

func _push_ribbon_segment(st: SurfaceTool, a2: Vector2, b2: Vector2, width: float, y: float, pad: float) -> void:
	var diff := b2 - a2
	var length := diff.length()
	if length < 0.2:
		return
	var fwd := diff / length
	var side := Vector2(-fwd.y, fwd.x) * (width * 0.5)
	var ext := fwd * (pad * 0.5)
	var p0 := a2 - ext - side
	var p1 := b2 + ext - side
	var p2 := b2 + ext + side
	var p3 := a2 - ext + side
	_push_world_quad(
		st,
		Vector3(p0.x, y, p0.y),
		Vector3(p1.x, y, p1.y),
		Vector3(p2.x, y, p2.y),
		Vector3(p3.x, y, p3.y)
	)

func _commit_ribbon_mesh(parent: Node3D, node_name: String, st: SurfaceTool, mat: Material) -> void:
	st.index()
	st.generate_tangents()
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func _flush_ribbon_builders(root: Node3D) -> void:
	var st_root := root.get_node_or_null("Streets") as Node3D
	if st_root == null:
		st_root = root
	if _walk_st != null:
		_commit_ribbon_mesh(st_root, "MergedSidewalks", _walk_st, mats.get_planar_ground_material("sidewalk", Color("#BDB9B0")))
		_walk_st = null
	if _road_st != null:
		_commit_ribbon_mesh(st_root, "MergedAsphalt", _road_st, mats.get_planar_ground_material("asphalt", Color("#323539")))
		_road_st = null
	if _foot_st != null:
		_commit_ribbon_mesh(st_root, "MergedFootways", _foot_st, mats.get_planar_ground_material("concrete", Color("#CBC6BC")))
		_foot_st = null

func _build_ground(root: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(560.0, 2.0, 740.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := 280.0
	var hd := 370.0
	_push_world_quad(
		st,
		Vector3(-hw, 0.0, -hd),
		Vector3(hw, 0.0, -hd),
		Vector3(hw, 0.0, hd),
		Vector3(-hw, 0.0, hd)
	)
	st.index()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mats.get_planar_ground_material("grass", Color("#476F38"))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	mi.material_override = mats.get_planar_ground_material("grass", Color("#4E803E"))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

	# Central paved civic courtyard around entrance, admin & auditorium
	var plaza_pts := PackedVector2Array([
		Vector2(-69.5, -2.0), Vector2(18.0, -12.0), Vector2(22.0, 44.0), Vector2(-64.5, 26.5)
	])
	var plaza_mi := MeshInstance3D.new()
	plaza_mi.name = "CentralPlaza"
	plaza_mi.mesh = _extrude_polygon_mesh(plaza_pts, 0.018, false)
	plaza_mi.material_override = mats.get_planar_ground_material("concrete", Color("#C8C3B9"))
	plaza_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(plaza_mi)

	# Inner courtyard tiled floor (05_central_courtyard)
	var inner_pts := PackedVector2Array([
		Vector2(-6.0, -7.0), Vector2(28.0, -12.0), Vector2(34.0, 26.0), Vector2(4.0, 22.0)
	])
	var inner_mi := MeshInstance3D.new()
	inner_mi.name = "InnerCourtyardTile"
	inner_mi.mesh = _extrude_polygon_mesh(inner_pts, 0.025, false)
	inner_mi.material_override = mats.get_planar_ground_material("tile", Color("#CFC9BE"))
	inner_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(inner_mi)

	var line_col := Color("#F5F5F0")
	_add_colored_box(root, Vector3(-10.0, 0.028, -148.0), Vector3(44.0, 0.01, 0.16), Vector3.ZERO, "batch_line", line_col)
	_add_colored_box(root, Vector3(-10.0, 0.028, -118.0), Vector3(44.0, 0.01, 0.16), Vector3.ZERO, "batch_line", line_col)
	_add_colored_box(root, Vector3(-32.0, 0.028, -133.0), Vector3(0.16, 0.01, 30.0), Vector3.ZERO, "batch_line", line_col)
	_add_colored_box(root, Vector3(12.0, 0.028, -133.0), Vector3(0.16, 0.01, 30.0), Vector3.ZERO, "batch_line", line_col)
	_add_colored_box(root, Vector3(-10.0, 0.028, -133.0), Vector3(0.16, 0.01, 30.0), Vector3.ZERO, "batch_line", line_col)

func _build_streets(root: Node3D, streets: Array) -> void:
	var st_root := Node3D.new()
	st_root.name = "Streets"
	root.add_child(st_root)

	# Pass 1: all sidewalks below asphalt; Pass 2: all asphalt + median crossovers; Pass 3: dashed centerlines
	for s in streets:
		var pts: Array = s.get("points", [])
		var w := float(s.get("width", 8.0))
		_add_polyline_to_ribbon(_walk_st, pts, w + 3.2, 0.024, 0.4)
	for s in streets:
		var pts: Array = s.get("points", [])
		var w := float(s.get("width", 8.0))
		_add_polyline_to_ribbon(_road_st, pts, w, 0.032, 0.4)

	# Paved median crossover openings matching real Av. Copacabana intersections
	var slope := 0.160
	var bou_ang := atan2(slope, 1.0)
	var cos_b := cos(bou_ang)
	var sin_b := sin(bou_ang)
	var right_v := Vector2(cos_b, -sin_b) * 7.0
	var fwd_v := Vector2(sin_b, cos_b)
	for cs in [[-150.0, 9.0], [-119.5, 9.0], [16.8, 16.0], [184.0, 10.0]]:
		var cz := float(cs[0])
		var clen := float(cs[1]) * 0.5
		var cx := -80.25 + (cz - 13.0) * slope
		var center := Vector2(cx, cz)
		var c0 := center - right_v - fwd_v * clen
		var c1 := center + right_v - fwd_v * clen
		var c2 := center + right_v + fwd_v * clen
		var c3 := center - right_v + fwd_v * clen
		_push_world_quad(_road_st, Vector3(c0.x, 0.032, c0.y), Vector3(c1.x, 0.032, c1.y), Vector3(c2.x, 0.032, c2.y), Vector3(c3.x, 0.032, c3.y))

	var line_col := Color("#F5F5F0")
	for s in streets:
		var pts: Array = s.get("points", [])
		_add_dashed_polyline(st_root, pts, 0.16, 0.036, line_col)

	# Vegetated central median islands (canteiro central) along Av. Copacabana
	var curb_col := Color("#ECEAE4")
	var grass_col := Color("#49873A")
	var shrub_cols := [
		Color("#3A7D2C"),
		Color("#5B9E3E"),
		Color("#D94E73"),
		Color("#EAB308"),
	]
	var curb_w := 4.5
	var grass_w := 3.9
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
		var xf_base := Transform3D(Basis(Vector3.UP, bou_ang), Vector3(x_mid, 0.0, z_mid))

		_add_colored_box(st_root, xf_base * Vector3(0.0, 0.08, 0.0), Vector3(curb_w, 0.16, body_len), Vector3(0.0, bou_ang, 0.0), "batch_wall", curb_col)
		_add_colored_box(st_root, xf_base * Vector3(0.0, 0.09, 0.0), Vector3(grass_w, 0.18, body_len), Vector3(0.0, bou_ang, 0.0), "batch_foliage", grass_col)

		var end_off := body_len * 0.5
		for sgn in [-1.0, 1.0]:
			_add_colored_cylinder(st_root, xf_base * Vector3(0.0, 0.08, sgn * end_off), Vector3(curb_w, 0.16, curb_w), Vector3(0.0, bou_ang, 0.0), "batch_wall", curb_col)
			_add_colored_cylinder(st_root, xf_base * Vector3(0.0, 0.09, sgn * end_off), Vector3(grass_w, 0.18, grass_w), Vector3(0.0, bou_ang, 0.0), "batch_foliage", grass_col)

		var shrub_n := int((seg_len - 4.0) / 6.0)
		for si in range(shrub_n + 1):
			var sz := -end_off + 1.0 + float(si) * 6.0
			if sz > end_off - 0.5:
				break
			var lx := 0.0 if si % 2 == 0 else (0.55 if si % 4 == 1 else -0.55)
			var col_idx := (si % 2) if si % 3 != 2 else (2 if si % 6 == 2 else 3)
			_add_colored_sphere(st_root, xf_base * Vector3(lx, 0.45, sz), Vector3(1.10, 0.78, 1.10), "batch_foliage", shrub_cols[col_idx], false, 1)

func _build_paths(paths: Array, is_asphalt: bool, y_height: float) -> void:
	var st := _road_st if is_asphalt else _foot_st
	for p in paths:
		var w := float(p.get("width", 2.5))
		_add_polyline_to_ribbon(st, p.get("points", []), w, y_height, w * 0.35)

func _add_polyline_to_ribbon(st: SurfaceTool, pts: Array, width: float, y: float, end_pad: float) -> void:
	if pts.size() < 2:
		return
	for i in range(pts.size() - 1):
		var a := Vector2(float(pts[i][0]), float(pts[i][1]))
		var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
		_push_ribbon_segment(st, a, b, width, y, end_pad)

func _is_in_copacabana_junction(wp: Vector3) -> bool:
	if wp.x > -42.0:
		return false
	for zj: float in [-150.0, -132.0, -119.5, -80.0, -28.0, 16.8, 185.0]:
		var tol := 9.5 if absf(zj - 16.8) < 1.0 else (6.8 if zj < -140.0 or zj > 180.0 else 5.5)
		if absf(wp.z - zj) < tol:
			return true
	return false

func _add_dashed_polyline(parent: Node3D, pts: Array, width: float, y: float, col: Color) -> void:
	if pts.size() < 2:
		return
	for i in range(pts.size() - 1):
		var a := Vector3(float(pts[i][0]), 0.0, float(pts[i][1]))
		var b := Vector3(float(pts[i + 1][0]), 0.0, float(pts[i + 1][1]))
		var seg := b - a
		var length := seg.length()
		if length < 0.2:
			continue
		var angle := atan2(seg.x, seg.z)
		var step := 4.5
		var n := int(length / step)
		for k in range(n):
			var t := (k + 0.5) / maxf(1.0, float(n))
			var wp := a.lerp(b, t)
			if _is_in_copacabana_junction(wp):
				continue
			_add_colored_box(parent, wp + Vector3(0.0, y, 0.0), Vector3(width, 0.012, 2.0), Vector3(0.0, angle, 0.0), "batch_line", col, false, 1)

func _build_perimeter_walls(root: Node3D, perim: Array, gates: Array) -> void:
	if perim.size() < 3:
		return
	var wall_body := StaticBody3D.new()
	wall_body.name = "PerimeterWalls"
	root.add_child(wall_body)
	var wall_col := Color("#DDD8CE")
	var rail_col := Color("#2F9E41")

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
		var pos := Vector3((p1.x + p2.x) * 0.5, h * 0.5, (p1.y + p2.y) * 0.5)
		var rot_y := atan2(diff.x, diff.y)

		var col := CollisionShape3D.new()
		var cbox := BoxShape3D.new()
		cbox.size = Vector3(0.32, 2.3, length)
		col.shape = cbox
		col.position = pos
		col.rotation.y = rot_y
		wall_body.add_child(col)

		_add_colored_box(root, pos, Vector3(0.28, h, length), Vector3(0.0, rot_y, 0.0), "batch_concrete", wall_col, true)
		if is_front:
			_add_colored_box(root, pos + Vector3(0.0, h * 0.5 + 0.5, 0.0), Vector3(0.10, 1.0, length), Vector3(0.0, rot_y, 0.0), "batch_metal_painted", rail_col, false)

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
	_build_buildings_slice(root, buildings, 0, buildings.size())

func _build_buildings_slice(root: Node3D, buildings: Array, start_idx: int, end_idx: int) -> void:
	var b_root := root.get_node_or_null("Buildings") as Node3D
	if b_root == null:
		b_root = Node3D.new()
		b_root.name = "Buildings"
		root.add_child(b_root)

	var lo := maxi(0, start_idx)
	var hi := mini(buildings.size(), end_idx)
	for i in range(lo, hi):
		var b: Dictionary = buildings[i]
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
			_add_building_sign(b_node, poly, h, sign_text, col_trim, b)

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

func _build_courtyard_building(parent: Node3D, poly: PackedVector2Array, h: float, inset: float, col_wall: Color, col_trim: Color, b: Dictionary) -> void:
	var outer_cw := _ensure_cw_screen(poly)
	var inner_cw := _compute_inset_polygon(outer_cw, inset)
	_courtyard_inners.append(inner_cw)

	if bool(b.get("walkable", false)):
		var inner_ccw := inner_cw.duplicate()
		inner_ccw.reverse()
		var loops: Array[PackedVector2Array] = [outer_cw, inner_ccw]
		_build_walkable_shell_loops(parent, loops, h, col_wall, col_trim, int(b.get("floors", 1)), bool(b.get("has_windows", true)), b)
		_build_building_roof(parent, outer_cw, inner_cw, h, b, true)
		return

	for i in range(outer_cw.size()):
		var j := (i + 1) % outer_cw.size()
		var wing := PackedVector2Array([outer_cw[i], outer_cw[j], inner_cw[j], inner_cw[i]])
		_add_building_volume(parent, wing, h, col_wall, col_trim, int(b.get("floors", 2)), true, b)

func _make_building_occluder(poly: PackedVector2Array, h: float) -> ArrayOccluder3D:
	var cw := _ensure_cw_screen(poly)
	var n := cw.size()
	if n < 3 or h < 2.5:
		return null
	# Inset footprint slightly (0.14m) along bisectors so facade windows/pilasters stay outside the occluder
	var inset_pts := PackedVector2Array()
	inset_pts.resize(n)
	for i in range(n):
		var prev := cw[(i - 1 + n) % n]
		var curr := cw[i]
		var nxt := cw[(i + 1) % n]
		var e0 := (curr - prev).normalized()
		var e1 := (nxt - curr).normalized()
		var in0 := Vector2(-e0.y, e0.x)
		var in1 := Vector2(-e1.y, e1.x)
		var bis := in0 + in1
		if bis.length_squared() > 0.001:
			bis = bis.normalized()
		else:
			bis = in1
		inset_pts[i] = curr + bis * 0.14

	var occ_h := h - 0.12
	var verts := PackedVector3Array()
	verts.resize(n * 2)
	for i in range(n):
		verts[i] = Vector3(inset_pts[i].x, 0.0, inset_pts[i].y)
		verts[n + i] = Vector3(inset_pts[i].x, occ_h, inset_pts[i].y)

	var indices := PackedInt32Array()
	# Top cap triangles
	var tris := Geometry2D.triangulate_polygon(inset_pts)
	if tris.is_empty():
		return null
	for ti in range(0, tris.size(), 3):
		var a := n + tris[ti]
		var b := n + tris[ti + 1]
		var c := n + tris[ti + 2]
		var va := verts[a]; var vb := verts[b]; var vc := verts[c]
		if (vb - va).cross(vc - va).y > 0.0:
			var tmp := b; b = c; c = tmp
		indices.append(a); indices.append(b); indices.append(c)

	# Side wall quads
	for i in range(n):
		var j := (i + 1) % n
		var v0 := i
		var v1 := j
		var v2 := n + j
		var v3 := n + i
		var edge := inset_pts[j] - inset_pts[i]
		var out_n := Vector3(edge.y, 0.0, -edge.x)
		if (verts[v1] - verts[v0]).cross(verts[v2] - verts[v0]).dot(out_n) <= 0.0:
			indices.append(v0); indices.append(v1); indices.append(v2)
			indices.append(v0); indices.append(v2); indices.append(v3)
		else:
			indices.append(v1); indices.append(v0); indices.append(v3)
			indices.append(v1); indices.append(v3); indices.append(v2)

	var occ := ArrayOccluder3D.new()
	occ.set_arrays(verts, indices)
	return occ

func _add_building_volume(parent: Node3D, poly: PackedVector2Array, h: float, col_wall: Color, col_trim: Color, floors: int, has_windows: bool, b: Dictionary) -> void:
	var wall_mat := mats.get_batch_material("vcol_wall")
	var btype := String(b.get("type", ""))
	var is_walkable := bool(b.get("walkable", false))

	if btype == "corridor":
		# Open covered walkway on concrete pillars (passable on foot!)
		var roof_col := Color("#6B6E73")
		var cw_cor := _ensure_cw_screen(poly)
		var canopy := StaticBody3D.new()
		var cmesh := _extrude_roof_cap_mesh(cw_cor, 0.0, 0.35, roof_col, false)
		var roof_vis := Node3D.new()
		roof_vis.name = "CorridorRoofGroup"
		roof_vis.position.y = h - 0.35
		canopy.add_child(roof_vis)
		var cmi := MeshInstance3D.new()
		cmi.mesh = cmesh
		cmi.material_override = mats.get_batch_material("vcol_roof")
		roof_vis.add_child(cmi)
		var ceil_mi := MeshInstance3D.new()
		ceil_mi.name = "CorridorCeiling"
		ceil_mi.mesh = _make_polygon_ceiling_mesh(cw_cor, 0.0)
		ceil_mi.material_override = mats.get_material("interior_wall", Color("#F4F2EC"))
		ceil_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		roof_vis.add_child(ceil_mi)
		if is_walkable:
			roof_nodes.append(roof_vis)
		var ccol := CollisionShape3D.new()
		ccol.shape = cmesh.create_trimesh_shape()
		ccol.position.y = h - 0.35
		canopy.add_child(ccol)
		parent.add_child(canopy)
		var pil_col := Color("#DEDAD2")
		for v in poly:
			_add_colored_cylinder(parent, Vector3(v.x, (h - 0.35) * 0.5, v.y), Vector3(0.30, h - 0.35, 0.30), Vector3.ZERO, "batch_concrete", pil_col, true)
		return

	var outer_cw := _ensure_cw_screen(poly)
	if is_walkable:
		var loops: Array[PackedVector2Array] = [outer_cw]
		_build_walkable_shell_loops(parent, loops, h, col_wall, col_trim, floors, has_windows, b)
		_build_building_roof(parent, outer_cw, PackedVector2Array(), h, b, true)
		return

	var body := StaticBody3D.new()
	var mesh := _extrude_polygon_mesh(poly, h, true, true, col_wall)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = wall_mat
	body.add_child(mi)

	var col_shape := CollisionShape3D.new()
	col_shape.shape = mesh.create_trimesh_shape()
	body.add_child(col_shape)

	# Software Occlusion Culling proxy for solid non-walkable buildings (desktop builds with Embree occlusion enabled)
	if not OS.has_feature("web"):
		var occ := _make_building_occluder(poly, h)
		if occ != null:
			var occ_inst := OccluderInstance3D.new()
			occ_inst.occluder = occ
			body.add_child(occ_inst)

	parent.add_child(body)
	_build_building_roof(parent, outer_cw, PackedVector2Array(), h, b, false)

	for i in range(outer_cw.size()):
		var p1 := outer_cw[i]
		var p2 := outer_cw[(i + 1) % outer_cw.size()]
		var edge := p2 - p1
		var edge_len := edge.length()
		if edge_len < 3.5:
			continue
		var solid_spans: Array[Vector2] = [Vector2(0.0, edge_len)]
		_add_edge_facade_details(parent, p1, p2, h, col_trim, floors, has_windows, btype, solid_spans, [], false, false, i == 0)

func _merge_edge_cuts(raw_cuts: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if raw_cuts.is_empty():
		return out
	var sorted := raw_cuts.duplicate()
	sorted.sort_custom(func(x, y): return float(x["a"]) < float(y["a"]))
	for item in sorted:
		var a := float(item["a"])
		var b := float(item["b"])
		var ch := float(item["h"])
		if b - a < 0.2:
			continue
		if out.is_empty() or a > float(out[out.size() - 1]["b"]) + 0.15:
			out.append({"a": a, "b": b, "h": ch})
		else:
			var prev: Dictionary = out[out.size() - 1]
			prev["b"] = maxf(float(prev["b"]), b)
			prev["h"] = maxf(float(prev["h"]), ch)
			out[out.size() - 1] = prev
	return out

func _project_entrances_to_loops(loops: Array[PackedVector2Array], entrances: Array, max_dist: float, h: float) -> Array:
	var all_cuts: Array = []
	for loop in loops:
		var loop_cuts: Array = []
		for _i in range(loop.size()):
			loop_cuts.append([])
		all_cuts.append(loop_cuts)

	var mapped_counts: Array[int] = []
	mapped_counts.resize(loops.size())
	for li in range(loops.size()):
		mapped_counts[li] = 0

	for ent in entrances:
		if not (ent is Dictionary):
			continue
		var pos_a: Array = ent.get("pos", [])
		if pos_a.size() < 2:
			continue
		var ep := Vector2(float(pos_a[0]), float(pos_a[1]))
		var door_w := clampf(float(ent.get("width", 2.4)), 1.2, 12.0)
		var door_h := clampf(float(ent.get("height", 2.6)), 2.3, maxf(2.35, h - 0.25))

		var best_li := -1
		var best_ei := -1
		var best_t := 0.5
		var best_d := max_dist + 0.001

		for li in range(loops.size()):
			var loop := loops[li]
			var n := loop.size()
			for ei in range(n):
				var p1 := loop[ei]
				var p2 := loop[(ei + 1) % n]
				var edge := p2 - p1
				var len_sq := edge.length_squared()
				if len_sq < 0.04:
					continue
				var t := clampf((ep - p1).dot(edge) / len_sq, 0.0, 1.0)
				var proj := p1 + edge * t
				var d := ep.distance_to(proj)
				if d < best_d:
					best_d = d
					best_li = li
					best_ei = ei
					best_t = t

		if best_li >= 0 and best_ei >= 0:
			var loop := loops[best_li]
			var n := loop.size()
			var p1 := loop[best_ei]
			var p2 := loop[(best_ei + 1) % n]
			var edge := p2 - p1
			var edge_len := edge.length()
			var edge_dir := edge / edge_len
			var s_center := best_t * edge_len
			var s0 := s_center - door_w * 0.5
			var s1 := s_center + door_w * 0.5

			# Handle doorway straddling a collinear vertex between adjacent edges
			if s0 < 0.0:
				var prev_ei := (best_ei - 1 + n) % n
				var prev_edge := loop[best_ei] - loop[prev_ei]
				var prev_len := prev_edge.length()
				if prev_len > 0.2 and (prev_edge / prev_len).dot(edge_dir) > 0.92:
					var pa := maxf(0.0, prev_len + s0)
					(all_cuts[best_li][prev_ei] as Array).append({"a": pa, "b": prev_len, "h": door_h})
			if s1 > edge_len:
				var next_ei := (best_ei + 1) % n
				var next_edge := loop[(next_ei + 1) % n] - loop[next_ei]
				var next_len := next_edge.length()
				if next_len > 0.2 and edge_dir.dot(next_edge / next_len) > 0.92:
					var nb := minf(next_len, s1 - edge_len)
					(all_cuts[best_li][next_ei] as Array).append({"a": 0.0, "b": nb, "h": door_h})

			var ca := clampf(s0, 0.0, edge_len)
			var cb := clampf(s1, 0.0, edge_len)
			if cb - ca >= 0.2:
				(all_cuts[best_li][best_ei] as Array).append({"a": ca, "b": cb, "h": door_h})
				mapped_counts[best_li] += 1

	# Ensure inner courtyard loop always has open doorway access to the garden
	if loops.size() >= 2 and mapped_counts[1] == 0:
		var cloop := loops[1]
		var cn := cloop.size()
		var edge_list: Array[Dictionary] = []
		for ei in range(cn):
			var elen := cloop[ei].distance_to(cloop[(ei + 1) % cn])
			if elen >= 4.0:
				edge_list.append({"ei": ei, "len": elen})
		edge_list.sort_custom(func(x, y): return float(x["len"]) > float(y["len"]))
		var open_cnt := mini(2, edge_list.size())
		var cd_h := clampf(2.55, 2.3, maxf(2.35, h - 0.3))
		for k in range(open_cnt):
			var ei := int(edge_list[k]["ei"])
			var elen := float(edge_list[k]["len"])
			var mid_s := elen * 0.5
			(all_cuts[1][ei] as Array).append({"a": maxf(0.4, mid_s - 1.3), "b": minf(elen - 0.4, mid_s + 1.3), "h": cd_h})

	# Safe fallback: if a walkable building has zero mapped outer entrances, open one on its longest edge
	if loops.size() >= 1 and mapped_counts[0] == 0:
		var oloop := loops[0]
		var best_e := 0
		var best_l := -1.0
		for ei in range(oloop.size()):
			var elen := oloop[ei].distance_to(oloop[(ei + 1) % oloop.size()])
			if elen > best_l:
				best_l = elen
				best_e = ei
		if best_l >= 3.0:
			var mid_s := best_l * 0.5
			(all_cuts[0][best_e] as Array).append({"a": maxf(0.3, mid_s - 1.3), "b": minf(best_l - 0.3, mid_s + 1.3), "h": clampf(2.55, 2.3, maxf(2.35, h - 0.3))})

	# Merge cuts on every edge
	for li in range(loops.size()):
		for ei in range(loops[li].size()):
			all_cuts[li][ei] = _merge_edge_cuts(all_cuts[li][ei])

	return all_cuts

func _push_oriented_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, desired_n: Vector3, w: float, h: float, col: Color) -> void:
	var n := desired_n.normalized()
	st.set_normal(n)
	st.set_color(col)
	var tri_n := (v1 - v0).cross(v2 - v0)
	if tri_n.dot(n) <= 0.0:
		_push_quad(st, v0, v1, v2, v3, w, h)
	else:
		_push_quad(st, v1, v0, v3, v2, w, h)

func _emit_wall_segment(
	st: SurfaceTool, body: StaticBody3D,
	p1: Vector2, edge_dir: Vector2, out_dir: Vector2, in_dir: Vector2,
	edge_len: float, iv0: Vector2, iv1: Vector2,
	seg_a: float, seg_b: float, y0: float, y1: float,
	wall_t: float, rot_y: float,
	col_out: Color, col_in: Color, col_jamb: Color, col_top: Color
) -> void:
	var seg_len := seg_b - seg_a
	var seg_h := y1 - y0
	if seg_len < 0.04 or seg_h < 0.04:
		return

	# Solid physics box collider strictly on this solid wall segment
	var col := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(wall_t, seg_h, seg_len)
	col.shape = cbox
	var mid2 := p1 + edge_dir * ((seg_a + seg_b) * 0.5) + in_dir * (wall_t * 0.5)
	col.position = Vector3(mid2.x, (y0 + y1) * 0.5, mid2.y)
	col.rotation.y = rot_y
	body.add_child(col)

	var oa := p1 + edge_dir * seg_a
	var ob := p1 + edge_dir * seg_b
	var at_start := seg_a <= 0.015
	var at_end := seg_b >= edge_len - 0.015
	var ia := iv0 if at_start else (oa + in_dir * wall_t)
	var ib := iv1 if at_end else (ob + in_dir * wall_t)
	if (ib - ia).dot(edge_dir) <= 0.02:
		ia = oa + in_dir * wall_t
		ib = ob + in_dir * wall_t

	var oa0 := Vector3(oa.x, y0, oa.y)
	var ob0 := Vector3(ob.x, y0, ob.y)
	var ob1 := Vector3(ob.x, y1, ob.y)
	var oa1 := Vector3(oa.x, y1, oa.y)
	var ia0 := Vector3(ia.x, y0, ia.y)
	var ib0 := Vector3(ib.x, y0, ib.y)
	var ib1 := Vector3(ib.x, y1, ib.y)
	var ia1 := Vector3(ia.x, y1, ia.y)

	var out_n := Vector3(out_dir.x, 0.0, out_dir.y)
	var in_n := Vector3(in_dir.x, 0.0, in_dir.y)
	var edge_n := Vector3(edge_dir.x, 0.0, edge_dir.y)

	# Outer face (exterior architectural color)
	_push_oriented_quad(st, oa0, ob0, ob1, oa1, out_n, seg_len, seg_h, col_out)
	# Inner face (bright warm interior plaster)
	_push_oriented_quad(st, ib0, ia0, ia1, ib1, in_n, ia.distance_to(ib), seg_h, col_in)
	# Doorway jamb reveals (only at actual doorway cuts, never creating coplanar overlaps at corners)
	if not at_start:
		_push_oriented_quad(st, ia0, oa0, oa1, ia1, -edge_n, wall_t, seg_h, col_jamb)
	if not at_end:
		_push_oriented_quad(st, ob0, ib0, ib1, ob1, edge_n, wall_t, seg_h, col_jamb)
	# Header soffit underside (when y0 > 0 above doorway)
	if y0 > 0.02:
		_push_oriented_quad(st, oa0, ob0, ib0, ia0, Vector3.DOWN, seg_len, wall_t, col_jamb)
	# Top cap (clean architectural wall thickness visible in Drone X-ray mode when roofs are hidden)
	_push_oriented_quad(st, oa1, ob1, ib1, ia1, Vector3.UP, seg_len, wall_t, col_top)

func _build_walkable_shell_loops(parent: Node3D, loops: Array[PackedVector2Array], h: float, col_wall: Color, col_trim: Color, floors: int, has_windows: bool, b: Dictionary) -> void:
	const WALL_T := 0.24
	var btype := String(b.get("type", ""))
	var entrances: Array = b.get("entrances", [])
	var all_cuts := _project_entrances_to_loops(loops, entrances, 2.5, h)

	var body := StaticBody3D.new()
	body.name = "WalkableShellBody"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var col_inner := Color("#EFECE6")
	var col_jamb := Color("#D8D3CA")
	var col_top := col_wall.darkened(0.08)
	var frame_col := Color("#26302B")

	for li in range(loops.size()):
		var loop := loops[li]
		var n := loop.size()
		var inner_v := _compute_inset_polygon(loop, WALL_T)
		var is_inner_courtyard := (li == 1)

		for ei in range(n):
			var ej := (ei + 1) % n
			var p1 := loop[ei]
			var p2 := loop[ej]
			var edge := p2 - p1
			var edge_len := edge.length()
			if edge_len < 0.1:
				continue
			var edge_dir := edge / edge_len
			var out_dir := Vector2(edge.y, -edge.x).normalized()
			var in_dir := -out_dir
			var rot_y := atan2(edge.x, edge.y)
			var rot_v := Vector3(0.0, rot_y, 0.0)
			var cuts: Array = all_cuts[li][ei]

			var solid_spans: Array[Vector2] = []
			var cursor := 0.0
			for cut in cuts:
				var ca := float(cut["a"])
				var cb := float(cut["b"])
				var ch := float(cut["h"])
				if ca - cursor > 0.06:
					solid_spans.append(Vector2(cursor, ca))
					_emit_wall_segment(st, body, p1, edge_dir, out_dir, in_dir, edge_len, inner_v[ei], inner_v[ej], cursor, ca, 0.0, h, WALL_T, rot_y, col_wall, col_inner, col_jamb, col_top)
				# Doorway header above open passage
				if h - ch > 0.05:
					_emit_wall_segment(st, body, p1, edge_dir, out_dir, in_dir, edge_len, inner_v[ei], inner_v[ej], ca, cb, ch, h, WALL_T, rot_y, col_wall, col_inner, col_jamb, col_top)
				# Open doorway dark-metal frame trim (jambs + lintel bar, ZERO center blocking)
				var mid_door := p1 + edge_dir * ((ca + cb) * 0.5) + in_dir * (WALL_T * 0.5)
				var ja := p1 + edge_dir * (ca + 0.03) + in_dir * (WALL_T * 0.5)
				var jb := p1 + edge_dir * (cb - 0.03) + in_dir * (WALL_T * 0.5)
				_add_colored_box(parent, Vector3(ja.x, ch * 0.5, ja.y), Vector3(WALL_T + 0.05, ch, 0.06), rot_v, "batch_metal", frame_col, false, 1)
				_add_colored_box(parent, Vector3(jb.x, ch * 0.5, jb.y), Vector3(WALL_T + 0.05, ch, 0.06), rot_v, "batch_metal", frame_col, false, 1)
				_add_colored_box(parent, Vector3(mid_door.x, ch - 0.03, mid_door.y), Vector3(WALL_T + 0.06, 0.07, maxf(0.1, cb - ca)), rot_v, "batch_metal", frame_col, false, 1)
				cursor = cb

			if edge_len - cursor > 0.06:
				solid_spans.append(Vector2(cursor, edge_len))
				_emit_wall_segment(st, body, p1, edge_dir, out_dir, in_dir, edge_len, inner_v[ei], inner_v[ej], cursor, edge_len, 0.0, h, WALL_T, rot_y, col_wall, col_inner, col_jamb, col_top)

			if edge_len >= 3.2:
				_add_edge_facade_details(parent, p1, p2, h, col_trim, floors, has_windows, btype, solid_spans, cuts, true, is_inner_courtyard, false)

	st.index()
	st.generate_tangents()
	var shell_mesh := st.commit()
	if shell_mesh != null and shell_mesh.get_surface_count() > 0:
		var mi := MeshInstance3D.new()
		mi.name = "ShellMesh"
		mi.mesh = shell_mesh
		mi.material_override = mats.get_batch_material("vcol_wall")
		body.add_child(mi)
	parent.add_child(body)

func _add_edge_facade_details(
	parent: Node3D, p1: Vector2, p2: Vector2, h: float, col_trim: Color,
	floors: int, has_windows: bool, btype: String,
	solid_spans: Array[Vector2], cuts: Array,
	is_walkable: bool, is_inner_courtyard: bool, add_fake_door: bool
) -> void:
	var edge := p2 - p1
	var edge_len := edge.length()
	if edge_len < 3.2:
		return
	var edge_dir := edge / edge_len
	var mid := (p1 + p2) * 0.5
	var angle := atan2(edge.x, edge.y)
	var out_dir := Vector2(edge.y, -edge.x).normalized()
	var rot_v := Vector3(0.0, angle, 0.0)

	var pil_col := Color("#F2F1ED")
	var mull_col := Color("#272B30")
	var ac_col := Color("#F0F2F5")
	var door_col := Color("#223228")
	var aud_terra := Color("#BA715C")
	var aud_mull := Color("#23272A")

	# Top architectural fascia trim (near roof edge, always clear of doorways)
	var trim_c := Color("#6E4E33") if btype == "social_house" else col_trim
	_add_colored_box(parent, Vector3(mid.x + out_dir.x * 0.08, h - 0.30, mid.y + out_dir.y * 0.08), Vector3(0.14, 0.46, edge_len), rot_v, "batch_wall", trim_c)

	# Architectural pilasters (skip positions overlapping any doorway cutout)
	if not is_inner_courtyard and btype in ["admin", "academic", "academic_cross", "library", "lab", "sports"] and edge_len >= 6.5:
		var pil_count := int(edge_len / 7.0) + 1
		for pi in range(pil_count):
			var pt := lerpf(0.04, 0.96, float(pi) / maxf(1.0, float(pil_count - 1)))
			var ps := pt * edge_len
			var blocked := false
			for cut in cuts:
				if ps >= float(cut["a"]) - 0.35 and ps <= float(cut["b"]) + 0.35:
					blocked = true
					break
			if blocked:
				continue
			var pos2 := p1 + edge_dir * ps + out_dir * 0.09
			_add_colored_box(parent, Vector3(pos2.x, h * 0.5, pos2.y), Vector3(0.18, h, 0.34), rot_v, "batch_wall", pil_col)

	# Auditorium terracotta base cladding (clipped to solid wall segments) + upper clerestory band
	if btype == "auditorium" and edge_len > 8.0:
		for sp in solid_spans:
			var sa := maxf(sp.x, edge_len * 0.06)
			var sb := minf(sp.y, edge_len * 0.94)
			var sl := sb - sa
			if sl >= 1.2:
				var smid := p1 + edge_dir * ((sa + sb) * 0.5) + out_dir * 0.07
				_add_colored_box(parent, Vector3(smid.x, h * 0.31, smid.y), Vector3(0.12, h * 0.60, sl), rot_v, "batch_wall", aud_terra)
		_add_static_box(parent, Vector3(mid.x + out_dir.x * 0.07, h * 0.72, mid.y + out_dir.y * 0.07), Vector3(0.10, 1.05, edge_len * 0.88), rot_v, win_mat)
		for m_i in range(9):
			var t := lerpf(-0.42, 0.42, float(m_i) / 8.0)
			var along := edge_dir * (t * edge_len)
			_add_colored_box(parent, Vector3(mid.x + along.x + out_dir.x * 0.08, h * 0.72, mid.y + along.y + out_dir.y * 0.08), Vector3(0.14, 1.12, 0.10), rot_v, "batch_metal", aud_mull, false, 1)

	# Ribbon windows + mullions + AC units (ground floor strictly inside solid spans clear of doors!)
	var show_win := has_windows or is_inner_courtyard
	if show_win:
		var full_span: Array[Vector2] = [Vector2(0.0, edge_len)]
		var eff_floors := maxi(1, floors)
		for fl in range(eff_floors):
			var wy := 1.9 + fl * (h / float(eff_floors))
			if wy + 0.75 > h - 0.45:
				continue
			var spans_to_use: Array[Vector2] = solid_spans if (is_walkable and fl == 0) else full_span
			for sp in spans_to_use:
				var margin := 0.48 if is_walkable else edge_len * 0.11
				var wa := sp.x + margin
				var wb := sp.y - margin
				var wlen := wb - wa
				if wlen < 1.3:
					continue
				var wmid := p1 + edge_dir * ((wa + wb) * 0.5)
				_add_static_box(parent, Vector3(wmid.x + out_dir.x * 0.06, wy, wmid.y + out_dir.y * 0.06), Vector3(0.08, 1.35, wlen), rot_v, win_mat)
				if wlen >= 4.2:
					var m_cnt := mini(8, maxi(2, int(wlen / 3.2)))
					for mi_w in range(m_cnt):
						var mt := lerpf(-0.42, 0.42, float(mi_w) / maxf(1.0, float(m_cnt - 1)))
						var along_m := edge_dir * (mt * wlen)
						_add_colored_box(parent, Vector3(wmid.x + along_m.x + out_dir.x * 0.07, wy, wmid.y + along_m.y + out_dir.y * 0.07), Vector3(0.11, 1.38, 0.08), rot_v, "batch_metal", mull_col, false, 1)
				if not is_inner_courtyard and fl == 1 and wlen >= 8.0:
					for ac_t: float in [-0.24, 0.24]:
						var along_ac: Vector2 = edge_dir * (ac_t * wlen)
						_add_colored_box(parent, Vector3(wmid.x + along_ac.x + out_dir.x * 0.14, wy - 0.92, wmid.y + along_ac.y + out_dir.y * 0.14), Vector3(0.26, 0.45, 0.68), rot_v, "batch_wall", ac_col, false, 1)

	if add_fake_door and not is_walkable and edge_len >= 5.0 and btype != "corridor":
		_add_colored_box(parent, Vector3(mid.x + out_dir.x * 0.09, 1.05, mid.y + out_dir.y * 0.09), Vector3(0.14, 2.1, 2.4), rot_v, "batch_metal", door_col)

func _build_building_roof(parent: Node3D, outer_cw: PackedVector2Array, inner_cw: PackedVector2Array, h: float, b: Dictionary, is_walkable: bool) -> void:
	var btype := String(b.get("type", ""))
	var roof_group := Node3D.new()
	roof_group.name = "RoofGroup"
	parent.add_child(roof_group)
	if is_walkable:
		roof_nodes.append(roof_group)

	var ceil_mat := mats.get_material("interior_wall", Color("#F4F2EC"))

	if btype == "social_house":
		var pmesh := _make_pitched_roof_mesh(outer_cw, h, 1.65, 0.45, Color("#9C4F38"), false)
		var pmi := MeshInstance3D.new()
		pmi.name = "PitchedRoof"
		pmi.mesh = pmesh
		pmi.material_override = mats.get_batch_material("vcol_roof")
		pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		roof_group.add_child(pmi)
		if is_walkable:
			var scmi := MeshInstance3D.new()
			scmi.name = "CeilingUnderside"
			scmi.mesh = _make_polygon_ceiling_mesh(outer_cw, h)
			scmi.material_override = ceil_mat
			scmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			roof_group.add_child(scmi)
		return

	var roof_col := Color("#6B6E73")
	if btype in ["auditorium", "library", "student_center", "academic_cross", "workshop"]:
		roof_col = Color("#E6E8EC") if btype != "workshop" else Color("#9EA4AB")
	var smooth_roof := btype in ["auditorium", "library", "student_center", "academic_cross"]

	var cap := MeshInstance3D.new()
	cap.name = "RoofCap"
	if inner_cw.size() >= 3:
		cap.mesh = _make_annular_roof_mesh(outer_cw, inner_cw, h, 0.25, roof_col, false)
	else:
		cap.mesh = _extrude_roof_cap_mesh(outer_cw, h, 0.25, roof_col, false)
	cap.material_override = mats.get_batch_material("vcol_wall" if smooth_roof else "vcol_roof")
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	roof_group.add_child(cap)

	if is_walkable:
		var ceil_mi := MeshInstance3D.new()
		ceil_mi.name = "CeilingUnderside"
		if inner_cw.size() >= 3:
			ceil_mi.mesh = _make_annular_ceiling_mesh(outer_cw, inner_cw, h)
		else:
			ceil_mi.mesh = _make_polygon_ceiling_mesh(outer_cw, h)
		ceil_mi.material_override = ceil_mat
		ceil_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		roof_group.add_child(ceil_mi)

	if btype in ["academic", "workshop"] and outer_cw.size() >= 4 and inner_cw.is_empty():
		var rib_mesh := _build_roof_ribs_mesh(outer_cw, h, btype)
		if rib_mesh != null:
			var rmi := MeshInstance3D.new()
			rmi.name = "RoofSkylights"
			rmi.mesh = rib_mesh
			rmi.material_override = mats.get_batch_material("batch_wall" if btype == "workshop" else "batch_metal")
			rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			roof_group.add_child(rmi)
	elif btype in ["library", "student_center", "academic_cross"]:
		var c2 := _poly_centroid(outer_cw)
		var dome := MeshInstance3D.new()
		dome.name = "OctagonalDome"
		var dm := CylinderMesh.new()
		dm.top_radius = 2.6; dm.bottom_radius = 4.2; dm.height = 1.4; dm.radial_segments = 8; dm.rings = 0
		dome.mesh = dm
		dome.position = Vector3(c2.x, h + 0.8, c2.y)
		dome.material_override = mats.get_material("wall", Color("#D9E4F0"))
		dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		roof_group.add_child(dome)

func _extrude_roof_cap_mesh(cw: PackedVector2Array, base_y: float, thickness: float, roof_col: Color, include_ceiling: bool) -> ArrayMesh:
	var tris := Geometry2D.triangulate_polygon(cw)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top_y := base_y + thickness
	var ceil_col := Color("#F2F0EC")
	var side_col := roof_col.darkened(0.06)

	for i in range(0, tris.size(), 3):
		var a := Vector3(cw[tris[i]].x, top_y, cw[tris[i]].y)
		var b := Vector3(cw[tris[i + 1]].x, top_y, cw[tris[i + 1]].y)
		var c := Vector3(cw[tris[i + 2]].x, top_y, cw[tris[i + 2]].y)
		if (b - a).cross(c - a).y > 0.0:
			var tmp := b; b = c; c = tmp
		st.set_normal(Vector3.UP)
		st.set_color(roof_col)
		st.set_uv(Vector2(a.x, a.z) * 0.14); st.add_vertex(a)
		st.set_uv(Vector2(b.x, b.z) * 0.14); st.add_vertex(b)
		st.set_uv(Vector2(c.x, c.z) * 0.14); st.add_vertex(c)

		if include_ceiling:
			var ca := Vector3(a.x, base_y, a.z)
			var cb := Vector3(c.x, base_y, c.z)
			var cc := Vector3(b.x, base_y, b.z)
			st.set_normal(Vector3.DOWN)
			st.set_color(ceil_col)
			st.set_uv(Vector2(ca.x, ca.z) * 0.14); st.add_vertex(ca)
			st.set_uv(Vector2(cb.x, cb.z) * 0.14); st.add_vertex(cb)
			st.set_uv(Vector2(cc.x, cc.z) * 0.14); st.add_vertex(cc)

	for i in range(cw.size()):
		var p0 := cw[i]
		var p1 := cw[(i + 1) % cw.size()]
		var edge := p1 - p0
		var elen := edge.length()
		if elen < 0.02:
			continue
		var out_n := Vector3(edge.y, 0.0, -edge.x).normalized()
		_push_oriented_quad(
			st,
			Vector3(p0.x, base_y, p0.y), Vector3(p1.x, base_y, p1.y),
			Vector3(p1.x, top_y, p1.y), Vector3(p0.x, top_y, p0.y),
			out_n, elen, thickness, side_col
		)

	st.index()
	st.generate_tangents()
	return st.commit()

func _make_annular_roof_mesh(outer_cw: PackedVector2Array, inner_cw: PackedVector2Array, base_y: float, thickness: float, roof_col: Color, include_ceiling: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top_y := base_y + thickness
	var ceil_col := Color("#F2F0EC")
	var side_col := roof_col.darkened(0.06)
	var n := mini(outer_cw.size(), inner_cw.size())

	for i in range(n):
		var j := (i + 1) % n
		var o0 := outer_cw[i]
		var o1 := outer_cw[j]
		var n0 := inner_cw[i]
		var n1 := inner_cw[j]
		# Top annular quad
		_push_oriented_quad(
			st,
			Vector3(o0.x, top_y, o0.y), Vector3(o1.x, top_y, o1.y),
			Vector3(n1.x, top_y, n1.y), Vector3(n0.x, top_y, n0.y),
			Vector3.UP, o0.distance_to(o1), o0.distance_to(n0), roof_col
		)
		# Ceiling underside quad
		if include_ceiling:
			_push_oriented_quad(
				st,
				Vector3(o0.x, base_y, o0.y), Vector3(o1.x, base_y, o1.y),
				Vector3(n1.x, base_y, n1.y), Vector3(n0.x, base_y, n0.y),
				Vector3.DOWN, o0.distance_to(o1), o0.distance_to(n0), ceil_col
			)
		# Outer parapet fascia
		var oedge := o1 - o0
		if oedge.length() >= 0.02:
			_push_oriented_quad(
				st,
				Vector3(o0.x, base_y, o0.y), Vector3(o1.x, base_y, o1.y),
				Vector3(o1.x, top_y, o1.y), Vector3(o0.x, top_y, o0.y),
				Vector3(oedge.y, 0.0, -oedge.x).normalized(), oedge.length(), thickness, side_col
			)
		# Inner courtyard parapet fascia (facing into courtyard)
		var iedge := n1 - n0
		if iedge.length() >= 0.02:
			_push_oriented_quad(
				st,
				Vector3(n0.x, base_y, n0.y), Vector3(n1.x, base_y, n1.y),
				Vector3(n1.x, top_y, n1.y), Vector3(n0.x, top_y, n0.y),
				Vector3(-iedge.y, 0.0, iedge.x).normalized(), iedge.length(), thickness, side_col
			)

	st.index()
	st.generate_tangents()
	return st.commit()

func _make_pitched_roof_mesh(cw: PackedVector2Array, base_y: float, ridge_h: float, overhang: float, roof_col: Color, include_ceiling: bool) -> ArrayMesh:
	var c2 := _poly_centroid(cw)
	var eaves := PackedVector2Array()
	eaves.resize(cw.size())
	for i in range(cw.size()):
		var dir := (cw[i] - c2).normalized()
		eaves[i] = cw[i] + dir * overhang

	var apex := Vector3(c2.x, base_y + ridge_h, c2.y)
	var eave_y := base_y - 0.04
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(eaves.size()):
		var p0 := eaves[i]
		var p1 := eaves[(i + 1) % eaves.size()]
		var v0 := Vector3(p0.x, eave_y, p0.y)
		var v1 := Vector3(p1.x, eave_y, p1.y)
		var slope_n := (v1 - v0).cross(apex - v0)
		if slope_n.y < 0.0:
			slope_n = -slope_n
		slope_n = slope_n.normalized()
		var tri_n := (v1 - v0).cross(apex - v0)
		var a := v0; var b := v1; var c := apex
		if tri_n.dot(slope_n) > 0.0:
			b = apex; c = v1
		st.set_normal(slope_n)
		st.set_color(roof_col)
		st.set_uv(Vector2(a.x, a.z) * 0.2); st.add_vertex(a)
		st.set_uv(Vector2(b.x, b.z) * 0.2); st.add_vertex(b)
		st.set_uv(Vector2(c.x, c.z) * 0.2); st.add_vertex(c)

	# Flat soffit / ceiling underside at base_y
	if include_ceiling:
		var tris := Geometry2D.triangulate_polygon(eaves)
		var ceil_col := Color("#F2EFEA")
		for i in range(0, tris.size(), 3):
			var a := Vector3(eaves[tris[i]].x, base_y, eaves[tris[i]].y)
			var b := Vector3(eaves[tris[i + 1]].x, base_y, eaves[tris[i + 1]].y)
			var c := Vector3(eaves[tris[i + 2]].x, base_y, eaves[tris[i + 2]].y)
			if (b - a).cross(c - a).y < 0.0:
				var tmp := b; b = c; c = tmp
			st.set_normal(Vector3.DOWN)
			st.set_color(ceil_col)
			st.set_uv(Vector2(a.x, a.z) * 0.14); st.add_vertex(a)
			st.set_uv(Vector2(b.x, b.z) * 0.14); st.add_vertex(b)
			st.set_uv(Vector2(c.x, c.z) * 0.14); st.add_vertex(c)

	st.index()
	st.generate_tangents()
	return st.commit()

func _make_polygon_ceiling_mesh(cw: PackedVector2Array, y_level: float) -> ArrayMesh:
	var tris := Geometry2D.triangulate_polygon(cw)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, tris.size(), 3):
		var a := Vector3(cw[tris[i]].x, y_level, cw[tris[i]].y)
		var b := Vector3(cw[tris[i + 1]].x, y_level, cw[tris[i + 1]].y)
		var c := Vector3(cw[tris[i + 2]].x, y_level, cw[tris[i + 2]].y)
		if (b - a).cross(c - a).y < 0.0:
			var tmp := b; b = c; c = tmp
		st.set_normal(Vector3.DOWN)
		st.set_uv(Vector2(a.x, a.z) * 0.14); st.add_vertex(a)
		st.set_uv(Vector2(b.x, b.z) * 0.14); st.add_vertex(b)
		st.set_uv(Vector2(c.x, c.z) * 0.14); st.add_vertex(c)
	st.index()
	return st.commit()

func _make_annular_ceiling_mesh(outer_cw: PackedVector2Array, inner_cw: PackedVector2Array, y_level: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := mini(outer_cw.size(), inner_cw.size())
	for i in range(n):
		var j := (i + 1) % n
		var o0 := outer_cw[i]
		var o1 := outer_cw[j]
		var n0 := inner_cw[i]
		var n1 := inner_cw[j]
		_push_oriented_quad(
			st,
			Vector3(o0.x, y_level, o0.y), Vector3(o1.x, y_level, o1.y),
			Vector3(n1.x, y_level, n1.y), Vector3(n0.x, y_level, n0.y),
			Vector3.DOWN, o0.distance_to(o1), o0.distance_to(n0), Color.WHITE
		)
	st.index()
	return st.commit()

func _build_roof_ribs_mesh(poly: PackedVector2Array, h: float, btype: String) -> ArrayMesh:
	var c2 := _poly_centroid(poly)
	var rib_col := Color("#EBEEF2") if btype == "workshop" else Color("#5B6770")
	var span := 10.5 if btype == "workshop" else 5.5
	var rh := 0.35 if btype == "workshop" else 0.16
	var rot_b := Basis(Vector3.UP, deg_to_rad(8.7))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	for k in range(-3, 4):
		var rc := Vector2(c2.x, c2.y + k * 4.2)
		if not (Geometry2D.is_point_in_polygon(rc + Vector2(-span, 0), poly) and Geometry2D.is_point_in_polygon(rc + Vector2(span, 0), poly)):
			continue
		var center := Vector3(rc.x, h + 0.25 + rh * 0.5, rc.y)
		var hx := span
		var hy := rh * 0.5
		var hz := 0.775
		var c0 := center + rot_b * Vector3(-hx, -hy, -hz)
		var c1 := center + rot_b * Vector3(hx, -hy, -hz)
		var c2p := center + rot_b * Vector3(hx, -hy, hz)
		var c3 := center + rot_b * Vector3(-hx, -hy, hz)
		var c4 := center + rot_b * Vector3(-hx, hy, -hz)
		var c5 := center + rot_b * Vector3(hx, hy, -hz)
		var c6 := center + rot_b * Vector3(hx, hy, hz)
		var c7 := center + rot_b * Vector3(-hx, hy, hz)
		_push_oriented_quad(st, c4, c5, c6, c7, Vector3.UP, hx * 2.0, hz * 2.0, rib_col)
		_push_oriented_quad(st, c0, c1, c5, c4, rot_b * Vector3.FORWARD, hx * 2.0, rh, rib_col.darkened(0.05))
		_push_oriented_quad(st, c2p, c3, c7, c6, rot_b * Vector3.BACK, hx * 2.0, rh, rib_col.darkened(0.05))
		_push_oriented_quad(st, c3, c0, c4, c7, rot_b * Vector3.LEFT, hz * 2.0, rh, rib_col.darkened(0.08))
		_push_oriented_quad(st, c1, c2p, c6, c5, rot_b * Vector3.RIGHT, hz * 2.0, rh, rib_col.darkened(0.08))
		count += 1
	if count == 0:
		return null
	st.index()
	st.generate_tangents()
	return st.commit()

func _add_building_sign(parent: Node3D, poly: PackedVector2Array, h: float, text: String, trim_col: Color, b: Dictionary = {}) -> void:
	var c := _poly_centroid(poly)
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 32
	lbl.pixel_size = 0.0136
	lbl.modulate = Color.WHITE
	lbl.outline_modulate = trim_col.darkened(0.55)
	lbl.outline_size = 6
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = false
	lbl.visibility_range_end = 110.0
	lbl.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	lbl.position = Vector3(c.x, h + 1.15, c.y)
	parent.add_child(lbl)

	var bid := String(b.get("id", ""))
	match bid:
		"biblioteca":
			_mount_facade_plaque(parent, poly, h, b, "BIBLIOTECA • IFSul", Color("#2F9E41"), Vector2(0.0, -1.0), 4.2)
		"bloco_800":
			_mount_facade_plaque(parent, poly, h, b, "BLOCO 800 • SALAS 801–812", Color("#2F9E41"), Vector2(-1.0, 0.0), 4.6)
		"auditorio":
			_mount_facade_plaque(parent, poly, h, b, "AUDITÓRIO 504 • PEDRO KAIZER", Color("#1F5A32"), Vector2(-0.85, -0.52).normalized(), 5.0)
		"sede_social":
			_mount_facade_plaque(parent, poly, h, b, "SEDE SOCIAL • IFSul", Color("#2F9E41"), Vector2(-0.7, -0.7).normalized(), 3.8)
		"vestiarios_esporte":
			_mount_facade_plaque(parent, poly, h, b, "EDUCAÇÃO FÍSICA", Color("#2F9E41"), Vector2(0.0, 1.0), 3.6)

func _mount_facade_plaque(parent: Node3D, poly: PackedVector2Array, h: float, b: Dictionary, plaque_text: String, bg_col: Color, prefer_dir: Vector2, plaque_w: float) -> void:
	var cw := _ensure_cw_screen(poly)
	var n := cw.size()
	if n < 3:
		return
	var pref := prefer_dir.normalized()
	var best_pos := Vector2.ZERO
	var best_out := pref
	var best_score := -1e9
	var found := false

	# Prefer mounting cleanly above an actual entrance facing prefer_dir
	var entrances: Array = b.get("entrances", [])
	for ent in entrances:
		if not (ent is Dictionary):
			continue
		var pa: Array = ent.get("pos", [])
		if pa.size() < 2:
			continue
		var ep := Vector2(float(pa[0]), float(pa[1]))
		var near_d := 2.6
		var near_out := Vector2.ZERO
		var near_proj := ep
		for i in range(n):
			var p1 := cw[i]
			var p2 := cw[(i + 1) % n]
			var edge := p2 - p1
			var lsq := edge.length_squared()
			if lsq < 1.0:
				continue
			var t := clampf((ep - p1).dot(edge) / lsq, 0.0, 1.0)
			var proj := p1 + edge * t
			var d := ep.distance_to(proj)
			if d < near_d:
				near_d = d
				near_proj = proj
				near_out = Vector2(edge.y, -edge.x).normalized()
		if near_d <= 2.5:
			var sc := near_out.dot(pref)
			if sc > best_score:
				best_score = sc
				best_pos = near_proj
				best_out = near_out
				found = true

	if not found:
		for i in range(n):
			var p1 := cw[i]
			var p2 := cw[(i + 1) % n]
			var edge := p2 - p1
			var elen := edge.length()
			if elen < 3.6:
				continue
			var out_d := Vector2(edge.y, -edge.x).normalized()
			var sc := out_d.dot(pref) + minf(elen, 12.0) * 0.02
			if sc > best_score:
				best_score = sc
				best_pos = (p1 + p2) * 0.5
				best_out = out_d
				found = true

	if not found:
		return

	var plaque_y := clampf(h - 0.95, 3.05, 3.65)
	# Keep Auditório plaque clear of the West relief logo if mounted near (-23.5, 24.0)
	if String(b.get("id", "")) == "auditorio" and best_pos.distance_to(Vector2(-23.5, 24.0)) < 4.5:
		plaque_y = minf(h - 0.55, 5.75)

	var plaque := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(plaque_w, 0.78, 0.14)
	plaque.mesh = pm
	plaque.material_override = mats.get_material("wall", bg_col)
	plaque.position = Vector3(best_pos.x + best_out.x * 0.17, plaque_y, best_pos.y + best_out.y * 0.17)
	plaque.rotation.y = atan2(best_out.x, best_out.y)
	plaque.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(plaque)

	var flbl := Label3D.new()
	flbl.text = plaque_text
	flbl.font_size = 32
	flbl.pixel_size = 0.0096
	flbl.outline_size = 0
	flbl.double_sided = false
	flbl.modulate = Color.WHITE
	flbl.visibility_range_end = 95.0
	flbl.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	flbl.position = Vector3(0.0, 0.0, 0.09)
	plaque.add_child(flbl)

func _build_courts(root: Node3D, courts: Array) -> void:
	var c_root := Node3D.new()
	c_root.name = "SportsCourts"
	root.add_child(c_root)
	var line_col := Color("#F5F5F0")
	var roof_col := Color("#DCE1E6")
	var truss_col := Color("#1D63B8")
	var curb_col := Color("#EAE8E2")
	var fence_mat := mats.get_material("fence")
	var goal_col := Color("#F0F2F5")
	var hoop_col := Color("#CD191E")
	var post_col := Color("#E2E8F0")

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

		var sport := String(c.get("sport", ""))
		var is_covered := bool(c.get("covered", false))
		var def_border := "#B8B4AC" if (sport == "outdoor_multi" or (sport == "multi" and not is_covered)) else "#B85D43"
		var def_surf := "#4F6D8A" if sport == "outdoor_multi" else "#255B8A"

		# Outer border + inner playing court (batched, no shadow casting for flat ground slabs)
		_add_colored_box(node, Vector3(0.0, 0.02, 0.0), Vector3(w, 0.04, d), Vector3.ZERO, "batch_wall", Color(c.get("border_color", def_border)))
		_add_colored_box(node, Vector3(0.0, 0.028, 0.0), Vector3(w * 0.84, 0.05, d * 0.86), Vector3.ZERO, "batch_wall", Color(c.get("surface_color", def_surf)))

		# Court painted markings
		var pw := w * 0.80
		var pd := d * 0.82
		_add_colored_box(node, Vector3(0, 0.058, pd * 0.5), Vector3(pw, 0.01, 0.14), Vector3.ZERO, "batch_line", line_col)
		_add_colored_box(node, Vector3(0, 0.058, -pd * 0.5), Vector3(pw, 0.01, 0.14), Vector3.ZERO, "batch_line", line_col)
		_add_colored_box(node, Vector3(pw * 0.5, 0.058, 0), Vector3(0.14, 0.01, pd), Vector3.ZERO, "batch_line", line_col)
		_add_colored_box(node, Vector3(-pw * 0.5, 0.058, 0), Vector3(0.14, 0.01, pd), Vector3.ZERO, "batch_line", line_col)
		if sport in ["multi", "outdoor_multi", "basketball", "futsal"]:
			var mark_parent: Node3D = node
			var mpw := pw
			var mpd := pd
			if w > d:
				var rot_m := Node3D.new()
				rot_m.rotation.y = PI * 0.5
				node.add_child(rot_m)
				mark_parent = rot_m
				mpw = pd
				mpd = pw
			_add_colored_box(mark_parent, Vector3(0, 0.058, 0), Vector3(mpw, 0.01, 0.14), Vector3.ZERO, "batch_line", line_col)
			var cr := clampf(minf(mpw, mpd) * 0.16, 1.3, 3.0)
			var ring := MeshInstance3D.new()
			ring.mesh = _make_torus_mesh(cr - 0.15, cr, 28, 4)
			ring.position = Vector3(0, 0.055, 0)
			ring.scale = Vector3(1.0, 0.15, 1.0)
			ring.material_override = mats.get_material("line_white")
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mark_parent.add_child(ring)
			var box_w := mpw * 0.46
			var box_d := clampf(mpd * 0.16, 2.0, 5.2)
			var goal_hw := clampf(mpw * 0.13, 1.0, 1.5)
			for end_s: float in [-1.0, 1.0]:
				var gz: float = end_s * (mpd * 0.48)
				var bz: float = end_s * (mpd * 0.5 - box_d)
				_add_colored_box(mark_parent, Vector3(0.0, 0.058, bz), Vector3(box_w, 0.01, 0.12), Vector3.ZERO, "batch_line", line_col)
				_add_colored_box(mark_parent, Vector3(-box_w * 0.5, 0.058, end_s * (mpd * 0.5 - box_d * 0.5)), Vector3(0.12, 0.01, box_d), Vector3.ZERO, "batch_line", line_col)
				_add_colored_box(mark_parent, Vector3(box_w * 0.5, 0.058, end_s * (mpd * 0.5 - box_d * 0.5)), Vector3(0.12, 0.01, box_d), Vector3.ZERO, "batch_line", line_col)
				_add_colored_box(mark_parent, Vector3(-goal_hw, 1.05, gz), Vector3(0.10, 2.1, 0.10), Vector3.ZERO, "batch_metal", goal_col)
				_add_colored_box(mark_parent, Vector3(goal_hw, 1.05, gz), Vector3(0.10, 2.1, 0.10), Vector3.ZERO, "batch_metal", goal_col)
				_add_colored_box(mark_parent, Vector3(0.0, 2.1, gz), Vector3(goal_hw * 2.0 + 0.1, 0.10, 0.10), Vector3.ZERO, "batch_metal", goal_col)
				_add_colored_box(mark_parent, Vector3(0.0, 3.05, gz - end_s * 0.6), Vector3(1.8, 1.1, 0.08), Vector3.ZERO, "batch_line", line_col)
				_add_colored_box(mark_parent, Vector3(0.0, 2.75, gz - end_s * 0.85), Vector3(0.45, 0.06, 0.45), Vector3.ZERO, "batch_line", hoop_col)
			if not is_covered:
				# Low clean curb border around outdoor multi-sport court with open entry gaps
				_add_colored_box(node, Vector3(0.0, 0.11, -d * 0.49), Vector3(w * 0.96, 0.18, 0.22), Vector3.ZERO, "batch_wall", curb_col)
				_add_colored_box(node, Vector3(0.0, 0.11, d * 0.49), Vector3(w * 0.96, 0.18, 0.22), Vector3.ZERO, "batch_wall", curb_col)
				_add_colored_box(node, Vector3(-w * 0.49, 0.11, 0.0), Vector3(0.22, 0.18, d * 0.96), Vector3.ZERO, "batch_wall", curb_col)
				_add_colored_box(node, Vector3(w * 0.49, 0.11, -d * 0.30), Vector3(0.22, 0.18, d * 0.36), Vector3.ZERO, "batch_wall", curb_col)
				_add_colored_box(node, Vector3(w * 0.49, 0.11, d * 0.30), Vector3(0.22, 0.18, d * 0.36), Vector3.ZERO, "batch_wall", curb_col)
		elif sport == "volleyball":
			_add_colored_box(node, Vector3(0, 1.25, -pd * 0.52), Vector3(0.12, 2.5, 0.12), Vector3.ZERO, "batch_metal", post_col)
			_add_colored_box(node, Vector3(0, 1.25, pd * 0.52), Vector3(0.12, 2.5, 0.12), Vector3.ZERO, "batch_metal", post_col)
			_add_static_box(node, Vector3(0, 2.0, 0), Vector3(0.04, 0.95, pd * 1.02), Vector3.ZERO, fence_mat)
			for f_side in [-1.0, 1.0]:
				_add_static_box(node, Vector3(0.0, 1.6, f_side * (d * 0.52)), Vector3(w, 3.2, 0.04), Vector3.ZERO, fence_mat)
			_add_static_box(node, Vector3(-w * 0.52, 1.6, 0.0), Vector3(0.04, 3.2, d), Vector3.ZERO, fence_mat)

		if bool(c.get("covered", false)):
			var roof_h := 8.0
			var pillar_body := StaticBody3D.new()
			pillar_body.name = "GymPillarsCollider"
			node.add_child(pillar_body)
			for sx: float in [-w * 0.48, w * 0.48]:
				for i in range(6):
					var pz := lerpf(-d * 0.46, d * 0.46, float(i) / 5.0)
					var pc := CollisionShape3D.new()
					var pbox := BoxShape3D.new()
					pbox.size = Vector3(0.42, roof_h, 0.42)
					pc.shape = pbox
					pc.position = Vector3(sx, roof_h * 0.5, pz)
					pillar_body.add_child(pc)
					for sub_z in [-0.18, 0.18]:
						_add_colored_box(node, Vector3(sx, roof_h * 0.5, pz + sub_z), Vector3(0.32, roof_h, 0.14), Vector3.ZERO, "batch_metal_painted", truss_col, true)
				_add_colored_box(node, Vector3(sx, roof_h - 0.3, 0.0), Vector3(0.28, 0.65, d * 0.96), Vector3.ZERO, "batch_metal_painted", truss_col)
				_add_colored_box(node, Vector3(sx, 0.3, 0.0), Vector3(0.26, 0.6, d * 0.96), Vector3.ZERO, "batch_wall", curb_col)
				if sx < 0.0:
					_add_static_box(node, Vector3(sx, 2.4, 0.0), Vector3(0.04, 3.6, d * 0.96), Vector3.ZERO, fence_mat)
				else:
					_add_static_box(node, Vector3(sx, 2.4, -d * 0.25), Vector3(0.04, 3.6, d * 0.44), Vector3.ZERO, fence_mat)
					_add_static_box(node, Vector3(sx, 2.4, d * 0.30), Vector3(0.04, 3.6, d * 0.36), Vector3.ZERO, fence_mat)

			for i in range(6):
				var pz := lerpf(-d * 0.46, d * 0.46, float(i) / 5.0)
				_add_colored_box(node, Vector3(0.0, roof_h - 0.18, pz), Vector3(w * 0.94, 0.48, 0.18), Vector3.ZERO, "batch_metal_painted", truss_col)
			for side: float in [-1.0, 1.0]:
				_add_colored_box(node, Vector3(side * w * 0.25, roof_h + 1.05, 0.0), Vector3(w * 0.54, 0.22, d + 1.5), Vector3(0.0, 0.0, -side * deg_to_rad(11.0)), "batch_metal_painted", roof_col, true)
			_add_colored_box(node, Vector3(0.0, 0.3, d * 0.49), Vector3(w * 0.96, 0.6, 0.26), Vector3.ZERO, "batch_wall", curb_col)
			_add_static_box(node, Vector3(0.0, 2.4, d * 0.49), Vector3(w * 0.96, 3.6, 0.04), Vector3.ZERO, fence_mat)
			_add_colored_box(node, Vector3(-w * 0.54, 2.0, -d * 0.45), Vector3(3.4, 3.8, 0.45), Vector3.ZERO, "batch_wall", curb_col, true)

func _build_parking_lots(root: Node3D, lots: Array) -> void:
	var p_root := Node3D.new()
	p_root.name = "ParkingLots"
	root.add_child(p_root)
	var asp := mats.get_planar_ground_material("asphalt", Color("#393C41"))
	var paver_asp := mats.get_planar_ground_material("concrete", Color("#8F8B85"))
	var white_col := Color("#F5F5F0")
	var yellow_col := Color("#EAB308")

	for lot in lots:
		var is_front := (String(lot.get("id", "")) == "estacionamento_principal")
		var poly := _to_vec2_array(lot.get("polygon", []))
		if poly.size() >= 3:
			var mi := MeshInstance3D.new()
			mi.mesh = _extrude_polygon_mesh(poly, 0.03, false)
			mi.material_override = paver_asp if is_front else asp
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			p_root.add_child(mi)

		for row in lot.get("bay_rows", []):
			var start := Vector2(float(row["start"][0]), float(row["start"][1]))
			var count := int(row.get("count", 6))
			var step := float(row.get("step", 2.6))
			var ang := deg_to_rad(float(row.get("angle_deg", 8.7)))
			var dir := Vector2(cos(ang), -sin(ang))
			var bay_fwd := Vector2(sin(ang), cos(ang))
			var lcol := yellow_col if is_front else white_col
			for i in range(count + 1):
				var p := start + dir * (i * step) + bay_fwd * 2.5
				_add_colored_box(p_root, Vector3(p.x, 0.036, p.y), Vector3(0.12, 0.01, 5.0), Vector3(0.0, ang, 0.0), "batch_line", lcol, false, 1)

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
		mi.mesh = _make_cylinder_mesh(r, r, h, 28)
		mi.material_override = mats.get_material("wall", Color("#F0EEE9"))
		body.add_child(mi)
		root.add_child(body)

		# Metallic maintenance cage ladder + red/white mast batched (parent already attached)
		_add_colored_box(body, Vector3(r + 0.28, 0.0, 0.0), Vector3(0.55, h * 0.92, 0.55), Vector3.ZERO, "batch_metal", Color("#CBD5E1"))
		for seg in range(4):
			var seg_col := Color("#CD191E") if seg % 2 == 0 else Color("#F5F5F0")
			_add_colored_cylinder(body, Vector3(0.0, h * 0.5 + 0.9 + seg * 1.8, 0.0), Vector3(0.16, 1.8, 0.16), Vector3.ZERO, "batch_line", seg_col)

	# White colonnade walkway + "Profissionais para o mundo." fascia & Auditório 3D IFSul Relief Logo + Portico
	var col_node := Node3D.new()
	col_node.name = "ColonnadeAndAuditorioPortico"
	root.add_child(col_node)
	var white_col := Color("#F3F2EE")
	var c_start := Vector3(-31.5, 0.0, -7.2)
	var c_end := Vector3(-8.5, 0.0, 5.2)
	var c_vec := c_end - c_start
	var c_len := c_vec.length()
	var c_ang := atan2(c_vec.x, c_vec.z)
	_add_colored_box(col_node, (c_start + c_end) * 0.5 + Vector3(0.0, 3.65, 0.0), Vector3(2.4, 0.72, c_len), Vector3(0.0, c_ang, 0.0), "batch_wall", white_col, true)
	for ci in range(7):
		var cp := c_start.lerp(c_end, float(ci) / 6.0)
		_add_colored_box(col_node, cp + Vector3(0.0, 1.7, 0.0), Vector3(0.35, 3.4, 0.35), Vector3.ZERO, "batch_wall", white_col, true)
	var motto := Label3D.new()
	motto.text = "Educação Pública e Gratuita: Profissionais para o mundo."
	motto.font_size = 32
	motto.pixel_size = 0.009
	motto.outline_size = 0
	motto.double_sided = false
	motto.visibility_range_end = 95.0
	motto.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	motto.modulate = Color("#1F3524")
	motto.position = (c_start + c_end) * 0.5 + Vector3(-1.25, 3.65, 0.65)
	motto.rotation.y = c_ang - PI * 0.5
	col_node.add_child(motto)

	# Auditório Pedro Kaizer West-facing Front Portico + Giant 3D Relief IFSul Logo + Mural
	var aud_front := Node3D.new()
	aud_front.name = "AuditorioFrontPortico"
	aud_front.position = Vector3(-22.8, 0.0, 21.8)
	aud_front.rotation.y = deg_to_rad(-8.5)
	col_node.add_child(aud_front)

	_add_colored_box(aud_front, Vector3(-3.2, 6.25, 1.5), Vector3(6.8, 0.55, 13.5), Vector3.ZERO, "batch_wall", white_col, true)
	for pz in [-4.5, 7.6]:
		_add_colored_box(aud_front, Vector3(-6.1, 3.05, pz), Vector3(0.55, 6.1, 0.55), Vector3.ZERO, "batch_wall", white_col, true)

	var relief_cells := [[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [0, 2], [1, 2], [2, 2], [0, 3], [1, 3]]
	for rc in relief_cells:
		var rpos := Vector3(-0.75, 5.1 - float(rc[1]) * 0.62, 1.5 + float(rc[0]) * 0.62)
		if rc[0] == 0 and rc[1] == 0:
			_add_colored_cylinder(aud_front, rpos, Vector3(0.56, 0.16, 0.56), Vector3(0.0, 0.0, PI * 0.5), "batch_line", Color("#CD191E"))
		else:
			_add_colored_box(aud_front, rpos, Vector3(0.16, 0.52, 0.52), Vector3.ZERO, "batch_line", Color("#2F9E41"))

	var aud_logo_txt := Label3D.new()
	aud_logo_txt.text = "INSTITUTO FEDERAL\nSUL-RIO-GRANDENSE\nCâmpus Sapucaia do Sul"
	aud_logo_txt.font_size = 32
	aud_logo_txt.pixel_size = 0.0101
	aud_logo_txt.outline_size = 0
	aud_logo_txt.double_sided = false
	aud_logo_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	aud_logo_txt.visibility_range_end = 100.0
	aud_logo_txt.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	aud_logo_txt.modulate = Color("#1D2E20")
	aud_logo_txt.position = Vector3(-0.78, 3.85, 3.4)
	aud_logo_txt.rotation.y = -PI * 0.5
	aud_front.add_child(aud_logo_txt)

	# Student colorful mural on north-facing terrace wall of Auditório
	var mural_bg := Node3D.new()
	mural_bg.position = Vector3(5.8, 2.3, -8.2)
	mural_bg.rotation.y = deg_to_rad(-16.0)
	aud_front.add_child(mural_bg)
	_add_colored_box(mural_bg, Vector3.ZERO, Vector3(4.6, 2.2, 0.14), Vector3.ZERO, "batch_wall", Color("#F4F0E8"))
	var mural_cols := [Color("#E11D48"), Color("#F59E0B"), Color("#2563EB"), Color("#16A34A"), Color("#9333EA")]
	for mi_c in range(5):
		_add_colored_box(mural_bg, Vector3(-1.6 + mi_c * 0.8, 0.0, 0.08), Vector3(0.75, 1.7, 0.04), Vector3.ZERO, "batch_line", mural_cols[mi_c])

	# Flagpoles + raised planter
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
		f_root.add_child(planter)
		_add_colored_box(f_root, Vector3(0.0, 0.225, 0.0), Vector3(7.0, 0.45, 2.6), Vector3.ZERO, "batch_concrete", Color("#CBC6BC"))

		var frng := RandomNumberGenerator.new()
		frng.seed = 2155
		for fx in range(12):
			var fcol := Color("#DB4B7A") if fx % 2 == 0 else Color("#4C8E3B")
			_add_colored_sphere(f_root, Vector3(-2.9 + fx * 0.52, 0.55, frng.randf_range(-0.7, 0.7)), Vector3(0.48, 0.36, 0.48), "batch_foliage", fcol, false, 1)

		var flag_colors := [Color("#009B3A"), Color("#D92525"), Color("#2F9E41"), Color("#1E55A0")]
		var pole_col := Color("#D8DCE0")
		for i in range(4):
			_add_colored_cylinder(f_root, Vector3(-2.4 + i * 1.6, 3.8, 0.0), Vector3(0.12, 7.5, 0.12), Vector3.ZERO, "batch_metal", pole_col)
			_add_colored_box(f_root, Vector3(-2.4 + i * 1.6 + 0.6, 7.0, 0.0), Vector3(1.15, 0.72, 0.04), Vector3.ZERO, "batch_line", flag_colors[i])

	# Horta Comunitária (NE corner next to Bloco 800)
	var horta: Dictionary = lm.get("horta", {})
	if not horta.is_empty():
		_build_horta(root, horta)

func _get_horta_frame(horta: Dictionary) -> Dictionary:
	var rot_deg := float(horta.get("rot_deg", 8.7))
	var rot_rad := deg_to_rad(rot_deg)
	var center2 := Vector2.ZERO
	var w := 14.0
	var d := 10.0
	if horta.has("center") and horta.has("size"):
		var ca: Array = horta["center"]
		var sa: Array = horta["size"]
		center2 = Vector2(float(ca[0]), float(ca[1]))
		w = float(sa[0])
		d = float(sa[1])
	elif horta.has("position") and horta.has("size"):
		var pa: Array = horta["position"]
		var sa: Array = horta["size"]
		center2 = Vector2(float(pa[0]), float(pa[2]) if pa.size() >= 3 else float(pa[1]))
		w = float(sa[0])
		d = float(sa[1])
	elif horta.has("polygon"):
		var hpoly := _to_vec2_array(horta["polygon"])
		if hpoly.size() >= 3:
			center2 = _poly_centroid(hpoly)
			var cs := cos(-rot_rad)
			var sn := sin(-rot_rad)
			var min_x := 1e9; var max_x := -1e9
			var min_z := 1e9; var max_z := -1e9
			for v in hpoly:
				var rel := v - center2
				var lx := rel.x * cs - rel.y * sn
				var lz := rel.x * sn + rel.y * cs
				min_x = minf(min_x, lx); max_x = maxf(max_x, lx)
				min_z = minf(min_z, lz); max_z = maxf(max_z, lz)
			w = max_x - min_x
			d = max_z - min_z
	return {"center": center2, "w": maxf(w, 6.0), "d": maxf(d, 5.0), "rot": rot_rad}

func _build_horta(root: Node3D, horta: Dictionary) -> void:
	var hf := _get_horta_frame(horta)
	var center2: Vector2 = hf["center"]
	var w: float = float(hf["w"])
	var d: float = float(hf["d"])
	var rot_rad: float = float(hf["rot"])

	var h_node := Node3D.new()
	h_node.name = "HortaComunitaria"
	h_node.position = Vector3(center2.x, 0.0, center2.y)
	h_node.rotation.y = rot_rad
	root.add_child(h_node)

	var wood_col := Color("#6E4E33")
	var plank_col := Color("#805B3A")
	var mulch_col := Color("#8B7A62")
	var soil_col := Color("#4B3423")
	var leaf_cols := [Color("#3E8B36"), Color("#56A641"), Color("#6EBA4C"), Color("#2F7630")]

	# Earth/mulch base pad
	_add_colored_box(h_node, Vector3(0.0, 0.025, 0.0), Vector3(w, 0.05, d), Vector3.ZERO, "batch_wall", mulch_col)

	# Low wooden perimeter border (with open 2.8m entrance on the south side facing Bloco 800 footway)
	_add_colored_box(h_node, Vector3(0.0, 0.22, -d * 0.5), Vector3(w, 0.40, 0.16), Vector3.ZERO, "batch_wood", wood_col)
	_add_colored_box(h_node, Vector3(-w * 0.5, 0.22, 0.0), Vector3(0.16, 0.40, d), Vector3.ZERO, "batch_wood", wood_col)
	_add_colored_box(h_node, Vector3(w * 0.5, 0.22, 0.0), Vector3(0.16, 0.40, d), Vector3.ZERO, "batch_wood", wood_col)
	var gap_half := minf(1.5, w * 0.20)
	var front_seg := maxf(0.5, w * 0.5 - gap_half)
	_add_colored_box(h_node, Vector3(-(gap_half + front_seg * 0.5), 0.22, d * 0.5), Vector3(front_seg, 0.40, 0.16), Vector3.ZERO, "batch_wood", wood_col)
	_add_colored_box(h_node, Vector3(gap_half + front_seg * 0.5, 0.22, d * 0.5), Vector3(front_seg, 0.40, 0.16), Vector3.ZERO, "batch_wood", wood_col)

	# Raised soil beds + batched plant rows
	var inner_w := w - 2.4
	var inner_d := d - 2.4
	var cols := 2 if inner_w >= 11.0 else 1
	var req_rows := int(horta.get("rows", 0))
	var rows := clampi(req_rows if req_rows > 0 else int(inner_d / 2.6), 2, 8)
	var bed_w := (inner_w - float(cols - 1) * 1.4) / float(cols)
	var bed_d := minf(1.45, (inner_d - float(rows - 1) * 0.95) / float(rows))
	var step_z := inner_d / float(rows)
	var step_x := inner_w / float(cols)

	var rng := RandomNumberGenerator.new()
	rng.seed = 8001
	for r in range(rows):
		var bz := -inner_d * 0.5 + (float(r) + 0.5) * step_z
		for c_i in range(cols):
			var bx := -inner_w * 0.5 + (float(c_i) + 0.5) * step_x
			_add_colored_box(h_node, Vector3(bx, 0.16, bz), Vector3(bed_w, 0.30, bed_d), Vector3.ZERO, "batch_wood", plank_col)
			_add_colored_box(h_node, Vector3(bx, 0.19, bz), Vector3(bed_w - 0.18, 0.28, bed_d - 0.18), Vector3.ZERO, "batch_wall", soil_col)
			var plant_n := maxi(3, int((bed_w - 0.4) / 0.82))
			for pi in range(plant_n):
				var px := bx - (bed_w - 0.55) * 0.5 + float(pi) * ((bed_w - 0.55) / maxf(1.0, float(plant_n - 1)))
				for pz_off in [-bed_d * 0.22, bed_d * 0.22]:
					var pcol: Color = leaf_cols[(r + pi + c_i) % leaf_cols.size()]
					var ps := rng.randf_range(0.34, 0.52)
					_add_colored_sphere(h_node, Vector3(px + rng.randf_range(-0.06, 0.06), 0.38 + ps * 0.25, bz + pz_off), Vector3(ps, ps * 0.78, ps), "batch_foliage", pcol, false, 1)

	# Small wooden garden sign at south entrance
	_add_colored_box(h_node, Vector3(-gap_half - 0.45, 0.65, d * 0.5 + 0.1), Vector3(0.10, 1.3, 0.10), Vector3.ZERO, "batch_wood", wood_col, false, 1)
	var hlbl := Label3D.new()
	hlbl.text = "HORTA • IFSul"
	hlbl.font_size = 28
	hlbl.pixel_size = 0.0085
	hlbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hlbl.visibility_range_end = 55.0
	hlbl.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	hlbl.modulate = Color("#F5F9F0")
	hlbl.outline_modulate = Color("#1F4A24")
	hlbl.outline_size = 5
	hlbl.position = Vector3(-gap_half - 0.45, 1.55, d * 0.5 + 0.1)
	h_node.add_child(hlbl)

func _build_entrance_signage(root: Node3D, data: Dictionary) -> void:
	var sign_node := Node3D.new()
	sign_node.name = "EntranceSignage"
	sign_node.position = Vector3(-64.2, 0.0, 2.2)
	sign_node.rotation.y = deg_to_rad(8.7)
	root.add_child(sign_node)

	var gate_root := Node3D.new()
	gate_root.position = Vector3(-63.2, 0.0, 17.5)
	gate_root.rotation.y = deg_to_rad(8.7)
	root.add_child(gate_root)
	var gate_col := Color("#D8DCE0")
	for gz in [-1.5, 7.2]:
		_add_colored_box(gate_root, Vector3(1.6, 0.95, gz), Vector3(3.2, 1.9, 0.08), Vector3.ZERO, "batch_metal", gate_col)
	var yellow_curb_col := Color("#E8B923")
	for c_spec in [[-8.0, 8.0], [8.8, 7.5]]:
		_add_colored_box(gate_root, Vector3(-2.2, 0.08, float(c_spec[0])), Vector3(0.24, 0.15, float(c_spec[1])), Vector3.ZERO, "batch_wall", yellow_curb_col)
	for oz in [-7.6, -6.5]:
		_add_colored_sphere(gate_root, Vector3(-1.2, 1.65, oz), Vector3(0.72, 0.80, 0.72), "batch_line", Color("#2F9E41"))
		_add_colored_cylinder(gate_root, Vector3(-1.2, 0.8, oz), Vector3(0.09, 1.6, 0.09), Vector3.ZERO, "batch_metal", gate_col)

	var cw_col := Color("#F5F5F0")
	for cwi in range(7):
		_add_colored_box(gate_root, Vector3(-2.0, 0.038, -2.7 + cwi * 0.9), Vector3(2.8, 0.012, 0.45), Vector3.ZERO, "batch_line", cw_col, false, 1)

	var bou_cw := Node3D.new()
	bou_cw.name = "CopacabanaCrosswalk"
	bou_cw.rotation.y = atan2(0.160, 1.0)
	var cw_z := 10.6
	bou_cw.position = Vector3(-80.25 + (cw_z - 13.0) * 0.160, 0.0, cw_z)
	root.add_child(bou_cw)
	for lane_x: float in [-6.15, 6.15]:
		for bi in range(7):
			var lx := lane_x - 2.85 + float(bi) * 0.95
			_add_colored_box(bou_cw, Vector3(lx, 0.038, 0.0), Vector3(0.44, 0.012, 2.5), Vector3.ZERO, "batch_line", cw_col, false, 1)

	# Bicycle rack behind Guarita
	var bike_rack := Node3D.new()
	bike_rack.position = Vector3(-54.8, 0.0, 12.6)
	bike_rack.rotation.y = deg_to_rad(8.7)
	root.add_child(bike_rack)
	var dark_met_col := Color("#1F2937")
	_add_colored_box(bike_rack, Vector3(0.0, 0.25, 0.0), Vector3(0.10, 0.5, 4.4), Vector3.ZERO, "batch_metal", dark_met_col, false, 1)
	for bi in range(5):
		var bz := -1.6 + bi * 0.8
		for wx in [-0.45, 0.45]:
			_add_colored_torus(bike_rack, Vector3(wx, 0.30, bz), Vector3(0.28, 0.28, 0.28), Vector3(PI * 0.5, 0.0, 0.0), "batch_metal", dark_met_col, 1)
		_add_colored_box(bike_rack, Vector3(0.0, 0.62, bz), Vector3(0.95, 0.06, 0.05), Vector3.ZERO, "batch_line", Color("#CD191E") if bi % 2 == 0 else Color("#2F9E41"), false, 1)

	# Hedged green lawn with 3D topiary "IFSul" (positioned cleanly in lawn south of covered walkway curb)
	var topiary := Node3D.new()
	topiary.name = "TopiaryIFSul"
	topiary.position = Vector3(-47.0, 0.0, -1.8)
	topiary.rotation.y = deg_to_rad(9.87)
	root.add_child(topiary)
	var lawn_col := Color("#4B8B3B")
	var hedge_col := Color("#7CB342")
	var top_col := Color("#A4C639")
	_add_colored_box(topiary, Vector3(0.0, 0.04, 0.0), Vector3(17.5, 0.06, 4.6), Vector3.ZERO, "batch_foliage", lawn_col)
	_add_colored_box(topiary, Vector3(0.0, 0.22, -2.2), Vector3(17.8, 0.38, 0.42), Vector3.ZERO, "batch_foliage", hedge_col)
	_add_colored_box(topiary, Vector3(0.0, 0.22, 2.2), Vector3(17.8, 0.38, 0.42), Vector3.ZERO, "batch_foliage", hedge_col)
	_add_colored_box(topiary, Vector3(-8.7, 0.22, 0.0), Vector3(0.42, 0.38, 4.4), Vector3.ZERO, "batch_foliage", hedge_col)
	_add_colored_box(topiary, Vector3(8.7, 0.22, 0.0), Vector3(0.42, 0.38, 4.4), Vector3.ZERO, "batch_foliage", hedge_col)
	var top_lbl := Label3D.new()
	top_lbl.text = "IFSul"
	top_lbl.font_size = 32
	top_lbl.pixel_size = 0.11
	top_lbl.double_sided = false
	top_lbl.visibility_range_end = 115.0
	top_lbl.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	top_lbl.modulate = Color("#C5E14B")
	top_lbl.outline_modulate = Color("#2F6B28")
	top_lbl.outline_size = 6
	top_lbl.position = Vector3(0.0, 0.16, 0.0)
	top_lbl.rotation.x = -PI * 0.5
	topiary.add_child(top_lbl)
	for hx in [-5.4, -2.7, 0.0, 2.7, 5.4]:
		_add_colored_box(topiary, Vector3(hx, 0.20, 0.0), Vector3(1.6, 0.28, 2.2), Vector3.ZERO, "batch_foliage", top_col)

	# Southern Pond with island, 4 white birdhouses & parking bollards
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
	pond_mi.mesh = _make_cylinder_mesh(6.5, 6.5, 0.05, 28)
	pond_mi.scale = Vector3(1.9, 1.0, 1.0)
	pond_mi.position.y = 0.03
	pond_mi.material_override = water_mat
	pond_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pond_node.add_child(pond_mi)
	var isl_mi := MeshInstance3D.new()
	isl_mi.mesh = _make_cylinder_mesh(2.8, 3.2, 0.28, 22)
	isl_mi.scale = Vector3(1.7, 1.0, 0.9)
	isl_mi.position = Vector3(1.5, 0.14, 0.0)
	isl_mi.material_override = mats.get_material("grass", lawn_col)
	isl_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pond_node.add_child(isl_mi)
	var bh_col := Color("#F3F2EE")
	var trunk_col := Color("#5A4230")
	for bh_i in range(4):
		var bx := -1.8 + bh_i * 1.4
		_add_colored_box(pond_node, Vector3(1.5 + bx, 0.52, 0.0), Vector3(0.08, 0.55, 0.08), Vector3.ZERO, "batch_wall", trunk_col, false, 1)
		_add_colored_box(pond_node, Vector3(1.5 + bx, 0.85, 0.0), Vector3(0.45, 0.42, 0.45), Vector3.ZERO, "batch_wall", bh_col, false, 1)
	# 4 stylized white ducks floating on SouthernPond
	var duck_specs := [
		[Vector3(-7.0, 0.13, -1.8), 0.55],
		[Vector3(-5.5, 0.13, 2.2), -0.85],
		[Vector3(7.9, 0.13, -2.0), 2.35],
		[Vector3(2.4, 0.13, 4.1), -2.45],
	]
	var duck_white := Color("#FAF9F5")
	var duck_beak := Color("#F59E0B")
	for ds in duck_specs:
		var dp: Vector3 = ds[0]
		var dyaw: float = float(ds[1])
		var dbasis := Basis(Vector3.UP, dyaw)
		var drot := Vector3(0.0, dyaw, 0.0)
		_add_colored_sphere(pond_node, dp, Vector3(0.38, 0.24, 0.54), "batch_wall", duck_white, false, 1, drot)
		_add_colored_sphere(pond_node, dp + dbasis * Vector3(0.0, 0.19, 0.22), Vector3(0.22, 0.22, 0.22), "batch_wall", duck_white, false, 1, drot)
		_add_colored_box(pond_node, dp + dbasis * Vector3(0.0, 0.17, 0.35), Vector3(0.09, 0.05, 0.14), drot, "batch_line", duck_beak, false, 1)
		_add_colored_box(pond_node, dp + dbasis * Vector3(0.0, 0.11, -0.26), Vector3(0.11, 0.08, 0.15), drot, "batch_wall", duck_white, false, 1)
	for bol_i in range(16):
		var bp := Vector3(-24.0 + bol_i * 2.8, 0.32, -11.5)
		_add_colored_box(pond_node, bp, Vector3(0.16, 0.64, 0.16), Vector3.ZERO, "batch_wall", bh_col, false, 1)

	# Water tower Agave & Purple Foliage Garden + North Admin Garden
	var agave_bed := Node3D.new()
	agave_bed.position = Vector3(-18.5, 0.0, -3.5)
	root.add_child(agave_bed)
	_add_colored_box(agave_bed, Vector3(0.0, 0.05, 0.0), Vector3(4.6, 0.06, 2.8), Vector3.ZERO, "batch_concrete", Color("#CFC3B4"))
	var purple_col := Color("#6B2D5C")
	var agave_col := Color("#4D8C7A")
	for ai in range(6):
		_add_colored_box(agave_bed, Vector3(-1.8 + ai * 0.72, 0.18, 0.9), Vector3(0.65, 0.24, 0.65), Vector3.ZERO, "batch_foliage", purple_col, false, 1)
		_add_colored_box(agave_bed, Vector3(-1.8 + ai * 0.72, 0.18, -0.9), Vector3(0.65, 0.24, 0.65), Vector3.ZERO, "batch_foliage", purple_col, false, 1)
	for ax in [-1.1, 0.2, 1.3]:
		var ag := MeshInstance3D.new()
		ag.mesh = _make_cylinder_mesh(0.55, 0.14, 0.75, 6)
		ag.position = Vector3(ax, 0.42, 0.0)
		ag.material_override = mats.get_material("foliage", agave_col)
		ag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ag.visibility_range_end = 110.0
		agave_bed.add_child(ag)

	var north_g := Node3D.new()
	north_g.position = Vector3(-31.0, 0.0, -50.5)
	north_g.rotation.y = deg_to_rad(8.7)
	root.add_child(north_g)
	_add_colored_box(north_g, Vector3(0.0, 0.18, 0.0), Vector3(10.0, 0.30, 0.45), Vector3.ZERO, "batch_foliage", hedge_col)
	_add_colored_box(north_g, Vector3(0.0, 0.18, 3.2), Vector3(10.0, 0.30, 0.45), Vector3.ZERO, "batch_foliage", hedge_col)
	_add_colored_box(north_g, Vector3(-5.0, 0.18, 1.6), Vector3(0.45, 0.30, 3.2), Vector3.ZERO, "batch_foliage", hedge_col)
	_add_colored_box(north_g, Vector3(5.0, 0.18, 1.6), Vector3(0.45, 0.30, 3.2), Vector3.ZERO, "batch_foliage", hedge_col)

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
	stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	totem_body.add_child(stripe)

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
		logo_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		totem_body.add_child(logo_mi)

		var title := Label3D.new()
		title.text = "IFSul — Câmpus Sapucaia do Sul\nINSTITUTO FEDERAL Sul-rio-grandense\nAv. Copacabana, 100"
		title.font_size = 32
		title.pixel_size = 0.0049
		title.outline_size = 0
		title.double_sided = false
		title.visibility_range_end = 75.0
		title.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		title.modulate = Color("#16381D")
		title.position = Vector3(side * 0.23, 1.8, -0.7 * side)
		title.rotation.y = -PI * 0.5 if side < 0 else PI * 0.5
		totem_body.add_child(title)

	sign_node.add_child(totem_body)
	_build_entrance_covered_walkway(root)

func _add_walkway_arrow(parent: Node3D, pos: Vector3, yaw: float, col: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var r := Vector3(0.0, yaw, 0.0)
	# Arrow shaft
	_add_colored_box(parent, pos + b * Vector3(0.0, 0.0, -0.10), Vector3(0.10, 0.008, 0.50), r, "batch_line", col)
	# Arrowhead chevron wings meeting at tip (+0.32 along local +Z)
	_add_colored_box(parent, pos + b * Vector3(-0.085, 0.0, 0.16), Vector3(0.085, 0.008, 0.32), Vector3(0.0, yaw - deg_to_rad(34.0), 0.0), "batch_line", col)
	_add_colored_box(parent, pos + b * Vector3(0.085, 0.0, 0.16), Vector3(0.085, 0.008, 0.32), Vector3(0.0, yaw + deg_to_rad(34.0), 0.0), "batch_line", col)

func _add_walkway_fluorescent_lamp(parent: Node3D, pos: Vector3, rot_v: Vector3, housing_col: Color, end_col: Color) -> void:
	_add_colored_box(parent, pos, Vector3(0.08, 0.09, 1.24), rot_v, "batch_wall", housing_col, false, 1)
	var b := Basis.from_euler(rot_v)
	for sgn in [-1.0, 1.0]:
		_add_colored_box(parent, pos + b * Vector3(0.0, -0.01, sgn * 0.59), Vector3(0.095, 0.10, 0.07), rot_v, "batch_metal", end_col, false, 1)
	for ty in [-0.024, 0.024]:
		_add_static_box(parent, pos + b * Vector3(-0.045, ty, 0.0), Vector3(0.032, 0.032, 1.10), rot_v, lamp_mat, false, 1)

func _add_selective_waste_bin(parent: Node3D, pos: Vector3, bin_col: Color, mouth_col: Color, badge_col: Color) -> void:
	# Horizontal curved-hood selective collector bin resting along the wall (matching photo)
	_add_colored_box(parent, pos + Vector3(-0.02, 0.14, 0.0), Vector3(0.62, 0.26, 0.42), Vector3.ZERO, "batch_wall", bin_col, false, 1)
	_add_colored_cylinder(parent, pos + Vector3(-0.02, 0.27, 0.0), Vector3(0.42, 0.62, 0.26), Vector3(0.0, 0.0, PI * 0.5), "batch_wall", bin_col, false, 1)
	# Front hooded rim & dark collection opening facing the walkway (-X)
	_add_colored_box(parent, pos + Vector3(-0.33, 0.20, 0.0), Vector3(0.05, 0.32, 0.44), Vector3(0.0, 0.0, deg_to_rad(10.0)), "batch_wall", bin_col.lightened(0.06), false, 1)
	_add_colored_box(parent, pos + Vector3(-0.34, 0.21, 0.0), Vector3(0.04, 0.22, 0.34), Vector3(0.0, 0.0, deg_to_rad(10.0)), "batch_wall", mouth_col, false, 1)
	# White recycling symbol badge on top hood
	_add_colored_box(parent, pos + Vector3(-0.10, 0.405, 0.0), Vector3(0.15, 0.008, 0.14), Vector3.ZERO, "batch_line", badge_col, false, 1)

func _add_walkway_white_planter(parent: Node3D, pos: Vector3, is_burgundy: bool, pot_col: Color, soil_col: Color) -> void:
	_add_colored_cylinder(parent, pos + Vector3(0.0, 0.20, 0.0), Vector3(0.46, 0.40, 0.46), Vector3.ZERO, "batch_wall", pot_col, false, 1)
	_add_colored_cylinder(parent, pos + Vector3(0.0, 0.38, 0.0), Vector3(0.50, 0.05, 0.50), Vector3.ZERO, "batch_wall", pot_col, false, 1)
	_add_colored_cylinder(parent, pos + Vector3(0.0, 0.39, 0.0), Vector3(0.42, 0.04, 0.42), Vector3.ZERO, "batch_wall", soil_col, false, 1)
	var leaf_cols: Array = [
		Color("#421D28"), Color("#632637"), Color("#7E3548"), Color("#3B7233"), Color("#528C42")
	] if is_burgundy else [
		Color("#2B662E"), Color("#3C7D39"), Color("#519446"), Color("#347032"), Color("#63A352")
	]
	for li in range(7):
		var ang := float(li) * (TAU / 7.0) + (0.25 if is_burgundy else 0.0)
		var tilt := deg_to_rad(28.0 + float(li % 3) * 10.0)
		var lcol: Color = leaf_cols[li % leaf_cols.size()]
		var lpos := pos + Vector3(cos(ang) * 0.14, 0.52 + float(li % 2) * 0.08, sin(ang) * 0.14)
		var lrot := Vector3(sin(ang) * tilt, ang, -cos(ang) * tilt)
		_add_colored_box(parent, lpos, Vector3(0.32, 0.04, 0.13), lrot, "batch_foliage", lcol, false, 1)
	_add_colored_sphere(parent, pos + Vector3(0.0, 0.56, 0.0), Vector3(0.42, 0.38, 0.42), "batch_foliage", leaf_cols[1], false, 1)

func _build_corrugated_canopy_mesh(length: float, width: float, x_center: float, z_start: float, base_y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wave_step := 0.24
	var steps := maxi(8, int(ceil(length / wave_step)))
	var dz := length / float(steps)
	var x0 := x_center - width * 0.5
	var x1 := x_center + width * 0.5
	var col_peak := Color(0.95, 0.92, 0.70, 0.88)
	var col_valley := Color(0.85, 0.81, 0.55, 0.92)
	for i in range(steps):
		var za := z_start + float(i) * dz
		var zb := za + dz
		var ya := base_y + (0.024 if (i % 2 == 0) else -0.024)
		var yb := base_y + (0.024 if ((i + 1) % 2 == 0) else -0.024)
		var ca := col_peak if (i % 2 == 0) else col_valley
		var cb := col_peak if ((i + 1) % 2 == 0) else col_valley
		var v0 := Vector3(x0, ya, za)
		var v1 := Vector3(x1, ya, za)
		var v2 := Vector3(x1, yb, zb)
		var v3 := Vector3(x0, yb, zb)
		var n := (v1 - v0).cross(v3 - v0).normalized()
		if n.y < 0.0:
			n = -n
		st.set_normal(n)
		st.set_color(ca); st.set_uv(Vector2(0.0, float(i) * 0.25)); st.add_vertex(v0)
		st.set_color(ca); st.set_uv(Vector2(1.0, float(i) * 0.25)); st.add_vertex(v1)
		st.set_color(cb); st.set_uv(Vector2(1.0, float(i + 1) * 0.25)); st.add_vertex(v2)
		st.set_color(ca); st.set_uv(Vector2(0.0, float(i) * 0.25)); st.add_vertex(v0)
		st.set_color(cb); st.set_uv(Vector2(1.0, float(i + 1) * 0.25)); st.add_vertex(v2)
		st.set_color(cb); st.set_uv(Vector2(0.0, float(i + 1) * 0.25)); st.add_vertex(v3)
		# Side eave fascia strips so the corrugated milky-yellow roof profile is visible from ground eye-level too
		var drop_a := ya - 0.065
		var drop_b := yb - 0.065
		for side_x in [x0, x1]:
			var sv0 := Vector3(side_x, drop_a, za)
			var sv1 := Vector3(side_x, drop_b, zb)
			var sv2 := Vector3(side_x, yb, zb)
			var sv3 := Vector3(side_x, ya, za)
			st.set_normal(Vector3(-1.0 if side_x == x0 else 1.0, 0.0, 0.0))
			st.set_color(col_peak); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(sv0)
			st.set_color(col_peak); st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(sv1)
			st.set_color(col_valley); st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(sv2)
			st.set_color(col_peak); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(sv0)
			st.set_color(col_valley); st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(sv2)
			st.set_color(col_valley); st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(sv3)
	st.index()
	return st.commit()

func _build_entrance_covered_walkway(root: Node3D) -> void:
	var ww_root := Node3D.new()
	ww_root.name = "EntranceCoveredWalkway"
	root.add_child(ww_root)

	var floor_col := Color("#4E5258")
	var groove_col := Color("#3E4248")
	var joint_col := Color("#2D3035")
	var curb_col_a := Color("#8C8A84")
	var curb_col_b := Color("#7E7C76")
	var arrow_col := Color("#EAB308")
	var divider_col := Color("#C29B22")
	var green_frame_col := Color("#2E6E36")
	var wall_siding_col := Color("#ECE6D2")
	var wall_rib_col := Color("#DDD6C0")
	var fire_pipe_col := Color("#C82222")
	var fire_dark_col := Color("#991818")
	var lamp_body_col := Color("#F4F4F0")
	var lamp_cap_col := Color("#9CA3AF")
	var pot_white := Color("#F0EFEA")
	var soil_dark := Color("#3B2D22")

	# --- 1. Main East-West Covered Walkway along Setor 100 (bloco_adm) South Facade ---
	var w_sw := Vector2(-60.9, -6.6)
	var w_se := Vector2(-31.6, -11.7)
	var ew_vec := w_se - w_sw
	var ew_dir := ew_vec.normalized()
	var ew_rot_y := atan2(ew_dir.x, ew_dir.y)

	var leg_ew := Node3D.new()
	leg_ew.name = "WalkwayLegEastWest"
	leg_ew.position = Vector3(w_sw.x, 0.0, w_sw.y)
	leg_ew.rotation.y = ew_rot_y
	ww_root.add_child(leg_ew)

	# In leg_ew local space: +Z runs East along bloco_adm south wall (0..29.74m), -X runs South toward garden (0..-2.80m)
	var s_start := -1.05
	var s_end := 30.15
	var ew_len := s_end - s_start
	var ew_mid := (s_start + s_end) * 0.5
	var s_door := 14.87 # bloco_adm south entrance at [-46.25, -9.15]

	# Cream-beige vertical ribbed wall cladding under the canopy (leaving the central doorway completely clear)
	for span in [[0.12, s_door - 1.52], [s_door + 1.52, 29.62]]:
		var sa := float(span[0])
		var sb := float(span[1])
		var slen := sb - sa
		var smid := (sa + sb) * 0.5
		_add_colored_box(leg_ew, Vector3(-0.135, 1.54, smid), Vector3(0.035, 3.00, slen), Vector3.ZERO, "batch_wall", wall_siding_col)
		var rib_n := int(slen / 0.55)
		for ri in range(rib_n + 1):
			var rz := sa + 0.20 + float(ri) * 0.55
			if rz <= sb - 0.15:
				_add_colored_box(leg_ew, Vector3(-0.156, 1.54, rz), Vector3(0.016, 2.98, 0.045), Vector3.ZERO, "batch_wall", wall_rib_col, false, 1)

	# Dark gray grooved concrete slab floor (y_top = 0.058m, cleanly above MergedFootways at 0.046m)
	_add_colored_box(leg_ew, Vector3(-1.42, 0.040, ew_mid), Vector3(2.68, 0.036, ew_len), Vector3.ZERO, "batch_concrete", floor_col)
	# East connecting apron joining ColonnadeAndAuditorioPortico ([-31.5, -7.2]) & corredor_convivencia entrance ([-28.0, -10.3])
	_add_colored_box(leg_ew, Vector3(-3.45, 0.040, 29.35), Vector3(1.50, 0.036, 2.60), Vector3.ZERO, "batch_concrete", floor_col)
	_add_colored_box(leg_ew, Vector3(-1.42, 0.040, 31.85), Vector3(2.68, 0.036, 3.40), Vector3.ZERO, "batch_concrete", floor_col)

	# Longitudinal comb grooves on dark gray floor
	for gx in [-0.55, -0.92, -1.30, -1.68, -2.06, -2.44]:
		_add_colored_box(leg_ew, Vector3(gx, 0.059, ew_mid), Vector3(0.03, 0.004, ew_len - 0.2), Vector3.ZERO, "batch_wall", groove_col, false, 1)
	# Faded yellow longitudinal two-way lane divider line
	_add_colored_box(leg_ew, Vector3(-1.72, 0.060, ew_mid), Vector3(0.045, 0.005, ew_len - 1.2), Vector3.ZERO, "batch_line", divider_col, false, 1)

	# Raised stone/concrete curb blocks along South (garden) side (open at West corner s_start..1.55 for Leg 1 and East end 28.2..30.15)
	var curb_s := 1.62
	var curb_idx := 0
	while curb_s < 28.15:
		var ccol := curb_col_a if (curb_idx % 2 == 0) else curb_col_b
		_add_colored_box(leg_ew, Vector3(-2.76, 0.082, curb_s + 0.31), Vector3(0.16, 0.135, 0.62), Vector3.ZERO, "batch_concrete", ccol)
		curb_s += 0.67
		curb_idx += 1

	# Lush garden strip & low ornamental shrubs right outside the South stone curb
	_add_colored_box(leg_ew, Vector3(-3.28, 0.032, 14.8), Vector3(0.88, 0.03, 26.2), Vector3.ZERO, "batch_foliage", Color("#488239"))
	for gsi in range(14):
		var gsz := 2.4 + float(gsi) * 1.85
		if absf(gsz - s_door) < 1.8:
			continue
		var gcol := Color("#3D7D31") if (gsi % 2 == 0) else Color("#55963E")
		_add_colored_sphere(leg_ew, Vector3(-3.26, 0.26, gsz), Vector3(0.68, 0.44, 0.68), "batch_foliage", gcol, false, 1)

	# Green tubular steel structure (#2E6E36): 11 bays (~2.836m each) + longitudinal beams + wall rails + transverse crossbars
	var ew_bays := 11
	var ew_step := ew_len / float(ew_bays)
	for bi in range(ew_bays + 1):
		var sz := s_start + float(bi) * ew_step
		# Transverse floor expansion joint at each bay
		_add_colored_box(leg_ew, Vector3(-1.42, 0.060, sz), Vector3(2.66, 0.005, 0.04), Vector3.ZERO, "batch_wall", joint_col)
		# Garden-side vertical green tubular post
		_add_colored_box(leg_ew, Vector3(-2.66, 1.525, sz), Vector3(0.08, 3.05, 0.08), Vector3.ZERO, "batch_metal_painted", green_frame_col, true)
		# Wall-side vertical green tubular post (nudge away from bloco_adm south doorway if needed)
		var wall_post_z := sz
		if absf(wall_post_z - s_door) < 1.48:
			wall_post_z = (s_door - 1.52) if (wall_post_z < s_door) else (s_door + 1.52)
		_add_colored_box(leg_ew, Vector3(-0.19, 1.525, wall_post_z), Vector3(0.08, 3.05, 0.08), Vector3.ZERO, "batch_metal_painted", green_frame_col, true)
		# Transverse upper green crossbar (travessa)
		_add_colored_box(leg_ew, Vector3(-1.425, 3.05, sz), Vector3(2.55, 0.075, 0.075), Vector3.ZERO, "batch_metal_painted", green_frame_col)

		# Two-way painted yellow directional arrows in each bay
		if bi < ew_bays:
			var bay_mid := sz + ew_step * 0.5
			# Garden lane (-2.14): pointing East (+Z, yaw = 0.0) toward Main Building
			_add_walkway_arrow(leg_ew, Vector3(-2.14, 0.062, bay_mid), 0.0, arrow_col)
			# Inner lane (-1.30): pointing West (-Z, yaw = PI) toward Portaria
			_add_walkway_arrow(leg_ew, Vector3(-1.30, 0.062, bay_mid), PI, arrow_col)

	# Top longitudinal green tubular beams (longarinas superiores)
	_add_colored_box(leg_ew, Vector3(-0.19, 3.05, ew_mid), Vector3(0.08, 0.085, ew_len + 0.08), Vector3.ZERO, "batch_metal_painted", green_frame_col)
	_add_colored_box(leg_ew, Vector3(-1.425, 3.08, ew_mid), Vector3(0.055, 0.055, ew_len + 0.08), Vector3.ZERO, "batch_metal_painted", green_frame_col)
	_add_colored_box(leg_ew, Vector3(-2.66, 3.05, ew_mid), Vector3(0.08, 0.085, ew_len + 0.08), Vector3.ZERO, "batch_metal_painted", green_frame_col)

	# Intermediate horizontal green rails along the wall side (y = 1.05m and y = 2.15m, split around doorway)
	for rail_y in [1.05, 2.15]:
		for rspan in [[s_start, s_door - 1.52], [s_door + 1.52, s_end]]:
			var ra := float(rspan[0])
			var rb := float(rspan[1])
			_add_colored_box(leg_ew, Vector3(-0.19, rail_y, (ra + rb) * 0.5), Vector3(0.065, 0.065, rb - ra), Vector3.ZERO, "batch_metal_painted", green_frame_col)

	# White fluorescent tube light fixtures mounted on the upper-middle green wall rail (y = 2.18m)
	for lz in [2.35, 7.90, 12.10, 18.25, 24.60, 28.50]:
		_add_walkway_fluorescent_lamp(leg_ew, Vector3(-0.24, 2.18, lz), Vector3.ZERO, lamp_body_col, lamp_cap_col)
	for nl_z in [7.90, 23.00]:
		var wlight := OmniLight3D.new()
		wlight.position = leg_ew.transform * Vector3(-1.35, 2.65, nl_z)
		wlight.light_color = Color("#FFF5D6")
		wlight.light_energy = 0.0
		wlight.visible = false
		wlight.omni_range = 14.0
		wlight.omni_attenuation = 1.2
		wlight.shadow_enabled = false
		wlight.distance_fade_enabled = true
		wlight.distance_fade_begin = 75.0
		wlight.distance_fade_length = 25.0
		wlight.set_meta("is_floodlight", false)
		ww_root.add_child(wlight)
		night_lights.append(wlight)

	# Red Fire Hydrant Pipe (#C82222) running along the base of bloco_adm south wall + wall Fire Hose Cabinet
	for fspan in [[0.25, s_door - 1.55], [s_door + 1.55, 26.20]]:
		var fa := float(fspan[0])
		var fb := float(fspan[1])
		var flen := fb - fa
		_add_colored_cylinder(leg_ew, Vector3(-0.20, 0.15, (fa + fb) * 0.5), Vector3(0.075, flen, 0.075), Vector3(PI * 0.5, 0.0, 0.0), "batch_metal_painted", fire_pipe_col)
		var clamp_n := int(flen / 2.2)
		for ci in range(clamp_n + 1):
			var cz := fa + 0.3 + float(ci) * 2.2
			if cz <= fb - 0.2:
				_add_colored_box(leg_ew, Vector3(-0.17, 0.15, cz), Vector3(0.09, 0.09, 0.05), Vector3.ZERO, "batch_metal", fire_dark_col, false, 1)
	# Vertical riser pipe & Red Fire Hose Cabinet (Abrigo de Mangueira de Incêndio) at s = 26.2m
	_add_colored_cylinder(leg_ew, Vector3(-0.20, 0.72, 26.20), Vector3(0.07, 1.15, 0.07), Vector3.ZERO, "batch_metal_painted", fire_pipe_col)
	_add_colored_box(leg_ew, Vector3(-0.24, 1.42, 26.55), Vector3(0.20, 0.82, 0.68), Vector3.ZERO, "batch_metal_painted", fire_pipe_col, false, 1)
	_add_colored_box(leg_ew, Vector3(-0.345, 1.42, 26.55), Vector3(0.02, 0.56, 0.46), Vector3.ZERO, "batch_wall", Color("#EAB308"), false, 1)

	# Agratto Split AC Outdoor Condenser Units on Wall Brackets + Galvanized Metal Rain Hood + Floor Condensate Drain Pipe
	var ac_body_col := Color("#E4E0D2")
	var ac_dark_col := Color("#2B2E2A")
	var hood_col := Color("#C4C8CE")
	for ac_z: float in [3.65, 17.55]:
		for b_off in [-0.30, 0.30]:
			_add_colored_box(leg_ew, Vector3(-0.34, 0.30, ac_z + b_off), Vector3(0.42, 0.04, 0.05), Vector3.ZERO, "batch_metal", Color("#D6D3C9"), false, 1)
			_add_colored_box(leg_ew, Vector3(-0.16, 0.20, ac_z + b_off), Vector3(0.04, 0.24, 0.05), Vector3.ZERO, "batch_metal", Color("#D6D3C9"), false, 1)
		_add_colored_box(leg_ew, Vector3(-0.37, 0.59, ac_z), Vector3(0.36, 0.54, 0.78), Vector3.ZERO, "batch_wall", ac_body_col, false, 1)
		for row_y in [0.46, 0.62]:
			for col_i in range(6):
				var vz := ac_z - 0.28 + float(col_i) * 0.112
				_add_colored_box(leg_ew, Vector3(-0.552, row_y, vz), Vector3(0.015, 0.12, 0.088), Vector3.ZERO, "batch_wall", ac_dark_col, false, 1)
		_add_colored_cylinder(leg_ew, Vector3(-0.37, 0.865, ac_z - 0.04), Vector3(0.28, 0.015, 0.28), Vector3.ZERO, "batch_metal", ac_dark_col, false, 1)
		_add_colored_box(leg_ew, Vector3(-0.50, 0.868, ac_z + 0.26), Vector3(0.05, 0.012, 0.22), Vector3.ZERO, "batch_metal", ac_dark_col, false, 1)
		_add_colored_box(leg_ew, Vector3(-0.74, 0.85, ac_z), Vector3(0.44, 0.022, 0.54), Vector3(0.0, 0.0, deg_to_rad(5.0)), "batch_metal", hood_col, false, 1)
		_add_colored_box(leg_ew, Vector3(-0.98, 0.78, ac_z), Vector3(0.16, 0.022, 0.54), Vector3(0.0, 0.0, deg_to_rad(32.0)), "batch_metal", hood_col, false, 1)
		_add_colored_cylinder(leg_ew, Vector3(-1.45, 0.070, ac_z - 0.60), Vector3(0.028, 2.52, 0.028), Vector3(0.0, 0.0, PI * 0.5), "batch_metal", Color("#7C8086"), false, 1)

	# Row of 5 Colored Selective Waste Bins + White Planters with Burgundy/Green Foliage along the wall (West & East spans)
	var bin_mouth := Color("#1C2024")
	var bin_badge := Color("#F4F4F0")
	for base_s: float in [0.0, 14.15]:
		_add_walkway_white_planter(leg_ew, Vector3(-0.46, 0.058, base_s + 2.05), true, pot_white, soil_dark)
		_add_selective_waste_bin(leg_ew, Vector3(-0.48, 0.058, base_s + 5.55), Color("#7C5841"), bin_mouth, bin_badge)
		_add_selective_waste_bin(leg_ew, Vector3(-0.48, 0.058, base_s + 6.22), Color("#2E7D32"), bin_mouth, bin_badge)
		_add_selective_waste_bin(leg_ew, Vector3(-0.48, 0.058, base_s + 6.89), Color("#C62828"), bin_mouth, bin_badge)
		_add_walkway_white_planter(leg_ew, Vector3(-0.46, 0.058, base_s + 7.56), false, pot_white, soil_dark)
		_add_selective_waste_bin(leg_ew, Vector3(-0.48, 0.058, base_s + 8.32), Color("#1565C0"), bin_mouth, bin_badge)
		_add_selective_waste_bin(leg_ew, Vector3(-0.48, 0.058, base_s + 9.52), Color("#616161"), bin_mouth, bin_badge)
		_add_walkway_white_planter(leg_ew, Vector3(-0.46, 0.058, base_s + 10.35), false, pot_white, soil_dark)
		_add_walkway_white_planter(leg_ew, Vector3(-0.46, 0.058, base_s + 11.85), true, pot_white, soil_dark)

	# --- 2. North-South Entrance Segment connecting Portaria Principal (guarita) to SW Corner of Leg 2 ---
	var ns_south := Vector2(-60.45, 7.42)
	var ns_north := Vector2(-60.182, -3.934)
	var ns_vec := ns_north - ns_south
	var ns_len := ns_vec.length()
	var ns_dir := ns_vec / ns_len
	var ns_rot_y := atan2(ns_dir.x, ns_dir.y)

	var leg_ns := Node3D.new()
	leg_ns.name = "WalkwayLegNorthSouth"
	leg_ns.position = Vector3(ns_south.x, 0.0, ns_south.y)
	leg_ns.rotation.y = ns_rot_y
	ww_root.add_child(leg_ns)

	# Dark gray grooved concrete slab floor on North-South leg
	_add_colored_box(leg_ns, Vector3(0.0, 0.040, ns_len * 0.5), Vector3(2.60, 0.036, ns_len), Vector3.ZERO, "batch_concrete", floor_col)
	for gx_ns in [-0.95, -0.58, -0.22, 0.22, 0.58, 0.95]:
		_add_colored_box(leg_ns, Vector3(gx_ns, 0.059, ns_len * 0.5), Vector3(0.03, 0.004, ns_len - 0.2), Vector3.ZERO, "batch_wall", groove_col, false, 1)
	_add_colored_box(leg_ns, Vector3(0.0, 0.060, ns_len * 0.5), Vector3(0.045, 0.005, ns_len - 0.8), Vector3.ZERO, "batch_line", divider_col, false, 1)

	# Raised stone/concrete curbs along West (+1.28) and East (-1.28, with 2.4m plaza opening near Portaria) edges
	var c_ns := 0.10
	var c_ns_i := 0
	while c_ns < ns_len - 0.45:
		var ccol_ns := curb_col_a if (c_ns_i % 2 == 0) else curb_col_b
		_add_colored_box(leg_ns, Vector3(1.28, 0.082, c_ns + 0.31), Vector3(0.16, 0.135, 0.62), Vector3.ZERO, "batch_concrete", ccol_ns)
		if c_ns > 2.45:
			_add_colored_box(leg_ns, Vector3(-1.28, 0.082, c_ns + 0.31), Vector3(0.16, 0.135, 0.62), Vector3.ZERO, "batch_concrete", ccol_ns)
		c_ns += 0.67
		c_ns_i += 1

	# Green tubular steel posts, top beams, crossbars & two-way yellow arrows on North-South leg (4 bays)
	var ns_bays := 4
	var ns_step := ns_len / float(ns_bays)
	for bi_ns in range(ns_bays + 1):
		var z_ns := float(bi_ns) * ns_step
		_add_colored_box(leg_ns, Vector3(0.0, 0.060, z_ns), Vector3(2.58, 0.005, 0.04), Vector3.ZERO, "batch_wall", joint_col)
		if bi_ns < ns_bays:
			for sx_ns in [-1.22, 1.22]:
				_add_colored_box(leg_ns, Vector3(sx_ns, 1.525, z_ns), Vector3(0.08, 3.05, 0.08), Vector3.ZERO, "batch_metal_painted", green_frame_col, true)
			_add_colored_box(leg_ns, Vector3(0.0, 3.05, z_ns), Vector3(2.52, 0.075, 0.075), Vector3.ZERO, "batch_metal_painted", green_frame_col)
			var mid_ns := z_ns + ns_step * 0.5
			# East lane (-0.58): pointing North (+Z, yaw = 0.0) toward Setor 100 / Main Building
			_add_walkway_arrow(leg_ns, Vector3(-0.58, 0.062, mid_ns), 0.0, arrow_col)
			# West lane (+0.58): pointing South (-Z, yaw = PI) toward Portaria
			_add_walkway_arrow(leg_ns, Vector3(0.58, 0.062, mid_ns), PI, arrow_col)

	for sx_beam in [-1.22, 0.0, 1.22]:
		var by_ns := 3.08 if is_zero_approx(sx_beam) else 3.05
		var bsz_ns := 0.055 if is_zero_approx(sx_beam) else 0.08
		_add_colored_box(leg_ns, Vector3(sx_beam, by_ns, ns_len * 0.5), Vector3(bsz_ns, bsz_ns, ns_len + 0.06), Vector3.ZERO, "batch_metal_painted", green_frame_col)

	for lz_ns in [2.85, 8.45]:
		_add_walkway_fluorescent_lamp(leg_ns, Vector3(0.0, 3.01, lz_ns), Vector3(0.0, 0.0, PI * 0.5), lamp_body_col, lamp_cap_col)

	# --- 3. Corrugated Translucent Milky-Yellow Canopy Roof (#EBE3A8) inside roof_nodes ---
	var roof_holder := Node3D.new()
	roof_holder.name = "EntranceWalkwayRoof"
	ww_root.add_child(roof_holder)
	roof_nodes.append(roof_holder)

	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.92, 0.89, 0.66, 0.88)
	canopy_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	canopy_mat.vertex_color_use_as_albedo = true
	canopy_mat.vertex_color_is_srgb = true
	canopy_mat.roughness = 0.34
	canopy_mat.emission_enabled = true
	canopy_mat.emission = Color("#EBE3A8")
	canopy_mat.emission_energy_multiplier = 0.16
	canopy_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var ew_canopy := MeshInstance3D.new()
	ew_canopy.name = "CanopyEastWest"
	ew_canopy.transform = leg_ew.transform
	ew_canopy.mesh = _build_corrugated_canopy_mesh(ew_len + 0.24, 2.82, -1.42, s_start - 0.12, 3.12)
	ew_canopy.material_override = canopy_mat
	ew_canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	roof_holder.add_child(ew_canopy)

	var ns_canopy := MeshInstance3D.new()
	ns_canopy.name = "CanopyNorthSouth"
	ns_canopy.transform = leg_ns.transform
	ns_canopy.mesh = _build_corrugated_canopy_mesh(ns_len + 0.10, 2.74, 0.0, -0.08, 3.12)
	ns_canopy.material_override = canopy_mat
	ns_canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	roof_holder.add_child(ns_canopy)

func _build_vegetation_and_props(root: Node3D, data: Dictionary) -> void:
	var props_root := Node3D.new()
	props_root.name = "PropsMultiMesh"
	root.add_child(props_root)

	# 1. Trees via spatially chunked MultiMeshInstance3D (campus shadow casters vs distant woodland)
	var tree_positions := _collect_tree_positions(data)
	var t_cyl := _make_cylinder_mesh(0.18, 0.28, 3.2, 8)
	var c_sph := _make_sphere_mesh(2.1, 3.2, 10, 5)
	var trunk_mat := mats.get_material("trunk")
	var fmat := mats.get_batch_material("batch_foliage")

	var tree_buckets: Dictionary = {
		"campus_n": [], "campus_s": [],
		"wood_n": [], "wood_s": []
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 1996
	for i in range(tree_positions.size()):
		var p: Vector2 = tree_positions[i]
		var sc := rng.randf_range(0.78, 1.45)
		var is_araucaria := (i % 9 == 0)
		var rec: Dictionary
		if is_araucaria:
			rec = {
				"t": Transform3D(Basis.from_scale(Vector3(sc * 0.7, sc * 2.4, sc * 0.7)), Vector3(p.x, 3.8 * sc, p.y)),
				"c1": Transform3D(Basis.from_scale(Vector3(sc * 1.45, sc * 0.42, sc * 1.45)), Vector3(p.x, 7.6 * sc, p.y)),
				"c2": Transform3D(Basis.from_scale(Vector3(sc * 0.95, sc * 0.30, sc * 0.95)), Vector3(p.x, 8.2 * sc, p.y)),
				"col1": Color("#295A27"),
				"col2": Color("#33692E")
			}
		else:
			var ox := rng.randf_range(-0.9, 0.9) * sc
			var oz := rng.randf_range(-0.9, 0.9) * sc
			var roll := rng.randf()
			var col := Color("#3D7A32") if roll < 0.72 else (Color("#E0B028") if roll < 0.86 else Color("#6E54A3"))
			rec = {
				"t": Transform3D(Basis.from_scale(Vector3(sc, sc, sc)), Vector3(p.x, 1.6 * sc, p.y)),
				"c1": Transform3D(Basis.from_scale(Vector3(sc, sc * 0.92, sc)), Vector3(p.x, 3.6 * sc, p.y)),
				"c2": Transform3D(Basis.from_scale(Vector3(sc * 0.78, sc * 0.75, sc * 0.78)), Vector3(p.x + ox, 4.7 * sc, p.y + oz)),
				"col1": col,
				"col2": col.lightened(0.08)
			}
		var bkey := ("wood_" if p.x >= 88.0 else "campus_") + ("n" if p.y < 0.0 else "s")
		(tree_buckets[bkey] as Array).append(rec)

	for bkey in ["campus_n", "campus_s", "wood_n", "wood_s"]:
		var recs: Array = tree_buckets[bkey]
		if recs.is_empty():
			continue
		var is_campus := String(bkey).begins_with("campus_")
		var t_mm := MultiMesh.new()
		t_mm.transform_format = MultiMesh.TRANSFORM_3D
		t_mm.mesh = t_cyl
		t_mm.instance_count = recs.size()

		var c1_mm := MultiMesh.new()
		c1_mm.transform_format = MultiMesh.TRANSFORM_3D
		c1_mm.use_colors = true
		c1_mm.mesh = c_sph
		c1_mm.instance_count = recs.size()

		var c2_mm := MultiMesh.new()
		c2_mm.transform_format = MultiMesh.TRANSFORM_3D
		c2_mm.use_colors = true
		c2_mm.mesh = c_sph
		c2_mm.instance_count = recs.size()

		for i in range(recs.size()):
			var r: Dictionary = recs[i]
			t_mm.set_instance_transform(i, r["t"])
			c1_mm.set_instance_transform(i, r["c1"])
			c1_mm.set_instance_color(i, r["col1"])
			c2_mm.set_instance_transform(i, r["c2"])
			c2_mm.set_instance_color(i, r["col2"])

		var t_mmi := MultiMeshInstance3D.new()
		t_mmi.multimesh = t_mm
		t_mmi.material_override = trunk_mat
		t_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if is_campus else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props_root.add_child(t_mmi)

		var c1_mmi := MultiMeshInstance3D.new()
		c1_mmi.multimesh = c1_mm
		c1_mmi.material_override = fmat
		c1_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if is_campus else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props_root.add_child(c1_mmi)

		var c2_mmi := MultiMeshInstance3D.new()
		c2_mmi.multimesh = c2_mm
		c2_mmi.material_override = fmat
		c2_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not is_campus:
			c2_mmi.visibility_range_end = 210.0
			c2_mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			detail_nodes.append({"node": c2_mmi, "base_range": 210.0})
		props_root.add_child(c2_mmi)

		for pair in [[t_mmi, is_campus], [c1_mmi, is_campus], [c2_mmi, false]]:
			var tm: MultiMeshInstance3D = pair[0]
			tree_mmi_list.append(tm)
			_tree_entries.append({"mmi": tm, "full": recs.size(), "casts_shadow": bool(pair[1])})

	full_tree_count = tree_positions.size()

	# 2. Light poles via MultiMeshInstance3D + key OmniLight3D night lights
	var pole_pts := [
		Vector2(-75, -100), Vector2(-70, -40), Vector2(-64, 15), Vector2(-56, 60), Vector2(-50, 110),
		Vector2(-65, -22), Vector2(-24, -10), Vector2(-10, 6), Vector2(14, -42), Vector2(14, -84),
		Vector2(-38, -72), Vector2(-4, 60), Vector2(-18, 95), Vector2(36, 18), Vector2(20, 74)
	]
	var pole_mm := MultiMesh.new()
	pole_mm.transform_format = MultiMesh.TRANSFORM_3D
	pole_mm.mesh = _make_cylinder_mesh(0.08, 0.12, 6.2, 8)
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
			light.visible = false
			light.omni_range = 32.0
			light.omni_attenuation = 1.15
			light.shadow_enabled = false
			light.distance_fade_enabled = true
			light.distance_fade_begin = 95.0
			light.distance_fade_length = 35.0
			light.set_meta("is_floodlight", false)
			props_root.add_child(light)
			night_lights.append(light)

	for fp in [Vector3(-60.0, 7.2, -84.0), Vector3(-23.0, 7.5, -105.0), Vector3(-22.0, 9.0, 4.0), Vector3(-28.0, 5.2, 22.0), Vector3(-24.0, 6.0, 82.0)]:
		var fl := OmniLight3D.new()
		fl.position = fp
		fl.light_color = Color("#FFF0D6")
		fl.light_energy = 0.0
		fl.visible = false
		fl.omni_range = 40.0
		fl.omni_attenuation = 1.05
		fl.shadow_enabled = false
		fl.distance_fade_enabled = true
		fl.distance_fade_begin = 115.0
		fl.distance_fade_length = 45.0
		fl.set_meta("is_floodlight", true)
		props_root.add_child(fl)
		night_lights.append(fl)

	var pole_mmi := MultiMeshInstance3D.new()
	pole_mmi.multimesh = pole_mm
	pole_mmi.material_override = mats.get_material("metal", Color("#7B8187"))
	pole_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	props_root.add_child(pole_mmi)

	var head_mmi := MultiMeshInstance3D.new()
	head_mmi.multimesh = head_mm
	head_mmi.material_override = lamp_mat
	head_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	bin_mm.mesh = _make_cylinder_mesh(0.22, 0.18, 0.85, 10)
	bin_mm.instance_count = bench_pts.size()

	for i in range(bench_pts.size()):
		var p: Vector2 = bench_pts[i]
		bench_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x, 0.28, p.y)))
		bin_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(p.x + 1.3, 0.43, p.y)))

	var bench_mmi := MultiMeshInstance3D.new()
	bench_mmi.multimesh = bench_mm
	bench_mmi.material_override = mats.get_material("ifsul_green")
	bench_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bench_mmi.visibility_range_end = 150.0
	detail_nodes.append({"node": bench_mmi, "base_range": 150.0})
	props_root.add_child(bench_mmi)

	var bin_mmi := MultiMeshInstance3D.new()
	bin_mmi.multimesh = bin_mm
	bin_mmi.material_override = mats.get_material("metal", Color("#2B3036"))
	bin_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bin_mmi.visibility_range_end = 135.0
	detail_nodes.append({"node": bin_mmi, "base_range": 135.0})
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
		wheel_mm.mesh = _make_cylinder_mesh(0.30, 0.30, 0.22, 12)
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
		car_mmi.material_override = mats.get_batch_material("batch_car")
		props_root.add_child(car_mmi)

		var cab_mmi := MultiMeshInstance3D.new()
		cab_mmi.multimesh = cab_mm
		var cab_mat := StandardMaterial3D.new()
		cab_mat.albedo_color = Color("#1E293B")
		cab_mat.metallic = 0.2
		cab_mat.roughness = 0.12
		cab_mmi.material_override = cab_mat
		cab_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props_root.add_child(cab_mmi)

		var wheel_mmi := MultiMeshInstance3D.new()
		wheel_mmi.multimesh = wheel_mm
		wheel_mmi.material_override = mats.get_material("rubber", Color("#18181B"))
		wheel_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wheel_mmi.visibility_range_end = 150.0
		detail_nodes.append({"node": wheel_mmi, "base_range": 150.0})
		props_root.add_child(wheel_mmi)

	# 5. Sapucaia do Sul surrounding neighborhood houses via spatially chunked MultiMeshes
	var house_chunks: Dictionary = {"west": [], "north": [], "south": []}
	var hrng := RandomNumberGenerator.new()
	hrng.seed = 93216
	for row_z: float in [-110.0, -92.0, -52.0, -34.0, -2.0, 12.0, 48.0, 68.0, 98.0, 122.0]:
		var x_west_base := -86.5 + (row_z - 13.0) * 0.160 - 13.5
		for col_i in range(5):
			var col_x := x_west_base - float(col_i) * 17.5
			(house_chunks["west"] as Array).append(Vector2(col_x + hrng.randf_range(-2.2, 2.2), row_z + hrng.randf_range(-2.0, 2.0)))
	for col_x in [-85.0, -64.0, -42.0, -20.0, 2.0, 24.0, 46.0]:
		(house_chunks["north"] as Array).append(Vector2(col_x, -188.0 + hrng.randf_range(-4.0, 4.0)))
		(house_chunks["north"] as Array).append(Vector2(col_x, -210.0 + hrng.randf_range(-4.0, 4.0)))
	for col_x in [-25.0, 0.0, 25.0, 52.0, 78.0]:
		(house_chunks["south"] as Array).append(Vector2(col_x, 198.0 + hrng.randf_range(-5.0, 5.0)))

	var hwm := BoxMesh.new()
	hwm.size = Vector3(9.5, 3.6, 8.0)
	var hrm := BoxMesh.new()
	hrm.size = Vector3(10.2, 0.9, 8.6)
	var hwmat := mats.get_batch_material("batch_wall")
	var hrmat := mats.get_material("wall", Color("#9C523B"))
	var hpal := [Color("#E6DFD3"), Color("#DED8CE"), Color("#D5DFD8"), Color("#E8DCC8")]
	var h_idx := 0
	for ckey in ["west", "north", "south"]:
		var hpts: Array = house_chunks[ckey]
		if hpts.is_empty():
			continue
		var hw_mm := MultiMesh.new()
		hw_mm.transform_format = MultiMesh.TRANSFORM_3D
		hw_mm.use_colors = true
		hw_mm.mesh = hwm
		hw_mm.instance_count = hpts.size()

		var hr_mm := MultiMesh.new()
		hr_mm.transform_format = MultiMesh.TRANSFORM_3D
		hr_mm.mesh = hrm
		hr_mm.instance_count = hpts.size()

		for i in range(hpts.size()):
			var hp: Vector2 = hpts[i]
			var ang := deg_to_rad(8.7 + hrng.randf_range(-2.0, 2.0))
			hw_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, ang), Vector3(hp.x, 1.8, hp.y)))
			hw_mm.set_instance_color(i, hpal[h_idx % hpal.size()])
			hr_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, ang), Vector3(hp.x, 4.0, hp.y)))
			h_idx += 1

		var hw_mmi := MultiMeshInstance3D.new()
		hw_mmi.multimesh = hw_mm
		hw_mmi.material_override = hwmat
		hw_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props_root.add_child(hw_mmi)

		var hr_mmi := MultiMeshInstance3D.new()
		hr_mmi.multimesh = hr_mm
		hr_mmi.material_override = hrmat
		hr_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props_root.add_child(hr_mmi)

func _make_rect_poly(center: Vector2, w: float, d: float, rot_rad: float, pad: float = 0.0) -> PackedVector2Array:
	var hw := w * 0.5 + pad
	var hd := d * 0.5 + pad
	var cs := cos(rot_rad)
	var sn := sin(rot_rad)
	var corners := [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]
	var out := PackedVector2Array()
	for lc in corners:
		out.append(center + Vector2(lc.x * cs + lc.y * sn, -lc.x * sn + lc.y * cs))
	return out

func _point_seg_dist_sq(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var lsq := ab.length_squared()
	if lsq < 0.0001:
		return p.distance_squared_to(a)
	var t := clampf((p - a).dot(ab) / lsq, 0.0, 1.0)
	return p.distance_squared_to(a + ab * t)

func _collect_tree_positions(data: Dictionary) -> Array[Vector2]:
	# Pre-cache exclusion zones once instead of parsing JSON polygons on every tree candidate
	var bldg_aabbs: Array[Rect2] = []
	for bpoly in building_polys:
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		for v in bpoly:
			mn.x = minf(mn.x, v.x); mn.y = minf(mn.y, v.y)
			mx.x = maxf(mx.x, v.x); mx.y = maxf(mx.y, v.y)
		bldg_aabbs.append(Rect2(mn - Vector2(5.2, 5.2), (mx - mn) + Vector2(10.4, 10.4)))

	var court_polys: Array[PackedVector2Array] = []
	for c in data.get("courts", []):
		var cp := _to_vec2_array(c.get("polygon", []))
		if cp.size() >= 3:
			court_polys.append(cp)
		elif c.has("center") and c.has("size"):
			var ca: Array = c["center"]
			var sa: Array = c["size"]
			court_polys.append(_make_rect_poly(Vector2(float(ca[0]), float(ca[1])), float(sa[0]), float(sa[1]), deg_to_rad(float(c.get("rot_deg", 0.0))), 1.5))

	var parking_polys: Array[PackedVector2Array] = []
	for pk in data.get("parking_lots", []):
		parking_polys.append(_to_vec2_array(pk.get("polygon", [])))

	# Exclude Horta zone (with 3.0m margin)
	var horta_polys: Array[PackedVector2Array] = []
	var lm: Dictionary = data.get("landmarks", {})
	var horta: Dictionary = lm.get("horta", {})
	if not horta.is_empty():
		var hf := _get_horta_frame(horta)
		horta_polys.append(_make_rect_poly(hf["center"], float(hf["w"]), float(hf["d"]), float(hf["rot"]), 3.0))

	# Exclude footway segments so trees never spawn inside walkways
	var foot_segs: Array = []
	for fw in data.get("footways", []):
		var fpts: Array = fw.get("points", [])
		for i in range(fpts.size() - 1):
			foot_segs.append([Vector2(float(fpts[i][0]), float(fpts[i][1])), Vector2(float(fpts[i + 1][0]), float(fpts[i + 1][1]))])

	var poi_xz := PackedVector2Array()
	for poi in data.get("pois", []):
		var arr: Array = poi.get("position", [0, 0, 0])
		poi_xz.append(Vector2(float(arr[0]), float(arr[2])))

	# Exclude >= 7.0m around every building entrance so trees never obscure doorways or facade signs
	var entrance_xz := PackedVector2Array()
	for bldg in data.get("buildings", []):
		for ent in bldg.get("entrances", []):
			if ent is Dictionary:
				var epos: Array = ent.get("pos", [])
				if epos.size() >= 2:
					entrance_xz.append(Vector2(float(epos[0]), float(epos[1])))

	var out: Array[Vector2] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 2008
	# Intentional patio & Setor 100 courtyard trees (only kept if outside solid building wings)
	for cp in [Vector2(14.5, 6.0), Vector2(18.5, 13.0), Vector2(10.5, 13.5), Vector2(-48.5, -24.5)]:
		var in_courtyard := false
		for ci in _courtyard_inners:
			if Geometry2D.is_point_in_polygon(cp, ci):
				in_courtyard = true
				break
		var in_bldg := false
		if not in_courtyard:
			for bpoly in building_polys:
				if Geometry2D.is_point_in_polygon(cp, bpoly):
					in_bldg = true
					break
		if not in_bldg:
			out.append(cp)
	for _i in range(145):
		var px := rng.randf_range(92.0, 190.0)
		var pz := rng.randf_range(-160.0, 120.0)
		out.append(Vector2(px, pz))
	for _i in range(110):
		var px := rng.randf_range(-52.0, 72.0)
		var pz := rng.randf_range(68.0, 152.0)
		var cand := Vector2(px, pz)
		if _is_tree_clear_cached(cand, bldg_aabbs, court_polys, parking_polys, horta_polys, foot_segs, poi_xz, entrance_xz):
			out.append(cand)
	for _i in range(28):
		var px := rng.randf_range(-40.0, 38.0)
		var pz := rng.randf_range(-155.0, -115.0)
		var cand := Vector2(px, pz)
		if _is_tree_clear_cached(cand, bldg_aabbs, court_polys, parking_polys, horta_polys, foot_segs, poi_xz, entrance_xz):
			out.append(cand)
	for mz: float in [-138.0, -128.0, -110.0, -96.0, -82.0, -68.0, -54.0, -40.0, -26.0, -12.0, 2.0, 30.0, 46.0, 62.0, 78.0, 94.0, 110.0, 126.0, 144.0, 162.0]:
		var mx := -80.25 + (mz - 13.0) * 0.160
		var cand := Vector2(mx, mz)
		if _is_tree_clear_cached(cand, bldg_aabbs, court_polys, parking_polys, horta_polys, foot_segs, poi_xz, entrance_xz):
			out.append(cand)
	return out

func _is_tree_clear_cached(p: Vector2, bldg_aabbs: Array[Rect2], court_polys: Array[PackedVector2Array], parking_polys: Array[PackedVector2Array], horta_polys: Array[PackedVector2Array], foot_segs: Array, poi_xz: PackedVector2Array, entrance_xz: PackedVector2Array) -> bool:
	# Keep SouthernPond water & island clear
	var dp := p - Vector2(-24.0, 81.0)
	if (dp.x * dp.x) / (14.5 * 14.5) + (dp.y * dp.y) / (8.5 * 8.5) < 1.0:
		return false
	for bi in range(building_polys.size()):
		if not bldg_aabbs[bi].has_point(p):
			continue
		var bpoly: PackedVector2Array = building_polys[bi]
		if Geometry2D.is_point_in_polygon(p, bpoly):
			return false
		for ei in range(bpoly.size()):
			var v0 := bpoly[ei]
			var v1 := bpoly[(ei + 1) % bpoly.size()]
			if _point_seg_dist_sq(p, v0, v1) < 12.25:
				return false
	for cpoly in court_polys:
		if Geometry2D.is_point_in_polygon(p, cpoly):
			return false
		for ei in range(cpoly.size()):
			if _point_seg_dist_sq(p, cpoly[ei], cpoly[(ei + 1) % cpoly.size()]) < 4.0:
				return false
	for pkpoly in parking_polys:
		if Geometry2D.is_point_in_polygon(p, pkpoly):
			return false
	for hpoly in horta_polys:
		if Geometry2D.is_point_in_polygon(p, hpoly):
			return false
	for seg in foot_segs:
		if _point_seg_dist_sq(p, seg[0], seg[1]) < 4.84:
			return false
	for pp in poi_xz:
		if p.distance_squared_to(pp) < 25.0:
			return false
	for ep in entrance_xz:
		if p.distance_squared_to(ep) < 49.0:
			return false
	return true

func set_vegetation_density(ratio: float, cast_shadows: bool = true) -> void:
	if full_tree_count <= 0:
		return
	var clamped_ratio := clampf(ratio, 0.1, 1.0)
	for entry in _tree_entries:
		var mmi: MultiMeshInstance3D = entry["mmi"]
		var full: int = int(entry["full"])
		if is_instance_valid(mmi) and mmi.multimesh != null:
			var target := clampi(int(round(float(full) * clamped_ratio)), 1, full)
			mmi.multimesh.visible_instance_count = target if target < full else -1
			if bool(entry["casts_shadow"]):
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func apply_detail_range_scale(scale: float) -> void:
	var s := clampf(scale, 0.4, 2.5)
	for item in detail_nodes:
		var node: GeometryInstance3D = item["node"] as GeometryInstance3D
		if is_instance_valid(node):
			node.visibility_range_end = float(item["base_range"]) * s

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

		var ring := MeshInstance3D.new()
		ring.mesh = _make_cylinder_mesh(1.15, 1.25, 0.08, 22)
		ring.position.y = 0.05
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color("#2F9E41")
		rmat.emission_enabled = true
		rmat.emission = Color("#2F9E41")
		rmat.emission_energy_multiplier = 0.8
		ring.material_override = rmat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.name = "Beacon"
		area.add_child(marker)

		var lbl := Label3D.new()
		lbl.text = "%d. %s\n[E] Explorar" % [i + 1, String(p.get("title", ""))]
		lbl.position.y = 2.95
		lbl.font_size = 32
		lbl.pixel_size = 0.0042
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.visibility_range_end = 30.0
		lbl.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		lbl.modulate = Color("#FFFBE6")
		lbl.outline_modulate = Color(0.05, 0.1, 0.06)
		lbl.outline_size = 6
		area.add_child(lbl)

		p_root.add_child(area)
		poi_nodes.append(area)
		poi_beacons.append(marker)

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

func _extrude_polygon_mesh(poly: PackedVector2Array, height: float, include_walls: bool, apply_vcol: bool = false, vcol: Color = Color.WHITE) -> ArrayMesh:
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
		if apply_vcol:
			st.set_color(vcol)
		st.set_uv(Vector2(a.x, a.z) * 0.14)
		st.add_vertex(a)
		st.set_uv(Vector2(b.x, b.z) * 0.14)
		st.add_vertex(b)
		st.set_uv(Vector2(c.x, c.z) * 0.14)
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
			var tri_n := (v1 - v0).cross(v2 - v0)
			st.set_normal(n)
			if apply_vcol:
				st.set_color(vcol)
			if tri_n.dot(n) <= 0.0:
				_push_quad(st, v0, v1, v2, v3, len, height)
			else:
				_push_quad(st, v1, v0, v3, v2, len, height)

	st.index()
	st.generate_tangents()
	return st.commit()

func cleanup() -> void:
	clear_room_beacon()
	if interior_builder != null:
		interior_builder.cleanup()
		interior_builder = null
	roof_nodes.clear()
	roofs_visible = true
	_courtyard_inners.clear()
	_build_root = null
	_colored_batches.clear()
	_plain_batches.clear()
	_sphere_batches.clear()
	_cyl_batches.clear()
	_torus_batches.clear()
	_unit_box_mesh = null
	_unit_sphere_mesh = null
	_unit_cyl_mesh = null
	_unit_torus_mesh = null
	_road_st = null
	_walk_st = null
	_foot_st = null
	tree_mmi_list.clear()
	_tree_entries.clear()
	detail_nodes.clear()
	poi_nodes.clear()
	poi_beacons.clear()
	night_lights.clear()
	building_polys.clear()
	mats.clear_caches()

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
