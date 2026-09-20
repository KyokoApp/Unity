extends Node3D
## TerrainChunk: satu kotak terrain (mesh visual + collision opsional).
## Data mesh dibangun di worker thread (build_mesh_data), node dirakit di main.

const CHUNK_SIZE := 100.0
const PHYS_RES := 16  # 16x16 sel fisika (17x17 titik)
const GRID_HALF := 4  # = GRID/2 world (dunia 8x8 chunk 100m); setengah pusat indeks

var cx: int
var cz: int
var lod: int = -1
var mesh_instance: MeshInstance3D
var body: StaticBody3D
var height_data := PackedFloat32Array()

func world_rect() -> Rect2:
	return Rect2(Vector2(cx - GRID_HALF, cz - GRID_HALF) * CHUNK_SIZE, Vector2(CHUNK_SIZE, CHUNK_SIZE))

func apply_mesh(mesh: ArrayMesh, material: Material, heights: PackedFloat32Array) -> void:
	height_data = heights
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mesh_instance.visibility_range_end_margin = 0.0
		add_child(mesh_instance)
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material

func set_collision(enabled: bool, island) -> void:
	if enabled and body == null and height_data.size() == (PHYS_RES + 1) * (PHYS_RES + 1):
		body = StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var shape := HeightMapShape3D.new()
		shape.map_width = PHYS_RES + 1
		shape.map_depth = PHYS_RES + 1
		shape.map_data = height_data
		col.shape = shape
		body.add_child(col)
		# skala XZ supaya 16 sel = 100 m; shape dipusatkan di tengah chunk
		var step: float = CHUNK_SIZE / PHYS_RES
		body.scale = Vector3(step, 1.0, step)
		body.position = Vector3((cx - GRID_HALF) * CHUNK_SIZE + CHUNK_SIZE * 0.5, 0.0,
				(cz - GRID_HALF) * CHUNK_SIZE + CHUNK_SIZE * 0.5)
		add_child(body)
	elif not enabled and body != null:
		body.queue_free()
		body = null

## Bangun ulang shape fisika setelah edit terrain (tanpa membuat node baru).
func refresh_collision(island) -> void:
	if body == null:
		return
	var shape := HeightMapShape3D.new()
	shape.map_width = PHYS_RES + 1
	shape.map_depth = PHYS_RES + 1
	shape.map_data = height_data
	(body.get_child(0) as CollisionShape3D).shape = shape

## Dibangun di worker thread. LOD: 0=48, 1=24, 2=12, 3=6 quads/sisi.
static func build_mesh_data(island, pcx: int, pcz: int, plod: int) -> Dictionary:
	var res: int = [48, 24, 12, 6][plod]
	var x0: float = (pcx - GRID_HALF) * CHUNK_SIZE
	var z0: float = (pcz - GRID_HALF) * CHUNK_SIZE
	var step: float = CHUNK_SIZE / res
	var n: int = res + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	var idx: int = 0
	var nan_n: int = 0
	var hmin: float = 1e9
	var hmax: float = -1e9
	for j in range(n):
		for i in range(n):
			var x: float = x0 + i * step
			var z: float = z0 + j * step
			var h: float = island.height_at(x, z)
			if is_nan(h) or is_inf(h):
				h = 0.0
				nan_n += 1
			var nrm: Vector3 = island.normal_at(x, z, maxf(step * 0.5, 0.8))
			if is_nan(nrm.x) or is_nan(nrm.y) or is_nan(nrm.z):
				nrm = Vector3.UP
				nan_n += 1
			verts[idx] = Vector3(x, h, z)
			normals[idx] = nrm
			colors[idx] = island.color_at(x, z, h)
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
			idx += 1
	var indices := PackedInt32Array()
	indices.resize(res * res * 6)
	var k: int = 0
	for j in range(res):
		for i in range(res):
			var a: int = j * n + i
			var b: int = a + 1
			var c: int = a + n
			var d: int = c + 1
			indices[k] = a; indices[k + 1] = c; indices[k + 2] = b
			indices[k + 3] = b; indices[k + 4] = c; indices[k + 5] = d
			k += 6
	# skirt: cincin turun di tepi untuk menyembunyikan retakan LOD
	var skirt: float = step * 0.8
	var base_count: int = verts.size()
	var skirt_index := []
	var edges := []
	for i in range(n):
		edges.append(i)
	for j in range(1, n):
		edges.append(j * n + (n - 1))
	for i in range(n - 2, -1, -1):
		edges.append((n - 1) * n + i)
	for j in range(n - 2, 0, -1):
		edges.append(j * n)
	for e in edges:
		var v: Vector3 = verts[e]
		verts.append(Vector3(v.x, v.y - skirt, v.z))
		normals.append(normals[e])
		colors.append(colors[e])
		skirt_index.append(e)
	var sidx := PackedInt32Array()
	var ec: int = edges.size()
	for t in range(ec):
		var t2: int = (t + 1) % ec
		var top_a: int = edges[t]
		var top_b: int = edges[t2]
		var bot_a: int = base_count + t
		var bot_b: int = base_count + t2
		sidx.append_array([top_a, bot_a, top_b, top_b, bot_a, bot_b])
	indices.append_array(sidx)
	# data fisika (resolusi tetap)
	var heights := PackedFloat32Array()
	heights.resize((PHYS_RES + 1) * (PHYS_RES + 1))
	var pstep: float = CHUNK_SIZE / PHYS_RES
	var hi: int = 0
	for j in range(PHYS_RES + 1):
		for i in range(PHYS_RES + 1):
			heights[hi] = island.height_at(x0 + i * pstep, z0 + j * pstep)
			hi += 1
	return {"verts": verts, "normals": normals, "colors": colors,
			"indices": indices, "heights": heights,
			"stats_nan": nan_n, "stats_hmin": hmin, "stats_hmax": hmax,
			"stats_v": verts.size()}

## Merangkai ArrayMesh dari data (dipanggil di main thread; murah).
static func make_mesh(data: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data["verts"]
	arrays[Mesh.ARRAY_NORMAL] = data["normals"]
	arrays[Mesh.ARRAY_COLOR] = data["colors"]
	arrays[Mesh.ARRAY_INDEX] = data["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
