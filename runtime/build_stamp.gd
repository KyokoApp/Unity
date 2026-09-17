class_name BuildStamp
extends RefCounted

## ============================================================
## BUILD STAMP — identitas build yang terbaca di perangkat.
##
## File ini DITIMPA oleh CI (android-build.yml, step "Stempel
## build") tepat sebelum ekspor APK, jadi APK yang diuji user
## selalu bisa dikenali dari layar: stempel tampil di layar
## loading, di strip debug sentuh, di PerfHud, dan masuk BootLog
## (user://aurelia-boot.log).
##
## Nilai di repo ini hanya dipakai saat jalan dari editor / run
## tanpa stempel CI. JANGAN dijadikan acuan versi APK.
## ============================================================

const ID := "dev-lokal"

static func id() -> String:
	return ID
