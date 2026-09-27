// Shader rumput — ADOPSI KESELURUHAN "Grass-Shader-Example" karya
// @_Malido (https://github.com/Malidos/Grass-Shader-Example, lisensi CC0)
// sesuai permintaan user ronde ini ("ganti grass nya pake ini
// keseluruhan"). Inti merk dipertahankan verbatim:
//   - displacement angin dr tekstur Perlin (scroll TIME, lag UV.y/2.5 di
//     ujung — ujung tertiup sedikit "ketinggalan" dr hembusan), 2 jalur:
//     wind push + player push-back (instance_shader_parameters/player_
//     position disetel world.gd tiap frame, spt Character.gd merk),
//   - normal dipaksa ke atas (day/night-safe) + flip FRONT_FACING,
//   - fake AO pangkal (pow(UV.y,5)), specular dinaikkan ke ujung,
//     diffuse_toon engine (bkn lagi light() kustom).
//   - KONVENSI UV MERK: v=1 AKAR, v=0 UJUNG (blade mesh world.gd dibalik
//     menyesuaikan: _build_grass_blade_mesh). (1.0-UV.y) = bobot ujung.
//
// Dua guardrail world-specific ASekai ditambahkan (wajib, bkn bagian
// demo): (1) rumput menyusut nol sebelum garis air laut pulau (RONDE
// INI: danau/sungai DIHILANGKAN — permintaan user: air hanya di tepi
// pulau; jadi tinggal island_water_factor saja), (2) fadeout dither
// bayer per-piksel mendekati kamera-terjauh (chunk-streaming world.gd
// membongkar petak di radius ini; tanpa fade = pop-in kasar).
// top/bottom color sengaja TETAP keluarga hijau tanah ASekai (ground
// (0.285,0.450,0.260) di bawah, tip (0.375,0.545,0.335) terang) — teknik
// "satu warna mulus" yg sudah dua ronde disetujui user; AO pangkal merk
// justru memperkuat peleburan itu.
shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_schlick_ggx;
// Nice Shader by @_Malido ^^

// STYLE VISUAL merk (ronde ini — permintaan user "pake style ini ajh"):
// PALET WARNA persis material ExampleScene merk (dari ExampleScene.tscn):
// top veil lime terang (0.627,0.804,0.282), bottom hijau lush (0.416,
// 0.616,0.224). (Ground tanah world.gd jg diringankan mendekati supaya
// peleburan darat->rumput tetap halus, lihat komentar di _grass_material.)
uniform vec3 top_color: source_color = vec3(0.627, 0.804, 0.282);
uniform vec3 bottom_color: source_color = vec3(0.416, 0.616, 0.224);
uniform float ambient_occlusion_factor: hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float specular_strength: hint_range(0.0, 1.0, 0.01) = 0.4;
uniform float player_displacement_strength: hint_range(0.0, 1.0, 0.01) = 0.4;
uniform float player_displacement_size: hint_range(0.0, 2.0, 0.01) = 1.0;

uniform vec3 wind_direction = vec3(1.0, -0.7, -0.5); // Use a negative y component to give it an extra touch (For displacement effect and noise scroll direction)
uniform float wind_strength: hint_range(0.0, 1.0, 0.01) = 0.3;
uniform sampler2D wind_noise; // Periln FBM Noise looks Best
uniform float wind_noise_size: hint_range(0.0, 1.0, 0.001) = 0.05; // high values dont work well
uniform float wind_noise_speed: hint_range(0.0, 1.0, 0.001) = 0.1;

// Instance the Player Position through a GDScript in the _physics_process
instance uniform vec3 player_position;

// ---- additions ASekai: OPEN WORLD MODE + fadeout dither jarak-kamera ----
// open_world=1 = hutan berkakikabut (tanpa pulau/batas): island shrink
// dinolkan & blade menaiki terrain_wave milik tanah (1 rumus, sinkron
// tiga titik: di sini & shader tanah & OpenWorldMode.terrain_wave() —
// WAJIB disamakan kalau diubah).
uniform float open_world = 0.0;
float terrain_wave(vec2 p) {
	return 0.34 * sin(p.x * 0.031 + 1.7) + 0.30 * sin(p.y * 0.036 + 0.3) * cos(p.x * 0.023);
}

// ---- additions ASekai: fadeout dither jarak-kamera (nilai dr world.gd) ----
// Setara fungsi lama: [(start,end)] — selesai PERSIS sebelum petak
// terluar dibongkar supaya pembongkaran chunk tak nge-pop.
uniform vec2 fadeout_envelope = vec2(33.0, 55.0);
varying float v_fade;

