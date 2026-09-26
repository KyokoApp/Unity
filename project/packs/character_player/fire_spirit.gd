extends Node3D
## "Peliharaan" elemental kecil yang melayang di samping bahu pemain
## (permintaan pengguna: "spirit elemental ... nembakin sihirnya dari situ,
## kayak peliharaan, goyang goyang jangan kaku"). Tuntutan dari revisi
## user (screenshot ronde ini): WARNA UNGU (bukan oranye — dipakai lagi
## fireball_core/shell.gdshader punya peluru arcane, SUDAH ungu & teruji,
## drpd bikin palet baru), UKURAN dikecilkan, kobaran api "jangan gede
## banget, sederhana tapi realistis", dan lidah apinya HARUS bergerak
## kalau pemain jalan (bukan cuma diam nempel) — makanya shader shell yg
## dipakai ulang itu py uniform `trail` yg SAMA persis dipakai peluru utk
## efek ekor saat melesat; di sini digerakkan oleh KECEPATAN PEMAIN
## (player.gd menyetel external_velocity tiap frame), bukan kecepatan
## proyektil sendiri (peliharaan ini sendiri diam relatif terhadap bahu).
##
## Dua sumber gerak "tak kaku" digabung:
##  1. Melayang: bob naik-turun + orbit kecil Lissajang 2-sumbu (idle,
##     jalan terus terlepas dr gerak pemain) + puter badan pelan.
##  2. Reaktif: nyala apinya condong ke BELAKANG arah jalan pemain (trail)
##     -> terasa spt kena angin akibat gerakan, bukan prop diam nempel.

const FX := preload("res://packs/character_player/fire_fx.gd")
const CORE_SHADER := preload("res://packs/character_player/fireball_core.gdshader")
const SHELL_SHADER := preload("res://packs/character_player/fireball_shell.gdshader")

## Titik jangkar relatif ke induk (Visual) — di samping bahu kanan, sedikit
## di depan spy kelihatan dari kamera belakang-atas.
var anchor := Vector3(0.30, 1.40, 0.09)

## Disetel player.gd tiap frame (kecepatan horizontal pemain, ruang dunia) —
## dipakai utk menggerakkan lidah api (bkn kecepatan node ini sendiri, yg
## nyaris diam relatif bahu).
var external_velocity := Vector3.ZERO

var _t := randf() * TAU
var _light: OmniLight3D
var _shell_mat: ShaderMaterial
var _core_mat: ShaderMaterial
var _pulse := 0.0
var _trail := Vector3.ZERO

func _ready() -> void:
	_build_visual()
	position = anchor

func _process(delta: float) -> void:
	_t += delta
	_pulse = maxf(_pulse - delta * 2.6, 0.0)

	# Melayang: naik-turun + orbit kecil dua-sumbu beda frekuensi (Lissajous)
	# spy lintasannya TAK melingkar sempurna/monoton -> kesan lbh hidup
	# drpd benda mekanis presisi. Amplitudo kecil (peliharaan MUNGIL).
	var bob := sin(_t * 1.7) * 0.035 + sin(_t * 3.1 + 1.2) * 0.014
	var ox := sin(_t * 1.3 + 0.4) * 0.035
	var oz := cos(_t * 1.05 + 2.1) * 0.03
	position = anchor + Vector3(ox, bob, oz)

	rotation.y = sin(_t * 0.6) * 0.4
	rotation.x = sin(_t * 1.9 + 0.7) * 0.06
	rotation.z = cos(_t * 1.4 + 1.5) * 0.06

	var s := 1.0 + sin(_t * 5.0) * 0.035 + _pulse * 0.3
	scale = Vector3.ONE * s

	if _light:
		_light.light_energy = 0.85 * (0.85 + 0.12 * sin(_t * 19.0) + 0.08 * sin(_t * 31.0)) + _pulse * 1.1

	# Reaktif thd langkah pemain: lidah api "diseret" ke arah BERLAWANAN
	# gerak pemain (spt kena angin lawan saat jalan) — dihaluskan (lerp)
	# spy tak nyentak tiap kali arah joystick berubah, mirip persis teknik
	# _trail di arcane_bolt.gd tapi sumbernya kecepatan PEMAIN, bukan diri
	# sendiri. Diubah ke RUANG LOKAL node ini (yg terus berputar pelan di
	# atas) via basis invers, krn shader shell beroperasi di ruang lokal.
	var target_trail := (-external_velocity * 0.045).limit_length(0.55)
	_trail = _trail.lerp(target_trail, 1.0 - exp(-9.0 * delta))
	var local_trail: Vector3 = global_transform.basis.inverse() * _trail
	if _shell_mat:
		_shell_mat.set_shader_parameter("trail", local_trail)
		_shell_mat.set_shader_parameter("flow_offset", Vector3(sin(_t * 0.4), _t * 0.6, cos(_t * 0.5)) * 0.22 + _trail * 0.4)
	if _core_mat:
		_core_mat.set_shader_parameter("flow_offset", Vector3(sin(_t * 0.5), _t * 0.5, cos(_t * 0.4)) * 0.18)

