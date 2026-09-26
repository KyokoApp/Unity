shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// AURA biru polos di sekitar inti laser Zoltraak. Memakai rumus liuk+glitch
// PERSIS sama dengan zoltraak_core.gdshader (uniform sama: beam_length, seed)
// supaya aura selalu menyatu konsentris dengan inti, bukan dua efek terpisah.

uniform float beam_length = 10.0;
uniform float seed = 0.0;
uniform float intensity = 1.5;
uniform float alpha_scale = 1.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	float along = VERTEX.y + beam_length * 0.5;
	float t = TIME;
	float wx = sin(along * 3.4 - t * 14.0 + seed) * 0.055;
	float wz = cos(along * 2.6 - t * 11.0 + seed * 1.7) * 0.048;
	float band = floor(along * 2.4);
	float slot = floor(t * 11.0);
	float gh = hash12(vec2(band + seed * 13.0, slot));
	float gm = hash12(vec2(band * 3.1 + 7.0 + seed, slot * 1.3)) * 2.0 - 1.0;
	float glitch = step(0.7, gh) * gm * 0.10;
	VERTEX.x += wx + glitch;
	VERTEX.z += wz + glitch * 0.6;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = smoothstep(0.0, 0.7, facing);
	ALBEDO = vec3(0.22, 0.52, 1.0) * intensity;
	ALPHA = edge * 0.5 * alpha_scale;
}
