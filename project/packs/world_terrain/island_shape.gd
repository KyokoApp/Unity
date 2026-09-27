extends RefCounted
class_name IslandShape
## Bentuk pulau (permintaan user, ronde ini: "world perkecil ukuran nya jadi
## 1km x 1km") — SEBELUMNYA 3km (RADIUS=1500), sekarang RADIUS=460 (~1km
## diameter tipikal ± harmonik pantai). Garis pantai "alami" dibentuk dari jumlah beberapa gelombang
## sinus (harmonik) pada sudut (theta) di sekeliling pusat pulau, bukan noise
## acak biasa. Sengaja pakai sinus (bukan Perlin/noise texture) supaya
## RUMUS YANG SAMA PERSIS gampang disalin manual ke GLSL (grass_blade.gdshader
## & shader tanah di world.gd _make_ground_material) tanpa risiko hasil
## sedikit beda antar-bahasa seperti kalau pakai noise berbasis hash/texture.
##
## PENTING: kalau formula RADIUS/harmonik di sini diubah, WAJIB disamakan
## juga secara manual di kedua shader itu (dicari komentar "IslandShape" di
## sana) — GDScript & GLSL tidak bisa berbagi kode langsung.
##
## DANAU + SUNGAI (permintaan user, ronde ini: "ada aliran danau atau
## sungai"): ditambah 1 danau bundar + 1 sungai yg mengalir dari tepi danau
## itu ke laut, memakai TEKNIK SAMA (medan jarak + smoothstep, bukan mesh
## terpisah) — cukup diukur dari posisi dunia (x,z) makanya tetap murah &
## gampang disalin ke GLSL persis spt formula pantai. Sungai dibuat berkelok
## lewat 1 gelombang sinus tegak lurus arah alirannya (bukan garis lurus kaku).

const RADIUS := 460.0           # radius dasar sblm dibengkokkan harmonik (~1km diameter)
const BEACH_WIDTH := 55.0       # lebar pita pasir/transisi darat->air (pantai laut)
const COAST_MARGIN := 30.0      # pemain berhenti sekian meter SEBELUM garis air penuh

# --- Danau (bundar, dgn pita "pantai" kecil di tepinya spt laut tapi lbh sempit) ---
# PERGESERAN (laporan user ronde ini: "mana danau dan sungai nya keknya masih
# world lama"): penempatan awal (350,450) r=90 TERNYATA 700m+ dr titik spawn
# (0,0) — nyaris tak pernah tertemui jalan kaki, apalagi waktu itu masih
# malam gelap+kabut 160m. Dekatkan BESAR-SEKALI: tepi danau sekarang ~60m dr
# spawn shg langsung kelihatan begitu game dibuka (apalagi skrg sore terang
# + kabut dilonggarkan, lihat world.gd).
const LAKE_CENTER := Vector2(95.0, 75.0)
const LAKE_RADIUS := 60.0
const LAKE_BANK := 14.0

# --- Sungai: mengalir dr tepi danau (arah RIVER_DIR, MENJAUHI spawn) sampai
# keluar ke laut. Berkelok lewat 1 sinus tegak lurus arah alirannya
# (v = offset menyamping).
const RIVER_DIR := Vector2(0.784, 0.621)      # ~satuan, arah: dari danau menjauhi pusat spawn ke laut
const RIVER_START := Vector2(142.04, 112.26)  # = LAKE_CENTER + RIVER_DIR*LAKE_RADIUS (tepi danau)
const RIVER_LENGTH := 620.0                    # lbh dr cukup utk tembus garis pantai (coast ~460m) di arah ini
const RIVER_HALF_WIDTH := 18.0
const RIVER_BANK := 10.0                       # lebar transisi tepi sungai
const RIVER_MEANDER_AMP := 16.0                # sejauh apa sungai berkelok menyamping
const RIVER_MEANDER_FREQ := 0.008              # makin kecil = kelokan makin lebar/landai

## Jarak dari pusat pulau (world XZ) sampai batas pantai, pada sudut theta
## (radian, dari atan2(z, x)). Hasil > jarak ini = laut.
static func radius_at(theta: float) -> float:
	return RADIUS * (1.0
		+ 0.20 * sin(theta * 3.0 + 1.3)
		+ 0.11 * sin(theta * 7.0 + 0.7)
		+ 0.06 * sin(theta * 11.0 + 2.4))

## 0.0 = darat penuh (jauh dr pantai laut), 1.0 = laut penuh (jauh dr pantai),
## di antaranya = pita pasir/transisi. HANYA garis pantai LAUT (bukan danau/
## sungai) — dipakai player.gd utk membatasi jalan kaki (lihat COAST_MARGIN).
static func water_factor(world_x: float, world_z: float) -> float:
	var theta := atan2(world_z, world_x)
	var r := sqrt(world_x * world_x + world_z * world_z)
	var coast := radius_at(theta)
	return clampf((r - (coast - BEACH_WIDTH)) / BEACH_WIDTH, 0.0, 1.0)

## 0.0 = darat, 1.0 = danau penuh, di antaranya = tepi danau. Rumus SAMA
## persis dgn yg disalin ke GLSL (world.gd & grass_blade.gdshader).
static func lake_factor(world_x: float, world_z: float) -> float:
	var d := Vector2(world_x, world_z).distance_to(LAKE_CENTER)
	return clampf((LAKE_RADIUS - d) / LAKE_BANK, 0.0, 1.0)

## 0.0 = darat, 1.0 = sungai penuh, di antaranya = tepi sungai. Rumus SAMA
## persis dgn yg disalin ke GLSL.
static func river_factor(world_x: float, world_z: float) -> float:
	var p := Vector2(world_x, world_z) - RIVER_START
	var perp := Vector2(-RIVER_DIR.y, RIVER_DIR.x)
	var u := p.dot(RIVER_DIR)
	var v := p.dot(perp)
	var meander := sin(u * RIVER_MEANDER_FREQ) * RIVER_MEANDER_AMP
	var dist := absf(v - meander)
	var w := clampf((RIVER_HALF_WIDTH - dist) / RIVER_BANK, 0.0, 1.0)
	var fade_in := clampf((u - (-RIVER_BANK)) / (RIVER_BANK * 2.0), 0.0, 1.0)
	var fade_out := 1.0 - clampf((u - (RIVER_LENGTH - RIVER_BANK)) / (RIVER_BANK * 2.0), 0.0, 1.0)
	return w * fade_in * fade_out

## Gabungan (laut ATAU danau ATAU sungai) — dipakai grass utk tahu di mana
## rumput TIDAK boleh tumbuh (semua badan air, bukan cuma laut).
static func any_water_factor(world_x: float, world_z: float) -> float:
	return maxf(water_factor(world_x, world_z),
		maxf(lake_factor(world_x, world_z), river_factor(world_x, world_z)))
