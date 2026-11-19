class_name CampusMaterials
extends RefCounted

var cache: Dictionary = {}
var batch_cache: Dictionary = {}
var _noise_cache: Dictionary = {}
var _tex_cache: Dictionary = {}
static var _logo_cache: Dictionary = {}

func _is_compat() -> bool:
	return OS.has_feature("web") or RenderingServer.get_current_rendering_method() == "gl_compatibility"

func get_material(key: String, tint: Color = Color.WHITE, uv_scale: Vector3 = Vector3.ONE) -> StandardMaterial3D:
	var cache_key := "%s_%s_%s" % [key, tint.to_html(false), str(uv_scale)]
	if cache.has(cache_key):
		return cache[cache_key]

	var compat := _is_compat()
	var mat := StandardMaterial3D.new()
	if compat:
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var default_uv := Vector3(0.14, 0.14, 0.14) if key in ["grass", "asphalt", "concrete", "sidewalk", "wall", "metal"] else Vector3.ONE
	mat.uv1_scale = uv_scale if uv_scale != Vector3.ONE else default_uv
	# Planar/extruded surfaces already supply metric UVs; keep triplanar disabled to cut texture fetches by 3x.
	var use_triplanar := (key == "metal" and not compat and uv_scale == Vector3.ONE)
	mat.uv1_triplanar = use_triplanar
	mat.uv1_world_triplanar = use_triplanar

	match key:
		"grass":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#528540")
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			_apply_pbr(mat, "grass_diff.jpg", "", "grass_rough.jpg", 0.92, 0.0, 2.5, 0.04)
		"asphalt":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#4C5056")
			_apply_pbr(mat, "asphalt_diff.jpg", "asphalt_nor.jpg", "asphalt_rough.jpg", 0.88, 0.0, 4.0, 0.06)
			mat.normal_scale = 0.45
		"concrete", "sidewalk":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#D5D1C8")
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			_apply_pbr(mat, "concrete_diff.jpg", "concrete_nor.jpg", "concrete_rough.jpg", 0.85, 0.0, 3.0, 0.04)
			mat.normal_scale = 0.35
		"wall":
			mat.albedo_color = tint
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			_apply_pbr(mat, "", "", "", 0.78, 0.0, 1.8, 0.015)
			mat.normal_scale = 0.25
		"tile":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#D8D4CC")
			_apply_pbr(mat, "tile_diff.jpg", "", "", 0.62, 0.05, 6.0, 0.02)
		"metal":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#4A5056")
			_apply_pbr(mat, "metal_diff.jpg", "", "", 0.38, 0.82, 8.0, 0.015)
		"glass":
			# Opaque slate-blue reflective glass sits flush over solid exterior walls: avoids alpha sorting/overdraw.
			mat.albedo_color = Color("#3A5B73")
			mat.roughness = 0.10
			mat.metallic = 0.35
			mat.emission_enabled = true
			mat.emission = Color("#FFE3A3")
			mat.emission_energy_multiplier = 0.0
		"fence":
			mat.albedo_color = Color(0.75, 0.80, 0.85, 0.24)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		"rubber":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#18181B")
			mat.roughness = 0.88
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		"ifsul_green":
			mat.albedo_color = Color("#2F9E41")
			mat.roughness = 0.55
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		"ifsul_red":
			mat.albedo_color = Color("#CD191E")
			mat.roughness = 0.50
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		"court_blue":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#255B8A")
			mat.roughness = 0.75
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		"court_red":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#A34F3A")
			mat.roughness = 0.78
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		"line_white":
			mat.albedo_color = Color("#F5F5F0")
			mat.roughness = 0.7
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		"trunk":
			mat.albedo_color = Color("#5A4230")
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			_apply_pbr(mat, "", "", "", 0.95, 0.0, 6.0, 0.03)
		"foliage":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#3E7B34")
			mat.roughness = 0.88
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		"lamp_glow":
			mat.albedo_color = Color("#FFF4D6")
			mat.emission_enabled = true
			mat.emission = Color("#FFE3A8")
			mat.emission_energy_multiplier = 0.0
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		"interior_wall":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#EFECE6")
			mat.roughness = 0.82
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		"interior_floor":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#DCD8D0")
			_apply_pbr(mat, "tile_diff.jpg", "", "", 0.58, 0.04, 6.0, 0.02)
		"wood":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#8B6240")
			mat.roughness = 0.72
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		"whiteboard":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#F6F8FA")
			mat.roughness = 0.22
			mat.metallic = 0.05
		"chalkboard":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#1E4D33")
			mat.roughness = 0.85
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		"interior_glass":
			mat.albedo_color = tint if tint != Color.WHITE else Color(0.55, 0.72, 0.82, 0.34)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.12
			mat.metallic = 0.20
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		"ceiling_lamp":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#FFFFFF")
			mat.emission_enabled = true
			mat.emission = Color("#FFF9EB")
			mat.emission_energy_multiplier = 1.35
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_:
			mat.albedo_color = tint
			mat.roughness = 0.8
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	cache[cache_key] = mat
	return mat

