// Shader rumput BARU — sesuai permintaan user ronde ini ("pake design ini
// ajh biar gampang, trus shader nya pake ini"): digabung dari DUA design
// shader yg dikirim user secara verbatim-ish:
//
//   DESIGN 1 (space-grass style, shader pertama user): dithered fadeout
//   per-pixel (mat4 dither + FRAGCOORD), warna bertingkat top/bottom +
//   noise_color kering bertekstur gol, foliage_texture (kartu silang,
//   mesh kartu-nya dibangun di world.gd _build_grass_blade_mesh), fitur
//   angin dari tekstur noise (wind_noise digulir TIME), wind_darken untuk
//   permainan cahaya-bayangan angin di ladang, fadeout_envelope jarak-
//   kamera. (Tinggi-heightmap TIDAK dipakai — dunia ASekai = pulau datar
//   y=0 absolut, jd heightmap_normals/unpack_normal dihapus: normal cukup
//   konstan ke atas spt kartu foliage klasik.)
//
//   DESIGN 2 (shader toon user: light() toon_ramp + rim): shading toon
//   bertingkat STEP turun dr toon_ramp (digulir dg ATTENUATION) + rim
//   light (shadow vs VIEW). Satu2nya perubahan: hint hint_albedo dihapus
//   (sudah usang/rem-4.4, cuma warning noise) — fungsi light() identik
//   100% dgn yg user kirim.
//
// Guardrail world-specific ASekai TETAP dipertahankan (hilang = bug
// besar melawan keputusan user lama): rumput MENYUSUT nol sebelum garis
// air (island/lake/river, rumus island_shape.gd disalin manual & WAJIB
// disamakan), variasi warna per-rumpun INSTANCE_CUSTOM.x, peleburan satu
// keluarga hijau dgn ground tanah (bottom_color = ground_color persis —
// teknik user-approved 'satu warna mulus').
//
// Dipakai oleh chunk-streaming world.gd (GrassChunk_*), 1 kartu-silang
// per rumpun; transform world_asli (node chunk diam di dunia).
shader_type spatial;
render_mode cull_disabled;

group_uniforms properties;
uniform float specular : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
// Jarak MULAI/TONAS pudar dither (meter dari kamera). Chunk render di
// world.gd: fade diminta selesai PERSIS sebelum petak terluar dibongkar,
// jd pembongkaran petak tak kelihatan nge-pop.
uniform vec2 fadeout_envelope = vec2(33.0, 55.0);

group_uniforms color;
// SATU KELUARGA HIJAU MULUS (teknik user-approved): bottom_color SAMA
// PERSIS dgn ground ground_color (0.285,0.450,0.260) — pangkal kartu
// lenyap mlebur ke tanah, yg terbaca cuma ujung (top) + aksen kering
// noise_color bertekstur gol.
uniform vec3 top_color : source_color = vec3(0.375, 0.545, 0.335);
uniform vec3 bottom_color : source_color = vec3(0.285, 0.450, 0.260);
uniform vec3 noise_color : source_color = vec3(0.46, 0.50, 0.28);

group_uniforms maps;
// Kartu rumput digambar RUNTIME (nol aset repo) di world.gd
// _make_grass_card_texture(): helai-helai putih tipis melebar di atas
// latar alpha-0; rgb putih polos — warna sesungguhnya dr sampel uniform.
uniform sampler2D foliage_texture;
uniform sampler2D color_noise;
uniform float color_noise_scale = 6.0;
uniform float color_noise_intensity : hint_range(0.0, 1.0) = 0;

group_uniforms wind;
uniform bool wind = true;
uniform sampler2D wind_noise;
uniform float wind_scale = 0.35;
uniform float wind_intensity = 0.30;
uniform float wind_speed = 0.25;
uniform float wind_darken : hint_range(0.0, 1.0) = 0.22;

group_uniforms toon_light;
// Ramp toon 4px (design 2 user) & rim light yg melekat ke tepi terang.
uniform sampler2D toon_ramp;
uniform float rim_power : hint_range(1.0, 100.0) = 1.6;
uniform float rim_size : hint_range(0.0, 1.0) = 0.35;

varying vec3 hm_pos;      // posisi dunia vertex (ruang kartu model->dunia)
varying float v_fade;     // hasil fadeout_envelope (0..1), utk dither discard
varying float v_variant;  // keacakan kecil per rumpun (INSTANCE_CUSTOM.x)

// ---- Batas air pulau (disalin MANUAL dr island_shape.gd & shader tanah —
// WAJIB disamakan kalau salah satu diubah; syarat design user: rumput tak
// boleh tumbuh di pasir/laut/danau/sungai) ----
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
const vec2 LAKE_CENTER = vec2(95.0, 75.0);
const float LAKE_RADIUS = 60.0;
const float LAKE_BANK = 14.0;
const vec2 RIVER_DIR = vec2(0.784, 0.621);
const vec2 RIVER_START = vec2(142.04, 112.26);
const float RIVER_LENGTH = 620.0;
const float RIVER_HALF_WIDTH = 18.0;
const float RIVER_BANK = 10.0;
const float RIVER_MEANDER_AMP = 16.0;
const float RIVER_MEANDER_FREQ = 0.008;
float lake_factor(vec2 p) {
	float d = length(p - LAKE_CENTER);
	return clamp((LAKE_RADIUS - d) / LAKE_BANK, 0.0, 1.0);
}
float river_factor(vec2 p) {
	vec2 rp = p - RIVER_START;
	vec2 perp = vec2(-RIVER_DIR.y, RIVER_DIR.x);
	float u = dot(rp, RIVER_DIR);
	float v = dot(rp, perp);
	float meander = sin(u * RIVER_MEANDER_FREQ) * RIVER_MEANDER_AMP;
	float dist = abs(v - meander);
	float w = clamp((RIVER_HALF_WIDTH - dist) / RIVER_BANK, 0.0, 1.0);
	float fade_in = clamp((u + RIVER_BANK) / (RIVER_BANK * 2.0), 0.0, 1.0);
	float fade_out = 1.0 - clamp((u - (RIVER_LENGTH - RIVER_BANK)) / (RIVER_BANK * 2.0), 0.0, 1.0);
	return w * fade_in * fade_out;
}
float any_water_factor(vec2 p) {
	return max(island_water_factor(p), max(lake_factor(p), river_factor(p)));
}

