extends CharacterBody3D
## Player: kontroler third-person dengan dukungan touch (di-set dari HUD),
## jalan/lari/sprint/jongkok/renang, interaksi dunia, SFX langkah, dan
## blob shadow (untuk preset rendah). Model = GLB KayKit (Knight).

signal stats_changed(kind: String, count: int)
signal nearest_interactable_changed(meta)

const AnimControllerScript := preload("res://packs/animations/animation_controller.gd")
const Materials := preload("res://packs/shaders_materials/materials.gd")

# Skin bawaan genre top-down: MANNEQUIN UAL (Quaternius CC0) dengan aksesori
# penyihir procedural (topi+orb) yang dipasang oleh _load_skin — atas permintaan
# user: "karakter apa saja yang penting BERANIMASI JALAN", dan BUKAN knight.
# GLB knight/polygirl lama tetap dihapus; UAL dipulihkan dari riwayat.
const SKINS := {
	"wizard": {
		# Universal Animation Library (Quaternius CC0):
		# 43 animasi lengkap (idle/walk/run/sprint/crouch/jump/swim/roll/dance/punch...)
		"path": "res://packs/character_player/ual_mannequin.glb",
		"height": 1.45,
		"wizard_accessories": true,
		"states": {
			"idle": ["Idle_Loop"],
			"walk": ["Walk_Loop"],
			"run": ["Jog_Fwd_Loop"],
			"sprint": ["Sprint_Loop"],
			"crouch_idle": ["Crouch_Idle_Loop"],
			"crouch_move": ["Crouch_Fwd_Loop"],
			"jump_start": ["Jump_Start"],
			"jump_fall": ["Jump_Loop"],
			"jump_land": ["Jump_Land"],
			"swim_idle": ["Swim_Idle_Loop"],
			"swim_move": ["Swim_Fwd_Loop"],
			"pickup": ["PickUp_Table", "Interact"],
			"interact": ["Interact"],
			"emote": ["Dance_Loop"],
			"attack": ["Punch_Jab"],
			"attack2": ["Punch_Cross"],
			"roll": ["Roll"],
			"sit": ["Sitting_Idle_Loop"],
		},
	},
}
var char_skin := "wizard"   # penyihir = mannequin UAL + aksesori (beranimasi penuh)

# ------- gerak -------
const SPEED_WALK := 2.4
const SPEED_RUN := 4.8
const SPEED_SPRINT := 7.2
const SPEED_CROUCH := 1.5
const SPEED_SWIM := 2.6
const DASH_IMPULSE := 9.0
const DASH_CD := 0.9
const ACCEL := 16.0
const AIR_ACCEL := 5.0
const GRAVITY := 24.0
const JUMP_VEL := 7.4
const COYOTE := 0.12
const JUMP_BUFFER := 0.15

# kamera
const PITCH_MIN := deg_to_rad(-58.0)
const PITCH_MAX := deg_to_rad(34.0)
const CAM_DIST := 11.0      # top-down agak miring (permintaan "lihat dari atas")
const LOOK_K := 0.0036

var world: Node
var settings
var anim: AnimControllerScript
var model_root: Node3D
var model_pivot: Node3D
var cam_pivot: Node3D
var cam_arm: SpringArm3D
var col_shape: CollisionShape3D
var blob: MeshInstance3D

# input terakhir dari HUD
var joy := Vector2.ZERO       # -1..1 (y positif = maju)
var _look_vel := Vector2.ZERO # px yang diubah per detik
var yaw := 0.0
var pitch := deg_to_rad(-52.0)  # awal top-down; usapan tetap bisa memutar

var sprint := false
var crouch := false
var _jump_buffer := 0.0
var _coyote := 0.0
var _was_on_floor := false
var _swimming := false
var _last_fall_speed := 0.0
var is_ready := false