func get_planar_ground_material(key: String, tint: Color = Color.WHITE) -> StandardMaterial3D:
	return get_material(key, tint, Vector3(0.999, 0.999, 1.0))

func get_batch_material(bucket: String) -> StandardMaterial3D:
	if batch_cache.has(bucket):
		return batch_cache[bucket]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	if _is_compat():
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	match bucket:
		"vcol_wall":
			mat.roughness = 0.78
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			_apply_pbr(mat, "", "", "", 0.78, 0.0, 1.8, 0.015)
			mat.normal_scale = 0.25
		"vcol_roof":
			mat.roughness = 0.84
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			_apply_pbr(mat, "concrete_diff.jpg", "concrete_nor.jpg", "concrete_rough.jpg", 0.84, 0.0, 3.0, 0.04)
			mat.normal_scale = 0.30
		"batch_wall":
			mat.roughness = 0.78
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		"batch_line":
			mat.roughness = 0.70
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		"batch_concrete":
			mat.roughness = 0.85
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		"batch_metal":
			mat.roughness = 0.38
			mat.metallic = 0.80
		"batch_metal_painted":
			mat.roughness = 0.40
			mat.metallic = 0.42
		"batch_foliage":
			mat.roughness = 0.88
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		"batch_car":
			mat.roughness = 0.22
			mat.metallic = 0.35
		"batch_wood":
			mat.roughness = 0.72
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		"batch_emissive":
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_:
			mat.roughness = 0.80
			mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	batch_cache[bucket] = mat
	return mat

func _apply_pbr(mat: StandardMaterial3D, diff: String, nor: String, rough: String, default_rough: float, metal: float, noise_freq: float, bump_amp: float) -> void:
	mat.roughness = default_rough
	mat.metallic = metal
	var compat := _is_compat()

	var diff_tex := _load_tex(diff)
	if diff_tex != null:
		mat.albedo_texture = diff_tex
	elif not compat:
		mat.albedo_texture = _make_procedural_albedo(noise_freq, bump_amp)

	if not compat:
		var nor_tex := _load_tex(nor)
		if nor_tex != null:
			mat.normal_enabled = true
			mat.normal_texture = nor_tex
		else:
			mat.normal_enabled = true
			mat.normal_texture = _make_procedural_normal(noise_freq)

		var rough_tex := _load_tex(rough)
		if rough_tex != null:
			mat.roughness_texture = rough_tex

func _load_tex(filename: String) -> Texture2D:
	if filename.is_empty():
		return null
	if _tex_cache.has(filename):
		return _tex_cache[filename]
	var res_path := "res://assets/textures/" + filename
	if ResourceLoader.exists(res_path):
		var res := ResourceLoader.load(res_path)
		if res is Texture2D:
			_tex_cache[filename] = res
			return res
	var abs_path := ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			var tex := ImageTexture.create_from_image(img)
			_tex_cache[filename] = tex
			return tex
	_tex_cache[filename] = null
	return null

