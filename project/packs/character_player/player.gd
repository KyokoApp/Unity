extends CharacterBody3D
## Player: kontroler third-person dengan dukungan touch (di-set dari HUD),
## jalan/lari/sprint/jongkok/renang, interaksi dunia, SFX langkah, dan
## blob shadow (untuk preset rendah). Model = GLB KayKit (Knight).

signal stats_changed(kind: String, count: int)
signal nearest_interactable_changed(meta)

const AnimControllerScript := preload("res://packs/animations/animation_controller.gd")
const Materials := preload("res://packs/shaders_materials/materials.gd")

# Skin ganti-ganti: PolyGirl (bawaan) / Knight — tiap skin punya peta nama animasi.
const SKINS := {
	"mannequin": {
		# Universal Animation Library (Quaternius CC0) — BAWAAN per 1.0.26:
		# 43 animasi lengkap (idle/walk/run/sprint/crouch/jump/swim/roll/speak/attack...)
		"path": "res://packs/character_player/ual_mannequin.glb",
		"height": 1.45,
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
			"attack": ["Punch_Jab", "Punch_Cross"],
			"sit": ["Sitting_Idle_Loop"],
		},
	},
	"polygirl": {
		"path": "res://packs/character_player/polygirl.glb",
		"height": 1.45,
		"states": {
			"idle": ["idle", "Idle 2", "Idle 3"],
			"walk": ["walk"],
			"run": ["walk_fast", "run"],
			"sprint": ["run", "walk_fast"],
			"crouch_idle": ["sit_idle", "idle"],
			"crouch_move": ["walk"],
			"jump_start": ["jump_start"],
			"jump_fall": ["jump_falling", "jump_loop"],
			"jump_land": ["jump_end"],
			"swim_idle": ["idle"],
			"swim_move": ["walk"],
			"pickup": ["inspect_ground_loop", "action_button_click"],
			"interact": ["action_button_click", "action_button_open_door"],
			"emote": ["cycle_talking"],
			"attack": ["action_button_open_door", "action_button_click"],
			"sit": ["sit_idle", "idle"],
		},
	},
	"knight": {
		"path": "res://packs/character_player/knight.glb",
		"height": 1.35,
		"states": {},
	},
}
var char_skin := "mannequin"   # diisi dari settings oleh game_root sebelum _ready (bawaan: UAL mannequin)

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
const CAM_DIST := 4.3
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
var pitch := deg_to_rad(-16.0)

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
	var def: Dictionary = SKINS.get(char_skin, SKINS["polygirl"])
	var pa := load(def["path"])
	if pa == null:
		push_error("[player] skin hilang: " + str(def["path"]) + " — fallback knight")
		char_skin = "knight"
		def = SKINS["knight"]
		pa = load(def["path"])
		if pa == null:
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
	# material toon + outline untuk karakter
	var first := true
	for mi in mesh_parents:
		var smi: MeshInstance3D = mi
		var mat := Materials.toon_vertex_color(true, 0.022)
		if (smi.mesh is Mesh) and smi.mesh.get_surface_count() > 0:
			# hormati material bawaan GLB (warna-skinned sudah baik), cukup tambahkan outline sebagai next_pass
			var base_mat: Material = smi.mesh.surface_get_material(0) if first else smi.get_active_material(0)
			if base_mat is StandardMaterial3D:
				# jadikan sedikit toon dengan shading cel via overlay outline saja
				pass
			if base_mat and not base_mat.next_pass:
				base_mat.next_pass = Materials.make_outline(0.008)  # garis tipis (permintaan)
		else:
			smi.material_override = mat
		first = false
	anim = AnimControllerScript.new()
	if not anim.setup(self, model_root, def.get("states", {})):
		anim = null
	# jejak boot terlihat: status animasi (diagnose "gliding" di perangkat)
	var rootc = get_tree().current_scene
	if rootc and rootc.has_method("_trace"):
		if anim:
			rootc.call("_trace", "boot: anim = OK (%d state teresolusi) skin=%s" % [anim.resolved.size(), char_skin])
		else:
			rootc.call("_trace", "boot: ⚠ anim = NULL — AnimationPlayer tidak ketemu di skin")

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
	if anim and anim.has("sprint"):
		anim.action("sprint", 320)

func press_crouch(down: bool) -> void:
	crouch = down
	_apply_crouch_shape()

func press_interact() -> void:
	if _near and _action_lock <= 0.0:
		_do_interact(_near)

## Dipanggil QualityManager/GameRoot saat preset tanpa shadow GPU.
func set_blob_shadow(enabled: bool) -> void:
	if blob:
		blob.visible = enabled

func press_emote() -> void:
	if anim and _action_lock <= 0.0:
		anim.action("emote", 1600)
		_action_lock = 1.2
		_play("emote")

func press_attack() -> void:
	if anim and _action_lock <= 0.0:
		anim.action("attack", 600)
		_action_lock = 0.5

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
		if _swimming:
			anim.set_swim(true, hspeed / SPEED_SWIM)
		elif not _swimming and not is_on_floor() and velocity.y < -2.5:
			anim.set_air("jump_fall")
		elif is_on_floor() and _action_lock <= 0.0:
			anim.set_move(clampf(hspeed / SPEED_RUN, 0.0, 1.0), _target_speed() >= SPEED_SPRINT and hspeed > SPEED_RUN + 0.2, crouch)
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
