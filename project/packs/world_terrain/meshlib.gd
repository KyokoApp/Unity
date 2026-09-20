extends RefCounted
## MeshLib: pembangun mesh prosedural low-poly dengan vertex color,
## dipakai oleh pack props (pohon, batu, bangunan). Semua statis.

## Beri warna vertex seragam ke arrays hasil PrimitiveMesh.
static func colorize(arrays: Array, color: Color) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols := PackedColorArray()
	cols.resize(verts.size())
	cols.fill(color)
	arrays = arrays.duplicate(true)
	arrays[Mesh.ARRAY_COLOR] = cols
	return arrays

static func from_box(size: Vector3, color: Color) -> Array:
	var bm := BoxMesh.new()
	bm.size = size
	var a: Array = bm.get_mesh_arrays()
	return colorize(a, color)

static func from_cyl(r_top: float, r_bot: float, h: float, seg: int, color: Color) -> Array:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	var a: Array = cm.get_mesh_arrays()
	return colorize(a, color)

static func from_cone(radius: float, h: float, seg: int, color: Color) -> Array:
	return from_cyl(0.0, radius, h, seg, color)

static func from_sphere(radius: float, radial: int, rings: int, color: Color) -> Array:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = radial
	sm.rings = rings
	var a: Array = sm.get_mesh_arrays()
	return colorize(a, color)

static func from_plane(size: Vector2, color: Color, double_sided_mesh := false) -> Array:
	var pm := PlaneMesh.new()
	pm.size = size
	var a: Array = pm.get_mesh_arrays()
	a = colorize(a, color)
	if double_sided_mesh:
		var ids: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var rev := PackedInt32Array()
		for i in range(0, ids.size(), 3):
			rev.append_array([ids[i], ids[i + 2], ids[i + 1]])
		ids.append_array(rev)
		a = a.duplicate(true)
		a[Mesh.ARRAY_INDEX] = ids
	return a

## Muat aset luar (.gltf/.glb) dan ambil ArrayMesh pertama (model KayKit = 1 mesh).
## Mengembalikan {mesh, offset_y} — offset_y agar kaki model menyentuh y=0.
static func load_external_mesh(path: String) -> Dictionary:
	var res = load(path)
	if res == null:
		push_warning("MeshLib: aset gagal dimuat: " + path)
		return {}
	var root: Node = res.instantiate() if res is PackedScene else res
	var mi := _find_mesh_instance(root)
	if mi == null or mi.mesh == null:
		if root is Node:
			root.free()
		push_warning("MeshLib: tidak ada MeshInstance3D di " + path)
		return {}
	var mesh: ArrayMesh = mi.mesh
	var aabb: AABB = mesh.get_aabb()
	if root is Node:
		root.free()
	return {"mesh": mesh, "offset_y": -aabb.position.y, "size": aabb.size}

static func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var mi := _find_mesh_instance(c)
		if mi != null:
			return mi
	return null

## Skala agar tinggi AABB = target_h meter.
static func fit_scale(info: Dictionary, target_h: float) -> float:
	if info.is_empty() or float(info["size"].y) <= 0.001:
		return 1.0
	return target_h / float(info["size"].y)