const mat4 dither = mat4(
	vec4(0.0625, 0.5625, 0.1875,  0.6875),
	vec4(0.8125, 0.3125, 0.9375,  0.4375),
	vec4(0.25, 0.75, 0.125, 0.625),
	vec4(1.0, 0.5, 0.875,  0.375));
float getValue(int x, int y) {
	return dither[x][y];
}
float remap(float value, float istart, float istop, float ostart, float ostop) {
	return ostart + (ostop - ostart) * ((value - istart) / (istop - istart));
}

// ---- addition ASekai: batas air HANYA di tepi pulau (danau/sungai telah
// dihapus ronde ini — permintaan user) — disalin dr island_shape.gd &
// shader tanah world.gd; WAJIB disamakan kalau salah satu diubah. ----
const float ISLAND_RADIUS = 460.0;
const float BEACH_WIDTH = 55.0;
float island_radius_at(float theta) {
	return ISLAND_RADIUS * (1.0
		+ 0.20 * sin(theta * 3.0 + 1.3)
		+ 0.11 * sin(theta * 7.0 + 0.7)
		+ 0.06 * sin(theta * 11.0 + 2.4));
}
float island_water_factor(vec2 p) {
	float theta = atan(p.y, p.x);
	float r = length(p);
	float coast = island_radius_at(theta);
	return clamp((r - (coast - BEACH_WIDTH)) / BEACH_WIDTH, 0.0, 1.0);
}

void vertex() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Guardrail #1: susutkan blade ke nol sblm garis air laut (fade mulai
	// wf 0.0-0.3 spy transisi pasir lembut, bukan garis potong) — kecuali
	// mode Open World (tanpa pulau/laut; hutan tanpa batas).
	float wf = island_water_factor(world_position.xz);
	VERTEX *= 1.0 - smoothstep(0.0, 0.3, wf) * (1.0 - open_world);
	// Open World: blade menaiki gelombang tanah (rumus sinkron tiga titik —
	// lihat komentar di terrain_wave di atas); diterapkan SEBELUM angin supaya
	// goyangan tetap di ruang puncak lokal orangnya helai.
	if (open_world > 0.5) {
		VERTEX.y += terrain_wave(world_position.xz);
	}

	// Guardrail #2 (addition): fadeout dither jarak-kamera.
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	float camera_distance = distance(world_position, cam_pos);
	v_fade = clamp(remap(camera_distance, fadeout_envelope.x,
		fadeout_envelope.y, 1.0, 0.0), 0.0, 1.0);
	VERTEX *= max(v_fade, 0.001);

	// ============ VERBATIM @_Malido (Grass-Shader-Example) ============
	vec3 wind_texture = texture(wind_noise, world_position.xz * wind_noise_size + normalize(-wind_direction.xz) * (TIME + UV.y / 2.5) * wind_noise_speed).rgb;
	vec3 wind_vector = (vec4(wind_texture * normalize(wind_direction) * wind_strength, 0.0) * MODEL_MATRIX).xyz;

	float player_height = smoothstep(1.0, 0.0, length(player_position.y - world_position.y + 0.3));
	vec3 push_direction = vec3(world_position - player_position) * vec3(1 , -0.3 ,1);
	float player_position_factor = smoothstep(player_displacement_size, 0.0, length(push_direction));

	vec3 player_push_vector = (vec4(normalize(push_direction), 0.0) * MODEL_MATRIX).xyz;

	// Apply Player Position displacement
	VERTEX += player_push_vector * (1.0 - UV.y) * player_position_factor * player_displacement_strength * player_height;
	// Apply Wind displacement linearly
	VERTEX += wind_vector * (1.0 - UV.y) * (1.0 - player_position_factor * 0.7);

	// A new normal correction, which aligns the normals of the mesh facing upwards no matter the original direction.
	NORMAL = vec3(0.0, 1.0, 0.0);
	// ============ AKHIR VERBATIM ============
}

void fragment() {
	// addition: dither discard per-piksel (bayer 4x4) sesuai v_fade.
	if (v_fade < getValue(int(FRAGCOORD.x) % 4, int(FRAGCOORD.y) % 4) - 0.001) {
		discard;
	}

	// ============ VERBATIM @_Malido (Grass-Shader-Example) ============
	vec3 color = mix(bottom_color, top_color, 1.0 - UV.y);

	// Add fake ambient occlusion by darkening the base of the mesh
	float ao_fallof = pow(UV.y, 5.0);
	vec3 ao_color = bottom_color * (1.0 - ambient_occlusion_factor);

	ALBEDO = mix(color, ao_color, ao_fallof);
	ROUGHNESS = 0.4;

	// Increase the Specular with Grass Height
	SPECULAR *= (1.0 - UV.y) * specular_strength;

	// Just removing some funny shading
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	// ============ AKHIR VERBATIM ============
}
