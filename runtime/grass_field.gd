class_name GrassField
extends Node3D

## ============================================================
## GRASS FIELD — rumput stylized (gradasi pangkal->ujung, goyangan
## angin, tanpa tekstur) digambar sebagai 2 MultiMeshInstance3D
## (LOD dekat 4 bilah & jauh 3 quad silang).
## (Port dari GrassField.cs — DrawMeshInstanced -> MultiMesh.)
##
## Perbaikan yang dipertahankan dari versi Unity:
## [1] CACHE SEL: sel 8 m dipertahankan; yang jauh dibuang, yang
##     baru dibangun (bukan Clear tiap pindah sel).
## [2] LOD DUA TINGKAT: dekat = rumpun 4 bilah, jauh = 3 quad
##     silang (2,6x lebih murah).
## [3] Penempatan deterministik lewat Hash3 (bukan Random acak) —
##     sel yang sama selalu menghasilkan rumput yang sama.
## ============================================================

@export var target: Node3D
@export var grass_material: Material
@export_range(10.0, 60.0) var radius: float = 30.0
## Ukuran sel cache. 8 m = setengah chunk terrain... dibagi 32x.
@export var cell_size: float = 8.0
@export_range(4, 96) var per_cell_base: int = 26
@export_range(6.0, 40.0) var lod_distance: float = 14.0

var active_clumps: int:
	get: return _near_count + _far_count
var active_cells: int:
	get: return _near.size() + _far.size()

var _mmi_near: MultiMeshInstance3D
var _mmi_far: MultiMeshInstance3D
var _near: Dictionary = {}   ## key(int) -> Array[Transform3D]
var _far: Dictionary = {}
var _near_count := 0
var _far_count := 0
var _last_cx := -2147483648
var _last_cz := -2147483648
var _per_cell := 0
var _on := false

func _ready() -> void:
	ensure_init()

## Inisialisasi idempoten (sama seperti EnsureInit di C#).
func ensure_init() -> void:
	if _mmi_near != null:
		return
	var resolved := GfxResolver.resolve(SettingsStore.load(), _is_touch())
	_on = resolved["grass_enabled"]
	if not _on:
		return

	var scale := 0.0
	if resolved["grass_count"] > 0 and per_cell_base > 0:
		scale = float(resolved["grass_count"]) / (per_cell_base * _cell_count())
	_per_cell = maxi(4, int(round(per_cell_base * scale)))

	if grass_material == null:
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/aurelia_grass.gdshader") as Shader
		mat.set_shader_parameter("fade_start", lod_distance * 1.57)
		mat.set_shader_parameter("fade_end", radius)
		grass_material = mat

	_mmi_near = _make_mmi(BuildClumpMesh.build(), "GrassNear", radius + cell_size)
	_mmi_far = _make_mmi(BuildClumpMesh.build_far(), "GrassFar", radius * 6.0)
	add_child(_mmi_near)
	add_child(_mmi_far)

	if target == null:
		target = get_tree().get_first_node_in_group("player") as Node3D

