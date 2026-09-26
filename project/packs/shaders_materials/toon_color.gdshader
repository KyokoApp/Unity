shader_type spatial;
render_mode cull_disabled;
// Varian toon memakai WARNA VERTEX (COLOR) — untuk terrain & props prosedural.
// cull_disabled: kebal perbedaan winding/culling antar driver (Adreno dsb).

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// detail painted opsional (dual-warna: rumput olive / pasir hangat), dipakai terrain
uniform bool detail_enabled = false;
uniform sampler2D detail_grass : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_sand : filter_linear_mipmap, repeat_enable;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.62;
uniform float detail_scale = 0.16;
uniform float band1 : hint_range(0.0, 1.0) = 0.36;
uniform float band2 : hint_range(0.0, 1.0) = 0.68;
uniform float softness : hint_range(0.01, 0.4) = 0.12;
uniform float shadow_tint : hint_range(0.1, 1.0) = 0.52;
uniform float mid_tint : hint_range(0.1, 1.0) = 0.78;
uniform float rim_amount : hint_range(0.0, 2.0) = 0.35;
uniform vec3 rim_color : source_color = vec3(0.95, 0.98, 1.0);

varying vec2 detail_uv;

void vertex() {
	detail_uv = VERTEX.xz * detail_scale;
}

void fragment() {
	ALBEDO = COLOR.rgb * albedo.rgb;
	if (detail_enabled) {
		// rumput: COLOR.g > COLOR.r ; pasir: COLOR.r > COLOR.g ; batuan ~campur
		float wg = clamp((COLOR.g - COLOR.r) * 8.0 + 0.5, 0.0, 1.0);
		vec3 dtl = mix(texture(detail_sand, detail_uv).rgb,
			texture(detail_grass, detail_uv).rgb, wg);
		ALBEDO *= mix(vec3(1.0), dtl * 2.0, detail_strength);
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float b = shadow_tint
		+ (mid_tint - shadow_tint) * smoothstep(band1 - softness, band1 + softness, l)
		+ (1.0 - mid_tint) * smoothstep(band2 - softness, band2 + softness, l);
	vec3 lc = LIGHT_COLOR * b * ATTENUATION;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	rim *= rim_amount * smoothstep(0.0, 0.25, l) * 0.4;
	DIFFUSE_LIGHT += ALBEDO * (lc + rim_color * rim);
	SPECULAR_LIGHT = vec3(0.0);
}
