shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, depth_draw_opaque;
// INTI laser Zoltraak (ala Frieren): tabung tipis putih->biru pudar yang
// meliuk pelan lalu "glitch" digital sesekali (offset tersentak-sentak,
// bukan mulus) di sepanjang sumbu Y lokal (arah tembak). Mesh: CylinderMesh
// tegak lurus, root node diputar supaya +Y == arah tembak.

uniform float beam_length = 10.0;
uniform float seed = 0.0;
uniform float intensity = 3.2;

varying float v_along01;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	float along = VERTEX.y + beam_length * 0.5; // 0 di pangkal -> beam_length di ujung
	v_along01 = clamp(along / max(beam_length, 0.001), 0.0, 1.0);
	float t = TIME;
	// gelombang halus (air mengalir)
	float wx = sin(along * 3.4 - t * 14.0 + seed) * 0.055;
	float wz = cos(along * 2.6 - t * 11.0 + seed * 1.7) * 0.048;
	// glitch digital: tersentak per-pita, berubah setiap ~0.09 detik
	float band = floor(along * 2.4);
	float slot = floor(t * 11.0);
	float gh = hash12(vec2(band + seed * 13.0, slot));
	float gm = hash12(vec2(band * 3.1 + 7.0 + seed, slot * 1.3)) * 2.0 - 1.0;
	float glitch = step(0.7, gh) * gm * 0.10;
	VERTEX.x += wx + glitch;
	VERTEX.z += wz + glitch * 0.6;
}

void fragment() {
	float shimmer = 0.5 + 0.5 * sin(TIME * 27.0 + v_along01 * 20.0 + seed * 4.0);
	vec3 c = mix(vec3(0.55, 0.80, 1.0), vec3(1.0, 1.0, 1.0), clamp(shimmer * 0.65 + 0.30, 0.0, 1.0));
	ALBEDO = c * intensity;
}
