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
	## PENTING: importer GLTF Godot MEMOTONG akhiran "_Loop" dari nama
	## klip (bukti REPORTA di ci-logs: library memuat "Idle_No", bukan
	## "Idle_No_Loop"). Kandidat dipilih untuk NAMA HASIL IMPOR.
	"idle": ["idle no", "idleno", "idle no loop", "idle_loop",
		"idle loop", "idle", "standing", "breathing", "stand"],
	"walk": ["walk carry", "walk carry loop", "walk", "walking",
		"walk forward", "walk loop"],
	## Tak ada klip lari di UAL2 Standard; run selalu jatuh ke walk
	## yang dipercepat oleh AnimDriver (clamp speed 2,4x).
	"run": ["run", "running", "sprint", "run forward", "jog"],
	"dash": ["sword dash", "shield dash", "dash", "dodge", "roll",
		"evade", "lunge"],
	"fall": ["ninjajump idle", "ninjajump idle loop", "fall", "falling",
		"air", "airborne", "in air"],
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
		var q: Quaternion = rest.basis.get_rotation_quaternion().normalized()
		rl[b] = q
		rg[b] = ((rg.get(pn, Quaternion.IDENTITY) if pn != "" else Quaternion.IDENTITY) * q).normalized()
	return {"order": order, "p": p, "rl": rl, "rg": rg}

## ------------------------------------------------------------
## LIVE RETARGET — arsitektur definitif untuk dua skeleton beda
## nama (UE -> VRoid): file animasi dijalankan NATIV di skeleton
## paketnya sendiri (AnimationPlayer menguasai — seratus persen
## benar), lalu DELTA ROTASI DUNIA tiap tulang terpetakan
## disalin per-frame ke skeleton pengguna.
##
## Kenapa bukan bake (klip ditulis ulang): klip GLT Godot
## memakai konvensi pose-rest yang rumit bila diteliti manual —
## dengan menyalin dari skeleton yang SEDANG reguler bermain,
## pose sumber dijamin engine; yang kita hitung hanya delta dunia.
## -------------------------------------------------------------

## ------------------------------------------------------------
## TAKSIR ARAH HADAP — dua skeleton bisa menatap sumbu-Z berbalikan
## (mis. konvensi ekspor UE vs VRM). Bila ya, delta dunia sumber
## dikonjugasikan oleh 180° sumbu-atas sebelum ditransplantasikan —
## tanpa ini gerak tampak terbalik (keluhan "animasi malah mundur",
## lengan naik bukan turun).
## ------------------------------------------------------------

## Posisi rest tulang dalam ruang skeleton (komposisi induk).
static func rest_pos_ctx(skel: Skeleton3D) -> Dictionary:
	var out := {}
	var g := {}
	var idx := {}
	for i in skel.get_bone_count():
		idx[skel.get_bone_name(i).to_lower()] = i
	for i in skel.get_bone_count():
		var b := skel.get_bone_name(i).to_lower()
		var pi := skel.get_bone_parent(i)
		var pn := ""
		if pi >= 0:
			pn = skel.get_bone_name(pi).to_lower()
		var rest: Transform3D = skel.get_bone_rest(i)
		var xf: Transform3D = (g.get(pn, Transform3D()) if pn != ""
			else Transform3D()) * rest
		g[b] = xf
		out[b] = xf.origin
	return out

## Vektor hadap skeleton dari posisi anatomi: lengan kiri-kanan untuk
## arah lateral, pelvis->kepala untuk vertikal. ZERO bila tulang tak
## cukup dikenali (jangan pernah menebak).
static func _fwd(skel: Skeleton3D) -> Vector3:
	var pos := rest_pos_ctx(skel)
	var pl := Vector3.ZERO
	var pr := Vector3.ZERO
	var p_hips := Vector3.ZERO
	var p_head := Vector3.ZERO
	var punya := 0
	for nm in pos:
		var c := _bone_core(nm)
		match [c["core"], c["side"]]:
			["upperarm", "l"]:
				pl = pos[nm]
				punya |= 1
			["upperarm", "r"]:
				pr = pos[nm]
				punya |= 2
			["hips", _]:
				p_hips = pos[nm]
				punya |= 4
			["head", _]:
				p_head = pos[nm]
				punya |= 8
	if punya != 15:
		return Vector3.ZERO
	var lat: Vector3 = pl - pr
	var up: Vector3 = p_head - p_hips
	if lat.length() < 1e-4 or up.length() < 1e-4:
		return Vector3.ZERO
	# karakter menghadap lateral x atas (aturan tangan kanan):
	# (kiri - kanan) x atas. Uji anatomi (kiri di +X) -> +Z. Benar.
	return lat.cross(up).normalized()

