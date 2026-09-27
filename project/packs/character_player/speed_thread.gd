extends MeshInstance3D
## Benang/Benang-speed "smooth" ala Yelan Genshin (permintaan user ronde
## ini: "trail mov speed jangan pake after image tapi kayak semacam benang
## smooth gitu ... dan pas pake move speed efek benang juga dapet di spirit
## api kecil itu"). Bukan lagi ghost-mesh karakter (itu penyebab layar penuh
## patung putih "permanen"): melainkan pita tipis ADDITIF pastel yang
## mengikuti di belakang sebuah anchor (punggung pemain / spirit api),
## digambar sebagai TRIANGLE_STRIP dari ring-buffer posisi dunia beberapa
## ratus milidetik terakhir — semakin kencang skill lari, semakin panjang
## benangnya tertinggal. Goyangan sinus tumbuh-ke-belakang supaya benang
## "ngalir" hidup, bukan garis lurus kaku (signature aliran Yelan).
##
## Nol-alokasi tetap diupayakan wajar utk mobile: mesh dibangun ulang hanya
## ketika benang sedang tampak (_alpha > kecil), satu ImmediateMesh dipakai
## ulang tiap frame, buffer posisi adalah array statis.

@export var width := 0.055          # lebar pita penuh (dimerutinkan ke ujung)
@export var points := 22            # banyak sampel histori (lebih = lebih halus/panjang)
@export var sample_interval := 0.016 # detik antar sampel
@export var wobble_amp := 0.05      # amplitudo goyangan maks di ujung belakang
@export var wobble_freq := 7.0      # laju goyangan
@export var phase := 0.0            # fase antar-benang supaya tak serempak
@export var tint := Color(0.62, 0.78, 1.0)

var _alpha := 0.0        # opasitas efektif sekarang (dierap ke _target)
var _target := 0.0       # 0 = padam, 1 = menyala penuh
var _t := 0.0
var _accum := 0.0
var _pts: PackedVector3Array = PackedVector3Array()
var _anchor: Node3D
var _anchor_offset := Vector3.ZERO
var _imm: ImmediateMesh

func setup(anchor: Node3D, offset: Vector3, p_tint: Color, p_width: float, p_phase: float) -> void:
	_anchor = anchor
	_anchor_offset = offset
	tint = p_tint
	width = p_width
	phase = p_phase

func set_target(t: float) -> void:
	_target = clampf(t, 0.0, 1.0)

func _ready() -> void:
	name = "SpeedThread"
	top_level = true                       # histori posisi tetap di ruang DUNIA
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 64.0               # strip menjangkau jauh ke belakang
	_imm = ImmediateMesh.new()
	mesh = _imm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.disable_receive_shadows = true
	material_override = mat

func _process(delta: float) -> void:
	_t += delta
	_alpha = lerpf(_alpha, _target, 1.0 - exp(-7.0 * delta))
	if _alpha < 0.02:
		if not _pts.is_empty():
			_pts.clear()
			_imm.clear_surfaces()
		return
	_accum += delta
	if _accum >= sample_interval and is_instance_valid(_anchor):
		_accum = 0.0
		_pts.insert(0, _anchor.to_global(_anchor_offset))  # sampel TERBARU di indeks 0
		while _pts.size() > points:
			_pts.remove_at(_pts.size() - 1)
	if _pts.size() < 2:
		return
	# Gambar strip: tiap titik melebar kiri-kanan tegak lurus arah kamera
	# lewat basis silang dgn vektor segmen + UP (pita horisontal — sudut
	# pandang kamera game ini belakang-atas, jadi pita datar terbaca jelas).
	var n := _pts.size()
	_imm.clear_surfaces()
	_imm.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n:
		var age := float(i) / float(n - 1)     # 0 kepala (anchor), 1 ujung ekor
		var p := _pts[i]
		# goyang sinus makin besar ke ekor + ayunan kecil vertikal
		var sway := sin(_t * wobble_freq + phase - age * 5.5) * wobble_amp * age
		var lift := cos(_t * wobble_freq * 0.73 + phase * 1.7 - age * 4.0) * wobble_amp * 0.45 * age
		var dir: Vector3
		if i == 0:
			dir = _pts[0] - _pts[1]
		elif i == n - 1:
			dir = _pts[n - 2] - _pts[n - 1]
		else:
			dir = _pts[i - 1] - _pts[i + 1]
		if dir.length_squared() < 0.0001:
			dir = Vector3.FORWARD
		dir = dir.normalized()
		var side := dir.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = dir.cross(Vector3.RIGHT)
		side = side.normalized()
		var w := width * (1.0 - age * age * 0.65)   # ekor sedikit mengerut
		var a := _alpha * (1.0 - age) * (1.0 - age) # alpha memudar ke ekor
		var c := p + side * sway + Vector3.UP * lift
		_imm.surface_set_color(Color(tint.r, tint.g, tint.b, a))
		_imm.surface_add_vertex(c + side * w)
		_imm.surface_set_color(Color(tint.r, tint.g, tint.b, a))
		_imm.surface_add_vertex(c - side * w)
	_imm.surface_end()
