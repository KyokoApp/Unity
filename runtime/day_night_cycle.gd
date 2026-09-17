class_name DayNightCycle
extends Node3D

## ============================================================
## DAY NIGHT CYCLE — matahari + ambient + kabut + LANGIT GRADIEN.
## (Port dari DayNightCycle.cs — RenderSettings -> WorldEnvironment
## + uniform shader global.)
##
## Langit (aurelia_sky) digerakkan dari tabel keyframe yang sama,
## jadi horizon dan kabut selalu senada — trik utama tampilan
## stylized yang "menyatu".
##
## Di Godot untuk gaya stylized mobile ini: 1 directional light +
## ambient datar yang di-keyframe + sky gradien + fog warna —
## persis pola versi Unity (realtime GI terlalu mahal untuk HP).
## ============================================================

@export var sun: DirectionalLight3D
@export var sky_material: ShaderMaterial
@export var environment: WorldEnvironment

@export_group("Waktu")
## Jam berjalan sendiri mengikuti waktu nyata. Default dipadamkan:
## tampilan dibekukan di jam emas senja (start_hour) supaya kesan
## pertama mirip referensi stylized hangat; tombol suasana masih bisa
## mengaktifkan kembali mode live bila dikehendaki.
@export var realtime: bool = false
## Berapa menit dunia nyata untuk satu hari game penuh.
@export_range(2.0, 120.0) var day_minutes: float = 15.0
## Jam saat scene mulai (0-24). 17,2 = jam emas sore (langit hangat,
## bayangan panjang lembut).
@export_range(0.0, 24.0) var start_hour: float = 17.2

var hour: float

## Tabel keyframe: jam, warna matahari, intensitas, ambient, kabut,
## + warna langit (zenith & horizon). Enam suasana.
const K_JAM := [0.0, 4.8, 6.5, 9.0, 15.0, 17.8, 19.5, 24.0]
const K_SUN := [
	Color(0.35, 0.42, 0.60), Color(0.45, 0.42, 0.55), Color(1.00, 0.72, 0.45),
	Color(1.00, 0.96, 0.88), Color(1.00, 0.93, 0.80), Color(1.00, 0.55, 0.28),
	Color(0.45, 0.40, 0.60), Color(0.35, 0.42, 0.60),
]
const K_INT := [0.10, 0.12, 0.75, 1.05, 0.95, 0.70, 0.12, 0.10]
const K_AMB := [
	Color(0.10, 0.12, 0.20), Color(0.14, 0.15, 0.24), Color(0.42, 0.40, 0.38),
	Color(0.50, 0.56, 0.64), Color(0.48, 0.50, 0.56), Color(0.42, 0.34, 0.32),
	Color(0.14, 0.15, 0.26), Color(0.10, 0.12, 0.20),
]
const K_FOG := [
	Color(0.05, 0.06, 0.10), Color(0.10, 0.10, 0.16), Color(0.62, 0.55, 0.48),
	Color(0.62, 0.70, 0.78), Color(0.66, 0.66, 0.70), Color(0.70, 0.48, 0.36),
	Color(0.10, 0.11, 0.18), Color(0.05, 0.06, 0.10),
]
const K_TOP := [
	Color(0.015, 0.025, 0.07), Color(0.10, 0.12, 0.22), Color(0.45, 0.58, 0.78),
	Color(0.36, 0.55, 0.82), Color(0.38, 0.56, 0.80), Color(0.28, 0.30, 0.52),
	Color(0.05, 0.06, 0.14), Color(0.015, 0.025, 0.07),
]
const K_HOR := [
	Color(0.07, 0.09, 0.16), Color(0.28, 0.24, 0.30), Color(0.98, 0.78, 0.58),
	Color(0.75, 0.82, 0.88), Color(0.76, 0.78, 0.82), Color(1.00, 0.62, 0.36),
	Color(0.16, 0.14, 0.24), Color(0.07, 0.09, 0.16),
]

const BTN_LABEL := ["Pagi", "Siang", "Sore", "Malam", "Live"]
const BTN_JAM := [6.5, 12.0, 17.2, 21.5, -1.0]

