extends RefCounted
## Updater: mengunduh manifest + resource pack secara inkremental.
## Hanya pack yang versi/hash-nya berubah yang diunduh ulang.
## Mendukung resume (HTTP Range), retry dengan backoff, verifikasi SHA-256,
## pembersihan pack lama, dan mode offline.

signal log_line(text)
signal stage(text)
signal pack_progress(pack_id, downloaded_bytes, total_bytes)
signal overall_progress(done_bytes, total_bytes)
signal confirm_needed(total_bytes, pack_count)
signal finished_ok(local_manifest)
signal finished_offline(local_manifest)
signal failed(reason)

const USER_AGENT := "PulauToon-Launcher/0.1 (+https://arena.ai)"
const MAX_RETRY := 4
const STATE_PATH := "user://launcher_state.json"
const LOCAL_MANIFEST_PATH := "user://local_manifest.json"
const PACKS_DIR := "user://packs"
const DOWNLOAD_OK_PATH := "user://download_ok.flag"

var tree: SceneTree  # diset dari Launcher
var _cancelled := false
var _confirmed := false
var _confirm_ok := true

func cancel() -> void:
	_cancelled = true

func respond_confirm(ok: bool) -> void:
	_confirm_ok = ok
	_confirmed = true

func _log(t: String) -> void:
	log_line.emit(t)
	print("[updater] ", t)

func _await_frame() -> void:
	await tree.process_frame

func _parse_url(u: String) -> Dictionary:
	var rest := u
	var scheme := "http"
	if rest.begins_with("https://"):
		scheme = "https"
		rest = rest.substr(8)
	elif rest.begins_with("http://"):
		rest = rest.substr(7)
	var slash := rest.find("/")
	var hostport := rest if slash == -1 else rest.substr(0, slash)
	var path := "/" if slash == -1 else rest.substr(slash)
	var host := hostport
	var port := 443 if scheme == "https" else 80
	var colon := hostport.rfind(":")
	if colon != -1 and hostport.count(":") == 1:
		host = hostport.substr(0, colon)
		port = int(hostport.substr(colon + 1))
	return {"scheme": scheme, "host": host, "port": port, "path": path}

## GET sederhana, mengembalikan PackedByteArray atau kosong bila gagal.
func _http_get(url: String, max_body := 64 * 1024 * 1024) -> PackedByteArray:
	var info := _parse_url(url)
	var c := HTTPClient.new()
	var tls = null
	if info.scheme == "https":
		tls = TLSOptions.client()
	var err := c.connect_to_host(info.host, info.port, tls)
	if err != OK:
		return PackedByteArray()
	var t0 := Time.get_ticks_msec()
	while c.get_status() == HTTPClient.STATUS_CONNECTING or c.get_status() == HTTPClient.STATUS_RESOLVING:
		c.poll()
		if Time.get_ticks_msec() - t0 > 15000 or _cancelled:
			c.close()
			return PackedByteArray()
		await _await_frame()
	if c.get_status() != HTTPClient.STATUS_CONNECTED:
		return PackedByteArray()
	err = c.request(HTTPClient.METHOD_GET, info.path, ["User-Agent: " + USER_AGENT, "Accept: */*"])
	if err != OK:
		c.close()
		return PackedByteArray()
	while not c.has_response():
		c.poll()
		if Time.get_ticks_msec() - t0 > 25000 or _cancelled:
			c.close()
			return PackedByteArray()
		await _await_frame()
	if c.get_response_code() != 200:
		c.close()
		return PackedByteArray()
	var body := PackedByteArray()
	while c.get_status() == HTTPClient.STATUS_BODY:
		c.poll()
		var chunk = c.read_response_body_chunk()
		if chunk.size() == 0:
			await _await_frame()
			continue
		body.append_array(chunk)
		if body.size() > max_body:
			break
	c.close()
	return body

func _fetch_manifest(base_url: String) -> Dictionary:
	var url := base_url.trim_suffix("/") + "/manifest.json"
	for attempt in range(3):
		if _cancelled:
			return {}
		_log("Mengunduh manifest (%d/3): %s" % [attempt + 1, url])
		var body := await _http_get(url)
		if body.size() > 0:
			var txt := body.get_string_from_utf8()
			var data = JSON.parse_string(txt)
			if typeof(data) == TYPE_DICTIONARY and data.has("packs") and data.has("pack_order"):
				_log("Manifest diterima: %d pack, game v%s" % [data["packs"].size(), str(data.get("game_version", "?"))])
				return data
			_log("Manifest tidak valid, mencoba lagi...")
		if attempt < 2:
			_log("Gagal mengunduh manifest, coba lagi dalam %d dtk" % (2 << attempt))
			var wait := float(2 << attempt)
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < wait * 1000.0:
				if _cancelled:
					return {}
				await _await_frame()
	return {}

