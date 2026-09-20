shader_type spatial;
// Cel-shading 3 band ringan untuk GPU mobile (tanpa lookup texture).

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool use_texture = false;
uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform float band1 : hint_range(0.0, 1.0) = 0.36;
uniform float band2 : hint_range(0.0, 1.0) = 0.68;
uniform float softness : hint_range(0.01, 0.4) = 0.16;
uniform float shadow_tint : hint_range(0.1, 1.0) = 0.60;
uniform float mid_tint : hint_range(0.1, 1.0) = 0.78;
uniform float rim_amount : hint_range(0.0, 2.0) = 0.5;
uniform vec3 rim_color : source_color = vec3(1.0, 0.90, 0.70);

void fragment() {
	vec4 c = albedo;
	if (use_texture) {
		c *= texture(albedo_texture, UV);
	}
	ALBEDO = c.rgb;
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