var _allow_shadows := true

func _ready() -> void:
	hour = start_hour
	if sun == null:
		sun = get_tree().get_first_node_in_group("sun") as DirectionalLight3D
	refresh_settings()
	apply()

func _process(delta: float) -> void:
	if realtime and day_minutes > 0.0:
		hour += delta * (24.0 / (day_minutes * 60.0))
		if hour >= 24.0:
			hour -= 24.0
		apply()

## Dipakai screenshot dan tombol suasana.
func set_hour(h: float, rt: bool) -> void:
	realtime = rt
	hour = fposmod(h, 24.0)
	apply()

## Dipanggil panel pengaturan setelah nilai berubah.
func refresh_settings() -> void:
	_allow_shadows = SettingsStore.load()["shadows"]
	apply() if is_inside_tree() else null

func label() -> String:
	var suasana := "malam"
	if hour < 4.8 or hour >= 19.5:
		suasana = "malam"
	elif hour < 6.5:
		suasana = "subuh"
	elif hour < 15.0:
		suasana = "siang"
	elif hour < 17.8:
		suasana = "sore"
	else:
		suasana = "senja"
	return "waktu %.1f (%s)" % [hour, suasana]

func apply() -> void:
	# Cari segmen keyframe.
	var i := 0
	while i < K_JAM.size() - 2 and hour >= K_JAM[i + 1]:
		i += 1
	var span := maxf(0.0001, K_JAM[i + 1] - K_JAM[i])
	var t := clampf((hour - K_JAM[i]) / span, 0.0, 1.0)

	var sun_col: Color = K_SUN[i].lerp(K_SUN[i + 1], t)
	var inten: float = lerpf(K_INT[i], K_INT[i + 1], t)
	var amb: Color = K_AMB[i].lerp(K_AMB[i + 1], t)
	var fog: Color = K_FOG[i].lerp(K_FOG[i + 1], t)
	var top: Color = K_TOP[i].lerp(K_TOP[i + 1], t)
	var hor: Color = K_HOR[i].lerp(K_HOR[i + 1], t)

	var sun_dir := Vector3.UP
	if sun != null:
		var ang := (hour / 24.0) * 360.0 - 90.0
		var rad := deg_to_rad(ang)
		sun_dir = Vector3(cos(rad), sin(rad), 0.30)
		sun.look_at_from_position(Vector3.ZERO, -sun_dir.normalized(), Vector3.UP)
		sun.light_color = sun_col
		sun.light_energy = inten
		# Malam hari: bayangan mati (cahaya 0,1 nyaris tak terlihat,
		# tapi shadow pass-nya tetap dibayar kalau menyala).
		sun.shadow_enabled = _allow_shadows and inten > 0.25

	# Ambient datar + warna fog lewat environment & uniform global
	# (dibaca semua shader Aurelia).
	if environment != null and environment.environment != null:
		var env := environment.environment
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = amb
		env.ambient_light_energy = 1.0
		# Fog engine dimatikan: shader Aurelia menghitung kabutnya
		# sendiri secara konsisten (lihat *_fog_* uniform global).
		env.fog_enabled = false

	_set_global("aurelia_fog_color", fog)
	_set_global("aurelia_ambient_color", amb)
	_set_global("aurelia_sun_color", sun_col)
	_set_global("aurelia_sun_direction", -sun_dir.normalized())

	if sky_material != null:
		sky_material.set_shader_parameter("top_color", top)
		sky_material.set_shader_parameter("horizon_color", hor)
		sky_material.set_shader_parameter("sun_color", sun_col)
		if sun != null:
			var to_sun := sun.global_transform.basis * Vector3.FORWARD * -1.0
			sky_material.set_shader_parameter("sun_direction", Vector3(to_sun.x, to_sun.y, to_sun.z))

## Uniform shader global, didaftarkan world_boot saat start.
static func _set_global(nama: String, value) -> void:
	RenderingServer.global_shader_parameter_set(nama, value)
