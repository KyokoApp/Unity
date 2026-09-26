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

varying float height_w;   // 0=akar, 1=ujung (dibaca dari COLOR.a mesh)
varying float variant;    // keacakan warna per-instance (INSTANCE_CUSTOM.x)

void vertex() {
	height_w = COLOR.a;
	variant = INSTANCE_CUSTOM.x;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
