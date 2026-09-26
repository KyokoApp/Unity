extends Node
## QualityManager: menerapkan preset Rendah/Sedang/Tinggi.
## Yang diatur: skala resolusi render, jarak pandang (ring chunk), kepadatan
## instance (rumput/pohon), kualitas shadow, batas FPS.
## World dan scatter mendaftarkan diri ke sini agar bisa di-update ulang.

var settings  # GameSettings
var world     # World (opsional, didaftarkan)
var sun: DirectionalLight3D  # didaftarkan oleh scene world
var blob_shadow: Node3D      # pemain (punya set_blob_shadow) — opsional

const PRESETS := {
	0: {  # Rendah
		"render_scale": 0.6, "chunk_rings": 4, "grass_density": 0.3,
		"tree_density": 0.6, "shadows": false, "shadow_size": 1024,
		"shadow_distance": 45.0, "fog": 1.25, "fps": 30,
	},
	1: {  # Sedang (default)
		"render_scale": 0.75, "chunk_rings": 6, "grass_density": 0.6,
		"tree_density": 0.85, "shadows": true, "shadow_size": 2048,
		"shadow_distance": 70.0, "fog": 1.0, "fps": 30,
	},
	2: {  # Tinggi
		"render_scale": 0.9, "chunk_rings": 8, "grass_density": 1.0,
		"tree_density": 1.0, "shadows": true, "shadow_size": 2048,
		"shadow_distance": 110.0, "fog": 0.85, "fps": 60,
	},
}

func get_preset() -> Dictionary:
	return PRESETS[clampi(settings.quality_preset, 0, 2)]

func apply_all() -> void:
	var p := get_preset()
	# skala resolusi
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = float(p.render_scale)
	# batas fps
	Engine.max_fps = int(p.fps) if settings.fps_cap == 0 else int(settings.fps_cap)
	# shadow
	if sun:
		sun.shadow_enabled = bool(p.shadows)
		sun.directional_shadow_max_distance = float(p.shadow_distance)
	RenderingServer.directional_shadow_atlas_set_size(int(p.shadow_size), true)
	# blob shadow murah menggantikan shadow map saat preset tanpa bayangan
	if blob_shadow and is_instance_valid(blob_shadow) and blob_shadow.has_method("set_blob_shadow"):
		blob_shadow.set_blob_shadow(not bool(p.shadows))
	# fog & jarak pandang diserahkan ke world
	if world and world.has_method("apply_quality"):
		world.apply_quality(p)

func apply_fps_cap() -> void:
	Engine.max_fps = int(settings.fps_cap)

func on_settings_changed(key: String) -> void:
	match key:
		"quality_preset":
			apply_all()
		"fps_cap":
			Engine.max_fps = int(settings.fps_cap)
