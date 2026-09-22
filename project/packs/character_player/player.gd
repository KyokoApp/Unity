extends CharacterBody3D
## Player: kontroler third-person dengan dukungan touch (di-set dari HUD),
## jalan/lari/sprint/jongkok/renang, interaksi dunia, SFX langkah, dan
## blob shadow (untuk preset rendah). Model = Mannequin (Quaternius UAL).

signal stats_changed(kind: String, count: int)
signal nearest_interactable_changed(meta)

const Materials := preload("res://packs/shaders_materials/materials.gd")
const AnimController := preload("res://packs/character_player/anim_controller.gd")

# SKIN "mannequin": mesh Quaternius Female Mannequin + animasi gabungan
# ual1 (lokomosi dasar: jalan/lari/sprint/jongkok/lompat/renang/roll) +
# ual2 (aksi: kombo pedang/dst). Ketiga file berbagi 1 skeleton persis
# (65 joint, nama sama) — tak perlu retarget BoneMap, cukup gabung
# AnimationLibrary di satu AnimationPlayer. anim=null -> fallback tanpa
# model (EmptyRoot), sesuai FAILSAFE lama (Ronde-26): GLB gagal tak pernah
# menjatuhkan boot.
const SKINS := {
	"mannequin": {
		"mesh": "res://packs/character_player/assets/mannequin_f.glb",
		"anims": {
			"ual1": "res://packs/character_player/assets/ual1_standard.glb",
			"ual2": "res://packs/character_player/assets/ual2_standard.glb",
		},
		"height": 1.75,
	},
	"wizard": {"mesh": "", "anims": {}, "height": 1.5},
}
var char_skin := "mannequin"

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
var anim
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
	if model_root and is_instance_valid(model_root):
		model_root.queue_free()
	anim = null
	var def: Dictionary = SKINS.get(char_skin, {})
	var mesh_path: String = def.get("mesh", "")
	var anim_paths: Dictionary = def.get("anims", {})
	if mesh_path == "" or anim_paths.is_empty():
		_use_empty_root("skin '%s' tanpa GLB (prosedural/kosong)" % char_skin)
		return
	_trace("boot: pemain… memuat GLB skin '%s'" % char_skin)
	var built := _build_mannequin(mesh_path, anim_paths)
	if built == null:
		# FAILSAFE (pelajaran Ronde-26): GLB/skeleton gagal tak boleh
		# menjatuhkan boot — mundur ke EmptyRoot, game tetap jalan.
		_use_empty_root("skin '%s' GAGAL dimuat, fallback aman" % char_skin)
		return
	model_root = built
	model_pivot.add_child(model_root)
	var n_anims := anim.player.get_animation_list().size() if anim else 0
	_trace("boot: skin '%s' siap — %d animasi tergabung ✔" % [char_skin, n_anims])

func _use_empty_root(reason: String) -> void:
	model_root = Node3D.new()
	model_root.name = "EmptyRoot"
	model_pivot.add_child(model_root)
	anim = null
	_trace("boot: %s" % reason)

func _trace(msg: String) -> void:
	var rootc = get_tree().current_scene
	if rootc and rootc.has_method("_trace"):
		rootc.call("_trace", msg)