func _load_local_manifest() -> Dictionary:
	if not FileAccess.file_exists(LOCAL_MANIFEST_PATH):
		return {}
	var f := FileAccess.open(LOCAL_MANIFEST_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if typeof(data) == TYPE_DICTIONARY else {}

func _save_local_manifest(m: Dictionary) -> void:
	var f := FileAccess.open(LOCAL_MANIFEST_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(m))
		f.close()

func _load_state() -> Dictionary:
	if not FileAccess.file_exists(STATE_PATH):
		return {}
	var f := FileAccess.open(STATE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else {}

func _save_state(s: Dictionary) -> void:
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(s))
		f.close()

func _sha256_of_file(path: String) -> String:
	var h := HashingContext.new()
	if h.start(HashingContext.HASH_SHA256) != OK:
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var chunk := f.get_buffer(1 << 20)
	while chunk.size() > 0:
		h.update(chunk)
		if _cancelled:
			f.close()
			return ""
		chunk = f.get_buffer(1 << 20)
	f.close()
	return h.finish().hex_encode()

func _pack_file(pack_id: String, version: String) -> String:
	return "%s/%s-%s.pck" % [PACKS_DIR, pack_id, version]

## Cek pack mana yang sudah utuh secara lokal (file + ukuran + versi cocok).
func _is_pack_present(pack_id: String, meta: Dictionary) -> bool:
	var path := _pack_file(pack_id, str(meta.get("version", "")))
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var ok := f.get_length() == int(meta.get("size", -1))
	f.close()
	return ok

## Uji ruang penyimpanan dengan menulis probe kecil.
func _probe_storage(needed_bytes: int) -> bool:
	var probe := PACKS_DIR + "/.probe"
	var to_write : int = min(needed_bytes, 8 * 1024 * 1024)
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	var buf := PackedByteArray()
	buf.resize(1024 * 256)
	var written := 0
	var ok := true
	while written < to_write:
		f.store_buffer(buf)
		written += buf.size()
		if f.get_error() != OK:
			ok = false
			break
	f.close()
	DirAccess.remove_absolute(probe)
	# dengan probe penuh, hitung rasio: bila probe sebagian saja yang bisa ditulis, ruang kurang
	return ok

## Unduh satu pack dengan resume + verifikasi. Return true bila sukses.
func _download_pack(pack_id: String, meta: Dictionary, base_url: String) -> bool:
	var version := str(meta["version"])
	var final_path := _pack_file(pack_id, version)
	if _is_pack_present(pack_id, meta):
		return true
	DirAccess.make_dir_recursive_absolute(PACKS_DIR)
	var url: String = str(meta["url"])
	if not url.begins_with("http"):
		url = base_url.trim_suffix("/") + "/" + url.trim_prefix("/")
	var tmp_path := final_path + ".tmp"
	var want_size := int(meta.get("size", -1))
	var want_hash := str(meta.get("sha256", ""))
	var info := _parse_url(url)

	for attempt in range(MAX_RETRY):
		if _cancelled:
			return false
		var resume_from := 0
		if FileAccess.file_exists(tmp_path):
			var fr := FileAccess.open(tmp_path, FileAccess.READ)
			if fr:
				resume_from = int(fr.get_length())
				fr.close()
			if want_size > 0 and resume_from >= want_size:
				resume_from = 0  # file tmp aneh, ulang dari nol
				DirAccess.remove_absolute(tmp_path)
		var c := HTTPClient.new()
		var tls = null
		if info.scheme == "https":
			tls = TLSOptions.client()
		if c.connect_to_host(info.host, info.port, tls) != OK:
			_log("  koneksi gagal, retry...")
			await _backoff(attempt)
			continue
		var t0 := Time.get_ticks_msec()
		while c.get_status() == HTTPClient.STATUS_CONNECTING or c.get_status() == HTTPClient.STATUS_RESOLVING:
			c.poll()
			if Time.get_ticks_msec() - t0 > 20000 or _cancelled:
				c.close()
				break
			await _await_frame()
		if c.get_status() != HTTPClient.STATUS_CONNECTED:
			c.close()
			await _backoff(attempt)
			continue
		var headers := ["User-Agent: " + USER_AGENT, "Accept: application/octet-stream"]
		if resume_from > 0:
			headers.append("Range: bytes=%d-" % resume_from)
			_log("  melanjutkan unduhan dari %s" % _fmt_bytes(resume_from))
		var rq := c.request(HTTPClient.METHOD_GET, info.path, headers)
		if rq != OK:
			c.close()
			await _backoff(attempt)
			continue
		t0 = Time.get_ticks_msec()
		while not c.has_response():
			c.poll()
			if Time.get_ticks_msec() - t0 > 25000 or _cancelled:
				c.close()
				break
			await _await_frame()
		if not c.has_response():
			c.close()
			await _backoff(attempt)
			continue
		var code := c.get_response_code()
		if code == 200 and resume_from > 0:
			# server tidak dukung Range -> mulai ulang dari nol (aman)
			_log("  server mengabaikan Range, unduh dari awal")
			resume_from = 0
		elif code != 200 and code != 206:
			_log("  HTTP %d, retry..." % code)
			c.close()
			await _backoff(attempt)
			continue
		var f: FileAccess
		if resume_from > 0:
			f = FileAccess.open(tmp_path, FileAccess.READ_WRITE)
			if f:
				f.seek(f.get_length())
		else:
			f = FileAccess.open(tmp_path, FileAccess.WRITE)
		if f == null:
			c.close()
			_log("  tidak bisa menulis file sementara")
			return false
		var downloaded := resume_from
		var body_len := c.get_response_body_length()
		var total := (resume_from + body_len) if body_len >= 0 else maxi(resume_from, want_size)
		pack_progress.emit(pack_id, downloaded, total)
		overall_progress.emit(_overall_base + downloaded, _overall_total)
		while c.get_status() == HTTPClient.STATUS_BODY:
			c.poll()
			var chunk = c.read_response_body_chunk()
			if chunk.size() == 0:
				if _cancelled:
					f.close(); c.close()
					return false
				await _await_frame()
				continue
			f.store_buffer(chunk)
			downloaded += chunk.size()
			pack_progress.emit(pack_id, downloaded, total)
			overall_progress.emit(_overall_base + downloaded, _overall_total)
		var dl_err := f.get_error()
		f.close()
		c.close()
		if dl_err != OK:
			_log("  kesalahan tulis disk")
			return false
		if want_size > 0 and downloaded != want_size:
			_log("  ukuran tidak cocok (%d != %d), unduh terpotong - retry" % [downloaded, want_size])
			await _backoff(attempt)
			continue
		# verifikasi hash
		stage.emit("Memverifikasi %s..." % pack_id)
		var got_hash := _sha256_of_file(tmp_path)
		if _cancelled:
			return false
		if want_hash != "" and got_hash != want_hash:
			_log("  HASH SALAH (%s), hapus & unduh ulang" % got_hash.substr(0, 12))
			DirAccess.remove_absolute(tmp_path)
			await _backoff(attempt)
			continue
		DirAccess.remove_absolute(final_path)
		var ren := DirAccess.rename_absolute(tmp_path, final_path)
		if ren != OK:
			_log("  gagal memindahkan file pack")
			return false
		_log("  OK: %s (%s)" % [pack_id, _fmt_bytes(downloaded)])
		return true
	return false

func _backoff(attempt: int) -> void:
	var wait := float(2 << attempt)
	_log("  menunggu %d dtk sebelum mencoba lagi..." % wait)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < wait * 1000.0:
		if _cancelled:
			return
		await _await_frame()

func _cleanup_old_packs(server_manifest: Dictionary) -> void:
	var dir := DirAccess.open(PACKS_DIR)
	if dir == null:
		return
	var keep := {}
	for pid in server_manifest.get("pack_order", []):
		var meta: Dictionary = server_manifest["packs"][pid]
		keep[_pack_file(pid, str(meta["version"])).get_file()] = true
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".pck") and not keep.has(name):
			_log("Menghapus pack lama: %s" % name)
			dir.remove(name)
		elif name.ends_with(".tmp"):
			pass  # biarkan untuk resume
		name = dir.get_next()
	dir.list_dir_end()

