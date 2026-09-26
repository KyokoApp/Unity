extends RefCounted
class_name IslandShape
## Bentuk pulau ~12km (permintaan user, bag. C lanjutan): BUKAN lingkaran,
## BUKAN kotak — garis pantai "alami" dibentuk dari jumlah beberapa gelombang
## sinus (harmonik) pada sudut (theta) di sekeliling pusat pulau, bukan noise
## acak biasa. Sengaja pakai sinus (bukan Perlin/noise texture) supaya
## RUMUS YANG SAMA PERSIS gampang disalin manual ke GLSL (grass_blade.gdshader
## & shader tanah di world.gd _make_ground_material) tanpa risiko hasil
## sedikit beda antar-bahasa seperti kalau pakai noise berbasis hash/texture.
##
## PENTING: kalau formula RADIUS/harmonik di sini diubah, WAJIB disamakan
## juga secara manual di kedua shader itu (dicari komentar "IslandShape" di
## sana) — GDScript & GLSL tidak bisa berbagi kode langsung.

const RADIUS := 6000.0          # radius dasar sblm dibengkokkan harmonik (~12km diameter)
const BEACH_WIDTH := 55.0       # lebar pita pasir/transisi darat->air
const COAST_MARGIN := 30.0      # pemain berhenti sekian meter SEBELUM garis air penuh

## Jarak dari pusat pulau (world XZ) sampai batas pantai, pada sudut theta
## (radian, dari atan2(z, x)). Hasil > jarak ini = laut.
static func radius_at(theta: float) -> float:
	return RADIUS * (1.0
		+ 0.20 * sin(theta * 3.0 + 1.3)
		+ 0.11 * sin(theta * 7.0 + 0.7)
		+ 0.06 * sin(theta * 11.0 + 2.4))

## 0.0 = darat penuh (jauh dr pantai), 1.0 = laut penuh (jauh dr pantai),
## di antaranya = pita pasir/transisi. Dipakai shader tanah utk blend warna.
static func water_factor(world_x: float, world_z: float) -> float:
	var theta := atan2(world_z, world_x)
	var r := sqrt(world_x * world_x + world_z * world_z)
	var coast := radius_at(theta)
	return clampf((r - (coast - BEACH_WIDTH)) / BEACH_WIDTH, 0.0, 1.0)
