shader_type spatial;
render_mode cull_disabled;

// ============================================================
// aurelia_toon.gdshader — shader karakter toon. (Port dari
// AureliaToon.shader Unity + AureliaToonLighting.hlsl.)
//
// Modelnya: diffuse bertingkat 2-4 dengan tepi HALUS (bukan
// posterize keras), bayangan berwarna (bukan hitam), rim lembut,
// specular anime yang mengeras di tengah. Satu directional light
// + ambient datar — cukup untuk stylized mobile.
//
// Outline inverted-hull tinggal di material next_pass
// (aurelia_toon_outline.gdshader) — padanan Pass "Outline" Unity.
// Versi tanpa semua ini: aurelia_toon_lite.gdshader.
// ============================================================

global uniform vec4 aurelia_fog_color : source_color;
global uniform float aurelia_fog_near;
global uniform float aurelia_fog_far;
global uniform vec4 aurelia_ambient_color : source_color;

uniform sampler2D base_map : source_color, filter_linear_mipmap;
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float ramp_strength : hint_range(0.0, 1.0) = 0.0;
uniform float toon_steps : hint_range(2.0, 5.0) = 3.0;
uniform float toon_softness : hint_range(0.0, 0.5) = 0.30;
uniform vec4 shadow_color : source_color = vec4(0.45, 0.42, 0.55, 1.0);
uniform float ambient_boost : hint_range(0.0, 2.0) = 1.0;
uniform vec4 rim_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 2.6;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.25;
uniform vec4 spec_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float spec_power : hint_range(4.0, 256.0) = 64.0;
uniform float spec_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength : hint_range(0.0, 4.0) = 0.0;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 tex = texture(base_map, UV);
	vec3 albedo = tex.rgb * base_color.rgb;
	float alpha = tex.a * base_color.a;
	if (alpha_cutoff > 0.001) {
		if (alpha < alpha_cutoff) {
			discard;
		}
	}
	ALBEDO = albedo;

	// Ambient datar proyek + emisi material, dilipat (1-fog) di
	// fragment (EMISSION hanya bisa diubah di sini) supaya total
	// kabut persis MixFog Unity.
	float depth = length(world_pos - CAMERA_POSITION_WORLD);
	float fogf = clamp((depth - aurelia_fog_near)
					   / max(1.0, aurelia_fog_far - aurelia_fog_near), 0.0, 1.0);
	EMISSION = (albedo * aurelia_ambient_color.rgb * ambient_boost
				+ emission_color.rgb * emission_strength) * (1.0 - fogf);
	ALPHA = alpha;
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		return;
	}
	vec3 n = normalize(NORMAL);
	float atten = SHADOW.r * ATTENUATION;

	// Half-lambert: sisi membelakangi cahaya jatuh ke tingkat
	// bayangan dengan lembut, tidak pernah hitam mendadak.
	float ndl = dot(n, LIGHT);
	float ramp_t = ndl * 0.5 + 0.5;

	// Tingkat bertingkat dengan tepi antialiased (AureliaSoftStep).
	float x = clamp(ramp_t * atten, 0.0, 1.0) * toon_steps;
	float band = floor(x);
	band += smoothstep(0.5 - toon_softness, 0.5 + toon_softness, fract(x));
	float stepped = band / toon_steps;

	// Warna cahaya toon: putih di terang, shadow_color di gelap.
	float ramp_w = clamp(ramp_t * atten, 0.0, 1.0);
	vec3 procedural = mix(shadow_color.rgb, vec3(1.0), stepped);
	vec3 light_col = procedural * mix(stepped, ramp_w, ramp_strength);

	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * light_col;

	// Rim lembut: tepi objek menangkap warna cahaya.
	float rim = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), rim_power) * rim_strength;
	DIFFUSE_LIGHT += rim_color.rgb * rim * LIGHT_COLOR * (0.35 + 0.65 * atten) * ALBEDO;

	// Specular anime: blob mengeras, bukan pantulan fisik.
	vec3 hv = normalize(LIGHT + VIEW);
	float spec_pow = pow(clamp(dot(n, hv), 0.0, 1.0), spec_power);
	float spec = smoothstep(0.45, 0.75, spec_pow) * spec_strength;
	DIFFUSE_LIGHT += spec_color.rgb * spec * atten * LIGHT_COLOR;

	// Kabut linear manual (konsisten dengan shader lain).
	float depth = -VERTEX.z;
	float fog = clamp((depth - aurelia_fog_near)
					  / max(1.0, aurelia_fog_far - aurelia_fog_near), 0.0, 1.0);
	DIFFUSE_LIGHT = mix(DIFFUSE_LIGHT, aurelia_fog_color.rgb, fog);
}