var step_timer := 0.0
var sfx := {}                 # nama -> AudioStreamPlayer3D
var _near := {}
var _near_timer := 0.0
var stats := {"flower": 0, "coconut": 0}
var head_offset_y := 0.0      # untuk efek visual renang
var _action_lock := 0.0
var _attack_alt := false
var _anim_probe := 0.0        # timer jejak anim on-device (diagnostik)
var _wiz_t := 0.0             # fase animasi kode penyihir (bob)
var _spin_t := 0.0            # sisa waktu putar saat emote
var _orb_node: MeshInstance3D # orb tongkat (berdenyut)
var _orbs := []               # proyektil sihir terbang: {n=node, v=vel, t=ttl}      # selang-seling attack/attack2 (pakai 2 animasi pukulan, bukan 1 terus)

func set_world(w: Node) -> void:
	world = w

func set_settings(s) -> void:
	settings = s

func _ready() -> void:
	col_shape = $Col
	model_pivot = $ModelPivot
	cam_pivot = $CameraPivot
	cam_arm = $CameraPivot/CamArm
	_load_skin()
	_make_blob_shadow()
	_make_sfx_players()
	# yaw awal menghadap laut? biarkan default; kamera mengikuti
	is_ready = true

func _load_skin() -> void:
	var def: Dictionary = SKINS.get(char_skin, SKINS["wizard"])
	var pa := load(def["path"])
	if pa == null:
		push_error("[player] skin hilang: " + str(def["path"]) + " — fallback penyihir prosedural")
		_load_wizard_procedural()
		return
	if model_root and is_instance_valid(model_root):
		model_root.queue_free()
	model_root = pa.instantiate()
	model_pivot.add_child(model_root)
	# normalisasi skala: cocokkan tinggi karakter ke target antar-skin
	var mesh_parents := []
	_find_mesh_instances(model_root, mesh_parents)
	var bbox := AABB()
	var first_box := true
	for mi in mesh_parents:
		var b: AABB = mi.get_aabb()
		if b.size == Vector3.ZERO:
			continue
		bbox = b if first_box else bbox.merge(b)
		first_box = false
	if not first_box and bbox.size.y > 0.05:
		var target: float = float(def.get("height", 1.4))
		model_root.scale = Vector3.ONE * clampf(target / bbox.size.y, 0.3, 3.0)
	# hormati material bawaan GLB; cukup tambahkan outline TIPIS sebagai next_pass
	var first := true
	for mi in mesh_parents:
		var smi: MeshInstance3D = mi
		if (smi.mesh is Mesh) and smi.mesh.get_surface_count() > 0:
			var base_mat: Material = smi.mesh.surface_get_material(0) if first else smi.get_active_material(0)
			if base_mat and not base_mat.next_pass:
				base_mat.next_pass = Materials.make_outline(0.008)
		else:
			smi.material_override = Materials.toon_vertex_color(true, 0.022)
		first = false
	var scale_k: float = model_root.scale.x
	if bool(def.get("wizard_accessories", false)):
		model_root.add_child(_build_wizard_accessories(bbox, scale_k))
	anim = AnimControllerScript.new()
	if not anim.setup(self, model_root, def.get("states", {})):
		anim = null
	var rootc = get_tree().current_scene
	if rootc and rootc.has_method("_trace"):
		if anim:
			var total_st: int = AnimControllerScript.STATES.size()
			var ok_st: int = anim.resolved.size()
			rootc.call("_trace", "boot: anim = %d/%d state ✔ skin=%s" % [ok_st, total_st, char_skin])
		else:
			rootc.call("_trace", "boot: ⚠ anim = NULL — AnimationPlayer tidak ketemu di skin")

## Darurat bila GLB rusak/hilang: tetap ada PENYIHIR primitif (cicilan #1).
func _load_wizard_procedural() -> void:
	if model_root and is_instance_valid(model_root):
		model_root.queue_free()
	model_root = _wiz_part_group()
	model_pivot.add_child(model_root)
	anim = null

