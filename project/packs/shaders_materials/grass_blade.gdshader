shader_type spatial;
// Helai rumput 3D di sekitar pemain (ronde-46 bag. C: tanah rumput lebat).
// Dipakai via MultiMeshInstance3D per PETAK (chunk streaming, lihat
// world.gd _build_grass_chunk/_update_grass_chunks) — 1 material dipakai
// bersama semua petak. cull_disabled supaya helai tipis tetap kelihatan
// dari kedua sisi (segitiga bersilang).
//
// PEROMBAKAN (user menunjuk referensi github.com/IcterusGames/
// SimpleGrassTextured & komplain "kok malah jadi ngikutin" thd versi
// sebelumnya): versi lama "membungkus" (wrap/modulo) posisi tiap helai ke
// petak kecil DI SEKITAR PEMAIN tiap frame — scr visual itu bikin petak
// rumput lebat SELALU persis nempel & seukuran sama di pemain kemanapun
// jalan (spt gelembung ikut pemain). Yang DIPORT dari referensi (bukan
// dipasang utuh — itu addon EDITOR yg dilukis manual, tak relevan dgn
// generate_async() prosedural kita) cuma PRINSIPnya: helai skrg TETAP di
// posisi dunia nyata (world.gd yg atur chunk mana dimuat/dibongkar), jadi
// shader ini JAUH lbh sederhana — tak ada lagi wrap/modulo sama sekali,
// cuma nyisa fade jarak biasa (spt kabut) berbasis player_pos supaya batas
// radius-muat petak tak kelihatan nge-pop pas dimuat/dibongkar.
render_mode cull_disabled;

uniform vec3 wind_dir = vec3(1.0, 0.0, 0.35);
uniform float wind_speed = 1.7;
// PERBAIKAN (laporan user: "rumput ... gk goyang yang kayak digithub" — msh
// terlalu halus dr referensi 3d-grass-shader): dinaikkan ~1.8x + ditambah
// gust sekunder (freq beda, lihat vertex()) spy goyangannya kelihatan jelas
// di perangkat & tak terasa seragam/monoton spt gelombang tunggal.
uniform float wind_strength = 0.29;
uniform vec3 base_color : source_color = vec3(0.09, 0.22, 0.08);  // dekat akar
uniform vec3 tip_color : source_color = vec3(0.42, 0.62, 0.20);   // dekat ujung
// PEROMBAKAN realisme (user: "kurang realistis"): sebagian kecil rumpun
// (dipilih pakai `variant`, bukan acak per-frame) dicondongkan ke warna
// agak kekuningan/kering, spt padang rumput asli yg tak pernah 100% hijau
// seragam satu warna persis.
uniform vec3 dry_tip_color : source_color = vec3(0.58, 0.52, 0.21);
uniform float shadow_tint : hint_range(0.0, 1.0) = 0.48;
uniform float mid_tint : hint_range(0.0, 1.0) = 0.85;
// Efek "backlight" (SSS palsu): ujung helai yg tipis tembus cahaya kalau
// matahari ada di belakangnya -> nyala keemasan khas rumput asli kena
// cahaya dr belakang, bukan flat-toon polos.
uniform float translucency : hint_range(0.0, 2.0) = 0.75;

// Posisi pemain (dunia, diperbarui tiap frame dr world.gd _process) +
// jarak mulai/selesai pudar. Petak yg dimuat streaming SELALU sedikit
// lebih lebar dr fade_end (lihat GRASS_UNLOAD_RADIUS_CHUNKS di world.gd)
// jadi helai SUDAH pudar tuntas ke nol SEBELUM petaknya benar2 dibongkar
// -> pemuatan/pembongkaran petak jadi tak kelihatan nge-pop sama sekali.
uniform vec2 player_pos = vec2(0.0, 0.0);
uniform float fade_start = 33.0;
uniform float fade_end = 55.0;

// "Injak" rumput (ronde-46, ide diadaptasi dari gameidea-studio/3d-grass-
// shader): helai menekuk MENJAUH dari pemain saat dilewati, di luar goyangan
// angin biasa -> berasa "menerobos rumput" waktu jalan, bukan cuma statis.
uniform float trample_power : hint_range(0.0, 3.0) = 1.1;
uniform float trample_radius : hint_range(0.1, 5.0) = 1.3;

// Batas pulau (ronde-46 lanjutan bag. C, permintaan user "pulau 12km +
// laut"; ronde ini: pulau diperkecil ke 3km + danau/sungai ditambah).
// Rumput TAK BOLEH tumbuh di pasir/laut/danau/sungai. Rumus disalin manual
// dr island_shape.gd (IslandShape) & dr shader tanah di world.gd — WAJIB
// disamakan kalau salah satu diubah (lihat komentar di island_shape.gd).
const float ISLAND_RADIUS = 1500.0;
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
// Danau + sungai (IslandShape.lake_factor/river_factor, disalin manual —
// permintaan user "ada aliran danau atau sungai"). WAJIB disamakan dgn
// island_shape.gd & world.gd kalau salah satu diubah.
const vec2 LAKE_CENTER = vec2(350.0, 450.0);
const float LAKE_RADIUS = 90.0;
const float LAKE_BANK = 14.0;
const vec2 RIVER_DIR = vec2(0.6, 0.8);
const vec2 RIVER_START = vec2(404.0, 522.0);
const float RIVER_LENGTH = 900.0;
const float RIVER_HALF_WIDTH = 16.0;
const float RIVER_BANK = 10.0;
const float RIVER_MEANDER_AMP = 55.0;
const float RIVER_MEANDER_FREQ = 0.006;
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

