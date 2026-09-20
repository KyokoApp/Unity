shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back;
// Air toon ringan: gelombang sinus + foam di tepi pantai (via peta tinggi pulau).

uniform vec4 shallow_color : source_color = vec4(0.20, 0.68, 0.68, 0.85);
uniform vec4 deep_color : source_color = vec4(0.07, 0.34, 0.47, 0.97);
uniform vec4 foam_color : source_color = vec4(0.95, 0.99, 0.95, 1.0);
uniform sampler2D shore_map : filter_linear, repeat_disable;
uniform float world_half = 800.0;
uniform float wave_speed = 0.9;
uniform float wave_scale = 0.10;
uniform float wave_height = 0.14;
uniform float band1 : hint_range(0.0, 1.0) = 0.35;
uniform float band2 : hint_range(0.0, 1.0) = 0.7;
uniform float softness : hint_range(0.01, 0.4) = 0.15;
uniform float shadow_tint : hint_range(0.1, 1.0) = 0.62;
uniform float mid_tint : hint_range(0.1, 1.0) = 0.85;

varying vec3 wpos;

void vertex() {
	float t = TIME * wave_speed;
	vec3 p = VERTEX;
	float h = sin(p.x * wave_scale + t) * 0.5
		+ sin(p.z * wave_scale * 1.3 + t * 1.4) * 0.35
		+ sin((p.x + p.z) * wave_scale * 0.7 + t * 0.8) * 0.25;
	VERTEX.y += h * wave_height;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float island_h(vec2 xz) {
	vec2 uv = (xz / (world_half * 2.0)) + 0.5;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return -30.0;
	}
	return texture(shore_map, uv).r * 255.0 - 20.0; // encode: (h + 20) / 255
}

void fragment() {
	float land = island_h(wpos.xz);          // >0 = darat di atas garis air
	float depth_f = smoothstep(0.0, -7.0, land); // 0 pantai -> 1 laut dalam
	vec4 col = mix(shallow_color, deep_color, depth_f);
	// pita foam mengikuti garis pantai, sedikit bergerak
	float foam_band = smoothstep(0.35, 0.06, abs(land + 0.2));
	float wob = sin(wpos.x * 1.9 + TIME * 2.1) * sin(wpos.z * 1.6 + TIME * 1.8);
	foam_band *= smoothstep(0.05, 0.42, wob);
	float sparkle = pow(max(0.0, sin(wpos.x * 3.1 + TIME) * sin(wpos.z * 2.7 - TIME * 1.25)), 8.0) * 0.10;
	ALBEDO = mix(col.rgb + sparkle, foam_color.rgb, foam_band);
	ALPHA = clamp(col.a + foam_band * 0.28, 0.0, 1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// normal palsu untuk kilau lembut
	NORMAL = normalize(mix(NORMAL, normalize(vec3(
		sin(wpos.x * 5.0 + TIME * 1.4) * 0.12, 1.0, cos(wpos.z * 4.4 + TIME * 1.2) * 0.12)), 0.45));
}

void light() {
	float l = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	float b = shadow_tint
		+ (mid_tint - shadow_tint) * smoothstep(band1 - softness, band1 + softness, l)
		+ (1.0 - mid_tint) * smoothstep(band2 - softness, band2 + softness, l);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * b * ATTENUATION;
	SPECULAR_LIGHT = vec3(0.0);
}
