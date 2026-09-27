class_name BuildTerrainEditor
extends RefCounted
## TERRAIN / PERBUKITAN MODULAR (butir 3 user) — BUKAN free-sculpt:
## GridMap + MeshLibrary custom yang DIBANGUN RUNTIME (nol aset mesh file):
##   item 0 = Datar (blok 2x1x2, atas rata),
##   item 1 = Miring (ram naik 1 m ke satu arah, diputar 4 cara),
##   item 2 = Sudut (ram diagonal naik ke pojok sel, utk pinggir bukit).
##
## Tap di mode Terrain: manager lulus world_pos raycast plane y=0, di sini
## dikonversi ke sel GridMap (local_to_map) + level yg sedang dipilih (UI
## Level +/-), lalu gridmap.set_cell_item(sel, item, orientasi). Rotasi
## tile lewat tombol putar (0/90/180/270 derajat membaca basis GridMap).
##
## Kolisi: tiap tile-nya punya SHAPE (GridMap otomatis membangun body
## fisika per kuadran di game) -> bukit BISA DINAIKI pemain sungguhan,
## karena collider tanah dasar dunia hanyalah WorldBoundary bidang y=0.
## Perf mobile: GridMap = SATU node, sel digambar batched (bukan instans
## node per tile) -> puluhan-ribu sel masih ringan; material dibagi satu.

var world: Node3D
var gridmap: GridMap
var meshlib: MeshLibrary

var current_item := 0         # 0=datar, 1=miring, 2=sudut
var rot_idx := 0              # 0..3 = putaran 90 derajat searah jarum jam
var build_level := 0          # level Y sel target (atas-bawah bukit)
var cells_changed := {}       # Vector3i -> {item, rot} utk save/load cepat
var last_placed := {}         # {cell, prev} — prev {item,rot} sel lama|{} kosong (utk undo manager)
var last_erased := {}         # {cell,item,rot} — sel terakhir terhapus (utk undo manager)

const CELL := Vector3(2.0, 1.0, 2.0)   # ukuran sel GridMap (m)
const ITEM_FLAT := 0
const ITEM_SLOPE := 1
const ITEM_CORNER := 2

func setup(p_world: Node3D) -> void:
	world = p_world
	_build_mesh_library()
	gridmap = GridMap.new()
	gridmap.name = "BuiltTerrain"
	gridmap.mesh_library = meshlib
	gridmap.cell_size = CELL
	world.add_child(gridmap)

## ---------------------------------------------------------------
## MeshLibrary runtime: 3 item tile dari mesh bawaan/SurfaceTool.
## Warna material disamakan dgn ground_color tanah (pastel) supaya bukit
## MELEBUR visual dgn ladang (bukan kelihatan balok beton asing).
func _build_mesh_library() -> void:
	meshlib = MeshLibrary.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.285, 0.450, 0.260)   # = ground_color shader tanah
	mat.roughness = 0.95
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	# --- item 0: Datar (BoxMesh 2x1x2; transform dipindah +0.5 y supaya
	# titik-tumbuh sel = DASAR tile & permukaan atas pas 1 m di atasnya) ---
	meshlib.create_item(ITEM_FLAT)
	var box := BoxMesh.new()
	box.size = CELL
	box.material = mat
	meshlib.set_item_mesh(ITEM_FLAT, box)
	# Godot 4: transform mesh item DIPISAH dr set_item_mesh (Godot3-era
	# 3-arg dipangkas) — auto-compile guard CI fase-1 menolak yg lama.
	meshlib.set_item_mesh_transform(ITEM_FLAT, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	var flat_shape := BoxShape3D.new()
	flat_shape.size = CELL
	meshlib.set_item_shapes(ITEM_FLAT, [flat_shape, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))])

	# --- item 1+2: Miring & Sudut: mesh custom via SurfaceTool ---
	meshlib.create_item(ITEM_SLOPE)
	var slope_mesh := _make_ramp_mesh(mat, false)
	meshlib.set_item_mesh(ITEM_SLOPE, slope_mesh)
	meshlib.set_item_shapes(ITEM_SLOPE, [slope_mesh.create_trimesh_shape(), Transform3D.IDENTITY])

	meshlib.create_item(ITEM_CORNER)
	var corner_mesh := _make_ramp_mesh(mat, true)
	meshlib.set_item_mesh(ITEM_CORNER, corner_mesh)
	meshlib.set_item_shapes(ITEM_CORNER, [corner_mesh.create_trimesh_shape(), Transform3D.IDENTITY])