func _make_procedural_albedo(freq: float, amp: float) -> NoiseTexture2D:
	var nkey := "alb_%.2f_%.3f" % [freq, amp]
	if _noise_cache.has(nkey):
		return _noise_cache[nkey]
	var tex := NoiseTexture2D.new()
	var sz := 128 if _is_compat() else 256
	tex.width = sz
	tex.height = sz
	tex.seamless = true
	var noise := FastNoiseLite.new()
	noise.frequency = freq * 0.02
	noise.fractal_octaves = 2 if _is_compat() else 3
	tex.noise = noise
	var grad := Gradient.new()
	var lo := clampf(1.0 - amp * 3.0, 0.72, 0.96)
	grad.set_color(0, Color(lo, lo, lo, 1.0))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 1.0))
	tex.color_ramp = grad
	_noise_cache[nkey] = tex
	return tex

func _make_procedural_normal(freq: float) -> NoiseTexture2D:
	var nkey := "nor_%.2f" % freq
	if _noise_cache.has(nkey):
		return _noise_cache[nkey]
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 2.0
	var noise := FastNoiseLite.new()
	noise.frequency = freq * 0.025
	noise.fractal_octaves = 3
	tex.noise = noise
	_noise_cache[nkey] = tex
	return tex

static func create_ifsul_logo_texture(size: int = 256) -> ImageTexture:
	var eff_size := mini(size, 128) if OS.has_feature("web") else size
	if _logo_cache.has(eff_size):
		return _logo_cache[eff_size]
	var img := Image.create(eff_size, eff_size, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 1.0))
	var green := Color("#2F9E41")
	var red := Color("#CD191E")
	var pad := int(eff_size * 0.08)
	var cell := int((eff_size - pad * 2) / 4.4)
	var gap := int(cell * 0.14)
	var r := int(cell * 0.16)

	# 3x4 IF modular grid: [col, row]
	var cells := [
		[0, 0], [1, 0], [2, 0],
		[0, 1], [1, 1],
		[0, 2], [1, 2], [2, 2],
		[0, 3], [1, 3]
	]
	# Top-left circle [0, 0] is red; remaining 9 squares are green
	for c in cells:
		var cx0: int = pad + int(c[0]) * (cell + gap) + int(cell * 0.2)
		var cy0: int = pad + int(c[1]) * (cell + gap)
		var cx1: int = mini(cx0 + cell, eff_size)
		var cy1: int = mini(cy0 + cell, eff_size)
		if c[0] == 0 and c[1] == 0:
			var rad: float = cell * 0.48
			var rad_sq: float = rad * rad
			var center := Vector2(cx0 + cell * 0.5, cy0 + cell * 0.5)
			for y in range(cy0, cy1):
				for x in range(cx0, cx1):
					if Vector2(x, y).distance_squared_to(center) <= rad_sq:
						img.set_pixel(x, y, red)
		else:
			img.fill_rect(Rect2i(cx0 + r, cy0, maxi(0, (cx1 - cx0) - r * 2), cy1 - cy0), green)
			img.fill_rect(Rect2i(cx0, cy0 + r, cx1 - cx0, maxi(0, (cy1 - cy0) - r * 2)), green)
			var r_sq := float(r * r)
			for y in range(cy0, cy1):
				var dy := mini(y - cy0, cy0 + cell - 1 - y)
				if dy >= r:
					continue
				for x in range(cx0, cx1):
					var dx := mini(x - cx0, cx0 + cell - 1 - x)
					if dx < r and float((r - dx) * (r - dx) + (r - dy) * (r - dy)) <= r_sq:
						img.set_pixel(x, y, green)
	var tex := ImageTexture.create_from_image(img)
	_logo_cache[eff_size] = tex
	return tex

func clear_caches() -> void:
	cache.clear()
	batch_cache.clear()
	_noise_cache.clear()
	_tex_cache.clear()
	_logo_cache.clear()
