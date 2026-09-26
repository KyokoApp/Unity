shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, depth_draw_opaque;
// INTI proyektil mana: energi biru bergolak (fbm 3D prosedural, tanpa tekstur).
// Tengah (menghadap kamera) = putih terang, tepi = biru terang -> biru tua.
// Nilai ALBEDO > 1.0 (HDR) supaya ditangkap glow environment.

uniform float intensity = 2.6;
uniform vec3 flow_offset = vec3(0.0); // digeser skrip searah gerak -> pola "mengalir" ke belakang
uniform float turbulence = 1.0;

varying vec3 obj_p;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	float x00 = mix(n000, n100, f.x);
	float x10 = mix(n010, n110, f.x);
	float x01 = mix(n001, n101, f.x);
	float x11 = mix(n011, n111, f.x);
	return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	obj_p = VERTEX;
	// permukaan bergolak pelan (bukan bola sempurna)
	float n = fbm(VERTEX * 3.2 + flow_offset + vec3(0.0, -TIME * 2.4, 0.0));
	VERTEX += NORMAL * (n - 0.47) * 0.10 * turbulence;
}

void fragment() {
	vec3 q = obj_p * 4.0 + flow_offset * 1.3 + vec3(0.0, -TIME * 3.0, 0.0);
	float n1 = fbm(q);
	float n2 = fbm(obj_p * 9.0 + flow_offset * 2.0 + vec3(TIME * 0.6, -TIME * 5.0, 0.0));
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float heat = facing * 1.15 + (n1 - 0.47) * 1.1 + (n2 - 0.47) * 0.45 - 0.1;
	heat = clamp(heat, 0.0, 1.0);
	vec3 c = mix(vec3(0.03, 0.08, 0.35), vec3(0.10, 0.30, 0.95), smoothstep(0.05, 0.40, heat));
	c = mix(c, vec3(0.45, 0.75, 1.0), smoothstep(0.40, 0.72, heat));
	c = mix(c, vec3(0.90, 0.97, 1.0), smoothstep(0.72, 0.95, heat));
	float flicker = 0.92 + 0.08 * sin(TIME * 23.0 + n1 * 6.0);
	ALBEDO = c * intensity * (0.55 + 0.65 * heat) * flicker;
}