## Bangun mesh tile "ram". corner=false: naik linear sepanjang +X
## (h(-1)=0 -> h(+1)=1). corner=true: naik diagonal menuju pojok (+X,+Z),
## permukaan miring diagonal — dipakai utk pinggiran bukit membulat.
## Vertex basis y=0 = dasar tile; tinggi tile = CELL.y.
func _make_ramp_mesh(mat: Material, corner: bool) -> ArrayMesh:
	var h := CELL.y
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# titik-titik lantai (base) & ketinggian tiap pojok permukaan
	# slope   : h naik lurus sepanjang +X  -> A(-1,-1)=0, C(-1,1)=0, B(1,-1)=h, D(1,1)=h
	# corner  : h naik DIAGONAL ke pojok   -> A=0, B(1,-1)=0.5h, C(-1,1)=0.5h, D(1,1)=h
	var hA := 0.0
	var hB := 0.5 * h if corner else h
	var hC := 0.5 * h if corner else 0.0
	var hD := h
	# helper lokal tulis satu segitiga (CCW dilihat dr luar/atas)
	var tri := func(a: Vector3, b: Vector3, c: Vector3) -> void:
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	# permukaan atas (miring)
	var pA := Vector3(-1, hA, -1)
	var pB := Vector3( 1, hB, -1)
	var pC := Vector3(-1, hC,  1)
	var pD := Vector3( 1, hD,  1)
	tri.call(pA, pC, pD)
	tri.call(pA, pD, pB)
	# lantai (bawah — masih butuh walau tersembunyi supaya sisi belakang
	# tak "bolong" bila dilihat dari tepi bukit)
	tri.call(Vector3(-1, 0, 1), Vector3(-1, 0, -1), Vector3(1, 0, -1))
	tri.call(Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(1, 0, 1))
	# dinding +X (utuh: 2 segitiga dari tinggi dinamis pB->pD)
	tri.call(Vector3(1, 0, -1), pB, pD)
	tri.call(Vector3(1, 0, -1), pD, Vector3(1, 0, 1))
	# dinding -X (tinggi rendah pA->pC; bila corner, segitiga kecil saja)
	tri.call(Vector3(-1, 0, 1), pC, pA)
	tri.call(Vector3(-1, 0, 1), pA, Vector3(-1, 0, -1))
	# dinding -Z (depan)
	tri.call(Vector3(1, 0, -1), Vector3(-1, 0, -1), pA)
	tri.call(Vector3(1, 0, -1), pA, pB)
	# dinding +Z
	tri.call(Vector3(-1, 0, 1), Vector3(1, 0, 1), pD)
	tri.call(Vector3(-1, 0, 1), pD, pC)
	st.generate_normals()
	st.set_material(mat)
	return st.commit()

## ---------------------------------------------------------------
## API dari UI/manager

func set_item(i: int) -> void:
	current_item = clampi(i, 0, 2)

## Tombol putar: geser 90 derajat searah jarum jam; status dibaca UI (teks).
func rotate_item() -> int:
	rot_idx = (rot_idx + 1) % 4
	return rot_idx

func set_level(l: int) -> int:
	build_level = clampi(l, -4, 16)
	return build_level

