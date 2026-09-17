class_name WorldData
extends RefCounted

## ============================================================
## WORLD DATA — port 1:1 dari game/world-data.mjs (lewat C#:
## Assets/_Project/Scripts/Core/WorldData.cs).
##
## Satu unit dunia = satu meter. Semua terrain/jalan deterministik
## dan di-sample di ruang dunia, jadi hasilnya identik di editor
## maupun di build, dan bisa dites headless tanpa scene.
##
## CATATAN FIDELITAS:
## - Math.imul / >>> di JS dipetakan ke aritmetika int GDScript
##   64-bit yang dimask & 0xFFFFFFFF — membungkus mod 2^32 persis
##   seperti JS (dan seperti `unchecked` di C#).
## - float di GDScript adalah double 64-bit, sama seperti C# double.
##   Vector3 dipakai HANYA untuk hasil akhir (warna/verteks).
## - sin/cos bisa beda beberapa ULP dari JS/C#. Tes memakai
##   toleransi, bukan kesamaan bit.
## ============================================================

const WORLD_SIZE: float = 3000.0   ## 24 km -> 12 km -> 6 km -> 3 km
const WORLD_LIMIT: float = WORLD_SIZE / 2.0 - 32.0
const CHUNK_SIZE: float = 256.0
const WATER_LEVEL: float = 0.0
const ROAD_SPACING: float = 750.0  ## 1500 hanya menyisakan lajur 0 & 1 di dunia 3 km

static func _clamp01(v: float) -> float:
	return maxf(0.0, minf(1.0, v))

static func _smooth(a: float, b: float, v: float) -> float:
	var t := _clamp01((v - a) / (b - a))
	return t * t * (3.0 - 2.0 * t)

## imul JS: perkalian 32-bit yang membuang bit tinggi.
static func _imul(a: int, b: int) -> int:
	return (a * b) & 0xFFFFFFFF

static func road_x(z: float, lane: int = 0) -> float:
	return lane * ROAD_SPACING + 70.0 * sin(z / 850.0)

static func road_z(x: float, lane: int = 0) -> float:
	return lane * ROAD_SPACING + 60.0 * sin(x / 600.0)

## Hasil sampling jalan (padanan struct RoadSample di C#).
## axis: "x" atau "z".
static func road_info(x: float, z: float) -> Dictionary:
	var lane_x := JsMath.round_to_int((x - road_x(z)) / ROAD_SPACING)
	var lane_z := JsMath.round_to_int((z - road_z(x)) / ROAD_SPACING)
	var dx: float = absf(x - road_x(z, lane_x))
	var dz: float = absf(z - road_z(x, lane_z))
	var wx := 8.0 if (absi(lane_x) % 2 == 0) else 4.0
	var wz := 8.0 if (absi(lane_z) % 2 == 0) else 4.0
	if dx - wx < dz - wz:
		return {"edge": dx - wx, "distance": dx, "half_width": wx,
				"along": z, "lane": lane_x, "axis": "z"}
	return {"edge": dz - wz, "distance": dz, "half_width": wz,
			"along": x, "lane": lane_z, "axis": "x"}

static func road_height(x: float, z: float) -> float:
	return 28.0 + 14.0 * sin(x * .0014) * cos(z * .0012) + 6.0 * sin((x + z) * .002)

static func terrain_h(x: float, z: float) -> float:
	var base_h := road_height(x, z)
	var north := _smooth(250.0, 1750.0, -z)   # diskala: dunia 1/16 luasnya
	var ridge := sin(x * .0028 + cos(z * .002)) * .5 + .5
	var h := base_h + 12.0 * sin(x * .012) * cos(z * .01) + 7.0 * sin((x - z) * .004)
	h += north * (45.0 + 180.0 * ridge * ridge) + 18.0 * sin(x * .0024) * sin(z * .0034)

	# Sungai menerus + dua danau lebar. Tanggul jalan tetap di atas air.
	var river: float = absf(x - (400.0 + 70.0 * sin(z * .002)))
	var lake_a := sqrt(pow((x + 1150.0) * .8, 2.0) + pow(z - 1150.0, 2.0))
	var lake_b := sqrt(pow(x - 1150.0, 2.0) + pow((z + 1150.0) * .8, 2.0))
	var wet := 1.0 - _smooth(30.0, 65.0, minf(river, minf(lake_a - 145.0, lake_b - 162.5)))
	h = h * (1.0 - wet) - 5.0 * wet

	var road := 1.0 - _smooth(4.0, 42.0, road_info(x, z)["edge"])
	return h * (1.0 - road) + base_h * road

## ---- Data 7 region (padanan class Region & array Regions di C#) ----
## color: rgb 0..1; foliage: 0xRRGGBB.
const REGIONS: Array = [
	{"id": "heartlands", "name": "Aurelia Heartlands", "subtitle": "Padang hijau & gerbang kerajaan", "x":    0.0, "z":    0.0, "color": Vector3(.36, .58, .23), "foliage": 0x729b53},
	{"id": "frost",      "name": "Frostspire Reach",   "subtitle": "Puncak es & menara penjaga",      "x": -750.0, "z": -750.0, "color": Vector3(.68, .76, .77), "foliage": 0x8eafb0},
	{"id": "highlands",  "name": "Crownfall Highlands","subtitle": "Pegunungan & reruntuhan kuno",    "x":    0.0, "z": -750.0, "color": Vector3(.43, .49, .42), "foliage": 0x58705b},
	{"id": "amber",      "name": "Amber Wastes",       "subtitle": "Bukit keemasan & kuil matahari",  "x":  750.0, "z": -750.0, "color": Vector3(.72, .56, .33), "foliage": 0xb88d4b},
	{"id": "forest",     "name": "Elderwood Wilds",    "subtitle": "Hutan tua & batu bercahaya",      "x": -750.0, "z":  750.0, "color": Vector3(.25, .43, .33), "foliage": 0x3c7963},
	{"id": "bloom",      "name": "Roseveil Expanse",   "subtitle": "Dataran bunga & pohon merah muda","x":    0.0, "z":  750.0, "color": Vector3(.49, .48, .39), "foliage": 0xba7993},
	{"id": "coast",      "name": "Azure Coast",        "subtitle": "Lembah sungai & kristal biru",    "x":  750.0, "z":  750.0, "color": Vector3(.46, .60, .47), "foliage": 0x6faca1},
]

