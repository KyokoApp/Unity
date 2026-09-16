class_name TerrainSurface
extends RefCounted

## ============================================================
## TERRAIN SURFACE — warna permukaan tanah, murni dari posisi.
## (Port dari TerrainSurface.cs — lihat sana untuk catatan lengkap.)
##
## SEMUA AMBANG DI BAWAH DIUKUR, bukan dikira.
## Sumber angka: pengukuran atas 361.201 titik sampel tiap 5 m di
## seluruh dunia 3 km:
##
##     tinggi   min -10,0 | maks 249,3 | rata-rata 40,6
##              p1=-5,0  p25=17,5  p50=33,3  p75=48,0  p95=131,9
##     di bawah permukaan air (y<0)     7,41%
##     gradien  p50=0,113  p75=0,192  p90=0,420  p95=0,960
##
## Konsekuensi:
##   - dasar air datar di -5 -> garis pantai di sekitar y=0,
##     jalur pasir tipis saja cukup.
##   - salju mulai di 150 m hanya menutupi ~1-2% dunia: puncak
##     pegunungan utara (ramp `north` ada di -z).
##   - batu mulai di gradien 0,35 -> ~10% dunia berbatu.
## ============================================================

## ---- jalur pasir / garis pantai ----
const SHORE_BOTTOM := -3.0   ## di bawah ini: lumpur dasar air
const SHORE_TOP    :=  3.5   ## di atas ini: tidak ada pasir
const SILT_TOP     := -1.5   ## batas lumpur -> pasir basah

## ---- batu (dipicu kemiringan, bukan ketinggian) ----
const ROCK_START := 0.35     ## ~19 derajat
const ROCK_FULL  := 0.95     ## ~43 derajat, = p95 terukur

## ---- salju ----
const SNOW_START     := 150.0 ## antara p95 (131,9) dan p99 (215,0)
const SNOW_FULL      := 200.0
const SNOW_SLOPE_OFF := 1.10  ## lereng terjal tidak menahan salju
const SNOW_SLOPE_ON  := 0.45

## ---- jalan ----
const ROAD_CORE_EDGE := 0.0   ## RoadInfo.edge <= 0 = badan jalan
const ROAD_FADE_EDGE := 24.0  ## bahu jalan memudar sampai sini
## CATATAN: terrain_h() meratakan tanah pakai `1 - smooth(4, 42, edge)`.
## Jalur warna sengaja lebih sempit (0..24) daripada jalur perataan
## (4..42) supaya warna jalan selalu berada DI DALAM area yang sudah
## datar — tidak ada jalan berwarna yang menggantung di tebing.

const SAND:     Vector3 = Vector3(0.76, 0.70, 0.52)
const WET_SAND: Vector3 = Vector3(0.44, 0.40, 0.32)
const SILT:     Vector3 = Vector3(0.22, 0.25, 0.22)
const ROCK:     Vector3 = Vector3(0.42, 0.41, 0.40)
const SNOW:     Vector3 = Vector3(0.93, 0.95, 0.98)
const ROAD_C:   Vector3 = Vector3(0.47, 0.42, 0.34)
const ROAD_EDGE_V: Vector3 = Vector3(0.38, 0.36, 0.29)

static func _clamp01(v: float) -> float:
	return 0.0 if v < 0.0 else (1.0 if v > 1.0 else v)

static func _smooth(a: float, b: float, v: float) -> float:
	var t := _clamp01((v - a) / (b - a))
	return t * t * (3.0 - 2.0 * t)

## Gradien magnitudo |grad h| lewat selisih terhingga pusat.
## Epsilon 0,5 m: cukup kecil untuk menangkap kemiringan nyata,
## cukup besar agar tidak dikuasai noise floating point.
const GRADIENT_EPSILON := 0.5

static func gradient_at(x: float, z: float) -> float:
	var e := GRADIENT_EPSILON
	var dx := (WorldData.terrain_h(x + e, z) - WorldData.terrain_h(x - e, z)) / (2.0 * e)
	var dz := (WorldData.terrain_h(x, z + e) - WorldData.terrain_h(x, z - e)) / (2.0 * e)
	return sqrt(dx * dx + dz * dz)

static func rock_amount(gradient: float) -> float:
	return _smooth(ROCK_START, ROCK_FULL, gradient)

## Salju butuh ketinggian DAN lereng landai.
static func snow_amount(height: float, gradient: float) -> float:
	var by_height := _smooth(SNOW_START, SNOW_FULL, height)
	if by_height <= 0.0:
		return 0.0
	var by_slope := 1.0 - _smooth(SNOW_SLOPE_ON, SNOW_SLOPE_OFF, gradient)
	return by_height * by_slope

static func road_amount(x: float, z: float) -> float:
	return 1.0 - _smooth(ROAD_CORE_EDGE, ROAD_FADE_EDGE, WorldData.road_info(x, z)["edge"])

## Warna akhir. `base_color` = WorldData.terrain_color(x,z) — diterima
## sebagai parameter supaya fungsi ini tetap murah untuk ribuan verteks.
static func color_at(x: float, z: float, height: float, gradient: float, base_color: Vector3) -> Vector3:
	var c := base_color

	# 1. dasar air / garis pantai
	if height < SHORE_TOP:
		var t := _smooth(SHORE_BOTTOM, SHORE_TOP, height)
		var low := SILT if height < SILT_TOP else WET_SAND
		c = low * (1.0 - t) + c * t
		var sand_t := _smooth(SILT_TOP, SHORE_TOP, height) * (1.0 - _smooth(SHORE_TOP - 1.2, SHORE_TOP, height))
		c = c * (1.0 - sand_t) + SAND * sand_t

	# 2. batu di lereng
	var rock := rock_amount(gradient)
	if rock > 0.0:
		c = c * (1.0 - rock) + ROCK * rock

	# 3. salju di puncak
	var snow := snow_amount(height, gradient)
	if snow > 0.0:
		c = c * (1.0 - snow) + SNOW * snow

	# 4. jalan — ditumpuk terakhir
	var road := road_amount(x, z)
	if road > 0.0:
		var core := _smooth(ROAD_CORE_EDGE, ROAD_CORE_EDGE + 6.0, WorldData.road_info(x, z)["edge"])
		var road_col := ROAD_C * (1.0 - core) + ROAD_EDGE_V * core
		c = c * (1.0 - road) + road_col * road

	return Vector3(_clamp01(c.x), _clamp01(c.y), _clamp01(c.z))

## Bentuk ringkas: hitung gradien sendiri (untuk preview & tes).
static func color_at_simple(x: float, z: float) -> Vector3:
	var h := WorldData.terrain_h(x, z)
	return color_at(x, z, h, gradient_at(x, z), WorldData.terrain_color(x, z))