// ---- Design 1 user: matriks bayer dither 4x4 (verbatim) ----
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

void vertex() {
	v_variant = INSTANCE_CUSTOM.x;
	// Posisi vertex DI DUNIA (instance chunk tetap diam, lihat world.gd) —
	// UV.y kartu = 0 akar/1 ujung (dibangun demikian di world.gd).
	vec3 world_pre = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Guardrail #1: susutkan kartu ke nol sebelum air (laut/danau/sungai).
	float wf = any_water_factor(world_pre.xz);
	float island_fade = 1.0 - smoothstep(0.0, 0.3, wf);
	VERTEX *= island_fade;

	// Guardrail #2: fadeout dither jarak-kamera (design 1) — hitung dari
	// kamera SEKARANG (INV_VIEW_MATRIX[3].xyz = posisi kamera dunia), dr
	// vertex ASLI (bukan yg sudah disusutkan).
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	float camera_distance = distance(world_pre, cam_pos);
	float fadeout = clamp(remap(camera_distance, fadeout_envelope.x,
		fadeout_envelope.y, 1.0, 0.0), 0.0, 1.0);
	v_fade = fadeout;
	// dan jg susutkan vertikal helai pd fade rendah (hemat fill-rate di
	// radius terluar, efek dither lainnya di fragment). Fade 0 = nol.
	VERTEX *= max(fadeout, 0.001);

	// Angin (design 1): sampling gumpalan besar di ruang dunia, digulir
	// TIME; bobot UV.y^2 -> cuma ujung yg tertiup (akar diam menapak).
	if (wind) {
		float wind_at = texture(wind_noise,
			world_pre.xz * wind_scale * 0.01 + vec2(TIME * wind_speed)).r;
		float wind_offset = wind_at * wind_intensity * UV.y * UV.y;
		// rakit di ruang dunia lalu balik ke model via transpose-matrix
		// (basis rotasi-murni) — WAJIB krn tiap rumpun diputar yaw acak.
		vec3 wind_world = vec3(0.943, 0.0, 0.331) * wind_offset;
		VERTEX += (vec4(wind_world, 0.0) * MODEL_MATRIX).xyz;
	}

	hm_pos = world_pre;
	// Normal kartu dicondongkan ke atas (foliage klasik) spy shading toon
	// toon_ramp membacanya spt kanopi, bukan dinding tegak. CATAT: di
	// vertex() NORMAL dinyatakan dlm RUANG MODEL (engine yg mentransform
	// ke view-space setelahnya) — JANGAN kalikan VIEW/MODEL_MATRIX manual
	// di sini (kesalahan double-transform pernah dibuat di putaran ini).
	NORMAL = normalize(mix(normalize(NORMAL), vec3(0.0, 1.0, 0.0), 0.72));
}

void fragment() {
	// ---- Design 1 user: dithered fadeout (verbatim) ----
	float limit = getValue(int(FRAGCOORD.x) % 4, int(FRAGCOORD.y) % 4);
	if (v_fade < limit - 0.001) {
		discard;
	}

	vec4 card = texture(foliage_texture, UV);
	ALPHA = card.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	// ---- Design 1 user: campur warna bertingkat + noise gersang ----
	float color_noise_at_position = mix(0.0,
		texture(color_noise, hm_pos.xz * color_noise_scale * 0.001).r,
		color_noise_intensity);
	vec3 base_color = mix(bottom_color, top_color, UV.y);
	// aksen kering hanya di ujung + hanya rumpun variant TINGGI (sekema
	// lama yg user approved: pangkal tetap satu warna dgn tanah).
	float dryness = smoothstep(0.90, 0.99, v_variant) * UV.y;
	vec3 mixed_color = mix(mix(base_color, noise_color, color_noise_at_position),
		noise_color, dryness);

	// ---- Design 1 user: permainan cahaya-bayangan angin di ladang ----
	float wind_darkening = mix(1.0,
		texture(wind_noise, hm_pos.xz * wind_scale * 0.01 + vec2(TIME * wind_speed)).r,
		wind_darken);
	if (!wind) { wind_darkening = 1.0; }

	ALBEDO = mixed_color * card.rgb * wind_darkening
		* mix(0.90, 1.10, v_variant);
	SPECULAR = specular;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}

// ---- Design 2 user: shading TOON via toon_ramp + rim light (verbatim,
// hanya tanpa hint_albedo yg usang) ----
void light() {
	float shadow = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float rim = (shadow * (clamp(dot(NORMAL, VIEW), 0.0, 1.0) < rim_size ? 1.0 : 0.0));

	vec4 processed_shadow = texture(toon_ramp, ((shadow * ATTENUATION)).xy);

	DIFFUSE_LIGHT += (processed_shadow.rgb + (rim * rim_power)) * ALBEDO * LIGHT_COLOR;
}