static func region_at(x: float, z: float) -> Dictionary:
	var result: Dictionary = REGIONS[0]
	var best := INF
	for r in REGIONS:
		var d: float = (x - r["x"]) * (x - r["x"]) + (z - r["z"]) * (z - r["z"])
		if d < best:
			best = d
			result = r
	return result

## Campuran warna dua region terdekat (rgb 0..1 sebagai Vector3).
static func terrain_color(x: float, z: float) -> Vector3:
	var first: Dictionary = {}
	var second: Dictionary = {}
	var d1 := INF
	var d2 := INF
	for r in REGIONS:
		var d := sqrt(pow(x - r["x"], 2.0) + pow(z - r["z"], 2.0))
		if d < d1:
			second = first
			d2 = d1
			first = r
			d1 = d
		elif d < d2:
			second = r
			d2 = d
	var blend := .5 * (1.0 - _smooth(0.0, 450.0, d2 - d1))
	var outc := Vector3.ZERO
	for i in 3:
		outc[i] = first["color"][i] * (1.0 - blend) + second["color"][i] * blend
	return outc

## Titik persimpangan: diiterasi 12 kali supaya konvergen, sama seperti JS.
static func intersection(lane_x: int, lane_z: int) -> Vector2:
	var x := lane_x * ROAD_SPACING
	var z := lane_z * ROAD_SPACING
	for i in 12:
		x = road_x(z, lane_x)
		z = road_z(x, lane_z)
	return Vector2(x, z)

## Waypoint per region, dibangun sekali (padanan static Waypoints di C#).
static func waypoints() -> Array:
	var list := []
	for r in REGIONS:
		var p := intersection(JsMath.round_to_int(r["x"] / ROAD_SPACING),
							  JsMath.round_to_int(r["z"] / ROAD_SPACING))
		list.append({"region": r, "x": p.x, "z": p.y})
	return list

## ---- RNG deterministik per chunk ----
## Di JS/C# ini closure xorshift. Lambda GDScript menangkap variabel
## lingkup BY VALUE, jadi pola closure-mutable tidak bisa — RNG jadi
## kelas kecil. Semantik angkakan angkanya identik.
class ChunkRng:
	extends RefCounted
	var _n: int

	func _init(cx: int, cz: int) -> void:
		_n = ((cx * 73856093) & 0xFFFFFFFF) ^ ((cz * 19349663) & 0xFFFFFFFF) ^ 0x51f15e

	func next() -> float:
		_n = (_n + 0x6D2B79F5) & 0xFFFFFFFF
		var t: int = _n
		t = ((t ^ (t >> 15)) * (t | 1)) & 0xFFFFFFFF
		var m: int = ((t ^ (t >> 7)) * (t | 61)) & 0xFFFFFFFF
		t = (t ^ ((t + m) & 0xFFFFFFFF)) & 0xFFFFFFFF
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0

static func random_for_chunk(cx: int, cz: int) -> ChunkRng:
	return ChunkRng.new(cx, cz)

## Chunk yang harus dimuat, urut dari yang terdekat.
##
## PENTING — urutan untuk jarak yang SAMA harus mengikuti urutan
## penyisipan (dz luar, dx dalam), karena itulah yang dihasilkan JS:
## sejak V8 7.0 Array.prototype.sort DIJAMIN stabil. GDScript
## sort_custom setara List.Sort .NET: TIDAK stabil, jadi indeks
## penyisipan dipakai sebagai pemutus seri secara eksplisit.
static func chunk_plan(x: float, z: float, radius: int = 3) -> Array:
	var cx := int(floor(x / CHUNK_SIZE))
	var cz := int(floor(z / CHUNK_SIZE))
	var list := []
	var idx := 0
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var tx: int = cx + dx
			var tz: int = cz + dz
			if tx * CHUNK_SIZE >= WORLD_SIZE / 2.0 or (tx + 1) * CHUNK_SIZE <= -WORLD_SIZE / 2.0 \
			or tz * CHUNK_SIZE >= WORLD_SIZE / 2.0 or (tz + 1) * CHUNK_SIZE <= -WORLD_SIZE / 2.0:
				continue
			list.append({
				"cx": tx, "cz": tz, "key": "%d,%d" % [tx, tz],
				"near": maxi(absi(dx), absi(dz)) <= 1,
				"distance": dx * dx + dz * dz,
				"_order": idx,
			})
			idx += 1
	# (distance, insertion index) — deterministik & stabil persis V8.
	list.sort_custom(func(a, b):
		if a["distance"] != b["distance"]:
			return a["distance"] < b["distance"]
		return a["_order"] < b["_order"])
	for c in list:
		c.erase("_order")
	return list