func _wiz_part(mesh: Mesh, color: Color, pos: Vector3,
			  rot_deg := Vector3.ZERO, unshaded := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if unshaded:
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_color = color
		sm.emission_enabled = true
		sm.emission = color
		sm.emission_energy_multiplier = 2.2
		mi.material_override = sm
	else:
		mi.material_override = Materials.toon(color, true, 0.012)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	return mi

func _cone(bottom_r: float, top_r: float, h: float, segs := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = bottom_r
	c.top_radius = top_r
	c.height = h
	c.radial_segments = segs
	return c

## Penyihir primitif utuh (dipakai hanya saat GLB gagal dimuat).
func _wiz_part_group() -> Node3D:
	var w := Node3D.new()
	w.name = "WizardRoot"
	w.add_child(_wiz_part(_cone(0.34, 0.14, 0.95), Color(0.42, 0.30, 0.64), Vector3(0, 0.475, 0)))
	var belt := TorusMesh.new(); belt.inner_radius = 0.135; belt.outer_radius = 0.175
	w.add_child(_wiz_part(belt, Color(0.88, 0.70, 0.28), Vector3(0, 0.60, 0), Vector3(90, 0, 0)))
	var chest := SphereMesh.new(); chest.radius = 0.17; chest.height = 0.30
	w.add_child(_wiz_part(chest, Color(0.48, 0.35, 0.70), Vector3(0, 0.94, 0)))
	var head := SphereMesh.new(); head.radius = 0.145; head.height = 0.26
	w.add_child(_wiz_part(head, Color(0.95, 0.83, 0.69), Vector3(0, 1.10, 0.01)))
	for ex in [-0.052, 0.052]:
		var eye := SphereMesh.new(); eye.radius = 0.022; eye.height = 0.035
		w.add_child(_wiz_part(eye, Color(0.12, 0.09, 0.12), Vector3(ex, 1.115, 0.125)))
	var star := SphereMesh.new(); star.radius = 0.035; star.height = 0.05
	w.add_child(_wiz_part(star, Color(1.0, 0.86, 0.35), Vector3(0.055, 1.33, 0.10), Vector3.ZERO, true))
	w.add_child(_build_wizard_accessories(AABB(Vector3(-0.4, 0, -0.4), Vector3(0.8, 1.5, 0.8)), 1.0))
	return w

## Aksesori penyihir (topi runcing + bintang, tongkat + orb pijar) untuk
## dipasang PADA MODEL GLB — tinggi model penuh H (dalam unit model lokal).
func _build_wizard_accessories(bbox: AABB, scale_k: float) -> Node3D:
	var acc := Node3D.new()
	acc.name = "WizardAccessories"
	# bbox dalam RUANG MODEL (sebelum skala model_root) — anchor = tinggi manekin
	var H: float = maxf(bbox.size.y, 0.6)
	var inv: float = 1.0 / maxf(scale_k, 0.05)
	var U: float = 1.45 / maxf(H, 0.2) * inv  # konversi tinggi dunia -> unit model
	var hat := _cone(0.13, 0.0, 0.52)
	acc.add_child(_wiz_part(hat, Color(0.35, 0.23, 0.54), Vector3(0, H * 1.02, -0.03 * U), Vector3(-8, 0, 5)))
	var brim := TorusMesh.new(); brim.inner_radius = 0.115; brim.outer_radius = 0.235
	acc.add_child(_wiz_part(brim, Color(0.35, 0.23, 0.54), Vector3(0, H * 0.79, -0.02 * U), Vector3(86, 0, 5)))
	var star := SphereMesh.new(); star.radius = 0.035; star.height = 0.05
	acc.add_child(_wiz_part(star, Color(1.0, 0.86, 0.35), Vector3(0.055 * U, H * 0.89, 0.10 * U), Vector3.ZERO, true))
	var staff := _cone(0.018, 0.022, 1.05, 8)
	acc.add_child(_wiz_part(staff, Color(0.38, 0.26, 0.16), Vector3(0.245 * U, H * 0.41, 0.06 * U), Vector3(6, 0, -9)))
	var orb := SphereMesh.new(); orb.radius = 0.062; orb.height = 0.105
	_orb_node = _wiz_part(orb, Color(0.55, 0.98, 0.90), Vector3(0.315 * U, H * 0.78, 0.10 * U), Vector3.ZERO, true)
	acc.add_child(_orb_node)
	return acc

func _find_mesh_instances(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_find_mesh_instances(c, out)

## Ganti skin karakter saat bermain (dari pengaturan / mode edit).
func set_skin(id: String) -> void:
	if not SKINS.has(id) or id == char_skin and model_root != null:
		return
	char_skin = id
	if model_pivot:
		_load_skin()

func _make_blob_shadow() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_L8)
	for j in range(64):
		for i in range(64):
			var d := Vector2(i - 32, j - 32).length() / 30.0
			var a: int = 0 if d > 1.0 else int(150.0 * pow(1.0 - d, 1.6))
			img.set_pixel(i, j, Color(a / 255.0, a / 255.0, a / 255.0))
	var tex := ImageTexture.create_from_image(img)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0, 0, 0, 0.55)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_texture = tex
	bm.albedo_texture_force_srgb = true
	bm.no_depth_test = false
	var qm := QuadMesh.new()
	qm.size = Vector2(1.5, 1.5)
	blob = MeshInstance3D.new()
	blob.mesh = qm
	blob.rotation_degrees.x = -90
	blob.material_override = bm
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.top_level = true
	blob.visible = false   # dipakai bila shadow GPU dimatikan
	add_child(blob)

func _make_sfx_players() -> void:
	for name in ["step1", "step2", "jump", "land", "splash", "pickup", "emote"]:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.volume_db = -6.0
		add_child(p)
		sfx[name] = p
	_load_sfx_file("step1", "res://packs/audio_sfx/footstep_1.wav")
	_load_sfx_file("step2", "res://packs/audio_sfx/footstep_2.wav")
	_load_sfx_file("jump", "res://packs/audio_sfx/jump.wav")
	_load_sfx_file("land", "res://packs/audio_sfx/land.wav")
	_load_sfx_file("splash", "res://packs/audio_sfx/splash.wav")
	_load_sfx_file("pickup", "res://packs/audio_sfx/pickup.wav")
	_load_sfx_file("emote", "res://packs/audio_sfx/emote.wav")

func _load_sfx_file(key: String, path: String) -> void:
	if ResourceLoader.exists(path):
		sfx[key].stream = load(path)

func _play(key: String) -> void:
	if sfx.has(key) and sfx[key].stream:
		sfx[key].play()

# =============== API dari HUD ===============

func set_joy(v: Vector2) -> void:
	joy = v

func add_look_px(dx: float, dy: float) -> void:
	_look_vel.x += dx * 60.0
	_look_vel.y += dy * 60.0

func press_jump() -> void:
	_jump_buffer = JUMP_BUFFER
	if _swimming:
		# keluar air: dorong ke atas permukaan
		velocity.y = maxf(velocity.y, 3.5)

func press_sprint(down: bool) -> void:
	sprint = down
	if sprint:
		crouch = false

## Dash: hentakan cepat searah gerak terakhir / arah hadap. Cooldown singkat.
var _dash_cd := 0.0
var _last_move_dir := Vector3(0, 0, -1)

func press_dash() -> void:
	if _dash_cd > 0.0 or _swimming:
		return
	_dash_cd = DASH_CD
	var dir := _last_move_dir
	if dir.length() < 0.1:
		dir = Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
	velocity.x = dir.x * DASH_IMPULSE
	velocity.z = dir.z * DASH_IMPULSE
	if anim:
		if anim.has("roll"):
			anim.action("roll", 320)
		elif anim.has("sprint"):
			anim.action("sprint", 320)

func press_crouch(down: bool) -> void:
	crouch = down
	_apply_crouch_shape()

## Toggle dari tombol HUD (satu ketuk = ubah stwsan). Versi hold dulu bisa
## nyangkut apabila jari bergeser sebelum diangkat (release tersesat).
func press_crouch_toggle() -> void:
	crouch = not crouch
	_apply_crouch_shape()

func press_interact() -> void:
	if _near and _action_lock <= 0.0:
		_do_interact(_near)

## Dipanggil QualityManager/GameRoot saat preset tanpa shadow GPU.
func set_blob_shadow(enabled: bool) -> void:
	if blob:
		blob.visible = enabled

func press_emote() -> void:
	if _action_lock > 0.0:
		return
	if anim:
		anim.action("emote", 1600)
		_action_lock = 1.2
		_play("emote")
	else:
		# penyihir prosedural: emote = putar riang + denyut orb
		_spin_t = 0.9
		_action_lock = 0.9
		_play("emote")

func press_attack() -> void:
	if _action_lock > 0.0:
		return
	if anim:
		var st := "attack2" if (_attack_alt and anim.has("attack2")) else "attack"
		_attack_alt = not _attack_alt
		anim.action(st, 600)
		_cast_orb()          # penyihir: pukulan ber-animasi TETAP menembakkan orb ✨
		_action_lock = 0.5
	else:
		# tembak orb sihir ke arah hadap karakter (versi awal: belum mengenai apa-apa)
		_cast_orb()
		_action_lock = 0.4

## Orb pijar: bola tak-terteduh + material emisi, terbang+pijar memudar saat lenyap.
func _cast_orb() -> void:
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.22
	sm.radial_segments = 12
	sm.rings = 8
	orb.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(0.55, 0.98, 0.90)
	smat.emission_enabled = true
	smat.emission = Color(0.50, 1.0, 0.90)
	smat.emission_energy_multiplier = 3.0
	orb.material_override = smat
	var dir := Vector3(sin(model_pivot.rotation.y), 0.0, cos(model_pivot.rotation.y))
	orb.position = global_position + dir * 0.5 + Vector3(0, 1.15, 0)
	get_tree().current_scene.add_child(orb)
	_orbs.append({"n": orb, "v": dir * 13.0 + Vector3(0, 0.4, 0), "t": 1.6})
	_play("attack")

func _update_orbs(delta: float) -> void:
	for i in range(_orbs.size() - 1, -1, -1):
		var o: Dictionary = _orbs[i]
		var n: Node3D = o["n"]
		if not is_instance_valid(n):
			_orbs.remove_at(i)
			continue
		o["v"] = o["v"] + Vector3(0, -2.4, 0) * delta
		n.position += o["v"] * delta
		n.scale = Vector3.ONE * (1.0 + 0.15 * sin(_wiz_t * 9.0))
		o["t"] = o["t"] - delta
		var dying: bool = o["t"] <= 0.0 or n.position.y < 0.05
		if dying:
			# menyentuh tanah/habis umur: berhenti, memudar mengecil, lalu lenyap
			o["v"] = Vector3.ZERO
			if n.position.y < 0.05:
				n.position.y = 0.05
			o["t"] = minf(o["t"], 0.18)
			if o["t"] <= 0.0:
				n.queue_free()
				_orbs.remove_at(i)
				continue
			n.scale = Vector3.ONE * maxf(o["t"] / 0.18, 0.05)
		else:
			n.scale = Vector3.ONE * (1.0 + 0.15 * sin(_wiz_t * 9.0))

func _apply_crouch_shape() -> void:
	var cap: CapsuleShape3D = col_shape.shape
	var h := 1.15 if crouch else 1.8
	cap.height = h
	col_shape.position.y = h * 0.5

# =============== fisika ===============

func _physics_process(delta: float) -> void:
	if not is_ready:
		return
	var water_y := -0.06
	var floor_h := -999.0
	if world:
		floor_h = world.height_at(global_position.x, global_position.z)
	if floor_h < -900.0:
		_swimming = false  # lantai tak ketemu = BUKAN air (world statis tak punya laut)
	else:
		var depth := water_y - floor_h
		_swimming = depth > 1.05 and global_position.y < water_y + 0.3
	# input arah relatif kamera (y layar positif=kebawah karena dorongan atas = maju
	# dipetakan ke -Z kamera lewat cam_basis; jangan dinegasikan dua kali)
	var wish := Vector2(joy.x, joy.y)
	if wish.length() > 1.0:
		wish = wish.normalized()
	var cam_basis := Basis(Vector3.UP, yaw)
	var move_dir := (cam_basis * Vector3(wish.x, 0, wish.y))
	if move_dir.length() > 0.05:
		_last_move_dir = move_dir.normalized()
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	var speed := _target_speed()
	# FAIL-SAFE desktop keyboard (untuk uji headless/dev)
	if joy == Vector2.ZERO:
		var kb := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if kb != Vector2.ZERO:
			wish = kb
			move_dir = (cam_basis * Vector3(wish.x, 0, wish.y))
		if Input.is_action_just_pressed("ui_accept"):
			press_jump()
		sprint = Input.is_key_pressed(KEY_SHIFT) or sprint
	# kamera
	_apply_camera(delta)
	# gerakan vertikal & horizontal
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = COYOTE
	else:
		_coyote = maxf(_coyote - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if _swimming:
		_swim_move(delta, move_dir)
	else:
		_ground_move(delta, move_dir, speed, on_floor)
	# melompat
	if _jump_buffer > 0.0 and (_coyote > 0.0) and not _swimming and not crouch:
		velocity.y = JUMP_VEL
		_jump_buffer = 0.0
		_coyote = 0.0
		if anim:
			anim.set_air("jump_start")
		_play("jump")
	# sebelum move_and_slide: simpan fall speed
	_last_fall_speed = -velocity.y if velocity.y < 0 else 0.0
	move_and_slide()
	# efek pendarat
	if not _was_on_floor and is_on_floor():
		if _last_fall_speed > 8.0:
			if anim:
				anim.action("jump_land", 320)
			_play("land")
		_coyote = 0.0
	_was_on_floor = is_on_floor()
	# animasi & model
	_update_model(delta, move_dir, speed)
	_update_orbs(delta)
	if _spin_t > 0.0:
		_spin_t -= delta
		if model_root:
			model_root.rotation.y += delta * TAU / 0.9
	# langkah kaki
	if is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.7:
		step_timer -= delta
		if step_timer <= 0.0:
			step_timer = 2.6 / maxf(Vector2(velocity.x, velocity.z).length(), 0.7)
			_play("step1" if randf() < 0.5 else "step2")
	# interaksi periodik
	_near_timer -= delta
	if _near_timer <= 0.0:
		_near_timer = 0.25
		_check_interactable()
	# cleanup safety: respawn bila jatuh dari dunia
	if global_position.y < -70.0 and world:
		global_position = world.find_spawn_point() + Vector3(0, 1, 0)
		velocity = Vector3.ZERO
	# blob shadow menempel di tanah (dipakai saat shadow GPU nonaktif)
	if blob and blob.visible:
		blob.global_position = Vector3(global_position.x, floor_h + 0.04, global_position.z)
	if _action_lock > 0.0:
		_action_lock -= delta

func _ground_move(delta: float, move_dir: Vector3, speed: float, on_floor: bool) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5  # jaga tetap nempel di lereng
	var target_xz := Vector3(move_dir.x, 0, move_dir.z) * speed * (joy.length() if joy.length() > 0.05 else 1.0)
	var acc := ACCEL if joy.length() > 0.05 or move_dir.length() > 0.01 else ACCEL
	var hv := Vector2(velocity.x, velocity.z)
	var tv := Vector2(target_xz.x, target_xz.z)
	hv = hv.move_toward(tv, (AIR_ACCEL if not on_floor else acc) * delta * (speed + 0.5))
	velocity.x = hv.x
	velocity.z = hv.y

func _swim_move(delta: float, move_dir: Vector3) -> void:
	# arah permukaan: bob di -0.30; gerakan lambat + sedikit melawan gravitasi
	var surf := -0.30
	var target_y := clampf((surf - global_position.y) * 6.0, -3.0, 3.0)
	velocity.y = lerpf(velocity.y, target_y, delta * 4.0)
	var hv := Vector2(velocity.x, velocity.z)
	var tv := Vector2(move_dir.x, move_dir.z) * SPEED_SWIM * maxf(joy.length(), 0.0)
	hv = hv.move_toward(tv, 3.5 * delta * SPEED_SWIM)
	velocity.x = hv.x
	velocity.z = hv.y

func _target_speed() -> float:
	if crouch:
		return SPEED_CROUCH
	if Input.is_key_pressed(KEY_SHIFT) or sprint:
		return SPEED_SPRINT
	return SPEED_RUN

func _apply_camera(delta: float) -> void:
	var sens := 1.0
	if settings:
		sens = clampf(settings.camera_sens, 0.3, 2.5)
	yaw -= _look_vel.x * LOOK_K * sens * delta * 60.0 * 0.016
	var invert := -1.0 if (settings and settings.invert_y) else 1.0
	pitch = clampf(pitch + _look_vel.y * LOOK_K * sens * delta * 60.0 * 0.016 * invert, PITCH_MIN, PITCH_MAX)
	_look_vel = _look_vel.lerp(Vector2.ZERO, delta * 12.0)
	cam_pivot.rotation = Vector3(pitch, yaw, 0)
	# gradien bobot kecil: kamera sedikit mendekat saat jongkok
	var want_len := CAM_DIST * (0.86 if crouch else 1.0)
	cam_arm.spring_length = lerpf(cam_arm.spring_length, want_len, delta * 6.0)

func _update_model(delta: float, move_dir: Vector3, speed: float) -> void:
	# putar model ke arah gerak
	if move_dir.length() > 0.01:
		var target_yaw := atan2(move_dir.x, move_dir.z)
		model_pivot.rotation.y = lerp_angle(model_pivot.rotation.y, target_yaw, delta * 10.0)
	var hspeed := Vector2(velocity.x, velocity.z).length()
	_wiz_t += delta * (1.1 + hspeed * 0.85)   # denyut orb/bob proyektil — universal
	if anim:
		# jejak diagnostik ON-DEVICE (foto saat keluhannya muncul):
		# menunjukkan state ANIMASI YANG BENAR-BENAR BERMAIN tiap 0,9 detik
		_anim_probe -= delta
		if _anim_probe <= 0.0:
			_anim_probe = 0.9
			var rc2 = get_tree().current_scene
			if rc2 and rc2.has_method("_trace"):
				rc2.call("_trace", "anim:%s sp:%.1f crouch:%s | %s" % [
					str(anim.current), hspeed, str(crouch), char_skin])
		if _swimming:
			anim.set_swim(true, hspeed / SPEED_SWIM)
		elif not _swimming and not is_on_floor() and velocity.y < -2.5:
			anim.set_air("jump_fall")
		elif is_on_floor() and _action_lock <= 0.0:
			anim.set_move(clampf(hspeed / SPEED_RUN, 0.0, 1.0), _target_speed() >= SPEED_SPRINT and hspeed > SPEED_RUN + 0.2, crouch)
	if model_root != null and anim == null:
		# penyihir prosedural tanpa library animasi: bob melayang + condong ke
		# arah lari dari kode; orb tongkat berdenyut; putar saat emote diatur
		# oleh _spin_t di _physics_process.
		var bob_t: float = 0.032 if hspeed < 0.25 else 0.018 + hspeed * 0.003
		model_root.position.y = sin(_wiz_t * 2.1) * bob_t
		var lean: float = 0.16 if hspeed > 0.4 else 0.0
		model_root.rotation.x = lerp_angle(model_root.rotation.x, lean, delta * 7.0)
		model_root.rotation.z = lerp_angle(model_root.rotation.z, -lean * 0.5, delta * 7.0)
		if velocity.y < -1.0 and not is_on_floor():
			model_root.rotation.x = lerp_angle(model_root.rotation.x, -0.22, delta * 6.0)
	if _orb_node and is_instance_valid(_orb_node):
		_orb_node.scale = Vector3.ONE * (1.0 + 0.18 * sin(_wiz_t * 6.3))
	# efek visual jongkok (memendek sedikit) & renang (mengambang lebih rendah)
	var want_head := -0.28 if crouch else 0.0
	head_offset_y = lerpf(head_offset_y, want_head, delta * 8.0)
	model_pivot.position.y = head_offset_y

func _check_interactable() -> void:
	if world == null:
		return
	var prev_key := str(_near.get("pos", Vector3.ZERO))
	_near = world.get_nearest_interactable(global_position + Vector3(0, 0.8, 0) - global_transform.basis.z * 0.3, 4.2)
	var new_key := str(_near.get("pos", Vector3.ZERO))
	if prev_key != new_key or (prev_key == "" and new_key != "") or (prev_key != "" and new_key == ""):
		nearest_interactable_changed.emit(_near)

func _do_interact(meta: Dictionary) -> void:
	var signature := str(meta.get("type", "?"))
	world.consume_interactable(meta)
	if anim:
		anim.action("pickup", 700)
	_action_lock = 0.55
	_play("pickup")
	if stats.has(signature):
		stats[signature] += 1
		stats_changed.emit(signature, stats[signature])
	_near = {}
	nearest_interactable_changed.emit(_near)
