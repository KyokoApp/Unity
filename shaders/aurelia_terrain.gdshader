shader_type spatial;
render_mode cull_disabled, specular_disabled;

// ============================================================
// aurelia_terrain.gdshader — terrain stylized. (Port dari
// AureliaTerrain.shader Unity.)
//
// Opaque, albedo dari VERTEX COLOR (dihitung TerrainSurface di
// core/, SUDAH DIUJI) — bukan texture splat: apa yang terlihat di
// layar = apa yang diuji, nol tekstur = nol memori tambahan.
//
// Pencahayaan: diffuse half-Lambert bertingkat (posterize lembut
// ala Genshin) + shadow directional + ambient global. Fog linear
// manual dari uniform global (dipakai semua shader Aurelia supaya
// kabut konsisten lintas material — lihat world_boot.gd).
//
// Detail noise sengaja dari posisi DUNIA, bukan UV chunk, supaya
// tidak ada jahitan di perbatasan chunk (sama seperti versi Unity).
// ============================================================

global uniform vec4 aurelia_fog_color : source_color;
global uniform float aurelia_fog_near;
global uniform float aurelia_fog_far;
global uniform vec4 aurelia_ambient_color : source_color;

uniform float detail_scale = 0.35;                 // per meter dunia
uniform float detail_strength : hint_range(0.0, 0.5) = 0.10;
uniform float large_scale = 0.012;
uniform float large_strength : hint_range(0.0, 0.5) = 0.14;
uniform float ambient_boost : hint_range(0.0, 2.0) = 1.0;
uniform float toon_steps : hint_range(2.0, 5.0) = 3.0;
uniform float toon_softness : hint_range(0.0, 0.5) = 0.30;

varying vec3 world_pos;
varying vec3 vertex_albedo;

// hash & value noise murah, tanpa tekstur
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_pos = wp.xyz;
	vertex_albedo = COLOR.rgb;
}

void fragment() {
	// dua lapis variasi dari posisi dunia XZ: halus & kasar.
	vec2 wp = world_pos.xz;
	float fine = value_noise(wp * detail_scale) - 0.5;
	float coarse = value_noise(wp * large_scale + 17.3) - 0.5;
	vec3 albedo = vertex_albedo * (1.0 + fine * detail_strength * 2.0
										 + coarse * large_strength * 2.0);

	ALBEDO = albedo;
	// Ambient datar dari siklus siang/malam (padanan SampleSH(N) di
	// Unity dengan ambientMode=Flat — konstan, tidak tergantung N).
	// Dilipat (1-fog) di sini (EMISSION hanya bisa diubah di fragment):
	// hasil akhir = (D+E)*(1-fog) + F*fog persis seperti MixFog.
	float depth = -VERTEX.z;
	float fogf = clamp((depth - aurelia_fog_near)
					   / max(1.0, aurelia_fog_far - aurelia_fog_near), 0.0, 1.0);
	EMISSION = albedo * aurelia_ambient_color.rgb * ambient_boost * (1.0 - fogf);
}

void light() {
	// Hanya directional (matahari); light lain dibiarkan nol.
	if (!LIGHT_IS_DIRECTIONAL) {
		return;
	}
	vec3 n = normalize(NORMAL);
	float ndl = dot(n, LIGHT);
	// half-Lambert: terrain low-poly terlihat keras dengan Lambert
	// murni; dunia ini memang bergaya flat-shaded.
	float diffuse = clamp(ndl * 0.5 + 0.5, 0.0, 1.0);
	diffuse = diffuse * diffuse;

	// Posterize LEMBUT ala Genshin: diffuse dilipat ke beberapa
	// tingkat dengan tepi halus.
	float tx = diffuse * toon_steps;
	float tb = floor(tx) + smoothstep(0.5 - toon_softness,
									  0.5 + toon_softness, fract(tx));
	diffuse = tb / toon_steps;

	// SHADOW (vec3) = pengali bayangan; ATTENUATION = atenuasi jarak.
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * diffuse * SHADOW * ATTENUATION;

	// Kabut linear manual (jarak pandang dari GfxResolver):
	// DIFFUSE diganti warna kabut (EMISSION sudah dilipat 1-fog di
	// fragment, jadi totalnya mix penuh persis MixFog Unity).
	float depth = -VERTEX.z;
	float fog = clamp((depth - aurelia_fog_near)
					  / max(1.0, aurelia_fog_far - aurelia_fog_near), 0.0, 1.0);
	DIFFUSE_LIGHT = mix(DIFFUSE_LIGHT, aurelia_fog_color.rgb, fog);
}
