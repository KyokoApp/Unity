class_name BuildRoadBuilder
extends RefCounted
## ROAD SYSTEM (butir 4 user): tiap jalan = Path3D + Curve3D di bawah satu
## container "BuiltRoads". Tiap tap tanah (mode Jalan) menambah titik ke
## curve yg sedang dibuat (curve.add_point), lalu MESH jalan dibuat ulang
## prosedural dg SurfaceTool mengikuti titik-titik curve (lebar dari slider
## UI). Tombol "Selesai" meng-KUNCI curve tsb; tap berikutnya otomatis
## mulai curve BARU utk jalan lain.
##
## Perf mobile: mesh ribbon flat poligon ringan (2 segitiga per meter),
## dibangun ulang HANYA saat titik ditambah/selesai (bukan per-frame);
## material dibagi satu. Tanpa Curve3D welding antar jalan (hemat).

var world: Node3D
var container: Node3D

var road_width := 3.0              # m — slider UI (2..8)
var active_curve: Curve3D = null   # curve yg sedang digambar (null = antar-road)
var active_path: Path3D = null
var active_mesh: MeshInstance3D = null
var roads: Array = []              # [{points:[Vector3], width, path, mesh}]
var _material: StandardMaterial3D

const ROAD_Y := 0.055              # tinggi visual jalan di atas tanah (anti z-fight)
const BAKE_STEP := 0.9             # rapat sampel curve (m/pasangan segitiga)

func setup(p_world: Node3D) -> void:
	world = p_world
	container = Node3D.new()
	container.name = "BuiltRoads"
	world.add_child(container)
	_material = StandardMaterial3D.new()
	# tanah padat agak kecoklatan (spt tanah diinjak) supaya terbaca sebagai
	# JALAN di atas ladang pastel tanpa norak; sedikit kemerahan tanah liat.
	_material.albedo_color = Color(0.48, 0.38, 0.26)
	_material.roughness = 0.98
	_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

func set_width(w: float) -> void:
	road_width = clampf(w, 1.5, 8.0)
	# rebuild live road aktif supaya perasaan slider "lebar" langsung wujud
	if active_curve != null and active_curve.point_count >= 2:
		_rebuild_mesh(active_curve, active_mesh, road_width)

## ---------------- penambahan titik & penyelesaian ----------------

## Tap tanah di mode Jalan: kalau belum ada curve aktif -> mulai BARU;
## lalu tambahkan titik (snap Y=0: jalan di bidang datar permainan).
func add_point(world_pos: Vector3) -> void:
	if active_curve == null:
		active_path = Path3D.new()
		active_path.name = "RoadDraft"
		active_curve = Curve3D.new()
		active_curve.bake_interval = BAKE_STEP
		active_path.curve = active_curve
		container.add_child(active_path)
		active_mesh = MeshInstance3D.new()
		active_mesh.name = "RoadDraftMesh"
		active_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		active_path.add_child(active_mesh)
	active_curve.add_point(Vector3(world_pos.x, 0.0, world_pos.z))
	if active_curve.point_count >= 2:
		_rebuild_mesh(active_curve, active_mesh, road_width)

## Tombol "Selesai": kunci curve aktif ke daftar jalan permanen.
func finish() -> bool:
	if active_curve == null or active_curve.point_count < 2:
		return false
	var pts: Array = []
	for i in active_curve.point_count:
		pts.append(active_curve.get_point_position(i))
	active_path.name = "Road_%d" % roads.size()
	roads.append({"points": pts, "width": road_width, "path": active_path, "mesh": active_mesh})
	active_curve = null
	active_path = null
	active_mesh = null
	return true

## Batalkan draft curve aktif tanpa menyimpan (mis. salah taruh).
func cancel_draft() -> void:
	if active_path != null and is_instance_valid(active_path):
		active_path.queue_free()
	active_curve = null
	active_path = null
	active_mesh = null

