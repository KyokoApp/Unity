shader_type spatial;
render_mode cull_disabled, blend_mix, depth_prepass_alpha;

// ============================================================
// aurelia_toon_lite.gdshader — toon TANPA rim/spec/outline.
// (Port dari AureliaToonLite.shader Unity.)
//
// Dipakai untuk material transparan karakter (alis, bulu mata,
// iris — outline justru merusak wajah) dan sebagai pengganti
// total saat preset Rendah mematikan outline.
//
// depth_prepass_alpha meniru perilaku TransparentZWrite di
// versi Unity (MToon wajah): mencegah bulu mata/alis tembus
// rambut. Model pencahayaan IDENTIK dengan aurelia_toon.gdshader
// supaya hasilnya konsisten.
// ============================================================

global uniform vec4 aurelia_fog_color : source_color;
global uniform float aurelia_fog_near;
global uniform float aurelia_fog_far;
global uniform vec4 aurelia_ambient_color : source_color;

uniform sampler2D base_map : source_color, filter_linear_mipmap;
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float toon_steps : hint_range(2.0, 5.0) = 3.0;
uniform float toon_softness : hint_range(0.0, 0.5) = 0.30;
uniform vec4 shadow_color : source_color = vec4(0.45, 0.42, 0.55, 1.0);
uniform float ambient_boost : hint_range(0.0, 2.0) = 1.0;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength : hint_range(0.0, 4.0) = 0.0;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;
varying float view_depth;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	view_depth = -VERTEX.z;
	vec4 tex = texture(base_map, UV);
	vec3 albedo = tex.rgb * base_color.rgb;
	float alpha = tex.a * base_color.a;
	if (alpha_cutoff > 0.001) {
		if (alpha < alpha_cutoff) {
			discard;
		}
	}
	ALBEDO = albedo;

	float depth = length(world_pos - CAMERA_POSITION_WORLD);
	float fogf = clamp((depth - aurelia_fog_near)
					   / max(1.0, aurelia_fog_far - aurelia_fog_near), 0.0, 1.0);
	EMISSION = (albedo * aurelia_ambient_color.rgb * ambient_boost
				+ emission_color.rgb * emission_strength) * (1.0 - fogf);
	ALPHA = alpha;
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 n = normalize(NORMAL);
		float atten = ATTENUATION;

		float ndl = dot(n, LIGHT);
		float ramp_t = ndl * 0.5 + 0.5;

		float x = clamp(ramp_t * atten, 0.0, 1.0) * toon_steps;
		float band = floor(x);
		band += smoothstep(0.5 - toon_softness, 0.5 + toon_softness, fract(x));
		float stepped = band / toon_steps;

		vec3 light_col = mix(shadow_color.rgb, vec3(1.0), stepped);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * light_col;

		float depth = view_depth;
		float fog = clamp((depth - aurelia_fog_near)
						  / max(1.0, aurelia_fog_far - aurelia_fog_near), 0.0, 1.0);
		DIFFUSE_LIGHT = mix(DIFFUSE_LIGHT, aurelia_fog_color.rgb, fog);
}
}
