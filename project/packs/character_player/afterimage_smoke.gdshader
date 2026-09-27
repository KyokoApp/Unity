shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
// Bayangan-asap SEKALI-TINGGAL utk dash (revisi user): SATU ghost abu2
// mengikuti bentuk karakter, "goyangan asap" (wobble vertex noise + naik
// perlahan), lalu padam. Pose karakter DIBEKUKAN dr sisi skrip (player.gd
// via skeleton hantu pribadi), shg bayangannya TAK ikut bergerak lagi —
// kesalahan versi lama (ghost merujuk skeleton hidup -> tampak ikut
// memainkan animasi jalan) sirna.
uniform vec3 smoke_color : source_color = vec3(0.68, 0.69, 0.72);
uniform float alpha = 0.40;
uniform float life01 : hint_range(0.0, 1.0) = 0.0;  // 0=fresh, 1=padam total (di-tween skrip)
uniform float wobble = 0.045;
uniform float rise = 0.10;                            // asap melayang naik seiring menua

varying vec3 vp;

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

void vertex() {
	vp = VERTEX;
	// wobble dua lapis: gumpalan besar malas + riak halus lebih cepat, makin
	// kuat seiring umur bayangan (asap "menyebar/mengembang" makin lama).
	float n1 = vnoise(vp * 4.5 + vec3(0.0, -TIME * 1.5, 0.0)) - 0.5;
	float n2 = vnoise(vp * 9.0 + vec3(TIME * 1.3, TIME * -2.1, 0.0)) - 0.5;
	VERTEX += NORMAL * (n1 * 2.0 * wobble * (0.3 + life01 * 1.7));
	VERTEX += vec3(n2 * wobble * (0.2 + life01), 0.0, n1 * wobble * (0.2 + life01));
	VERTEX.y += life01 * rise;
}

void fragment() {
	float facing = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float edge = smoothstep(0.0, 0.45, facing);
	float n = vnoise(vp * 7.0 + vec3(0.0, -TIME * 2.4, 0.0));
	float wisps = smoothstep(0.30, 0.78, n);
	ALBEDO = smoke_color * (0.82 + wisps * 0.28);
	ALPHA = alpha * (1.0 - life01) * edge * (0.45 + 0.55 * wisps);
}
