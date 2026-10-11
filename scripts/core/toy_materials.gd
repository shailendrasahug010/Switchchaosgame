class_name ToyMaterials
extends RefCounted
## Shared cartoon materials for the "toy universe" look.
## One material per color/kind is created and reused everywhere, which keeps
## draw-call batching effective and memory low on mobile.

static var _cache: Dictionary = {}


## Glossy toy plastic: soft wrap lighting, toon highlight and a little rim light.
static func plastic(color: Color) -> StandardMaterial3D:
	var key := "plastic_" + color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.38
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.5
	_cache[key] = m
	return m


## Matte painted wood/foam for big level pieces.
static func matte(color: Color) -> StandardMaterial3D:
	var key := "matte_" + color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_cache[key] = m
	return m


## Self-lit color for candle flames, stars and indicator lights.
static func glow(color: Color, energy: float = 1.2) -> StandardMaterial3D:
	var key := "glow_%s_%.2f" % [color.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	_cache[key] = m
	return m


## Flat, unlit color (eyes, UI-like markers) that reads clearly at any light level.
static func flat(color: Color) -> StandardMaterial3D:
	var key := "flat_" + color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cache[key] = m
	return m


## See-through glass bubble (Moon Mode helmet, ghost previews).
static func glass(color: Color, alpha: float = 0.3) -> StandardMaterial3D:
	var key := "glass_%s_%.2f" % [color.to_html(), alpha]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.1
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.rim_enabled = true
	m.rim = 0.6
	m.cull_mode = BaseMaterial3D.CULL_BACK
	_cache[key] = m
	return m


enum Pattern { NONE, CHECKER, STRIPES, DOTS, GRID, SPRINKLES }

const SPRINKLE_COLORS: Array[Color] = [
	Color("ff5fa8"), Color("3f9dff"), Color("ffd23f"), Color("2fc97a"), Color("ffffff"), Color("a77bff"),
]


## Painted pattern projected in world space, so it tiles evenly on blocks of
## any size. [param tiles_per_meter] controls how big the pattern looks.
static func patterned(base: Color, accent: Color, pattern: int, tiles_per_meter: float = 0.5) -> StandardMaterial3D:
	if pattern == Pattern.NONE:
		return matte(base)
	var key := "pat_%s_%s_%d_%.3f" % [base.to_html(), accent.to_html(), pattern, tiles_per_meter]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = pattern_texture(base, accent, pattern)
	m.roughness = 0.8
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * tiles_per_meter
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_cache[key] = m
	return m


## A small seamless 64x64 pattern texture.
static func pattern_texture(base: Color, accent: Color, pattern: int) -> ImageTexture:
	var key := "tex_%s_%s_%d" % [base.to_html(), accent.to_html(), pattern]
	if _cache.has(key):
		return _cache[key]
	const N := 64
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	img.fill(base)
	match pattern:
		Pattern.CHECKER:
			for y in N:
				for x in N:
					if (x / 32 + y / 32) % 2 == 1:
						img.set_pixel(x, y, accent)
		Pattern.STRIPES:
			for y in N:
				for x in N:
					if (x + y) % 32 < 12:
						img.set_pixel(x, y, accent)
		Pattern.DOTS:
			var centers: Array[Vector2] = [Vector2(16, 16), Vector2(48, 48)]
			for y in N:
				for x in N:
					for c in centers:
						var d := Vector2(x + 0.5, y + 0.5) - c
						# wrap so dots stay round across tile edges
						d.x = fposmod(d.x + N * 0.5, N) - N * 0.5
						d.y = fposmod(d.y + N * 0.5, N) - N * 0.5
						if d.length() < 7.5:
							img.set_pixel(x, y, accent)
		Pattern.GRID:
			for y in N:
				for x in N:
					if x < 3 or y < 3:
						img.set_pixel(x, y, accent)
		Pattern.SPRINKLES:
			var rng := RandomNumberGenerator.new()
			rng.seed = 1234
			for i in 26:
				var c := SPRINKLE_COLORS[i % SPRINKLE_COLORS.size()]
				var cx := rng.randi_range(0, N - 1)
				var cy := rng.randi_range(0, N - 1)
				var horizontal := rng.randf() < 0.5
				for j in 7:
					for k in 3:
						var px := cx + (j if horizontal else k)
						var py := cy + (k if horizontal else j)
						img.set_pixel(px % N, py % N, c)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func clear_cache() -> void:
	_cache.clear()