## Quaternion flip arah hadap (180° sumbu atas) bila keduanya berbalikan.
static func facing_flip(from_skel: Skeleton3D, to_skel: Skeleton3D) -> Quaternion:
	var f := _fwd(from_skel)
	var t := _fwd(to_skel)
	if f == Vector3.ZERO or t == Vector3.ZERO:
		return Quaternion.IDENTITY
	if f.dot(t) < -0.2:
		return Quaternion(Vector3.UP, PI)
	return Quaternion.IDENTITY

## ------------------------------------------------------------
## PITAI SEKUNDER (J_Sec_*) — konversi VRM->GLB menyimpan rambut
## spring-bone pada POSE BIND "bergerak ke atas-luar" (fisika
## VRoid-lah yang seharusnya menjatuhkannya). Tanpa solver spring,
## pucuk pita terlihat melengkung di atas kepala. Solusi sekali
## pakai setelah bind: putar ROOT tiap rantai sehingga arah
## segmen pertamanya menjuntai ke bawah (sedikit keluar), anak
## kroni mengikuti secara struktural. Mengembalikan jumlah root
## yang diputar.
## ------------------------------------------------------------
static func droop_sec_bones(skel: Skeleton3D) -> int:
	var idx := {}
	var nama := {}
	for i in skel.get_bone_count():
		nama[i] = skel.get_bone_name(i)
		idx[nama[i].to_lower()] = i
	# rest dunia per tulang (komposisi induk) untuk arah segmen.
	var gxf := {}
	for i in skel.get_bone_count():
		var pn_idx := skel.get_bone_parent(i)
		var rest: Transform3D = skel.get_bone_rest(i)
		var px: Transform3D = gxf.get(pn_idx, Transform3D())
		gxf[i] = px * rest
	var digerakkan := 0
	for i in skel.get_bone_count():
		var nm_l: String = nama[i].to_lower()
		if not nm_l.begins_with("j_sec"):
			continue
		var pn2 := skel.get_bone_parent(i)
		if pn2 >= 0 and nama[pn2].to_lower().begins_with("j_sec"):
			continue  # hanya ROOT rantai — kroni ikut otomatis
		# cari anak pertama rantai untuk arah segmen awal.
		var anak := -1
		for j in skel.get_bone_count():
			if skel.get_bone_parent(j) == i and nama[j].to_lower().begins_with("j_sec"):
				anak = j
				break
		if anak < 0:
			continue
		var d0: Vector3 = (gxf[anak] as Transform3D).origin - (gxf[i] as Transform3D).origin
		if d0.length() < 1e-4:
			continue
		d0 = d0.normalized()
		# arah target: menjuntai ke bawah + sedikit keluar (x mengikuti
		# sisi posisi root), kroni membawa lekuk manis ikatan aslinya.
		var arah := Vector3(0.25 * signf((gxf[i] as Transform3D).origin.x), -0.96, 0.0).normalized()
		var r := Quaternion(d0, arah)
		var rest_l: Transform3D = skel.get_bone_rest(i)
		var rest_g: Quaternion = (gxf[i] as Transform3D).basis.get_rotation_quaternion()
		var g_new: Quaternion = (r * rest_g).normalized()
		var plah: Quaternion = Quaternion.IDENTITY
		if pn2 >= 0:
			plah = (gxf[pn2] as Transform3D).basis.get_rotation_quaternion()
		var lokal_abs: Quaternion = (plah.inverse() * g_new).normalized()
		var rest_lq: Quaternion = rest_l.basis.get_rotation_quaternion()
		var pose: Quaternion = (rest_lq.inverse() * lokal_abs).normalized()
		skel.set_bone_pose_rotation(i, pose)
		digerakkan += 1
	return digerakkan