## Deformasi bola/recak menjadi batu tak beraturan (deterministik dari seed).
static func deform(a: Array, seed: int, strength: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	a = a.duplicate(true)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var bump := {}
	for i in range(verts.size()):
		var key := [snappedf(verts[i].x, 0.001), snappedf(verts[i].y, 0.001), snappedf(verts[i].z, 0.001)]
		if not bump.has(key):
			bump[key] = rng.randf_range(-strength, strength)
		verts[i] += normals[i] * bump[key]
	a[Mesh.ARRAY_VERTEX] = verts
	return a

## Pindahkan/rotasi arrays (transformasi pada vertex & normal).
static func xform(a: Array, t: Transform3D) -> Array:
	a = a.duplicate(true)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var bs := t.basis.orthonormalized()
	for i in range(verts.size()):
		verts[i] = t * verts[i]
		normals[i] = (bs * normals[i]).normalized()
	a[Mesh.ARRAY_VERTEX] = verts
	a[Mesh.ARRAY_NORMAL] = normals
	return a

## Gabung banyak arrays (harus sama-sama punya COLOR) jadi satu arrays.
static func merge(list: Array) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for a in list:
		var base := verts.size()
		verts.append_array(a[Mesh.ARRAY_VERTEX])
		normals.append_array(a[Mesh.ARRAY_NORMAL])
		colors.append_array(a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray())
		for idx in a[Mesh.ARRAY_INDEX]:
			indices.append(base + idx)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = colors
	out[Mesh.ARRAY_INDEX] = indices
	return out

static func to_mesh(arrays: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

## Rampingkan pohon beringin: batang + beberapa bola daun.
static func make_broadleaf_tree(rng: RandomNumberGenerator) -> Array:
	var trunk_c := Color(0.50, 0.36, 0.26)
	var leaf_a := Color(0.25, 0.58, 0.42)
	var leaf_b := Color(0.34, 0.66, 0.48)
	var parts := []
	var trunk_h := rng.randf_range(2.2, 3.2)
	var trunk := from_cyl(0.14, 0.24, trunk_h, 6, trunk_c)
	parts.append(xform(trunk, Transform3D(Basis(), Vector3(0, trunk_h * 0.5, 0))))
	var blobs := 3 + rng.randi_range(0, 2)
	for i in range(blobs):
		var r := rng.randf_range(0.9, 1.5)
		var off := Vector3(rng.randf_range(-0.9, 0.9), trunk_h + rng.randf_range(-0.2, 0.9), rng.randf_range(-0.9, 0.9))
		var s := from_sphere(r, 7, 5, leaf_a.lerp(leaf_b, rng.randf()))
		s = deform(s, rng.randi(), 0.12)
		var t := Transform3D(Basis.from_scale(Vector3(1.0, rng.randf_range(0.75, 0.95), 1.0)), off)
		parts.append(xform(s, t))
	return merge(parts)

static func make_pine_tree(rng: RandomNumberGenerator) -> Array:
	var trunk_c := Color(0.40, 0.28, 0.18)
	var pine_a := Color(0.16, 0.40, 0.33)
	var pine_b := Color(0.19, 0.46, 0.36)
	var parts := []
	var th := rng.randf_range(0.8, 1.2)
	parts.append(xform(from_cyl(0.12, 0.18, th, 6, trunk_c), Transform3D(Basis(), Vector3(0, th * 0.5, 0))))
	var layers := 3
	var y := th * 0.7
	var r := rng.randf_range(1.1, 1.4)
	for i in range(layers):
		var h := rng.randf_range(1.0, 1.3)
		parts.append(xform(from_cone(r, h, 8, pine_a.lerp(pine_b, rng.randf())),
				Transform3D(Basis(), Vector3(0, y + h * 0.5, 0))))
		y += h * 0.72
		r *= 0.68
	return merge(parts)

static func make_rock(rng: RandomNumberGenerator) -> Array:
	var s := from_sphere(rng.randf_range(0.35, 0.8), 7, 5, Color(0.50, 0.48, 0.45))
	s = deform(s, rng.randi(), 0.16)
	var flat := rng.randf_range(0.55, 0.8)
	return xform(s, Transform3D(Basis.from_scale(Vector3(1.0, flat, 0.9)), Vector3(0, 0.1, 0)))

static func make_bush(rng: RandomNumberGenerator) -> Array:
	var s := from_sphere(rng.randf_range(0.3, 0.55), 7, 5, Color(0.22, 0.48, 0.20))
	s = deform(s, rng.randi(), 0.1)
	return xform(s, Transform3D(Basis.from_scale(Vector3(1.0, 0.75, 1.0)), Vector3(0, 0.22, 0)))

## Rumput: 3 quad menyilang (UV.y = tinggi untuk gradasi shader).
static func make_grass_tuft() -> Array:
	var parts := []
	var c := Color(1, 1, 1)
	for i in range(3):
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.5, 0.5)
		var a: Array = pm.get_mesh_arrays()
		a = colorize(a, c)
		var ang := float(i) * PI / 3.0
		var t := Transform3D(Basis(Vector3.UP, ang), Vector3(0, 0.25, 0))
		parts.append(xform(a, t))
	return merge(parts)

static func make_flower() -> Array:
	var parts := []
	var stem := from_cyl(0.02, 0.02, 0.28, 5, Color(0.25, 0.5, 0.2))
	parts.append(xform(stem, Transform3D(Basis(), Vector3(0, 0.14, 0))))
	for i in range(2):
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.22, 0.22)
		var a: Array = pm.get_mesh_arrays()
		a = colorize(a, Color(0.95, 0.55, 0.75))
		var ang := float(i) * PI / 2.0
		parts.append(xform(a, Transform3D(Basis(Vector3.UP, ang), Vector3(0, 0.3, 0))))
	return merge(parts)

