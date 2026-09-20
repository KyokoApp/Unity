shader_type spatial;
render_mode cull_disabled;
// Rumput kartun: quad silang berayun angin + menyingkap saat diinjak pemain.

uniform vec4 albedo_bottom : source_color = vec4(0.16, 0.40, 0.26, 1.0);
uniform vec4 albedo_tip : source_color = vec4(0.38, 0.68, 0.38, 1.0);
uniform float sway = 0.16;
uniform float sway_speed = 1.8;
uniform float band1 : hint_range(0.0, 1.0) = 0.35;
uniform float band2 : hint_range(0.0, 1.0) = 0.7;
uniform float softness : hint_range(0.01, 0.4) = 0.15;
uniform float shadow_tint : hint_range(0.1, 1.0) = 0.60;
uniform float mid_tint : hint_range(0.1, 1.0) = 0.8;
// interaksi pemain (diset dari skrip setiap frame)
uniform vec3 player_pos = vec3(0.0, -999.0, 0.0);
uniform float push_radius = 1.6;
uniform float push_strength = 0.9;

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	float phase = wp.x * 0.15 + wp.z * 0.17;
	float k = clamp(VERTEX.y, 0.0, 2.0);
	VERTEX.x += sin(TIME * sway_speed + phase) * sway * k;
	VERTEX.z += cos(TIME * sway_speed * 0.9 + phase * 1.3) * sway * 0.7 * k;
	// dorong menjauh dari kaki pemain (uap air senja: lembut & pendek)
	vec2 to_player = wp.xz - player_pos.xz;
	float d = length(to_player);
	if (d < push_radius && abs(wp.y - (player_pos.y)) < 3.0) {
		float f = 1.0 - d / push_radius;
		vec2 dir = to_player / max(d, 0.001);
		float push = f * f * push_strength * k;
		VERTEX.xz += dir * push;
		VERTEX.y -= push * 0.35; // sedikit tertekan
	}
}

void fragment() {
	ALBEDO = mix(albedo_bottom.rgb, albedo_tip.rgb, UV.y);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float l = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	float b = shadow_tint
		+ (mid_tint - shadow_tint) * smoothstep(band1 - softness, band1 + softness, l)
		+ (1.0 - mid_tint) * smoothstep(band2 - softness, band2 + softness, l);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * b * ATTENUATION;
	SPECULAR_LIGHT = vec3(0.0);
}
