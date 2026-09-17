class_name WorldScatter
extends RefCounted

## ============================================================
## WORLD SCATTER — port dari game/world-stream.mjs bagian build()
## + penempatan/pengambilan orb dari index.html (lewat C#).
##
## Yang diport HANYA keputusannya: apa yang ditaruh, di mana,
## seberapa besar, menghadap ke mana, dan collider-nya. Pembuatan
## mesh ada di runtime/prop_field.gd.
##
## CATATAN FIDELITAS — BACA SEBELUM MENGUBAH APA PUN:
##
## 1. URUTAN KONSUMSI RNG ADALAH KONTRAK. x, z, scale, lalu
##    (rock? yaw : yaw-daun). Kalau satu saja geser, SEMUA properti
##    setelahnya pindah tempat.
##
## 2. `random()<.22 || region.id==='amber'` — operand KIRI dievaluasi
##    lebih dulu, jadi random() SELALU dikonsumsi meski region amber.
##
## 3. Cabang `continue` (terlalu rendah / dekat jalan / dekat
##    waypoint) terjadi SETELAH x, z, scale diambil tapi SEBELUM
##    yaw — iterasi yang dilewati tetap menghabiskan 3 angka acak.
## ============================================================

const PROP_TRUNK := 0
const PROP_LEAF := 1
const PROP_PINE := 2
const PROP_ROCK := 3

const ORB_COUNT := 12.0
## Radius ambil orb. Di JS: mode==='car' ? 4.0 : 2.4.
## Game ini tanpa mobil, jadi yang dipakai selalu 2.4.
const ORB_PICKUP_RADIUS := 2.4
const ORB_PICKUP_HEIGHT := 3.8
const ORB_BOB_AMOUNT := 0.22
const ORB_BOB_SPEED := 1.6

## Port setia dari loop sebar properti di world-stream.mjs.
## Mengembalikan { "props": [prop...], "colliders": [collider...] }
## prop: {kind, x, y, z, sx, sy, sz, yaw, foliage, has_foliage}
##   (posisi LOKAL terhadap chunk, persis seperti JS)
## collider: {x, z, r} — koordinat DUNIA.
static func build(cx: int, cz: int, near: bool, props_near: int, props_far: int) -> Dictionary:
	var props := []
	var colliders := []

	var random := WorldData.random_for_chunk(cx, cz)
	var ox := cx * WorldData.CHUNK_SIZE
	var oz := cz * WorldData.CHUNK_SIZE
	var count := props_near if near else props_far

	for i in count:
		var x := random.next() * WorldData.CHUNK_SIZE
		var z := random.next() * WorldData.CHUNK_SIZE
		var wx := x + ox
		var wz := z + oz
		var y := WorldData.terrain_h(wx, wz)
		var scale := .65 + random.next() * 1.05
		var region := WorldData.region_at(wx, wz)

		# Urutan tiga syarat ini disimpan sama seperti aslinya.
		if y < 2.0 or WorldData.road_info(wx, wz)["edge"] < 10.0 or _any_waypoint_within(wx, wz, 70.0):
			continue

		# PENTING: random() dikonsumsi LEBIH DULU, selalu.
		# Lihat catatan fidelitas #2 di atas.
		if random.next() < .22 or region["id"] == "amber":
			var yaw := random.next() * 6.28
			props.append({"kind": PROP_ROCK, "x": x, "y": y + scale, "z": z,
						  "sx": scale * 2.0, "sy": scale * 1.5, "sz": scale * 1.7,
						  "yaw": yaw, "foliage": 0, "has_foliage": false})
			if near:
				colliders.append({"x": wx, "z": wz, "r": scale * 1.7})
			continue

		props.append({"kind": PROP_TRUNK, "x": x, "y": y + 3.5 * scale, "z": z,
					  "sx": scale, "sy": scale, "sz": scale,
					  "yaw": 0.0, "foliage": 0, "has_foliage": false})

		var pine: bool = region["id"] == "frost" or region["id"] == "highlands"
		var type_yaw := random.next() * 6.28
		var sy := scale if pine else .85 * scale
		props.append({"kind": PROP_PINE if pine else PROP_LEAF,
				  "x": x, "y": y + 8.0 * scale, "z": z,
				  "sx": scale, "sy": sy, "sz": scale,
				  "yaw": type_yaw, "foliage": region["foliage"], "has_foliage": true})
		# Kanopi Genshin bukan SATU bola — mahkota dibuat 3 lobus:
		# 1 utama + 2 pendamping di sekeliling puncak. Offset diturunkan
		# dari hash integer POSISI (bukan dari stream `random` — jumlah
		# konsumsi RNG tetap, layout chunk lama tidak bergeser).
		if not pine:
			for k in 2:
				var frak := _lohash(int(wx * 7.0 + wz * 13.0), i * 3 + k)
				var ox2 := (frak - 0.5) * 2.4 * scale
				var oz2 := (_lohash(int(wz * 9.0 - wx * 5.0), i * 5 + k)
					- 0.5) * 2.4 * scale
				var s2 := scale * (0.42 + 0.30
					* _lohash(int(wx * 11.0 + wz * 3.0), i * 7 + k))
				props.append({"kind": PROP_LEAF,
						  "x": x + ox2, "y": y + (7.1 + 1.5 * float(k)) * scale,
						  "z": z + oz2, "sx": s2, "sy": 0.78 * s2, "sz": s2,
						  "yaw": frak * 6.28, "foliage": region["foliage"],
						  "has_foliage": true})
		if near:
			colliders.append({"x": wx, "z": wz, "r": .65 * scale})

	return {"props": props, "colliders": colliders}