func _make_mmi(mesh: Mesh, nama: String, _vis: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nama
	mmi.multimesh = mm
	mmi.material_override = grass_material
	# Tidak melempar bayangan (seperti versi Unity — biaya shadow
	# pass rumput 3 cm tidak sepadan) dan jangan ikut GI.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mmi

## Dipanggil panel pengaturan / quality_applier setelah preset berubah.
func refresh_settings() -> void:
	var resolved := GfxResolver.resolve(SettingsStore.load(), _is_touch())
	_on = resolved["grass_enabled"]
	var scale := 0.0
	if resolved["grass_count"] > 0 and per_cell_base > 0:
		scale = float(resolved["grass_count"]) / (per_cell_base * _cell_count())
	_per_cell = maxi(4, int(round(per_cell_base * scale)))
	_near.clear()
	_far.clear()
	_last_cx = -2147483648
	if not _on and _mmi_near != null:
		_mmi_near.multimesh.instance_count = 0
		_mmi_far.multimesh.instance_count = 0

func set_enabled_by_quality(on: bool) -> void:
	if on:
		ensure_init()
		refresh_settings()
	else:
		_on = false
		if _mmi_near != null:
			_mmi_near.multimesh.instance_count = 0
			_mmi_far.multimesh.instance_count = 0

func _cell_count() -> int:
	var n := int(ceil(radius / cell_size))
	var c := 0
	for x in range(-n, n + 1):
		for z in range(-n, n + 1):
			if x * x + z * z <= n * n:
				c += 1
	return c

## Dipanggil tiap frame saat bermain: perbarui sel lalu gambar.
func _process(_delta: float) -> void:
	draw_now()

## Diagnosa ringkas — dipakai perf_hud.
func init_state() -> String:
	return "on=%s clump=%s target=%s per_cell=%d cells=%d" % [
		_on, _mmi_near != null, target != null, _per_cell, active_cells]

## Dipakai WorldBoot: bangun sel awal sinkron sebelum loading selesai.
func populate_now() -> void:
	ensure_init()
	if not _on or target == null:
		return
	_refresh_cells(target.global_position, true)
	_flush()

func draw_now() -> void:
	ensure_init()
	if not _on or _mmi_near == null or target == null:
		return
	_refresh_cells(target.global_position, false)
	_flush()

func _refresh_cells(p: Vector3, force: bool) -> void:
	var cx := int(floor(p.x / cell_size))
	var cz := int(floor(p.z / cell_size))
	if not force and cx == _last_cx and cz == _last_cz and active_cells > 0:
		return
	_last_cx = cx
	_last_cz = cz

	var n := int(ceil(radius / cell_size))
	var wanted := {}
	var near_r2 := lod_distance * lod_distance
	for x in range(-n, n + 1):
		for z in range(-n, n + 1):
			if x * x + z * z > n * n:
				continue
			var sx: int = cx + x
			var sz: int = cz + z
			var k := _key(sx, sz)
			wanted[k] = true
			if _near.has(k) or _far.has(k):
				continue
			var forms := _place_cell(sx, sz, p)
			if forms.is_empty():
				continue
			var ccx := (sx + 0.5) * cell_size
			var ccz := (sz + 0.5) * cell_size
			var d2 := (ccx - p.x) * (ccx - p.x) + (ccz - p.z) * (ccz - p.z)
			if d2 <= near_r2:
				_near[k] = forms
			else:
				_far[k] = forms

	for k in _near.keys():
		if not wanted.has(k):
			_near.erase(k)
	for k in _far.keys():
		if not wanted.has(k):
			_far.erase(k)

func _flush() -> void:
	_near_count = _flush_set(_near, _mmi_near)
	_far_count = _flush_set(_far, _mmi_far)

func _flush_set(cells: Dictionary, mmi: MultiMeshInstance3D) -> int:
	var mm := mmi.multimesh
	var total := 0
	for k in cells:
		total += cells[k].size()
	mm.instance_count = total
	var i := 0
	for k in cells:
		for xf in cells[k]:
			mm.set_instance_transform(i, xf)
			i += 1
	return total

func _key(x: int, z: int) -> int:
	return x * 100000 + z

func _place_cell(cx: int, cz: int, focus: Vector3) -> Array:
	# Hamparan padat di dekat pemain lalu menipis — anggaran instance
	# yang SAMA dibagi berbeda, supaya kesan "padang rumput" terbaca.
	var ccx := (cx + 0.5) * cell_size
	var ccz := (cz + 0.5) * cell_size
	var d := Vector2(ccx, ccz).distance_to(Vector2(focus.x, focus.z))
	var t := smoothstep(0.0, 1.0, clampf(d / radius, 0.0, 1.0))
	var count := maxi(3, int(round(_per_cell * lerpf(2.6, 0.30, t))))
	var list := []
	var ox := cx * cell_size
	var oz := cz * cell_size

	for i in count:
		var hx := _hash3(cx, cz, i * 3)
		var hz := _hash3(cx, cz, i * 3 + 1)
		var hr := _hash3(cx, cz, i * 3 + 2)

		var x := ox + hx * cell_size
		var z := oz + hz * cell_size

		var y := WorldData.terrain_h(x, z)
		if y < WorldData.WATER_LEVEL + 0.25:
			continue
		var y2 := WorldData.terrain_h(x + 1.0, z)
		var y3 := WorldData.terrain_h(x, z + 1.0)
		if absf(y2 - y) > 0.9 or absf(y3 - y) > 0.9:
			continue

		var yaw := hr * TAU
		var scale := 0.75 + _hash3(cx, cz, i * 5 + 1) * 0.65
		list.append(Transform3D(
			Basis.from_euler(Vector3(0, yaw, 0)).scaled(Vector3(scale, scale, scale)),
			Vector3(x, y - 0.04, z)))
	return list

## Hash integer deterministik: sel yang sama selalu menghasilkan
## rumput yang sama (port dari Hash3 di GrassField.cs).
## Hash integer deterministik: sel yang sama selalu menghasilkan
## rumput yang sama (port dari Hash3 di GrassField.cs, aritmetika
## int32-wrap — GDScript int 64-bit di-mask & 0xFFFFFFFF, low-32-bit
## hasil perkalian 64-bit identik dengan overflow int32 C#).
static func _hash3(x: int, z: int, i: int) -> float:
	var n: int = (x * 127 + z * 311 + i * 741 + 1013) & 0xFFFFFFFF
	n = ((n << 13) ^ n) & 0xFFFFFFFF
	var nn: int = (n * n) & 0xFFFFFFFF
	nn = (nn * 15731 + 789221) & 0xFFFFFFFF
	var v: int = (n * nn + 1376312589) & 0x7fffffff
	return float(v) / float(0x7fffffff)

func _is_touch() -> bool:
	return DisplayServer.is_touchscreen_available()

## ============================================================
## PEMBANGUN MESH RUMPUT — dipisah supaya bisa dites headless.
## LOD DEKAT: rumpun 4 bilah meruncing (24 vertex, 16 segitiga).
## LOD JAUH: 3 quad silang (12 vertex, 6 segitiga).
## uv.y = tinggi normalized untuk gradasi + amplitudo angin.
## (Port dari BuildClump/BuildFarClump di GrassField.cs.)
## ============================================================
class BuildClumpMesh:
	extends RefCounted

	static func build() -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

		for b in 4:
			var yaw := deg_to_rad(b * 90.0 + b * 17.0)
			var tilt := deg_to_rad(14.0 + b * 5.0)
			var h: float = 0.30 + b * 0.05
			var w := 0.05
			var rot := Basis.from_euler(Vector3(0, yaw, 0))
			var lean := Basis.from_euler(Vector3(0, 0, tilt))
			var fwd := rot * lean * Vector3.FORWARD
			var side := rot * Vector3.RIGHT

			var ys := [0.0, h * 0.55, h]
			var ws := [w, w * 0.62, 0.004]
			var cu := [0.0, 0.05, 0.16]
			var tv := [0.0, 0.55, 1.0]

			var base: Array = []
			for s in 3:
				var center: Vector3 = rot * lean * Vector3(0, ys[s], cu[s])
				base.append([center - side * ws[s], center + side * ws[s], tv[s]])
			for s in 2:
				var l0: Array = base[s]
				var l1: Array = base[s + 1]
				_quad(st, l0[0], l0[1], l1[0], l1[1], l0[2], l1[2], b / 3.0, fwd)
		return st.commit()

	static func build_far() -> ArrayMesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for b in 3:
			var yaw := deg_to_rad(b * 60.0 + b * 13.0)
			var rot := Basis.from_euler(Vector3(0, yaw, 0))
			var side := rot * Vector3.RIGHT
			var fwd := rot * Vector3.FORWARD
			var w := 0.17
			var h := 0.34
			var v0 := -side * w
			var v1 := side * w
			var v2 := -side * w * 0.55 + Vector3.UP * h
			var v3 := side * w * 0.55 + Vector3.UP * h
			_quad_uv(st, v0, v1, v2, v3, fwd,
					 Vector2(0, 0), Vector2(1, 0), Vector2(0.2, 1), Vector2(0.8, 1))
		return st.commit()

	## Dua segitiga (cara menulis quad) dengan uv.y = tinggi.
	static func _quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3,
					  v3: Vector3, t0: float, t1: float, bu: float, n: Vector3) -> void:
		_quad_uv(st, v0, v1, v2, v3, n,
				 Vector2(bu, t0), Vector2(bu, t0), Vector2(bu, t1), Vector2(bu, t1))

	static func _quad_uv(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3,
						 v3: Vector3, n: Vector3, uv0: Vector2, uv1: Vector2,
						 uv2: Vector2, uv3: Vector2) -> void:
		var verts := [v0, v1, v2, v2, v1, v3]
		var uvs := [uv0, uv1, uv2, uv2, uv1, uv3]
		for i in 6:
			st.set_normal(n)
			st.set_uv(uvs[i])
			st.add_vertex(verts[i])
