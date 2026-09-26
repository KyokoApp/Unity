extends Node3D
## "Peliharaan" elemental api kecil yang melayang di samping bahu pemain
## (permintaan pengguna: "spirit elemental api kecil ... nembakin sihirnya
## dari situ, kayak peliharaan, goyang goyang jangan kaku"). Dua tuntutan
## kunci dari kalimat itu:
##   1. posisinya di bahu, bukan di tangan/dada spt peluru sebelumnya
##      (lihat player.gd _hand_position, skrg mengembalikan posisi node ini),
##   2. TIDAK BOLEH statis/kaku menempel — jadi node ini py gerak idle sendiri
##      (melayang naik-turun + orbit kecil Lissajous di sekitar titik jangkar
##      bahu, plus sedikit puter badan) yg berjalan terus terlepas dr
##      animasi tubuh karakter, spt makhluk hidup mengambang, bukan prop diam.
## Visual pakai fire_spirit_core/shell.gdshader (palet ORANYE/merah, sengaja
## BEDA dr fireball_core/shell.gdshader yg dipakai peluru arcane ungu) +
## OmniLight kecil + percikan ember GPUParticles tipis (biaya rendah, cuma
## 1 instance per pemain, bukan per tembakan spt trail peluru).

const FX := preload("res://packs/character_player/fire_fx.gd")
const CORE_SHADER := preload("res://packs/character_player/fire_spirit_core.gdshader")
const SHELL_SHADER := preload("res://packs/character_player/fire_spirit_shell.gdshader")

## Titik jangkar relatif ke induk (Visual) — kira-kira di samping bahu kanan,
## sedikit di depan supaya kelihatan dari kamera belakang-atas.
var anchor := Vector3(0.34, 1.42, 0.10)

var _t := randf() * TAU
var _light: OmniLight3D
var _shell_mat: ShaderMaterial
var _core_mat: ShaderMaterial
var _core_mi: MeshInstance3D
var _shell_mi: MeshInstance3D
var _pulse := 0.0

func _ready() -> void:
	_build_visual()
	position = anchor

func _process(delta: float) -> void:
	_t += delta
	_pulse = maxf(_pulse - delta * 2.6, 0.0)

	# Melayang: naik-turun + orbit kecil dua-sumbu beda frekuensi (Lissajous)
	# supaya lintasannya TIDAK melingkar sempurna/monoton -> terasa lebih
	# spt makhluk hidup yg gelisah drpd benda mekanis yg presisi.
	var bob := sin(_t * 1.7) * 0.05 + sin(_t * 3.1 + 1.2) * 0.02
	var ox := sin(_t * 1.3 + 0.4) * 0.05
	var oz := cos(_t * 1.05 + 2.1) * 0.045
	position = anchor + Vector3(ox, bob, oz)

	# Puter badan pelan + goyang sedikit condong (bukan cuma geser posisi)
	# spy makin tak kaku, disaat sama membiarkan sedikit "menghadap" ke luar.
	rotation.y = sin(_t * 0.6) * 0.5
	rotation.x = sin(_t * 1.9 + 0.7) * 0.08
	rotation.z = cos(_t * 1.4 + 1.5) * 0.08

	var s := 1.0 + sin(_t * 5.0) * 0.04 + _pulse * 0.35
	scale = Vector3.ONE * s

	if _light:
		_light.light_energy = 1.05 * (0.85 + 0.12 * sin(_t * 19.0) + 0.08 * sin(_t * 31.0)) + _pulse * 1.4
	if _shell_mat:
		_shell_mat.set_shader_parameter("flow_offset", Vector3(sin(_t * 0.4), _t * 0.6, cos(_t * 0.5)) * 0.3)
	if _core_mat:
		_core_mat.set_shader_parameter("flow_offset", Vector3(sin(_t * 0.5), _t * 0.5, cos(_t * 0.4)) * 0.25)

## Dipanggil player.gd tiap kali menembak — kedipan/gemuruh singkat spy
## kelihatan "sumber" sihirnya benar dr peliharaan ini, bukan cuma dekoratif.
func pulse() -> void:
	_pulse = 1.0

func _build_visual() -> void:
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.075
	core_mesh.height = 0.15
	core_mesh.radial_segments = 12
	core_mesh.rings = 6
	core.mesh = core_mesh
	_core_mat = ShaderMaterial.new()
	_core_mat.shader = CORE_SHADER
	_core_mat.set_shader_parameter("intensity", 2.6)
	_core_mat.set_shader_parameter("turbulence", 0.85)
	core.material_override = _core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	_core_mi = core

	var shell := MeshInstance3D.new()
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = 0.125
	shell_mesh.height = 0.25
	shell_mesh.radial_segments = 14
	shell_mesh.rings = 7
	shell.mesh = shell_mesh
	_shell_mat = ShaderMaterial.new()
	_shell_mat.shader = SHELL_SHADER
	_shell_mat.set_shader_parameter("intensity", 1.5)
	_shell_mat.set_shader_parameter("rise", 0.55)
	shell.material_override = _shell_mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.extra_cull_margin = 2.0
	add_child(shell)
	_shell_mi = shell

	var halo := MeshInstance3D.new()
	halo.mesh = FX.quad(Vector2(0.34, 0.34), FX.fx_mat(FX.soft_tex(0.15), true, Color(1.0, 0.55, 0.15, 0.55), BaseMaterial3D.BILLBOARD_ENABLED))
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.20)
	_light.light_energy = 1.05
	_light.omni_range = 3.2
	_light.shadow_enabled = false
	add_child(_light)

	# percikan ember tipis, murah (amount kecil) — cukup utk kesan "hidup"
	# tanpa membebani mobile (cuma 1 instance per pemain, tak per-tembakan).
	var embers := FX.particles("SpiritEmbers", 9, 0.9)
	embers.local_coords = false
	embers.randomness = 0.55
	embers.fixed_fps = 60
	embers.interpolate = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	pm.direction = Vector3.UP
	pm.spread = 40.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.45
	pm.gravity = Vector3(0, 0.35, 0)
	pm.damping_min = 0.3
	pm.damping_max = 0.7
	pm.scale_min = 0.25
	pm.scale_max = 0.55
	pm.scale_curve = FX.curve([Vector2(0, 1.0), Vector2(1, 0.0)], 1.0)
	pm.color_ramp = FX.ramp([0.0, 0.4, 1.0], [Color(2.4, 1.3, 0.3), Color(1.0, 0.4, 0.08), Color(0.4, 0.1, 0.02, 0.0)])
	embers.process_material = pm
	embers.draw_pass_1 = FX.quad(Vector2(0.05, 0.05), FX.fx_mat(FX.soft_tex(0.2), true, Color(1, 1, 1, 1)))
	add_child(embers)