## Hash deterministik bebas-struktur (salah satu putaran mix-murmur
## ringan) — dipakai offset lobus kanopi TANPA menyentuh ChunkRng.
static func _lohash(a: int, b: int) -> float:
	var n: int = (a * 374761393 + b * 668265263) & 0xFFFFFFFF
	n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
	return float((n ^ (n >> 16)) & 0xFFFFFFFF) / 4294967296.0

## WAYPOINTS.some(w => hypot(wx-w.x, wz-w.z) < r)
static func _any_waypoint_within(wx: float, wz: float, r: float) -> bool:
	for w in WorldData.waypoints():
		var d := sqrt((wx - w["x"]) * (wx - w["x"]) + (wz - w["z"]) * (wz - w["z"]))
		if d < r:
			return true
	return false

## Penempatan 12 orb dari index.html:469-476. Murni deterministik:
## waypoint[i % 7], geser +-18 di x, mundur 25 + 55 per putaran.
## Y sudah termasuk +1.1.
static func place_orbs() -> Array:
	var list := []
	var wps := WorldData.waypoints()
	for i in int(ORB_COUNT):
		var w: Dictionary = wps[i % wps.size()]
		var x: float = w["x"] + (18.0 if i % 2 == 1 else -18.0)
		var z: float = w["z"] - 25.0 - floor(i / float(wps.size())) * 55.0
		var y := WorldData.terrain_h(x, z)
		list.append({"x": x, "y": y + 1.1, "z": z, "base_y": y + 1.1})
	return list

## Gerakan naik-turun orb: baseY + sin(t*1.6 + position.x)*0.22.
## Catatan: JS memakai o.position.x yang SUDAH berupa koordinat dunia.
static func orb_y(base_y: float, world_x: float, t: float) -> float:
	return base_y + sin(t * ORB_BOB_SPEED + world_x) * ORB_BOB_AMOUNT

## Syarat pengambilan, index.html:1461-1462 (cabang non-mobil).
static func orb_collectible(orb_x: float, orb_y: float, orb_z: float,
							player_x: float, player_z: float, ground_y: float) -> bool:
	var d := sqrt((orb_x - player_x) * (orb_x - player_x) + (orb_z - player_z) * (orb_z - player_z))
	return d < ORB_PICKUP_RADIUS and absf(orb_y - (ground_y + 1.0)) < ORB_PICKUP_HEIGHT
