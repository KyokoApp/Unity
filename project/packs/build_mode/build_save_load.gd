class_name BuildSaveLoad
extends RefCounted
## SAVE / LOAD peta Build Mode ke JSON (spesifikasi user butir 6):
## seluruh data map (objek tertanam, sel GridMap terrain, titik-titik curve
## jalan) ditulis ke SATU berkas JSON via FileAccess di folder user://
## supaya peta yg sudah dibangun PERSIST antar sesi/hp.
##
## Static-helper (RefCounted, dipanggil tanpa node): skema dict:
## {
##   "version"  : 1,
##   "objects"  : [ {id, pos:[x,y,z], rot_y, scale}, ... ],
##   "terrain"  : { "cells" : [ [x, y, z, item, rot], ... ] },
##   "roads"    : [ { points : [[x,y,z], ...], width : float }, ... ],
## }
## Format kompak (array posisi, bukan objek bertele-tele) supaya berkas
## tetap kecil di HP walau ribuan sel/objek (peta pulau 1.5 km bisa
## menampung ratusan objek user).

const SAVE_PATH := "user://build_map.json"
const SAVE_VERSION := 1

## Tulis dict ke berkas JSON (FileAccess.WRITE). Dipisah dari constant
## SAVE_PATH supaya probe/dev bisa memakai berkas uji terpisah tanpa
## menimpa peta user sungguhan.
static func save_to(data: Dictionary, path: String = SAVE_PATH) -> String:
	if data.is_empty():
		return "kosong"
	data["version"] = SAVE_VERSION
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "gagal buka: " + error_string(FileAccess.get_open_error())
	# JSON.stringify tanpa indent = berkas terkecil yang masih manusiawi
	# buat dicek (bolean indent hanya utk debug; mobile-friendly tetap).
	f.store_string(JSON.stringify(data))
	f.close()
	return ""

## Baca berkas JSON -> Dictionary kosong {} bila belum ada save (peta
## baru) atau parse gagal (berkas corrupt — lebih baik mulai fresh drpd
## crash saat boot).
static func load_from(path: String = SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed
	return {}

## true bila sudah ada file save (tombol "Muat" bisa dinonaktifkan /
## status UI diberitahu tanpa harus memuat isinya dulu).
static func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)

## Pembantu pembulat posisi (3 desimal terasa tak kasat tapi berkas 3x
## lebih kecil & cepat di-parse drpd 2^53 digit float mentah).
static func pack_vec3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]

static func unpack_vec3(a: Array, fallback := Vector3.ZERO) -> Vector3:
	if a.size() < 3:
		return fallback
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
