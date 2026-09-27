extends RefCounted
class_name IslandShape
## Bentuk pulau (keputusan geometri ronde sebelumnya: garis pantai "alami"
## dari jumlah beberapa gelombang sinus/harmonik pada sudut theta, bukan
## noise acak — supaya RUMUS YANG SAMA PERSIS gampang disalin manual ke GLSL
## di grass_blade.gdshader & shader tanah world.gd tanpa risiko hasil
## sedikit beda antar-bahasa).
##
## PERUBAHAN RONDE INI (permintaan user: "hilangin juga danau nya biar
## bagian air hanya ada disisi pulau"): DANAU & SUNGAI DIHILANGKAN
## KESELURUHAN — sisa badan air di dunia HANYA laut sekeliling pantai pulau.
## Semua lapisan serentak dibersihkan: konstanta+fungsi lake/river di sini,
## salinan rumus di shader tanah (world.gd _make_ground_material) & di
## grass_blade.gdshader. Fungsi any_water_factor() dipertahankan (API yg
## dipakai pemanggil lain) dan kini identik water_factor().
##
## PENTING (tetap berlaku): kalau formula RADIUS/harmonik diubah, WAJIB
## disamakan manual di kedua shader itu (cari komentar "IslandShape" di
## sana) — GDScript & GLSL tidak bisa berbagi kode langsung.

const RADIUS := 460.0           # radius dasar sblm dibengkokkan harmonik (~1km diameter)
const BEACH_WIDTH := 55.0       # lebar pita pasir/transisi darat->air (pantai laut)
const COAST_MARGIN := 30.0      # pemain berhenti sekian meter SEBELUM garis air penuh

## Jarak dari pusat pulau (world XZ) sampai batas pantai, pada sudut theta
## (radian, dari atan2(z, x)). Hasil > jarak ini = laut.
static func radius_at(theta: float) -> float:
	return RADIUS * (1.0
		+ 0.20 * sin(theta * 3.0 + 1.3)
		+ 0.11 * sin(theta * 7.0 + 0.7)
		+ 0.06 * sin(theta * 11.0 + 2.4))

## 0.0 = darat penuh (jauh dr pantai laut), 1.0 = laut penuh (jauh dr pantai),
## di antaranya = pita pasir/transisi. HANYA garis pantai LAUT — satu-satunya
## badan air yg tersisa di dunia (danau/sungai dihapus ronde ini).
static func water_factor(world_x: float, world_z: float) -> float:
	var theta := atan2(world_z, world_x)
	var r := sqrt(world_x * world_x + world_z * world_z)
	var coast := radius_at(theta)
	return clampf((r - (coast - BEACH_WIDTH)) / BEACH_WIDTH, 0.0, 1.0)

## API kompatibel (paket lain memanggil ini utk cek "boleh tanam rumput
## di sini?"): kini identik water_factor — TAK ADA air pedalaman lagi.
static func any_water_factor(world_x: float, world_z: float) -> float:
	return water_factor(world_x, world_z)
