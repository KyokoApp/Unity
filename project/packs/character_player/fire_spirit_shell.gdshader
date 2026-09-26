shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;
// SELUBUNG api (aditif) di sekitar inti peliharaan elemental — jilatan
// nyala selalu ke ATAS spt api sungguhan, sisi pemudaran lembut di tepi.
// Palet oranye/merah (BUKAN ungu, beda dr fireball_shell.gdshader punya
// peluru arcane) sesuai permintaan pengguna "spirit elemental api".

uniform float intensity = 1.7;
uniform vec3 flow_offset = vec3(0.0);
uniform float rise = 0.5;
uniform float alpha_scale = 1.0;

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
	vec3 nrm = normalize(VERTEX);
	float n = fbm(VERTEX * 2.8 + flow_offset + vec3(0.0, -TIME * 3.6, 0.0));
	float up = max(nrm.y, 0.0);
	VERTEX.y += up * up * rise * (0.45 + 1.1 * n);
	VERTEX += NORMAL * (n - 0.47) * 0.20;
	obj_p = VERTEX;
}

void fragment() {
	float n = fbm(obj_p * 3.8 + flow_offset * 1.5 + vec3(0.0, -TIME * 4.6, 0.0));
	float n2 = fbm(obj_p * 7.8 + vec3(TIME * 0.9, -TIME * 6.4, 0.0));
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = smoothstep(0.0, 0.65, facing);
	float flame = smoothstep(0.28, 0.74, n + (n2 - 0.47) * 0.6 + facing * 0.25);
	vec3 c = mix(vec3(0.55, 0.10, 0.02), vec3(1.0, 0.55, 0.12), flame);
	ALBEDO = c * intensity;
	ALPHA = clamp(edge * flame * alpha_scale, 0.0, 1.0);
}
