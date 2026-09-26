shader_type spatial;
// Helai rumput 3D dekat pemain (ronde-46 bag. C: tanah rumput lebat).
// Dipakai via MultiMeshInstance3D di world.gd (_build_grass). cull_disabled
// supaya helai tipis tetap kelihatan dari kedua sisi (segitiga bersilang).
render_mode cull_disabled;

uniform vec3 wind_dir = vec3(1.0, 0.0, 0.35);
uniform float wind_speed = 1.7;
uniform float wind_strength = 0.16;
uniform vec3 base_color : source_color = vec3(0.09, 0.22, 0.08);  // dekat akar
uniform vec3 tip_color : source_color = vec3(0.42, 0.62, 0.20);   // dekat ujung
uniform float shadow_tint : hint_range(0.0, 1.0) = 0.48;
uniform float mid_tint : hint_range(0.0, 1.0) = 0.85;
// "Pembungkus" posisi (ronde-46 bag. C perbaikan): world.gd TAK PERNAH
// menggeser node MultiMesh ini lagi (dulu bikin rumput terlihat ikut
// menyeret bareng pemain spt aura, laporan user "jalan aneh"). Sebagai
// gantinya tiap instance dibungkus (wrap) ke petak wrap_size di sekitar
// wrap_center (posisi pemain, diperbarui tiap frame) -> helai TERLIHAT
// DIAM terpaku di tanah selagi jalan, cuma yg pas di tepi terjauh yg
// "lompat" ke sisi berlawanan (disamarkan kabut jauh).
uniform vec2 wrap_center = vec2(0.0, 0.0);
uniform float wrap_size = 84.0;
// "Injak" rumput (ronde-46, ide diadaptasi dari gameidea-studio/3d-grass-
// shader): helai menekuk MENJAUH dari pemain saat dilewati, di luar goyangan
// angin biasa -> berasa "menerobos rumput" waktu jalan, bukan cuma statis.
// Dipakai lagi wrap_center sbg posisi pemain (sudah diberi tahu tiap frame
// dari world.gd), jadi tak perlu uniform posisi pemain terpisah.
uniform float trample_power : hint_range(0.0, 3.0) = 1.1;
uniform float trample_radius : hint_range(0.1, 5.0) = 1.3;

varying float height_w;   // 0=akar, 1=ujung (dibaca dari COLOR.a mesh)
varying float variant;    // keacakan warna per-instance (INSTANCE_CUSTOM.x)

void vertex() {
	height_w = COLOR.a;
	variant = INSTANCE_CUSTOM.x;
	// posisi asli instance (kolom translasi MODEL_MATRIX) dibungkus ke petak
	// wrap_size terdekat dari pemain, lalu MODEL_MATRIX ditimpa langsung —
	// rotasi/skala per-helai (kolom lain) tak tersentuh, cuma translasinya.
	vec2 inst_xz = MODEL_MATRIX[3].xz;
	vec2 rel = inst_xz - wrap_center;
	rel = mod(rel + vec2(wrap_size * 0.5), vec2(wrap_size)) - vec2(wrap_size * 0.5);
	MODEL_MATRIX[3].xz = wrap_center + rel;

	// Fade tepi (perbaikan #2, radius domain diperkecil dr 42->30 biar lbh
	// padat): tanpa ini, helai persis di garis wrap_size/2 akan "lompat"
	// (pop) ke sisi berlawanan tiap kali dilewati batas -> kentara krn
	// radius baru kini jauh dari fog_depth_begin. Jadi helai yg mendekati
	// garis batas MENGECIL ke arah akarnya sendiri (bukan tersembunyi tiba2)
	// sampai nol persis di garis batas -> lompatannya jadi tak kelihatan.
	float edge_dist = length(rel);
	float edge_fade = 1.0 - smoothstep(wrap_size * 0.5 * 0.80, wrap_size * 0.5 * 0.985, edge_dist);
	VERTEX *= edge_fade;

	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Tekukan injak: cuma dihitung (termasuk inverse(MODEL_MATRIX) yg agak
	// mahal) utk helai yg BENAR2 dekat pemain — dibungkus if supaya ribuan
	// helai jauh lainnya tak ikut nanggung biayanya (hemat GPU mobile).
	vec2 to_player = world_pos.xz - wrap_center;
	float dist_p = length(to_player);
	if (dist_p < trample_radius) {
		vec2 away_w = dist_p > 0.0005 ? (to_player / dist_p) : vec2(0.0);
		float trample = smoothstep(trample_radius, 0.0, dist_p) * height_w * height_w;
		vec3 away_model = (inverse(MODEL_MATRIX) * vec4(away_w.x, 0.0, away_w.y, 0.0)).xyz;
		VERTEX += away_model * trample * trample_power;
	}

	float phase = INSTANCE_CUSTOM.y * TAU;
	float sway = sin(TIME * wind_speed + world_pos.x * 0.6 + world_pos.z * 0.6 + phase);
	// hanya bagian atas helai yg bergoyang (akar diam) -> height_w^2 sbg bobot
	VERTEX += wind_dir * sway * wind_strength * height_w * height_w;
	// normal "palsu" dicondongkan ke atas biar cahaya tak terlihat pipih-datar
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.55));
}


void fragment() {
	vec3 col = mix(base_color, tip_color, height_w);
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
	SPECULAR_LIGHT = vec3(0.0);
}
