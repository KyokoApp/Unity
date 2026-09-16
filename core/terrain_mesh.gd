class_name TerrainMesh
extends RefCounted

## ============================================================
## TERRAIN MESH — pembuat grid chunk dari WorldData.terrain_h().
## (Port dari TerrainMesh.cs.)
##
## Hasilnya Dictionary array polos (Packed*Array), bukan ArrayMesh,
## jasi bisa dibangun di WORKER THREAD (RPG.Core setara tidak
## menyentuh RenderingServer) dan dites tanpa scene. Konversi ke
## ArrayMesh terjadi di runtime/terrain_chunk_streamer.gd (main
## thread).
##
## DUA sifat yang wajib dijaga (ada tesnya):
##
## 1. TIDAK ADA RETAKAN antar chunk.
##    Chunk (cx,cz) verteks i=quads berada di x = (cx+1)*CHUNK_SIZE,
##    persis sama dengan chunk (cx+1,cz) verteks i=0. Karena
##    terrain_h() fungsi murni dari (x,z) dan dihitung double,
##    tingginya identik. Resolusi seragam di semua chunk — LOD
##    beda-beda akan menimbulkan retakan (ditolak, sama seperti
##    keputusan di C#).
##
## 2. NORMAL TIDAK BOLEH BERJAHIT.
##    Normal dari selisih terhingga terrain_h, BUKAN cross-product
##    segitiga mesh — normal jadi fungsi kontinu di seluruh dunia.
##
## Urutan segitiga: sama dengan versi C# (A,C,B) lalu (C,D,B) —
## cross(C-A, B-A) menghadap +Y di ruang tangan-kanan y-up.
## Material terrain memakai cull_disabled jadi urutan ini bukan
## syarat visibilitas, hanya kebersihan geometri.
## ============================================================

## 32 quad = 8 m per segitiga pada CHUNK_SIZE 256 m.
## Komponen berfrekuensi tertinggi di terrain_h adalah
## `12*sin(x*.012)*cos(z*.01)` dengan panjang gelombang 2*pi/0.012
## = 524 m. Sampling 8 m = ~65 sampel per gelombang — jauh di atas
## Nyquist. (16 quad = kandidat tier rendah, komentar sama di C#.)
const DEFAULT_QUADS := 32

## Batas atas yang aman. 64 quad = 4 m, 4.225 verteks per chunk.
const MAX_QUADS := 64

static func chunk_in_world(cx: int, cz: int) -> bool:
	var s := WorldData.CHUNK_SIZE
	return not (cx * s >= WorldData.WORLD_SIZE / 2.0 or (cx + 1) * s <= -WorldData.WORLD_SIZE / 2.0 \
		or cz * s >= WorldData.WORLD_SIZE / 2.0 or (cz + 1) * s <= -WorldData.WORLD_SIZE / 2.0)

static func chunk_index(world_coord: float) -> int:
	return int(floor(world_coord / WorldData.CHUNK_SIZE))

## Bangun satu chunk. Mengembalikan Dictionary kosong ({}) kalau
## chunk di luar dunia — pemanggil tidak perlu mengecek batas.
## quads di luar 1..MAX_QUADS -> push_error + {} (padanan throw di C#).
static func build(cx: int, cz: int, quads: int = DEFAULT_QUADS) -> Dictionary:
	if quads < 1 or quads > MAX_QUADS:
		push_error("TerrainMesh.build: quads harus 1..%d, dapat %d" % [MAX_QUADS, quads])
		return {}
	if not chunk_in_world(cx, cz):
		return {}

	var size := WorldData.CHUNK_SIZE
	var step := size / quads
	var ox := cx * size
	var oz := cz * size
	var n: int = quads + 1

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var triangles := PackedInt32Array()
	vertices.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	uvs.resize(n * n)
	triangles.resize(quads * quads * 6)

	var e := TerrainSurface.GRADIENT_EPSILON

	for j in n:
		for i in n:
			var x := ox + i * step
			var z := oz + j * step
			var h := WorldData.terrain_h(x, z)

			# Gradien lewat selisih terhingga pusat. Sengaja TIDAK dari
			# grid mesh: grid 8 m melembutkan transisi tepi sungai.
			var dx := (WorldData.terrain_h(x + e, z) - WorldData.terrain_h(x - e, z)) / (2.0 * e)
			var dz := (WorldData.terrain_h(x, z + e) - WorldData.terrain_h(x, z - e)) / (2.0 * e)

			var vi: int = j * n + i
			# normal permukaan y = h(x,z) -> normalize(-dh/dx, 1, -dh/dz)
			var nrm := Vector3(-dx, 1.0, -dz).normalized()
			var col := TerrainSurface.color_at(x, z, h, sqrt(dx * dx + dz * dz),
											   WorldData.terrain_color(x, z))

			vertices[vi] = Vector3(x, h, z)
			normals[vi] = nrm
			colors[vi] = Color(col.x, col.y, col.z, 1.0)
			uvs[vi] = Vector2(float(i) / quads, float(j) / quads)

	var t := 0
	for j in quads:
		for i in quads:
			var a: int = j * n + i
			var b: int = j * n + (i + 1)
			var c: int = (j + 1) * n + i
			var d: int = (j + 1) * n + (i + 1)
			triangles[t] = a;  t += 1
			triangles[t] = c;  t += 1
			triangles[t] = b;  t += 1
			triangles[t] = c;  t += 1
			triangles[t] = d;  t += 1
			triangles[t] = b;  t += 1

	return {
		"cx": cx, "cz": cz, "quads": quads,
		"origin_x": ox, "origin_z": oz, "step": step,
		"vertices": vertices, "normals": normals,
		"colors": colors, "uvs": uvs, "triangles": triangles,
		"vertex_count": n * n,
		"triangle_count": quads * quads * 2,
	}

## Tinggi persis di sebuah titik dunia — dipakai character_motor supaya
## karakter menempel ke permukaan yang sama dengan mesh-nya.
static func height_at(x: float, z: float) -> float:
	return WorldData.terrain_h(x, z)
