extends RefCounted
## Island: model prosedural pulau (heightmap + bioma).
## Deterministik dari seed, dan aman dipanggil konkuren dari worker thread
## (semua fungsi query bersifat read-only setelah _init).

const SEA_LEVEL := 0.0
var world_seed: int
var half: float                 # setengah ukuran dunia (m)
var n_base: FastNoiseLite
var n_hill: FastNoiseLite
var n_moist: FastNoiseLite
var n_detail: FastNoiseLite
var river_points := PackedVector2Array()
var lake_center := Vector2()
var lake_radius := 85.0
# field jarak-sungai: grid 200x200 @8m, ditandai dari polyline (runtime O(1))
const RF_GRID := 200
const RF_STEP := 8.0
var _river_field := PackedFloat32Array()

enum BIOME { SEA, BEACH, GRASS, FOREST, ROCK, HILL }

func _init(seed: int = 20260919, size_m: float = 1600.0) -> void:
	world_seed = seed
	half = size_m * 0.5
	n_base = FastNoiseLite.new()
	n_base.seed = seed
	n_base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_base.frequency = 0.0016
	n_base.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_base.fractal_octaves = 4
	n_base.fractal_gain = 0.55
	n_base.fractal_lacunarity = 2.1
	n_hill = FastNoiseLite.new()
	n_hill.seed = seed * 7 + 13
	n_hill.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_hill.frequency = 0.0021
	n_hill.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	n_hill.fractal_octaves = 3
	n_moist = FastNoiseLite.new()
	n_moist.seed = seed * 31 + 7
	n_moist.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_moist.frequency = 0.0019
	n_moist.fractal_octaves = 3
	n_detail = FastNoiseLite.new()
	n_detail.seed = seed * 101 + 3
	n_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_detail.frequency = 0.016
	n_detail.fractal_octaves = 2
	lake_center = Vector2(-0.28 * half, 0.14 * half)
	_compute_river()

