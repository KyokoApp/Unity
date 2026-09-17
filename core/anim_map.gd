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
	"idle": ["idle", "idle loop", "standing", "breathing", "stand"],
	"walk": ["walk", "walking", "walk forward", "walk loop"],
	"run": ["run", "running", "sprint", "run forward", "jog"],
	"dash": ["dash", "dodge", "roll", "evade", "lunge"],
	"fall": ["fall", "falling", "air", "airborne", "in air"],
	"jump": ["jump", "jump up", "leap", "takeoff"],
	"land": ["land", "landing", "touchdown"],
	"attack0": ["attack1", "attack 1", "attack_1", "combo1", "slash1",
		"attack", "slash", "sword", "punch", "hit"],
	"attack1": ["attack2", "attack 2", "attack_2", "combo2", "slash2",
		"attack", "slash", "sword", "punch", "hit"],
	"attack2": ["attack3", "attack 3", "attack_3", "combo3", "slash3",
		"attack", "slash", "sword", "punch", "hit"],
	"skill": ["skill", "cast", "spell", "ability", "magic"],
	"burst": ["burst", "ultimate", "ult", "finisher", "special"],
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
