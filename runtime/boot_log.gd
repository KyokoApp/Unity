class_name BootLog
extends RefCounted

## ============================================================
## BOOT LOG — perekam pesan sejak SEBELUM scene dimuat.
## (Port dari BootLog.cs.)
##
## Masalah yang diselesaikan: kalau game macet di HP, tidak ada
## logcat dan tidak ada console. Kelas ini menampung pesan boot,
## menampilkannya di loading screen (kotak merah, didorong oleh
## WorldBoot), dan menulis salinan ke file:
##   user://aurelia-boot.log
## ============================================================

const MAX_LINES := 40

static var _lines: Array[String] = []
static var _error_count: int = 0
static var _file_path: String = ""
static var _installed: bool = false

static func install() -> void:
	if _installed:
		return
	_installed = true
	_file_path = "user://aurelia-boot.log"
	var f := FileAccess.open(_file_path, FileAccess.WRITE)
	if f != null:
		f.store_line("=== boot %s (%s) ===" % [
			Time.get_datetime_string_from_system(),
			OS.get_name()])
		f.close()
	else:
		_file_path = ""
	add("BootLog aktif.")

static func add(line: String) -> void:
	if line.is_empty():
		return
	_lines.append(line)
	if line.begins_with("[Error]") or line.begins_with("[Exception]") \
	or line.find("FATAL") >= 0:
		_error_count += 1
	while _lines.size() > MAX_LINES:
		_lines.remove_at(0)
	if not _file_path.is_empty():
		var f := FileAccess.open(_file_path, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
			f.store_line(line)
			f.close()

static func has_errors() -> bool:
	return _error_count > 0

static func tail(n: int = 10) -> String:
	var from: int = maxi(0, _lines.size() - n)
	return "\n".join(_lines.slice(from))