## Sungai: gradient-descent dari titik tinggi sampai laut.
func _compute_river() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 5 + 77
	# cari titik mulai agak tinggi di pedalaman
	var start := Vector2()
	var best := -1.0
	for i in range(300):
		var p := Vector2(rng.randf_range(-0.45, 0.45), rng.randf_range(-0.45, 0.45)) * half
		var h := _land_height(p.x, p.y)
		if h > best:
			best = h
			start = p
	var pts := PackedVector2Array()
	var pos := start
	pts.append(pos)
	var step := 14.0
	var ang := rng.randf_range(0.0, TAU)
	for i in range(220):
		var g := _gradient(pos.x, pos.y)
		var target := -atan2(g.y, g.x)  # arah menurun
		# belok halus dengan noise agar berkelok
		ang = lerp_angle(ang, target, 0.25) + n_moist.get_noise_2d(pos.x * 0.05, pos.y * 0.05) * 0.35
		pos += Vector2(cos(ang), sin(ang)) * step
		pts.append(pos)
		if _land_height(pos.x, pos.y) < 0.2 or pos.length() > half:
			break
	# teruskan sedikit ke laut supaya muara tembus pantai
	if pts.size() >= 2:
		var dir := (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
		pts.append(pos + dir * step * 2.0)
		pts.append(pos + dir * step * 4.0)
	river_points = pts
	_build_river_field()

## Bangun grid jarak-segmen-sungai: rapatkan polyline (2m), tandai radius 64m.
func _build_river_field() -> void:
	_river_field.resize(RF_GRID * RF_GRID)
	_river_field.fill(1e9)
	if river_points.size() < 2:
		return
	var dense := PackedVector2Array()
	for i in range(river_points.size() - 1):
		var a := river_points[i]
		var b := river_points[i + 1]
		var seg := b - a
		var n := maxi(1, int(ceil(seg.length() / 2.0)))
		for j in range(n):
			dense.append(a + seg * (float(j) / n))
	dense.append(river_points[river_points.size() - 1])
	const R := 64.0
	var rc := int(ceil(R / RF_STEP))
	for p in dense:
		var cx := int(round((p.x + half) / RF_STEP))
		var cz := int(round((p.y + half) / RF_STEP))
		for dz in range(cz - rc, cz + rc + 1):
			for dx in range(cx - rc, cx + rc + 1):
				if dx < 0 or dz < 0 or dx >= RF_GRID or dz >= RF_GRID:
					continue
				var posc := Vector2(dx * RF_STEP - half, dz * RF_STEP - half)
				var d := p.distance_to(posc)
				var idx := dz * RF_GRID + dx
				if d < _river_field[idx]:
					_river_field[idx] = d

func _gradient(x: float, z: float) -> Vector2:
	var e := 6.0
	return Vector2(
		_land_height(x + e, z) - _land_height(x - e, z),
		_land_height(x, z + e) - _land_height(x, z - e)) / (2.0 * e)

func _dist_to_river(x: float, z: float) -> float:
	if river_points.size() < 2:
		return 1e9
	var p := Vector2(x, z)
	var best := 1e9
	for i in range(river_points.size() - 1):
		var a := river_points[i]
		var b := river_points[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / max(ab.length_squared(), 0.001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best

## Tinggi dasar murni (tanpa ukir sungai/danau) — dipakai komputasi sungai.
func _land_height(x: float, z: float) -> float:
	var d := Vector2(x, z).length() / half
	var edge := clampf(1.0 - d, 0.0, 1.0)
	var shelf := smoothstep(0.0, 0.10, edge)
	var core := smoothstep(0.10, 0.42, edge)
	var e1: float = n_base.get_noise_2d(x, z) * 0.5 + 0.5
	var h := -9.0 * (1.0 - shelf) + shelf * 0.35
	h += core * (1.4 + e1 * 5.2)
	var hillv: float = n_hill.get_noise_2d(x, z) * 0.5 + 0.5
	var hill_mask := smoothstep(0.52, 0.8, hillv) * core * smoothstep(0.15, 0.4, e1)
	h += hill_mask * pow(hillv, 1.4) * 38.0
	h += n_detail.get_noise_2d(x, z) * 0.55 * core
	return h

## Tinggi final (dengan ukir sungai + danau). Ini API utama.
func height_at(x: float, z: float) -> float:
	var h := _land_height(x, z)
	# danau
	var dl := Vector2(x, z).distance_to(lake_center)
	if dl < lake_radius * 1.6:
		var lk := exp(-pow(dl / lake_radius, 2.0))
		h = lerpf(h, -2.8, clampf(lk * 0.9, 0.0, 1.0))
	# sungai
	var dr := _dist_to_river(x, z)
	if dr < 40.0 and h > SEA_LEVEL:
		var carve := 4.2 * exp(-pow(dr / 9.0, 2.0))
		var k := smoothstep(0.15, 1.6, h)  # tidak mengukir di bawah permukaan
		h -= carve * k
	return h

func normal_at(x: float, z: float, eps: float = 1.2) -> Vector3:
	var hl := height_at(x - eps, z)
	var hr := height_at(x + eps, z)
	var hd := height_at(x, z - eps)
	var hu := height_at(x, z + eps)
	return Vector3(hl - hr, 2.0 * eps, hd - hu).normalized()

func slope_at(x: float, z: float) -> float:
	return 1.0 - normal_at(x, z).y

func moisture_at(x: float, z: float) -> float:
	return n_moist.get_noise_2d(x, z) * 0.5 + 0.5

func is_river_near(x: float, z: float, r: float) -> bool:
	return _dist_to_river(x, z) < r

func biome_at(x: float, z: float, h: float = 9999.0) -> int:
	if h > 9000.0:
		h = height_at(x, z)
	if h < SEA_LEVEL + 0.05:
		return BIOME.SEA
	var s := slope_at(x, z)
	if h > 22.0 or s > 0.42:
		return BIOME.ROCK
	if h > 9.0 and s > 0.28:
		return BIOME.HILL
	if h < 0.95:
		return BIOME.BEACH
	var m := moisture_at(x, z)
	if m > 0.48 and h < 12.0:
		return BIOME.FOREST
	return BIOME.GRASS

## Warna vertex terrain untuk satu titik (campuran bioma).
func color_at(x: float, z: float, h: float) -> Color:
	var s := slope_at(x, z)
	var m := moisture_at(x, z)
	# palet mid-tone jenuh sedang
	var sand := Color(0.85, 0.76, 0.54)
	var grass_dry := Color(0.55, 0.66, 0.30)
	var grass_lush := Color(0.30, 0.60, 0.24)
	var forest := Color(0.22, 0.46, 0.20)
	var rock := Color(0.52, 0.50, 0.47)
	var seabed := Color(0.62, 0.68, 0.55)
	var c: Color
	if h < SEA_LEVEL + 0.05:
		c = seabed.lerp(sand, smoothstep(-3.0, 0.0, h))
	elif h < 0.95:
		c = sand
	else:
		var g := grass_dry.lerp(grass_lush, smoothstep(0.30, 0.75, m))
		c = g.lerp(forest, smoothstep(0.42, 0.75, m) * clampf(1.0 - s * 2.2, 0.0, 1.0))
		# campuran pasir di garis pantai
		c = sand.lerp(c, smoothstep(0.9, 1.8, h))
	# batuan pada lereng curam / tinggi
	var rk := smoothstep(0.32, 0.55, s)
	rk = maxf(rk, smoothstep(16.0, 26.0, h))
	c = c.lerp(rock, rk)
	# variasi lembut
	var v := n_detail.get_noise_2d(x * 1.7, z * 1.7) * 0.035
	c = c.lightened(v) if v > 0.0 else c.darkened(-v)
	return c

## Titik spawn di pantai: menyapu radial dari tepi ke dalam hingga pasir landai.
func find_spawn_point() -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 5150
	var ang0 := rng.randf_range(0.0, TAU)
	for attempt in range(60):
		var ang := ang0 + attempt * 0.11
		var dir := Vector2(cos(ang), sin(ang))
		var r := half
		while r > half * 0.1:
			var p := dir * r
			var h := height_at(p.x, p.y)
			if h > 0.3 and h < 1.1 and biome_at(p.x, p.y, h) == BIOME.BEACH and slope_at(p.x, p.y) < 0.12:
				if not is_river_near(p.x, p.y, 30.0):
					return Vector3(p.x, h, p.y)
			r -= 8.0
	# fallback aman
	return Vector3(0, maxf(height_at(0, 0), 1.0) + 0.5, 0)