## Dipanggil player.gd tiap kali menembak — kedipan singkat spy kelihatan
## "sumber" sihirnya benar dr peliharaan ini, bukan cuma dekoratif.
func pulse() -> void:
	_pulse = 1.0

## Ukuran MUNGIL & kobaran api SEDERHANA (permintaan user: "jangan gede
## banget sederhana tapi realistis") — kira2 separuh dari ukuran percobaan
## pertama, intensity/turbulence/rise juga diturunkan spy nyalanya tenang
## & rapi, bukan liar/besar.
func _build_visual() -> void:
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.042
	core_mesh.height = 0.084
	core_mesh.radial_segments = 10
	core_mesh.rings = 5
	core.mesh = core_mesh
	_core_mat = ShaderMaterial.new()
	_core_mat.shader = CORE_SHADER
	_core_mat.set_shader_parameter("intensity", 2.1)
	_core_mat.set_shader_parameter("turbulence", 0.6)
	core.material_override = _core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)

	var shell := MeshInstance3D.new()
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = 0.068
	shell_mesh.height = 0.136
	shell_mesh.radial_segments = 12
	shell_mesh.rings = 6
	shell.mesh = shell_mesh
	_shell_mat = ShaderMaterial.new()
	_shell_mat.shader = SHELL_SHADER
	_shell_mat.set_shader_parameter("intensity", 1.15)
	_shell_mat.set_shader_parameter("rise", 0.30)
	shell.material_override = _shell_mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.extra_cull_margin = 1.5
	add_child(shell)

	var halo := MeshInstance3D.new()
	halo.mesh = FX.quad(Vector2(0.17, 0.17), FX.fx_mat(FX.soft_tex(0.15), true, Color(0.55, 0.35, 1.0, 0.5), BaseMaterial3D.BILLBOARD_ENABLED))
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)

	_light = OmniLight3D.new()
	_light.light_color = Color(0.6, 0.42, 1.0)
	_light.light_energy = 0.85
	_light.omni_range = 2.0
	_light.shadow_enabled = false
	add_child(_light)

	# percikan kecil, murah (amount kecil) — cukup utk kesan "hidup" tanpa
	# bikin kobarannya kelihatan besar/ramai (permintaan "sederhana").
	var embers := FX.particles("SpiritEmbers", 5, 0.7)
	embers.local_coords = false
	embers.randomness = 0.5
	embers.fixed_fps = 60
	embers.interpolate = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.direction = Vector3.UP
	pm.spread = 35.0
	pm.initial_velocity_min = 0.10
	pm.initial_velocity_max = 0.30
	pm.gravity = Vector3(0, 0.3, 0)
	pm.damping_min = 0.3
	pm.damping_max = 0.7
	pm.scale_min = 0.18
	pm.scale_max = 0.38
	pm.scale_curve = FX.curve([Vector2(0, 1.0), Vector2(1, 0.0)], 1.0)
	pm.color_ramp = FX.ramp([0.0, 0.4, 1.0], [Color(1.6, 1.1, 2.4), Color(0.55, 0.35, 1.0), Color(0.3, 0.15, 0.5, 0.0)])
	embers.process_material = pm
	embers.draw_pass_1 = FX.quad(Vector2(0.035, 0.035), FX.fx_mat(FX.soft_tex(0.2), true, Color(1, 1, 1, 1)))
	add_child(embers)
