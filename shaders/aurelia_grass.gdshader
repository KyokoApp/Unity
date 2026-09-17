shader_type spatial;
render_mode cull_disabled, specular_disabled;

// ============================================================
// aurelia_grass.gdshader — rumput stylized. (Port dari
// AureliaGrass.shader Unity, digambar ribuan instance lewat
// MultiMeshInstance3D di runtime/grass_field.gd.)
//
// Pilihan yang disengaja (sama persis dengan versi Unity):
//   * OPAQUE, bukan alpha-tested. Siluet bilah sudah meruncing di
//     geometri — opaque = tanpa sortir, tanpa overdraw, ramah HP.
//   * Angin di VERTEX shader: simpangan = sin(waktu + posisi
//     dunia), dikalikan uv.y supaya pangkal diam, ujung bergerak.
//   * Jarak jauh DITENGGELAMKAN ke pangkalnya (bukan alpha-fade),
//     lalu kabut menutupi sisanya.
//   * Tidak melempar bayangan: bayangan rumput 3 cm tidak terbaca
//     di layar 6 inci, biayanya nyata (runtime/grass_field.gd
//     mematikan cast_shadow di MultiMesh, seperti versi Unity yang
//     tidak punya pass ShadowCaster).
// ============================================================

global uniform vec4 aurelia_fog_color : source_color;
global uniform float aurelia_fog_near;
global uniform float aurelia_fog_far;
global uniform vec4 aurelia_ambient_color : source_color;

uniform vec4 base_color : source_color = vec4(0.16, 0.34, 0.13, 1.0);
uniform vec4 tip_color : source_color = vec4(0.45, 0.66, 0.24, 1.0);
uniform float wind_strength : hint_range(0.0, 0.6) = 0.16;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.1;
uniform float fade_start : hint_range(10.0, 80.0) = 22.0;
uniform float fade_end : hint_range(20.0, 120.0) = 30.0;

varying vec3 albedo_v;

// Hash murah dari posisi dunia instance: tiap rumpun punya fase
// angin dan variasi rona sendiri, tanpa data per-instance.
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	// Posisi dunia PANGKAL rumpun (titik origin instance).
	vec3 origin_ws = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = hash21(origin_ws.xz);

	// Angin: pangkal (uv.y=0) diam, ujung (uv.y=1) penuh. Dua
	// gelombang berfrekuensi beda supaya tidak terlihat sin murni.
	// (Arah x/z dalam ruang model == dunia: instance hanya yaw+skala.)
	float t = TIME * wind_speed;
	float w1 = sin(t * 1.7 + origin_ws.x * 0.35 + origin_ws.z * 0.22);
	float w2 = sin(t * 3.9 + origin_ws.x * 0.11 - origin_ws.z * 0.31) * 0.35;
	float amp = (w1 + w2) * wind_strength * UV.y * UV.y;
	VERTEX.x += amp;
	VERTEX.z += amp * 0.6;

	// Tenggelamkan rumpun jauh ke pangkalnya supaya tidak pop saat
	// sel cache dibangun; kabut menyamarkan sisanya. Karena origin
	// instance di ruang model adalah (0,0,0), mix(origin,pos,fade)
	// di dunia EKUIVALEN dengan menskalakan VERTEX di ruang model.
	vec3 pos_ws = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = distance(pos_ws, CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
	VERTEX *= fade;

	// Variasi rona per rumpun (+/- 8%).
	vec2 uv2 = vec2(UV.x, UV.y * (0.92 + h * 0.16));

	// Gradasi pangkal -> ujung (dihitung di vertex: 24/12 verteks
	// per rumpun jauh lebih murah daripada per fragmen).
	albedo_v = mix(base_color.rgb, tip_color.rgb, clamp(uv2.y, 0.0, 1.0));
}

void fragment() {
	ALBEDO = albedo_v;
	// Ambient datar proyek. EMISSION hanya bisa diubah di fragment —
	// lipat (1-fog) di sini supaya total fog persis MixFog Unity.
	float depth = -VERTEX.z;
	float fogf = clamp((depth - aurelia_fog_near)
					   / max(1.0, aurelia_fog_far - aurelia_fog_near), 0.0, 1.0);
	EMISSION = albedo_v * aurelia_ambient_color.rgb * (1.0 - fogf);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		// Half-Lambert dari matahari: sisi membelakangi tetap terang.
		float ndl = dot(normalize(NORMAL), LIGHT) * 0.5 + 0.5;
		vec3 lit = ALBEDO * LIGHT_COLOR * (ndl * 0.75 + 0.25) * SHADOW * ATTENUATION;

		// Kabut linear manual (konsisten lintas shader).
		float depth = -VERTEX.z;
		float fog = clamp((depth - aurelia_fog_near)
						  / max(1.0, aurelia_fog_far - aurelia_fog_near), 0.0, 1.0);
		lit = mix(lit, aurelia_fog_color.rgb, fog);
		DIFFUSE_LIGHT += lit;
}
}