## Persiapan rest + daftar tulang terpetakan (dihitung SEKALI).
static func prepare_live(from_skel: Skeleton3D, to_skel: Skeleton3D,
		ctx_f: Dictionary, ctx_t: Dictionary, bone_map: Dictionary) -> Dictionary:
	var per_bone := {}
	for fb in bone_map:
		var fi := from_skel.find_bone(String(fb))
		var ti := to_skel.find_bone(String(bone_map[fb]))
		if fi < 0 or ti < 0:
			continue
		var fb_low := String(fb).to_lower()
		var tb_low := String(bone_map[fb]).to_lower()
		var rest_f: Quaternion = ctx_f["rg"].get(fb_low, Quaternion.IDENTITY)
		per_bone[tb_low] = {
			"fi": fi, "ti": ti,
			"rest_f_inv": rest_f.inverse(),
			"rest_t": ctx_t["rg"].get(tb_low, Quaternion.IDENTITY),
		}
	var flip := facing_flip(from_skel, to_skel)
	return {"from_skel": from_skel, "to_skel": to_skel,
		"ctx_t": ctx_t, "per_bone": per_bone, "count": per_bone.size(),
		"flip_q": flip, "flip": 1 if flip != Quaternion.IDENTITY else 0}

## Salin delta dunia per frame (dipanggil SETELAH AnimationPlayer
## menyelesaikan frame-nya — driver menjamin urutan lewat _process).
static func live_apply(prep: Dictionary) -> void:
	var from_skel: Skeleton3D = prep["from_skel"]
	var to_skel: Skeleton3D = prep["to_skel"]
	var ctx_t: Dictionary = prep["ctx_t"]
	var per_bone: Dictionary = prep["per_bone"]
	## Wajib segarkan cache tulang sumber: tanpa ini get_bone_global_pose
	## baru mengetahui pose pada notifikasi berikut (di game = beda satu
	## frame, di uji headless langsung SALAH BESAR — tulang induk
	## dianggap tak pernah berpose).
	if from_skel.has_method("force_update_all_bone_transforms"):
		from_skel.call("force_update_all_bone_transforms")
	elif from_skel.has_method("force_update_all_dirty_bones"):
		from_skel.call("force_update_all_dirty_bones")
	var gt := {}
	for b in ctx_t["order"]:
		var pn: String = ctx_t["p"].get(b, "")
		var pg: Quaternion = gt.get(pn, Quaternion.IDENTITY)
		var rl: Quaternion = ctx_t["rl"].get(b, Quaternion.IDENTITY)
		var local_abs: Quaternion = rl
		if per_bone.has(b):
			var e: Dictionary = per_bone[b]
			var qa: Quaternion = from_skel.get_bone_global_pose(e["fi"]).basis.get_rotation_quaternion().normalized()
			var d: Quaternion = (qa * e["rest_f_inv"]).normalized()
			## Konjugasi flip arah hadap (identity bila sepakat).
			var fq: Quaternion = prep["flip_q"]
			if fq != Quaternion.IDENTITY:
				d = (fq * d * fq.inverse()).normalized()
			var g_abs: Quaternion = (d * e["rest_t"]).normalized()
			local_abs = (pg.inverse() * g_abs).normalized()
			## set_bone_pose_rotation = pose (rest-relative):
			## kunci tulisan = rl⁻¹ * lokal-absolut.
			var pose_val: Quaternion = (rl.inverse() * local_abs).normalized()
			to_skel.set_bone_pose_rotation(e["ti"], pose_val)
		gt[b] = (pg * local_abs).normalized()

## Retarget klip humanoid (tulang beda nama): pindahkan delta rotasi
## dunia per tulang yang terpetakan. Mengembalikan Animation BARU
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