## Pohon kelapa: batang melengkung + daun palem + kelapa.
static func make_palm(rng: RandomNumberGenerator) -> Array:
	var trunk_c := Color(0.55, 0.41, 0.30)
	var leaf_c := Color(0.22, 0.58, 0.45)
	var parts := []
	var h := rng.randf_range(3.0, 4.2)
	var bend := Vector3(rng.randf_range(-0.05, 0.05), 0, 0)
	var nseg := 5
	var prev := Vector3(0, h / nseg, 0)
	var top := Vector3()
	for i in range(nseg):
		bend.x += rng.randf_range(0.05, 0.16)
		var p0 := prev * (1.0 / nseg) * i
		var p1 := prev * (1.0 / nseg) * (i + 1) + Vector3(bend.x, 0, 0) * (h / nseg)
		var seg := from_cyl(0.10, 0.13, h / nseg * 1.05, 6, trunk_c)
		var mid := (p0 + p1) * 0.5
		seg = xform(seg, Transform3D(Basis(), mid))
		parts.append(seg)
		top = p1
	var nleaf := 6
	for i in range(nleaf):
		var ang := float(i) / nleaf * TAU + rng.randf_range(-0.15, 0.15)
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.55, 2.4)
		pm.subdivide_depth = 3
		var a: Array = pm.get_mesh_arrays()
		a = colorize(a, leaf_c)
		# melengkungkan daun
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		for vi in range(verts.size()):
			var yy := verts[vi].y
			verts[vi].z += pow(abs(yy) / 2.4, 2.0) * -0.7 * sign(yy)
		var tb := Basis(Vector3.UP, ang) * Basis(Vector3.RIGHT, -0.5)
		parts.append(xform(a, Transform3D(tb, top + Vector3(0, 0.15, 0))))
	# kelapa
	for i in range(rng.randi_range(2, 4)):
		var cn := from_sphere(0.14, 6, 4, Color(0.42, 0.30, 0.16))
		parts.append(xform(cn, Transform3D(Basis(), top - Vector3(rng.randf_range(-0.2, 0.2), 0.32, rng.randf_range(-0.2, 0.2)))))
	return merge(parts)

## Prisma sederhana untuk atap.
static func make_roof_prism(size: Vector3, color: Color) -> Array:
	var hx := size.x * 0.5
	var hy := size.y
	var hz := size.z * 0.5
	var v := PackedVector3Array([
		Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz),  # 0,1 bawah belakang
		Vector3(-hx, 0, hz), Vector3(hx, 0, hz),    # 2,3 bawah depan
		Vector3(0, hy, -hz), Vector3(0, hy, hz),    # 4,5 puncak
	])
	var idx := PackedInt32Array([
		0, 4, 1,  # belakang
		2, 3, 5,
		0, 2, 4, 2, 5, 4,  # sisi kiri
		1, 4, 3, 3, 4, 5,  # sisi kanan
	])
	var n := PackedVector3Array()
	n.resize(v.size())
	var nrm := []
	var cols := PackedColorArray()
	cols.resize(v.size())
	cols.fill(color)
	for i in range(0, idx.size(), 3):
		var p0: Vector3 = v[idx[i]]
		var p1: Vector3 = v[idx[i + 1]]
		var p2: Vector3 = v[idx[i + 2]]
		var fn: Vector3 = (p1 - p0).cross(p2 - p0).normalized()
		n[idx[i]] = fn
		n[idx[i + 1]] = fn
		n[idx[i + 2]] = fn
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = v
	out[Mesh.ARRAY_NORMAL] = n
	out[Mesh.ARRAY_COLOR] = cols
	out[Mesh.ARRAY_INDEX] = idx
	return out
