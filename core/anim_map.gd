class_name AnimMap
extends RefCounted

## ============================================================
## ANIM MAP — pemetaan nama klip animasi GLB (dari sumber mana
## pun: Mixamo, Blender, VRM-convert) -> peran game Aurelia.
##
## Semua fungsi MURNI di atas resource Animation (tanpa scene),
## bisa dites headless 100%:
##   resolve()        — pilih klip untuk tiap peran dari daftar nama
##   retarget_clip()  — kirim ulang semua track tulang ke skeleton
##                      model yang sebenarnya (prafiks path diganti)
##   strip_xz()       — nol-kan gerak maju root di klip lokomosi
##                      (motor yang menggerakkan badan, bukan klip)
##   apply_loop()     — klip lokomosi harus LOOP_LINEAR
## ============================================================

## Urutan penting: peran ini dibaca CharacterAnimDriver.setup().
const ROLE_ORDER := ["idle", "walk", "run", "dash", "fall", "jump",
	"land", "attack0", "attack1", "attack2", "skill", "burst"]

## Peran lokomosi (strip_xz + loop) vs one-shot.
const LOCO_ROLES := ["idle", "walk", "run", "dash", "fall"]

const _CAND := {
	## UAL2 Standard (aset pengguna): nama-nama eksplisit didahulukan —
	## tanpa ini resolve() menunjuk klip bergaya (Idle_FoldArms saat
	## siaga, "walk carry" membawa kardus saat jalan) yang terlihat aneh.
	"idle": ["idle no loop", "idle_loop", "idle loop", "idle", "standing",
		"breathing", "stand"],
	"walk": ["walk carry loop", "walk", "walking", "walk forward",
		"walk loop"],
	## Tak ada klip lari di UAL2 Standard; run selalu jatuh ke walk
	## yang dipercepat oleh AnimDriver (clamp speed 2,4x).
	"run": ["run", "running", "sprint", "run forward", "jog"],
	"dash": ["sword dash", "shield dash", "dash", "dodge", "roll",
		"evade", "lunge"],
	"fall": ["ninjajump idle loop", "fall", "falling", "air", "airborne",
		"in air"],
	"jump": ["jump start", "ninjajump start", "jump up", "jump", "leap",
		"takeoff"],
	"land": ["jump land", "ninjajump land", "land", "landing",
		"touchdown"],
	"attack0": ["sword regular a", "attack1", "attack 1", "attack_1",
		"combo1", "slash1", "attack", "slash", "sword", "punch", "hit"],
	"attack1": ["sword regular b", "attack2", "attack 2", "attack_2",
		"combo2", "slash2", "attack", "slash", "sword", "punch", "hit"],
	"attack2": ["sword regular c", "attack3", "attack 3", "attack_3",
		"combo3", "slash3", "attack", "slash", "sword", "punch", "hit"],
	"skill": ["overhand throw", "skill", "cast", "spell", "ability",
		"magic"],
	"burst": ["sword heavy combo", "burst", "ultimate", "ult",
		"finisher", "special"],
}

