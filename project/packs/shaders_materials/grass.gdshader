shader_type spatial;
render_mode cull_disabled;
// Rumput kartun: quad silang berayun angin (tanpa tekstur).

uniform vec4 albedo_bottom : source_color = vec4(0.18, 0.45, 0.16, 1.0);
uniform vec4 albedo_tip : source_color = vec4(0.38, 0.72, 0.28, 1.0);
uniform float sway = 0.16;
uniform float sway_speed = 1.8;
uniform float band1 : hint_range(0.0, 1.0) = 0.35;
uniform float band2 : hint_range(0.0, 1.0) = 0.7;
uniform float softness : hint_range(0.01, 0.4) = 0.15;
uniform float shadow_tint : hint_range(0.1, 1.0) = 0.55;
uniform float mid_tint : hint_range(0.1, 1.0) = 0.8;

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	float phase = wp.x * 0.15 + wp.z * 0.17;
	float k = clamp(VERTEX.y, 0.0, 2.0);
	VERTEX.x += sin(TIME * sway_speed + phase) * sway * k;
	VERTEX.z += cos(TIME * sway_speed * 0.9 + phase * 1.3) * sway * 0.7 * k;
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