## Bangun node model: mesh (skin) ditumpangkan ke Skeleton3D milik file
## animasi PERTAMA (anim_paths diproses sesuai urutan key — Dictionary di
## GDScript 4 mempertahankan urutan insersi). File animasi datang dengan
## AnimationPlayer+Skeleton3D yang sudah saling konsisten secara native,
## jadi track path animasi dijamin benar; mesh cuma "numpang" lewat
## MeshInstance3D.skeleton (aman krn nama 65 joint identik di ketiga file
## — dicek manual sebelum ronde ini, pola sama dgn "shared skeleton" utk
## sistem equipment di Godot). Library animasi lain digabung sesudahnya.
## NB (Ronde-37): variabel resource SENGAJA tak diberi type-hint eksplisit
## (var polos, bukan `: Resource`/`: PackedScene`) sebelum instantiate() —
## GDScript 4 bisa gagal resolve method lewat type-hint base class yg tak
## punya method itu. Var polos = dispatch dinamis by tipe RUNTIME, aman.
func _build_mannequin(mesh_path: String, anim_paths: Dictionary) -> Node3D:
	var first_key: String = anim_paths.keys()[0]
	if not ResourceLoader.exists(anim_paths[first_key]) or not ResourceLoader.exists(mesh_path):
		_trace("boot: pemain… GLB tak ditemukan di pack")
		return null
	var host_res = load(anim_paths[first_key])
	if host_res == null or not (host_res is PackedScene):
		_trace("boot: pemain… load() library '%s' gagal" % first_key)
		return null
	_trace("boot: pemain… library '%s' termuat, instantiate…" % first_key)
	var host: Node3D = host_res.instantiate()
	var skeleton := _find_skeleton(host)
	var aplayer := _find_anim_player(host)
	if skeleton == null or aplayer == null or skeleton.get_bone_count() == 0:
		_trace("boot: pemain… skeleton/AnimationPlayer tak ketemu di '%s'" % first_key)
		host.queue_free()
		return null
	_trace("boot: pemain… skeleton ✔ (%d tulang), memuat mesh…" % skeleton.get_bone_count())
	var mesh_res = load(mesh_path)
	if mesh_res == null or not (mesh_res is PackedScene):
		_trace("boot: pemain… load() mesh gagal")
		host.queue_free()
		return null
	var mesh_holder: Node = mesh_res.instantiate()
	var meshes: Array = []
	_find_mesh_instances(mesh_holder, meshes)
	if meshes.is_empty():
		_trace("boot: pemain… tak ada MeshInstance3D di mesh_holder")
		host.queue_free()
		mesh_holder.queue_free()
		return null
	_trace("boot: pemain… %d mesh ditemukan, menempel ke skeleton…" % meshes.size())
	for mi in meshes:
		var mi3: MeshInstance3D = mi
		var old_parent := mi3.get_parent()
		if old_parent:
			old_parent.remove_child(mi3)
		host.add_child(mi3)   # taruh di root host; NodePath skeleton tetap relatif-benar
		mi3.transform = Transform3D.IDENTITY
		mi3.skeleton = mi3.get_path_to(skeleton)
		_apply_toon(mi3)
	mesh_holder.queue_free()
	_trace("boot: pemain… mesh tertempel ✔, menggabung library lain…")
	for key in anim_paths.keys():
		if key != first_key:
			_merge_library(aplayer, key, anim_paths[key])
	host.name = "Model"
	anim = AnimController.new()
	anim.setup(aplayer)
	_trace("boot: pemain… AnimController siap ✔")
	return host

func _merge_library(target: AnimationPlayer, ns: String, path: String) -> void:
	_trace("boot: pemain… gabung library '%s'…" % ns)
	if not ResourceLoader.exists(path):
		return
	var res = load(path)
	if res == null or not (res is PackedScene):
		return
	var inst: Node = res.instantiate()
	var src := _find_anim_player(inst)
	if src:
		for lib_name in src.get_animation_library_list():
			var lib := src.get_animation_library(lib_name)
			if lib == null:
				continue
			if target.has_animation_library(ns):
				target.remove_animation_library(ns)
			target.add_animation_library(ns, lib)
	inst.queue_free()

func _apply_toon(mi: MeshInstance3D) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	for i in range(mesh.get_surface_count()):
		var mat := mesh.surface_get_material(i)
		var mname: String = mat.resource_name if mat else ""
		if mname.find("Joint") != -1:
			mi.set_surface_override_material(i, Materials.toon(Color(0.80, 0.40, 0.04), true, 0.008))
		else:
			mi.set_surface_override_material(i, Materials.toon(Color(0.40, 0.19, 0.71), true, 0.008))

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null

func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r:
			return r
	return null

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
	if anim and anim.has("emote"):
		anim.action("emote", 150)
		_play("emote")

## Kombo pedang UAL2 (satu klip gabungan 3 hit, ~3 dtk) — dikunci lewat
## AnimController._busy sampai selesai, jadi tak bisa di-spam-tap (aman,
## tak ada state-machine kombo manual yang rawan nyangkut seperti dulu).
func press_attack() -> void:
	if _action_lock > 0.0 or anim == null or not anim.has("attack"):
		return
	anim.action("attack", 120)
	_action_lock = 0.2

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
	elif model_root != null:
		# penyihir prosedural tanpa library animasi: bob melayang + condong ke
		# arah lari dari kode; orb tongkat berdenyut; putar saat emote diatur
		# oleh _spin_t di _physics_process.
		_wiz_t += delta * (1.1 + hspeed * 0.85)
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
