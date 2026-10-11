class_name MeshFactory
extends RefCounted
## Low-poly primitive meshes, cached and shared. Everything visual in the
## prototype is built from these, so there are no external model files to
## license and the whole look can be restyled from code.

static var _cache: Dictionary = {}


static func sphere(radius: float, height: float = -1.0, segments: int = 20, rings: int = 10) -> SphereMesh:
	if height <= 0.0:
		height = radius * 2.0
	var key := "sphere_%.3f_%.3f_%d_%d" % [radius, height, segments, rings]
	if not _cache.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = height
		m.radial_segments = segments
		m.rings = rings
		_cache[key] = m
	return _cache[key]


static func hemisphere(radius: float, segments: int = 20, rings: int = 6) -> SphereMesh:
	var key := "hemi_%.3f_%d_%d" % [radius, segments, rings]
	if not _cache.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius
		m.is_hemisphere = true
		m.radial_segments = segments
		m.rings = rings
		_cache[key] = m
	return _cache[key]


static func capsule(radius: float, height: float, segments: int = 16, rings: int = 4) -> CapsuleMesh:
	var key := "capsule_%.3f_%.3f_%d_%d" % [radius, height, segments, rings]
	if not _cache.has(key):
		var m := CapsuleMesh.new()
		m.radius = radius
		m.height = maxf(height, radius * 2.0)
		m.radial_segments = segments
		m.rings = rings
		_cache[key] = m
	return _cache[key]


static func cylinder(top_radius: float, bottom_radius: float, height: float, segments: int = 20) -> CylinderMesh:
	var key := "cyl_%.3f_%.3f_%.3f_%d" % [top_radius, bottom_radius, height, segments]
	if not _cache.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top_radius
		m.bottom_radius = bottom_radius
		m.height = height
		m.radial_segments = segments
		m.rings = 1
		_cache[key] = m
	return _cache[key]


static func cone(radius: float, height: float, segments: int = 16) -> CylinderMesh:
	return cylinder(0.0, radius, height, segments)


static func box(size: Vector3) -> BoxMesh:
	var key := "box_%.3f_%.3f_%.3f" % [size.x, size.y, size.z]
	if not _cache.has(key):
		var m := BoxMesh.new()
		m.size = size
		_cache[key] = m
	return _cache[key]


static func torus(inner_radius: float, outer_radius: float, rings: int = 20, ring_segments: int = 8) -> TorusMesh:
	var key := "torus_%.3f_%.3f_%d_%d" % [inner_radius, outer_radius, rings, ring_segments]
	if not _cache.has(key):
		var m := TorusMesh.new()
		m.inner_radius = inner_radius
		m.outer_radius = outer_radius
		m.rings = rings
		m.ring_segments = ring_segments
		_cache[key] = m
	return _cache[key]


## A chunky five-point star prism (collectible stars, dizzy stars, confetti).
static func star(outer_radius: float = 0.5, inner_radius: float = 0.22, thickness: float = 0.18, points: int = 5) -> ArrayMesh:
	var key := "star_%.3f_%.3f_%.3f_%d" % [outer_radius, inner_radius, thickness, points]
	if _cache.has(key):
		return _cache[key]
	var outline: Array[Vector2] = []
	for i in points * 2:
		var angle := PI * 0.5 + TAU * float(i) / float(points * 2)
		var r := outer_radius if i % 2 == 0 else inner_radius
		outline.append(Vector2(cos(angle), sin(angle)) * r)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := thickness * 0.5
	var front_center := Vector3(0, 0, half * 1.6)  # puffy front
	var back_center := Vector3(0, 0, -half * 1.6)
	var n := outline.size()
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		var af := Vector3(a.x, a.y, half)
		var bf := Vector3(b.x, b.y, half)
		var ab := Vector3(a.x, a.y, -half)
		var bb := Vector3(b.x, b.y, -half)
		# front fan (counter-clockwise seen from +Z)
		_tri(st, front_center, af, bf)
		# back fan
		_tri(st, back_center, bb, ab)
		# side wall
		_tri(st, af, ab, bb)
		_tri(st, af, bb, bf)
	st.generate_normals()
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot uses clockwise winding for front faces.
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)


## Convenience: a MeshInstance3D with mesh, material and transform in one call.
static func make(mesh: Mesh, material: Material, position: Vector3 = Vector3.ZERO,
		scale: Vector3 = Vector3.ONE, rotation_degrees: Vector3 = Vector3.ZERO,
		casts_shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = position
	mi.scale = scale
	mi.rotation_degrees = rotation_degrees
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func clear_cache() -> void:
	_cache.clear()