## Delete mode: tap dekat suatu jalan -> hapus SELURUH jalan itu.
func delete_at(world_pos: Vector3) -> bool:
	var best := -1
	var bd := INF
	for i in roads.size():
		var pts: Array = roads[i]["points"]
		# kedekatan ke titik-titik curve (murah; smooth cukup utk seleksi)
		for p in pts:
			var d := (Vector3(p.x, 0, p.z) - Vector3(world_pos.x, 0, world_pos.z)).length()
			if d < bd:
				bd = d
				best = i
	# toleransi: setengah lebar jalan + sedikit
	if best >= 0 and bd <= float(roads[best]["width"]) * 0.5 + 2.0:
		var r: Dictionary = roads[best]
		if is_instance_valid(r["path"]):
			r["path"].queue_free()
		roads.remove_at(best)
		return true
	return false

## ---------------- generasi mesh ribbon ----------------

## Buat strip segitiga sepanjang curve: tiap titik sampel -> 2 vertex
## (kiri-kanan tegak lurus tangen, di bidang XZ). UV.y = panjang tempuh.
## Normal di-set manual ke Vector3.UP (jalan rata) — shading konsisten
## tanpa peduli winding segitiga, lbh murah drpd generate_normals().
func _rebuild_mesh(curve: Curve3D, mesh_node: MeshInstance3D, width: float) -> void:
	var pts: PackedVector3Array = curve.get_baked_points()
	if pts.size() < 2:
		return
	# buffer samping tiap titik dulu (tahap 1) supaya quad lurus menyambung
	var sides: Array = []
	var dists: Array = [0.0]
	var half := width * 0.5
	var up := Vector3.UP
	for i in pts.size():
		var t := _tangent_at(pts, i)
		var side := up.cross(t)
		if side.length_squared() < 0.0001:
			side = sides[i - 1] if i > 0 else Vector3.RIGHT
		sides.append(side.normalized())
		if i > 0:
			dists.append(float(dists[i - 1]) + (pts[i] - pts[i - 1]).length())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var yv := Vector3(0, ROAD_Y, 0)
	for i in range(1, pts.size()):
		var l0 := pts[i - 1] - sides[i - 1] * half + yv
		var r0 := pts[i - 1] + sides[i - 1] * half + yv
		var l1 := pts[i] - sides[i] * half + yv
		var r1 := pts[i] + sides[i] * half + yv
		var u0 := float(dists[i - 1]) / width
		var u1 := float(dists[i]) / width
		# quad = 2 segitiga (normal up manual + uv panjang-tempuh)
		var verts: Array = [
			[l1, Vector2(0.0, u1)], [r1, Vector2(1.0, u1)], [l0, Vector2(0.0, u0)],
			[l0, Vector2(0.0, u0)], [r1, Vector2(1.0, u1)], [r0, Vector2(1.0, u0)],
		]
		for pair in verts:
			st.set_normal(up)
			st.set_uv(pair[1])
			st.add_vertex(pair[0])
	st.set_material(_material)
	mesh_node.mesh = st.commit()

## Tangen lokal di sampel i (selisih tetangga supaya halus di tengah).
func _tangent_at(pts: PackedVector3Array, i: int) -> Vector3:
	if i == 0:
		return (pts[1] - pts[0]).normalized()
	if i == pts.size() - 1:
		return (pts[i] - pts[i - 1]).normalized()
	return (pts[i + 1] - pts[i - 1]).normalized()

## ---------------- Save / Load ----------------

func collect_data() -> Array:
	var out: Array = []
	for r in roads:
		var packed_pts: Array = []
		for p in r["points"]:
			packed_pts.append(BuildSaveLoad.pack_vec3(p))
		out.append({"points": packed_pts, "width": snappedf(float(r["width"]), 0.01)})
	return out

func clear_all() -> void:
	for c in container.get_children():
		c.queue_free()
	roads.clear()
	cancel_draft()

func restore(data: Array) -> void:
	clear_all()
	for d in data:
		var w := float(d.get("width", 3.0))
		# mulai curve baru per jalan
		active_curve = null
		for pa in d.get("points", []):
			add_point(BuildSaveLoad.unpack_vec3(pa))
		if active_mesh != null:
			_rebuild_mesh(active_curve, active_mesh, w)
		# simpan sbg road permanen dg width-nya sendiri
		if active_curve != null and active_curve.point_count >= 2:
			var saved_width := road_width
			road_width = w
			finish()
			road_width = saved_width