## Normalisasi nama klip: huruf kecil, hanya alfanumerik.
static func norm(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out

## Cari AnimationPlayer pertama di bawah root (rekursif).
static func find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var p := find_player(c)
		if p != null:
			return p
	return null

## Cari Skeleton3D pertama di bawah root (rekursif).
static func find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var s := find_skeleton(c)
		if s != null:
			return s
	return null

## Pilih klip tiap peran. names = daftar nama klip yang tersedia.
## Hasil {role: nama_klip} — peran tak ketemu = "".
static func resolve(names: Array) -> Dictionary:
	var normed := []
	for i in names.size():
		normed.append(norm(str(names[i])))
	var out := {}
	for role in ROLE_ORDER:
		out[role] = ""
		var cands: Array = _CAND.get(role, [])
		# 1) cocok persis (setelah norm)
		for cand in cands:
			var nc := norm(cand)
			for i in names.size():
				if normed[i] == nc:
					out[role] = str(names[i])
					break
			if out[role] != "":
				break
		# 2) awalan
		if out[role] == "":
			for cand in cands:
				var nc := norm(cand)
				for i in names.size():
					if normed[i].begins_with(nc):
						out[role] = str(names[i])
						break
				if out[role] != "":
					break
		# 3) substring
		if out[role] == "":
			for cand in cands:
				var nc := norm(cand)
				for i in names.size():
					if normed[i].find(nc) >= 0:
						out[role] = str(names[i])
						break
				if out[role] != "":
					break
	return out

## Isi fallback peran efektif (run kosong -> walk -> idle, dst).
## Mengubah dan mengembalikan Dictionary yang sama.
static func fill_fallbacks(m: Dictionary) -> Dictionary:
	if m.get("run", "") == "":
		m["run"] = m.get("walk", "")
	if m.get("walk", "") == "":
		m["walk"] = m.get("run", "")
	if m.get("idle", "") == "":
		m["idle"] = m.get("walk", "")
	if m.get("fall", "") == "":
		m["fall"] = m.get("idle", "")
	if m.get("jump", "") == "":
		m["jump"] = m.get("idle", "")
	if m.get("attack2", "") == "":
		m["attack2"] = m.get("attack1", "")
	if m.get("attack1", "") == "":
		m["attack1"] = m.get("attack0", "")
	if m.get("attack0", "") == "":
		m["attack0"] = m.get("attack1", "")
	return m

## Klip dari file lain menunjuk skeleton file itu ("Armature:Bone"
## dll). Ganti SELURUH prafiks nama-node track tulang ke prefix
## skeleton model pemain (mis. "RootNode/Skeleton3D:Bone" tetap,
## hanya segmen tulang yang dipertahankan). Track non-tulang
## (morf, value, audio, metode) dibuang — retarget morph antar
## file tidak pernah aman.
static func retarget_clip(anim: Animation, skel_prefix: String) -> Animation:
	var dup: Animation = anim.duplicate()
	for i in range(dup.get_track_count() - 1, -1, -1):
		var t: Animation.TrackType = dup.track_get_type(i)
		var p: NodePath = dup.track_get_path(i)
		if t == Animation.TYPE_POSITION_3D or t == Animation.TYPE_ROTATION_3D \
		or t == Animation.TYPE_SCALE_3D:
			var sub := String(p.get_concatenated_subnames())
			if sub == "":
				continue  ## track node (bukan tulang) — biarkan apa adanya
			dup.track_set_path(i, NodePath("%s:%s" % [skel_prefix, sub]))
		else:
			dup.remove_track(i)
	return dup

## Nol-kan XZ track posisi tulang pinggul (in-place semu): karakter
## tidak lagi "lari meninggalkan" titiknya — motor memegang posisi.
## Sum biomechanik penting (bounce Y) dipertahankan utuh.
static func strip_xz(anim: Animation) -> Animation:
	for i in dup_iter(anim):
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var sub := String(anim.track_get_path(i).get_concatenated_subnames())
		if not _is_hips(sub):
			continue
		for k in anim.track_get_key_count(i):
			var v: Vector3 = anim.track_get_key_value(i, k)
			v.x = 0.0
			v.z = 0.0
			anim.track_set_key_value(i, k, v)
	return anim

static func _is_hips(subname: String) -> bool:
	var n := norm(subname)
	return n.find("hips") >= 0 or n.find("pelvis") >= 0 or n.find("root") >= 0

## ============================================================
## RETARGET HUMANOID TULANG-BEDA-NAMA
## Skeleton sumber (kemasan UE, UAL2: pelvis/spine_01/clavicle_l/…)
## vs model pengguna (VRoid/VRM: J_Bip_C_Hips/J_Bip_L_UpperArm/…)
## berbeda NAMA dan biasanya orientasi rest. Strategi kalibrasi ilmiah:
## pindahkan DELTA rotasi dunia tiap tulang (pose_anim_global * rest_global⁻¹)
## ke frame rest target — benar walaupun orientasi sumbu tulang beda.
## Hanya track ROTASI tulang-dipetakan; posisi tidak dipindahkan
## (gerak vertikal kecil hilang; aman untuk ponsel & kamera).
## ============================================================

## Tabel alias -> inti tulang. Kunci = nama dinormalkan (tanpa "_").
const _ALIAS := {
	"root": "root", "hips": "hips", "pelvis": "hips",
	"spine": "spine1", "spine01": "spine1", "spine1": "spine1",
	"spine02": "spine2", "spine2": "spine2", "chest": "spine2",
	"spine03": "spine3", "spine3": "spine3", "upperchest": "spine3",
	"neck": "neck", "neck01": "neck", "neck1": "neck",
	"head": "head",
	"clavicle": "clavicle", "shoulder": "clavicle",
	"upperarm": "upperarm", "lowerarm": "lowerarm", "forearm": "lowerarm",
	"hand": "hand", "wrist": "hand",
	"upperleg": "upperleg", "thigh": "upperleg",
	"lowerleg": "lowerleg", "calf": "lowerleg", "shin": "lowerleg",
	"foot": "foot", "ankle": "foot",
	"toes": "toes", "toe": "toes", "ball": "toes",
	"thumb1": "thumb1", "thumb2": "thumb2", "thumb3": "thumb3",
	"thumb01": "thumb1", "thumb02": "thumb2", "thumb03": "thumb3",
	"index1": "index1", "index2": "index2", "index3": "index3",
	"index01": "index1", "index02": "index2", "index03": "index3",
	"middle1": "middle1", "middle2": "middle2", "middle3": "middle3",
	"middle01": "middle1", "middle02": "middle2", "middle03": "middle3",
	"ring1": "ring1", "ring2": "ring2", "ring3": "ring3",
	"ring01": "ring1", "ring02": "ring2", "ring03": "ring3",
	"pinky1": "pinky1", "pinky2": "pinky2", "pinky3": "pinky3",
	"pinky01": "pinky1", "pinky02": "pinky2", "pinky03": "pinky3",
	"little1": "pinky1", "little2": "pinky2", "little3": "pinky3",
	"little01": "pinky1", "little02": "pinky2", "little03": "pinky3",
}

## Inti & sisi sebuah nama tulang. {"core","side"}; core="" = bukan
## tulang inti yang bisa dipetakan (jari leaf, tulang twist, J_Sec_*, dst).
static func _bone_core(n: String) -> Dictionary:
	var s := n.to_lower().strip_edges()
	var side := "c"
	if s.begins_with("j_bip_l_"):
		side = "l"
		s = s.substr(8)
	elif s.begins_with("j_bip_r_"):
		side = "r"
		s = s.substr(8)
	elif s.begins_with("j_bip_c_"):
		s = s.substr(8)
	elif s.begins_with("j_"):
		return {"core": "", "side": ""}
	elif s.ends_with("_l"):
		side = "l"
		s = s.substr(0, s.length() - 2)
	elif s.ends_with("_r"):
		side = "r"
		s = s.substr(0, s.length() - 2)
	s = s.replace("_", "")
	var core: String = _ALIAS.get(s, "")
	if core == "" or core == "root":
		return {"core": core, "side": ""}
	return {"core": core, "side": side}

## Peta tebakan nama tulang {nama_sumber_asli: nama_target_asli}.
static func guess_bone_map(from_skel: Skeleton3D, to_skel: Skeleton3D) -> Dictionary:
	var idx_to := {}
	for i in to_skel.get_bone_count():
		var nm := to_skel.get_bone_name(i)
		var c := _bone_core(nm)
		if c["core"] != "":
			idx_to["%s|%s" % [c["side"], c["core"]]] = nm
	var out := {}
	for i in from_skel.get_bone_count():
		var nm := from_skel.get_bone_name(i)
		var c := _bone_core(nm)
		if c["core"] == "":
			continue
		var k := "%s|%s" % [c["side"], c["core"]]
		if idx_to.has(k):
			out[nm] = idx_to[k]
	return out

## Konteks rest skeleton: urutan tulang (induk dulu), rest lokal &
## rest global (rotasi), dan induk. Kunci nama = lowercase asli.
static func rest_ctx(skel: Skeleton3D) -> Dictionary:
	var order: Array = []
	for i in skel.get_bone_count():
		order.append(skel.get_bone_name(i).to_lower())
	var p := {}
	var rl := {}
	var rg := {}
	var idx := {}
	for i in skel.get_bone_count():
		idx[skel.get_bone_name(i).to_lower()] = i
	for b in order:
		var i: int = idx[b]
		var pi := skel.get_bone_parent(i)
		var pn := ""
		if pi >= 0:
			pn = skel.get_bone_name(pi).to_lower()
		p[b] = pn
		var rest: Transform3D = skel.get_bone_rest(i)
		var q: Quaternion = rest.basis.get_rotation_quaternion()
		rl[b] = q
		rg[b] = (rg.get(pn, Quaternion.IDENTITY) if pn != "" else Quaternion.IDENTITY) * q
	return {"order": order, "p": p, "rl": rl, "rg": rg}

## Sample sebuah track rotasi pada waktu t (slerp antar kunci).
static func _sample_quat(anim: Animation, ti: int, t: float) -> Quaternion:
	var n := anim.track_get_key_count(ti)
	if n == 0:
		return Quaternion.IDENTITY
	var v0: Quaternion = anim.track_get_key_value(ti, 0)
	if n == 1 or t <= anim.track_get_key_time(ti, 0):
		return v0
	for k in range(1, n):
		var tk: float = anim.track_get_key_time(ti, k)
		if t <= tk:
			var ta: float = anim.track_get_key_time(ti, k - 1)
			var qa: Quaternion = anim.track_get_key_value(ti, k - 1)
			var qb: Quaternion = anim.track_get_key_value(ti, k)
			var f := 0.0 if tk <= ta else (t - ta) / (tk - ta)
			return qa.slerp(qb, clampf(f, 0.0, 1.0))
	return anim.track_get_key_value(ti, n - 1)

## Retarget klip humanoid (tulang beda nama): pindahkan delta rotasi
## dunia per tulang yang terpetakan. Mengembalikan Animation BARU
## (track detik posisi/skala/morf dibuang dengan sadar).
static func retarget_humanoid(anim: Animation, from_ctx: Dictionary,
		to_ctx: Dictionary, bone_map: Dictionary, skel_prefix: String) -> Animation:
	var out := Animation.new()
	out.length = anim.length

	# waktu kunci gabungan dari track rotasi + track per tulang sumber
	var times: Array = []
	var track_of := {}                    # bone_lower -> index track
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var sub := String(anim.track_get_path(i).get_concatenated_subnames()).to_lower()
		track_of[sub] = i
		for k in anim.track_get_key_count(i):
			var t: float = anim.track_get_key_time(i, k)
			if not times.has(t):
				times.append(t)
	times.sort()
	if times.is_empty():
		return out

	# pemetaan balik: tulang target_lower -> tulang sumber_lower
	var fwd := {}
	for fb in bone_map:
		fwd[String(fb).to_lower()] = String(bone_map[fb]).to_lower()
	var rev := {}
	for fb2 in fwd:
		rev[fwd[fb2]] = fb2
	# nama asli tulang target (untuk path track)
	var to_asli := {}
	for b in to_ctx["order"]:
		to_asli[b] = b
	for nm in bone_map.values():
		to_asli[String(nm).to_lower()] = String(nm)

	var rows := {}     # target_lower -> [[t, quat_lokal], ...]
	for t in times:
		# 1) pose global sumber pada t (induk dulu)
		var gf := {}
		for b in from_ctx["order"]:
			var lq: Quaternion = from_ctx["rl"].get(b, Quaternion.IDENTITY)
			if track_of.has(b):
				lq = _sample_quat(anim, track_of[b], t)
			var pn: String = from_ctx["p"].get(b, "")
			gf[b] = gf.get(pn, Quaternion.IDENTITY) * lq
		# 2) latih global target: delta dunia ditransplantasi ke rest target
		var gt := {}
		for b2 in to_ctx["order"]:
			var pn2: String = to_ctx["p"].get(b2, "")
			var pg: Quaternion = gt.get(pn2, Quaternion.IDENTITY)
			var lq2: Quaternion
			if rev.has(b2):
				var sb: String = rev[b2]
				var rest_from: Quaternion = from_ctx["rg"].get(sb, Quaternion.IDENTITY)
				var d: Quaternion = gf.get(sb, rest_from) * rest_from.inverse()
				lq2 = pg.inverse() * (d * to_ctx["rg"].get(b2, Quaternion.IDENTITY))
				if not rows.has(b2):
					rows[b2] = []
				rows[b2].append([t, lq2])
			else:
				lq2 = to_ctx["rl"].get(b2, Quaternion.IDENTITY)
			gt[b2] = pg * lq2

	# 3) tulis track rotasi per tulang terpetakan
	for b2 in rows:
		var ti := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(ti, NodePath("%s:%s" % [skel_prefix, to_asli.get(b2, b2)]))
		for row in rows[b2]:
			out.track_insert_key(ti, row[0], row[1])
	return out

## Iterasi indeks track (helper: hindari range terbalik menyebar).
static func dup_iter(anim: Animation) -> Array:
	var idx := []
	for i in anim.get_track_count():
		idx.append(i)
	return idx

## Atur mode loop per peran. Mengembalikan anim yang sama.
static func apply_loop(anim: Animation, role: String) -> Animation:
	if role in LOCO_ROLES:
		anim.loop_mode = Animation.LOOP_LINEAR
	else:
		anim.loop_mode = Animation.LOOP_NONE
	return anim

## Ringkasan pemetaan untuk BootLog.
static func report(m: Dictionary) -> String:
	var bagian := []
	for role in ROLE_ORDER:
		var v: String = m.get(role, "")
		if v != "":
			bagian.append("%s=%s" % [role, v])
	return "anim map: " + (", ".join(bagian) if not bagian.is_empty() else "(kosong)")
