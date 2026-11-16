class_name CampusMaterials
extends RefCounted

var cache: Dictionary = {}
var _noise_cache: Dictionary = {}

func _is_compat() -> bool:
	return OS.has_feature("web") or RenderingServer.get_current_rendering_method() == "gl_compatibility"

func get_material(key: String, tint: Color = Color.WHITE, uv_scale: Vector3 = Vector3.ONE) -> StandardMaterial3D:
	var cache_key := "%s_%s_%s" % [key, tint.to_html(false), str(uv_scale)]
	if cache.has(cache_key):
		return cache[cache_key]

	var compat := _is_compat()
	var mat := StandardMaterial3D.new()
	var default_uv := Vector3(0.14, 0.14, 0.14) if key in ["grass", "asphalt", "concrete", "sidewalk", "wall"] else Vector3.ONE
	mat.uv1_scale = uv_scale if uv_scale != Vector3.ONE else default_uv
	var use_triplanar := (key in ["grass", "asphalt", "concrete", "sidewalk", "brick"]) or (key == "wall" and not compat)
	mat.uv1_triplanar = use_triplanar
	mat.uv1_world_triplanar = use_triplanar

	match key:
		"grass":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#528540")
			_apply_pbr(mat, "grass_diff.jpg", "", "grass_rough.jpg", 0.92, 0.0, 2.5, 0.04)
		"asphalt":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#4C5056")
			_apply_pbr(mat, "asphalt_diff.jpg", "asphalt_nor.jpg", "asphalt_rough.jpg", 0.88, 0.0, 4.0, 0.06)
			mat.normal_scale = 0.45
		"concrete", "sidewalk":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#D5D1C8")
			_apply_pbr(mat, "concrete_diff.jpg", "concrete_nor.jpg", "concrete_rough.jpg", 0.85, 0.0, 3.0, 0.04)
			mat.normal_scale = 0.35
		"wall":
			mat.albedo_color = tint
			_apply_pbr(mat, "", "", "", 0.78, 0.0, 1.8, 0.015)
			mat.normal_scale = 0.25
		"tile":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#D8D4CC")
			_apply_pbr(mat, "tile_diff.jpg", "", "", 0.62, 0.05, 6.0, 0.02)
		"metal":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#4A5056")
			_apply_pbr(mat, "metal_diff.jpg", "", "", 0.38, 0.82, 8.0, 0.015)
		"glass":
			mat.albedo_color = Color(0.16, 0.33, 0.46, 0.82)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.08
			mat.metallic = 0.35
			mat.emission_enabled = true
			mat.emission = Color("#FFE3A3")
			mat.emission_energy_multiplier = 0.0
		"ifsul_green":
			mat.albedo_color = Color("#2F9E41")
			mat.roughness = 0.55
		"ifsul_red":
			mat.albedo_color = Color("#CD191E")
			mat.roughness = 0.50
		"court_blue":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#255B8A")
			mat.roughness = 0.75
		"court_red":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#A34F3A")
			mat.roughness = 0.78
		"line_white":
			mat.albedo_color = Color("#F5F5F0")
			mat.roughness = 0.7
		"trunk":
			mat.albedo_color = Color("#5A4230")
			_apply_pbr(mat, "", "", "", 0.95, 0.0, 6.0, 0.03)
		"foliage":
			mat.albedo_color = tint if tint != Color.WHITE else Color("#3E7B34")
			mat.roughness = 0.88
		"lamp_glow":
			mat.albedo_color = Color("#FFF4D6")
			mat.emission_enabled = true
			mat.emission = Color("#FFE3A8")
			mat.emission_energy_multiplier = 0.0
		_:
			mat.albedo_color = tint
			mat.roughness = 0.8

	cache[cache_key] = mat
	return mat

func _apply_pbr(mat: StandardMaterial3D, diff: String, nor: String, rough: String, default_rough: float, metal: float, noise_freq: float, bump_amp: float) -> void:
	mat.roughness = default_rough
	mat.metallic = metal

	var diff_tex := _load_tex(diff)
	if diff_tex != null:
		mat.albedo_texture = diff_tex
	else:
		mat.albedo_texture = _make_procedural_albedo(noise_freq, bump_amp)

	var nor_tex := _load_tex(nor)
	if nor_tex != null:
		mat.normal_enabled = true
		mat.normal_texture = nor_tex
	elif not _is_compat():
		mat.normal_enabled = true
		mat.normal_texture = _make_procedural_normal(noise_freq)

	var rough_tex := _load_tex(rough)
	if rough_tex != null:
		mat.roughness_texture = rough_tex

func _load_tex(filename: String) -> Texture2D:
	if filename.is_empty():
		return null
	var res_path := "res://assets/textures/" + filename
	if ResourceLoader.exists(res_path):
		var res := ResourceLoader.load(res_path)
		if res is Texture2D:
			return res
	var abs_path := ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
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
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 1.0))
	var green := Color("#2F9E41")
	var red := Color("#CD191E")
	var pad := int(size * 0.08)
	var cell := int((size - pad * 2) / 4.4)
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
		var cx1: int = mini(cx0 + cell, size)
		var cy1: int = mini(cy0 + cell, size)
		if c[0] == 0 and c[1] == 0:
			var rad: float = cell * 0.48
			var center := Vector2(cx0 + cell * 0.5, cy0 + cell * 0.5)
			for y in range(cy0, cy1):
				for x in range(cx0, cx1):
					if Vector2(x, y).distance_to(center) <= rad:
						img.set_pixel(x, y, red)
		else:
			for y in range(cy0, cy1):
				for x in range(cx0, cx1):
					var dx := mini(x - cx0, cx0 + cell - 1 - x)
					var dy := mini(y - cy0, cy0 + cell - 1 - y)
					if dx >= r or dy >= r or Vector2(r - dx, r - dy).length() <= float(r):
						img.set_pixel(x, y, green)
	return ImageTexture.create_from_image(img)
