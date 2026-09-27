shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;
// SELUBUNG kobaran api arcane (aditif) di sekitar inti peluru/peliharaan.
// RONDE INI (laporan user: "spirit api kurang realistis untuk animasi
// gerakan lidah api atau kobaran nya kurang baik") — gerakan jilatan dirombak
// biar terasa spt api BENERAN (bukan kabut ungu yg bergolak acak):
//  (1) lidah-lidah DISAMPING diletakkan MENYEMPIT ke atas (taper vertikal
//      kuat dgn 2 oktaf noise CONTOUR-terpisah -> cabang jilatan yg
//      tajam & bergerak independen, bukan gelung gelombang seragam),
//  (2) lidah juga bergetar ke samping (xz) seiring kenaikan y — gerak
//      "menari" kecil khas udara panas, bukan diam naik lurus vertikal,
//  (3) dimulai dr titik yg SAMA di seluruh selubung -> terlihat pembakaran
//      menempel di badan api utama (selalu jilat ke atas),
//  - saat bergerak, sisi belakang memanjang jadi EKOR (uniform `trail`,
//    dihaluskan di skrip -> transisi diam/jalan mulus),
//  - tepi siluet memudar lembut, pola noise mengalir ke atas & ke belakang.

uniform float intensity = 1.6;
uniform vec3 trail = vec3(0.0);        // vektor ekor (node visual tidak diputar -> ruang lokal = dunia)
uniform vec3 flow_offset = vec3(0.0);
uniform float rise = 0.55;             // tinggi jilatan energi ke atas
uniform float alpha_scale = 1.0;

varying vec3 obj_p;
varying float tail_w;

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
	float tl = length(trail);
	vec3 td = vec3(0.0, 1.0, 0.0);
	if (tl > 0.0001) {
		td = trail / tl;
	}
	float back = pow(max(dot(nrm, td), 0.0), 1.6);
	// n1: aliran laju biasa ke atas; n2: laju LBH CEPAT & lebih kecil-belokan,
	// ~x.x laju nyata lidah api yg menari & menjilat cepat, bukan "kabut
	// bergerak pelan". Digeser orbit xz pula spy jilatan tak monokrom semua
	// sisi sama.
	float n1 = fbm(VERTEX * 2.6 + flow_offset + vec3(0.0, -TIME * 3.2, 0.0));
	float n2 = fbm(VERTEX * 5.2 + flow_offset * 2.3 + vec3(0.0, -TIME * 7.0, 0.0));
	float up = max(nrm.y, 0.0);
	// taper vertikal: gerakan ke-UP/growing mengkristal SANGAT tajam di ujung
	// atas selubung (meruncing dgn 2 oktaf noise bukan 1), lembut di ekor
	// bawah — inilah ciri lidah api menaik (tak simetris > "torso bergolak").
	VERTEX += trail * back * (0.65 + 0.7 * n1);
	VERTEX.y += up * up * rise * (0.45 + 1.1 * n1 + 0.9 * n2);
	// goyang ke samping dgn y -- aliran udara panas berkelok-kelok (bukan
	// lurus-kaku spt asap gantungan), dan pendek bila dekat dasar selubungnya
	// diste-kan.
	vec2 sway_dir = vec2(cos(TIME * 3.1 + n1 * 6.3), sin(TIME * 2.7 + n2 * 4.0));
	VERTEX.xz += sway_dir * (0.02 + up * up * 0.10);
	VERTEX += NORMAL * (n1 - 0.47) * (0.16 + up * 0.10);
	tail_w = max(back * min(tl, 1.0), up * up * 0.8);
	obj_p = VERTEX;
}

void fragment() {
	float n = fbm(obj_p * 3.6 + flow_offset * 1.5 + vec3(0.0, -TIME * 4.2, 0.0));
	float n2 = fbm(obj_p * 7.5 + vec3(TIME * 0.8, -TIME * 6.0, 0.0));
	float n3 = fbm(obj_p * 4.4 + vec3(0.0, -TIME * 9.5, 0.0));
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = smoothstep(0.0, 0.65, facing);
	// torn-curves: angka yg berbeda-beda atas ruangan-waktu -> lingkaran
	// garis filamen punggung kecil/jaring yg kelihatan "memberikan bentuk
	// runcing pun bersih" terhadap lidah-lidah.
	float flame = smoothstep(0.30, 0.75, n + (n2 - 0.47) * 0.6 + (n3 - 0.5) * 0.55 + facing * 0.25 - tail_w * 0.25);
	// palet pastel-Ungu nyambung dgn palet dunia sore hangat + mat lavender
	// karakter (permintaan user: "buat warna gk bentrok ama warna lain"):
	// ungu gelap-tenang di bayangan (0.32,0.12,0.58), lavender pastel lembut
	// di terang, ujung HDR-tipis pastel cyan-putih utk bloom glow env.
	vec3 c = mix(vec3(0.32, 0.12, 0.58), vec3(0.68, 0.46, 0.96), flame);
	// ujung ultimo terang pastel-lavender (echo panas), murni HDR tipis ditangkap bloom env.
	c += vec3(0.55, 0.50, 1.0) * smoothstep(0.55, 0.98, flame) * 0.6;
	ALBEDO = c * intensity;
	ALPHA = clamp(edge * flame * (1.0 - tail_w * 0.45) * alpha_scale, 0.0, 1.0);
}