var _overall_base := 0
var _overall_total := 0

func _fmt_bytes(b: int) -> String:
	if b >= 1024 * 1024 * 1024:
		return "%.2f GB" % (b / 1073741824.0)
	if b >= 1024 * 1024:
		return "%.1f MB" % (b / 1048576.0)
	return "%.0f KB" % (b / 1024.0)

## Titik masuk utama. Dipanggil sekali dari Launcher.
func run(server_url: String) -> void:
	_cancelled = false
	stage.emit("Mengecek pembaruan...")
	DirAccess.make_dir_recursive_absolute(PACKS_DIR)
	var server_manifest := await _fetch_manifest(server_url)
	if server_manifest.is_empty():
		var local := _load_local_manifest()
		if not local.is_empty():
			var all_ok := true
			for pid in local.get("pack_order", []):
				if not _is_pack_present(pid, local["packs"][pid]):
					all_ok = false
					break
			if all_ok:
				_log("Server tidak terjangkau — memakai pack lokal (offline).")
				finished_offline.emit(local)
				return
			_log("Server tidak terjangkau dan pack lokal belum lengkap.")
			failed.emit("Server tidak terjangkau dan belum ada konten lokal lengkap. Periksa koneksi lalu coba lagi.")
			return
		failed.emit("Server tidak terjangkau dan belum ada konten lokal. Periksa koneksi lalu coba lagi.")
		return
	# bandingkan versi & keberadaan file
	var needed: Array = []
	var total_bytes := 0
	for pid in server_manifest["pack_order"]:
		var meta: Dictionary = server_manifest["packs"][pid]
		var local_state := _load_state()
		var state_ok := false
		if local_state.has(pid):
			var st: Dictionary = local_state[pid]
			state_ok = str(st.get("version", "")) == str(meta.get("version", "")) and str(st.get("sha256", "")) == str(meta.get("sha256", ""))
		if state_ok and _is_pack_present(pid, meta):
			continue
		needed.append(pid)
		total_bytes += int(meta.get("size", 0))
	if needed.is_empty():
		_log("Semua pack sudah versi terbaru.")
		_save_local_manifest(server_manifest)
		finished_ok.emit(server_manifest)
		return
	_log("Perlu mengunduh %d pack (%s): %s" % [needed.size(), _fmt_bytes(total_bytes), ", ".join(needed)])
	# cek ruang
	stage.emit("Memeriksa ruang penyimpanan...")
	if not _probe_storage(total_bytes):
		failed.emit("Ruang penyimpanan tidak cukup (butuh sekitar %s)." % _fmt_bytes(total_bytes))
		return
	# konfirmasi bila besar (atau di Android: sarankan Wi-Fi)
	if total_bytes > 0:
		_confirmed = false
		_confirm_ok = true
		confirm_needed.emit(total_bytes, needed.size())
		while not _confirmed and not _cancelled:
			await _await_frame()
		if _cancelled or not _confirm_ok:
			failed.emit("Unduhan dibatalkan pengguna.")
			return
	# unduh berurutan sesuai pack_order
	_overall_base = 0
	_overall_total = total_bytes
	var state := _load_state()
	for pid in needed:
		var meta: Dictionary = server_manifest["packs"][pid]
		stage.emit("Mengunduh %s (%s)..." % [pid, _fmt_bytes(int(meta.get("size", 0)))])
		_log("Pack %s v%s" % [pid, str(meta["version"])])
		var done_bytes: int = int(meta.get("size", 0))
		var ok := await _download_pack(pid, meta, server_url)
		_overall_base += done_bytes
		overall_progress.emit(_overall_base, _overall_total)
		if not ok:
			if _cancelled:
				failed.emit("Unduhan dibatalkan.")
			else:
				failed.emit("Gagal mengunduh pack '%s'." % pid)
			return
		state[pid] = {"version": str(meta["version"]), "sha256": str(meta.get("sha256", ""))}
		_save_state(state)
	_cleanup_old_packs(server_manifest)
	_save_local_manifest(server_manifest)
	var f := FileAccess.open(DOWNLOAD_OK_PATH, FileAccess.WRITE)
	if f:
		f.store_string(Time.get_datetime_string_from_system(true))
		f.close()
	stage.emit("Semua pack siap.")
	finished_ok.emit(server_manifest)
