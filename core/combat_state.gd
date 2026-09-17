class_name CombatState
extends RefCounted

## ============================================================
## COMBAT STATE — logika tempur & stamina, MURNI (tanpa engine).
##
## Aturan main, bukan presentasi: aturan kombo ("serangan ke-2
## dalam 0,9 detik = kombo 1") dan stamina ("regen setelah 1 detik
## tidak dipakai"). Bisa dites headless; character_motor tinggal
## memanggilnya.
##
## Semua waktu dalam DETIK, stamina 0..1.
## ============================================================

var stamina: float = 1.0

## >= 0 = sedang menyerang (detik sejak tebasan mulai). -1 = idle.
var attack_t: float = -1.0
var combo: int = 0                 ## 0..2, arah tebasan
var attack_dur: float = 0.55       ## lama satu tebasan
var combo_window: float = 0.9      ## jeda maks antar tebasan
var stamina_regen: float = 0.3     ## per detik
var regen_delay: float = 1.0       ## jeda sebelum regen jalan

var _last_end: float = -100.0
var _since_use: float = 100.0

func is_attacking() -> bool:
	return attack_t >= 0.0

func attack01() -> float:
	return 0.0 if attack_t < 0.0 else minf(1.0, attack_t / maxf(1e-6, attack_dur))

## now = waktu game (detik). Gagal kalau masih mid-swing.
func try_attack(now: float) -> bool:
	if attack_t >= 0.0:
		return false
	combo = int(combo + 1) % 3 if (now - _last_end < combo_window) else 0
	attack_t = 0.0
	return true

## now = waktu game. stamina_drain = stamina/detik (0 = regen).
func update(dt: float, now: float, stamina_drain: float) -> void:
	if attack_t >= 0.0:
		attack_t += dt
		if attack_t >= attack_dur:
			attack_t = -1.0
			_last_end = now

	if stamina_drain > 0.0:
		stamina = maxf(0.0, stamina - stamina_drain * dt)
		_since_use = 0.0
	else:
		_since_use += dt
		if _since_use > regen_delay:
			stamina = minf(1.0, stamina + stamina_regen * dt)

## Dash/skill: gagal kalau stamina kurang (tidak jadi negatif).
func spend_stamina(amount: float) -> bool:
	if stamina < amount:
		return false
	stamina -= amount
	_since_use = 0.0
	return true

func reset() -> void:
	stamina = 1.0
	attack_t = -1.0
	combo = 0
	_last_end = -100.0
	_since_use = 100.0