varying float height_w;   // 0=akar, 1=ujung (dibaca dari COLOR.a mesh)
varying float variant;    // keacakan warna per-instance (INSTANCE_CUSTOM.x)

void vertex() {
	height_w = COLOR.a;
	variant = INSTANCE_CUSTOM.x;

	// Posisi instance SKRG TETAP nyata di dunia (node petaknya diam persis
	// di titik tengah chunk, lihat world.gd) — tinggal diukur jaraknya ke
	// pemain buat fade, tak ada lagi wrap/modulo spt versi lama.
	vec2 inst_xz = MODEL_MATRIX[3].xz;
	float dist_edge = length(inst_xz - player_pos);
	float edge_fade = 1.0 - smoothstep(fade_start, fade_end, dist_edge);
	VERTEX *= edge_fade;

	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Rumput lenyap sblm garis air (laut/danau/sungai) — fade mulai SEBELUM
	// pasir/tepi penuh (wf 0.0-0.3) spy transisinya alami, bukan terpotong
	// tajam pas garis air. Pakai teknik shrink-ke-akar yg sama spt edge_fade
	// di atas (aman digabung, tinggal dikali lagi).
	float wf = any_water_factor(world_pos.xz);
	float island_fade = 1.0 - smoothstep(0.0, 0.3, wf);
	VERTEX *= island_fade;


	// Tekukan injak: cuma dihitung (termasuk inverse(MODEL_MATRIX) yg agak
	// mahal) utk helai yg BENAR2 dekat pemain — dibungkus if supaya ribuan
	// helai jauh lainnya tak ikut nanggung biayanya (hemat GPU mobile).
	vec2 to_player = world_pos.xz - player_pos;
	float dist_p = length(to_player);
	if (dist_p < trample_radius) {
		vec2 away_w = dist_p > 0.0005 ? (to_player / dist_p) : vec2(0.0);
		float trample = smoothstep(trample_radius, 0.0, dist_p) * height_w * height_w;
		vec3 away_model = (inverse(MODEL_MATRIX) * vec4(away_w.x, 0.0, away_w.y, 0.0)).xyz;
		VERTEX += away_model * trample * trample_power;
	}

	float phase = INSTANCE_CUSTOM.y * TAU;
	// Dua gelombang beda frekuensi+arah dijumlah (bukan satu sinus tunggal)
	// spy goyangannya terasa spt "gust" angin sungguhan yg tak seragam antar
	// rumpun, bukan gelombang mekanis berulang persis — lebih dekat ke kesan
	// referensi 3d-grass-shader yg diminta user.
	float sway = sin(TIME * wind_speed + world_pos.x * 0.6 + world_pos.z * 0.6 + phase);
	float gust = sin(TIME * wind_speed * 0.37 + world_pos.x * 0.11 - world_pos.z * 0.08 + phase * 1.7);
	float sway_total = sway * 0.7 + gust * 0.5;
	// hanya bagian atas helai yg bergoyang (akar diam) -> height_w^2 sbg bobot
	VERTEX += wind_dir * sway_total * wind_strength * height_w * height_w;
	// normal "palsu" dicondongkan ke atas biar cahaya tak terlihat pipih-datar
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.55));
}


void fragment() {
	vec3 col = mix(base_color, tip_color, height_w);
	// Sebagian rumpun (variant tinggi) condong ke warna kering — cuma di
	// area dekat ujung (height_w) spy pangkalnya ttp hijau spt rumput nyata.
	float dryness = smoothstep(0.74, 0.97, variant);
	col = mix(col, dry_tip_color, dryness * height_w);
	// variasi terang/gelap ringan per rumpun biar tak seragam monoton ("lebat")
	col *= mix(0.82, 1.22, variant);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float b = shadow_tint + (mid_tint - shadow_tint) * smoothstep(0.15, 0.5, l)
		+ (1.0 - mid_tint) * smoothstep(0.55, 0.85, l);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * b * ATTENUATION;
	// Backlight/SSS palsu: makin dekat sudut pandang ke arah "lawan cahaya"
	// (matahari di belakang helai relatif ke kamera), makin nyala keemasan
	// tipis di ujung (height_w) — efek translusen khas daun/rumput tipis.
	float back = pow(clamp(dot(-LIGHT, VIEW), 0.0, 1.0), 2.5) * height_w;
	DIFFUSE_LIGHT += tip_color * LIGHT_COLOR * back * translucency * ATTENUATION;
	SPECULAR_LIGHT = vec3(0.0);
}
