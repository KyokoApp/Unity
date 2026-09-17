class_name JsMath
extends RefCounted

## ============================================================
## JS-MATH — pembulatan yang SETIA kepada ECMAScript.
##
## Ini ada karena uji paritas JS-vs-engine menangkap bug nyata:
## round() bawaan GDScript membulatkan setengah MENJAUHI nol
## (away from zero), sedangkan Math.round di JS membulatkan
## setengah ke +Infinity:
##
##     Math.round(22.5)   di JS       -> 23
##     Math.round(-22.5)  di JS       -> -22
##     round(-22.5)       di GDScript -> -23   <-- beda!
##
## Akibatnya nyata, bukan kosmetik: dustCount preset 'balanced'
## jadi 22 alih-alih 23, fogFar 1282 alih-alih 1283 — jumlah
## partikel dan jarak pandang bergeser diam-diam dari versi
## three.js aslinya.
##
## Karena itu SEMUA pembulatan yang di-port dari JS wajib lewat
## kelas ini. (Port dari Assets/_Project/Scripts/Core/JsMath.cs)
## ============================================================

## Definisi ECMAScript: Math.round(x) = floor(x + 0.5).
## NaN tetap NaN; +Inf/-Inf tetap apa adanya.
static func round_half_up(v: float) -> float:
	if is_nan(v) or is_inf(v):
		return v
	return floor(v + 0.5)

static func round_to_int(v: float) -> int:
	var r := round_half_up(v)
	# Jaga-jaga nilai di luar rentang int; tidak terjadi pada angka
	# di game ini, tapi cast yang overflow itu undefined.
	if r > 9223372036854775807.0:
		return 9223372036854775807
	if r < -9223372036854775808.0:
		return -9223372036854775808
	return int(r)