## Koordinat sel GridMap utk world_pos (sel XZ dr posisi, level dr UI).
func _cell_of(world_pos: Vector3) -> Vector3i:
	var local := gridmap.to_local(world_pos)
	# sel XZ dari posisi, level Y dari pilihan UI (bukan dari tinggi tap,
	# supaya bukit bertingkat tetap intuitif dikontrol)
	return Vector3i(int(floor(local.x / CELL.x)), build_level, int(floor(local.z / CELL.z)))

## Isi sel sekarang (utk catatan undo) — {} bila kosong.
func state_at_cell(cell: Vector3i) -> Dictionary:
	if gridmap == null:
		return {}
	var item := gridmap.get_cell_item(cell)
	if item == GridMap.INVALID_CELL_ITEM:
		return {}
	return {"item": item, "rot": gridmap.get_cell_item_orientation(cell)}

## Tap di tanah (world_pos raycast manager): hitung sel GridMap, pasang/
## ganti tile di sel itu dengan item+rotasi sekarang. Sebelum menimpa,
## sel LAMA dicatat ke last_placed supaya aksi ini bisa di-undo manager.
func place_at(world_pos: Vector3) -> bool:
	if gridmap == null:
		return false
	var cell := _cell_of(world_pos)
	last_placed = {"cell": cell, "prev": state_at_cell(cell), "item": current_item, "rot": _orientation()}
	gridmap.set_cell_item(cell, current_item, _orientation())
	cells_changed[cell] = {"item": current_item, "rot": _orientation()}
	return true

## Pasang sel EKSPLISIT (undo "tile place" dg prev != kosong / "tile del").
func set_cell_explicit(cell: Vector3i, item: int, rot: int) -> void:
	if gridmap == null:
		return
	gridmap.set_cell_item(cell, item, rot)
	cells_changed[cell] = {"item": item, "rot": rot}

## Kosongkan sel (undo "tile place" dg prev kosong).
func clear_cell(cell: Vector3i) -> void:
	if gridmap == null:
		return
	if gridmap.get_cell_item(cell) != GridMap.INVALID_CELL_ITEM:
		gridmap.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)
	cells_changed.erase(cell)

## Delete mode: hapus tile di sel yg disentuh (level ikut yg sekarang;
## kalau kosong, coba level di bawah/atas 1 — bukit jarang rata).
func delete_at(world_pos: Vector3) -> bool:
	if gridmap == null:
		return false
	var local := gridmap.to_local(world_pos)
	var cx := int(floor(local.x / CELL.x))
	var cz := int(floor(local.z / CELL.z))
	var levels := [build_level, build_level - 1, build_level + 1, 0, 1, 2, 3]
	for l in levels:
		var cell := Vector3i(cx, l, cz)
		if gridmap.get_cell_item(cell) != GridMap.INVALID_CELL_ITEM:
			# catatan utk undo (manager): apa yg tepat dihapus
			last_erased = {"cell": cell, "item": gridmap.get_cell_item(cell), "rot": gridmap.get_cell_item_orientation(cell)}
			gridmap.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)
			cells_changed.erase(cell)
			return true
	return false

## indeks orientasi GridMap utk rot_idx (90° per langkah thd poros Y).
func _orientation() -> int:
	var b := Basis(Vector3.UP, rot_idx * PI * 0.5)
	return gridmap.get_orthogonal_index_from_basis(b.orthonormalized())

## ---------------------------------------------------------------
## Save / Load

func collect_data() -> Array:
	var out: Array = []
	for cell in cells_changed.keys():
		var d: Dictionary = cells_changed[cell]
		out.append([cell.x, cell.y, cell.z, d["item"], d["rot"]])
	return out

func clear_all() -> void:
	if gridmap:
		gridmap.clear()
	cells_changed.clear()

func restore(cells: Array) -> void:
	clear_all()
	if gridmap == null:
		return
	for a in cells:
		if a.size() < 5:
			continue
		var cell := Vector3i(int(a[0]), int(a[1]), int(a[2]))
		gridmap.set_cell_item(cell, int(a[3]), int(a[4]))
		cells_changed[cell] = {"item": int(a[3]), "rot": int(a[4])}
