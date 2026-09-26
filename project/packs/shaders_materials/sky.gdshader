shader_type sky;
// Langit kartun: gradasi 3-stop + cakram & halo (matahari siang / bulan malam
// — mekanisme SAMA, cuma warna/ukuran ditukar oleh world.gd sesuai waktu),
// ditambah taburan bintang prosedural (ronde-46 bag. C: dunia malam permanen).
// Nilai di-lerp oleh world.gd (_apply_daylight).
//
// Perbaikan laporan user: bintang JANGAN berkelap-kelip (dianggap tak
// realistis) & jumlahnya dikurangi jauh ("sedikit saja") — star_density
// diperkecil & TIDAK ADA lagi animasi kedip berbasis TIME; tiap bintang
// murni statis dgn kecerahan tetap (dari hash), spt langit malam sungguhan.

uniform vec3 horizon_color : source_color = vec3(0.62, 0.88, 0.80);
uniform vec3 zenith_color : source_color = vec3(0.30, 0.74, 0.69);
uniform vec3 ground_color : source_color = vec3(0.36, 0.44, 0.44);
// Titik gradasi ke-4 (ronde-46, ide diadaptasi dari plugin "day-and-night-
// cycle" maetzemax — teknik "smooth color transitions" mrk pakai 4 titik:
// atas/langit -> cakrawala -> dekat-tanah -> dasar. Kita TIDAK pakai plugin
// itu apa adanya (isinya siklus siang-malam otomatis + ProceduralSkyMaterial
// tanpa bintang/bulan, bentrok sama "malam permanen" yg baru dikunci) —
// cuma teknik gradasi 4-titiknya yg diadaptasi ke shader custom kita sendiri
// (tetap pertahankan bintang+bulan). world.gd biasanya isi ini dgn
// ground_color.darkened(...), meniru cara mrk turunkan warna dasar dari
// satu warna basis biar tetap harmonis.
uniform vec3 ground_bottom_color : source_color = vec3(0.05, 0.07, 0.10);
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.72);
uniform float sun_size = 0.035;
uniform float halo = 0.22;
// 0 = siang (tak ada bintang), 1 = malam gelap penuh (bintang penuh terlihat)
uniform float star_visibility : hint_range(0.0, 1.0) = 0.0;
uniform float star_density = 16.0;   // diperkecil jauh dari versi awal (55) -> jauh lebih jarang/sedikit

float star_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void sky() {
	float y = EYEDIR.y;
	// Gradasi 4-titik dgn smoothstep (bukan clamp linear + cabang if/else
	// spt sebelumnya) -> transisi lembut TANPA "seam"/kink yg kentara pas
	// tepat di garis cakrawala (y=0), krn smoothstep landai (turunan nol)
	// di kedua ujungnya, persis di titik sambung itu.
	vec3 base;
	if (y >= 0.0) {
		base = mix(horizon_color, zenith_color, smoothstep(0.0, 0.65, y));
	} else {
		vec3 lower = mix(horizon_color, ground_color, smoothstep(0.0, -0.35, y));
		base = mix(lower, ground_bottom_color, smoothstep(-0.35, -1.0, y));
	}
	COLOR = base;

	// Bintang: proyeksi sederhana arah pandang ke petak-petak, hanya di atas
	// cakrawala & memudar mendekati horizon (bukan hard cutoff yg aneh).
	// STATIS (tak ada TIME di sini sama sekali) — realistis, tak berkedip.
	//
	// PERBAIKAN #2 (laporan "gk kayak referensi github"): versi sebelumnya
	// TIDAK punya bentuk titik sama sekali — seluruh SEL yg lolos ambang
	// diwarnai rata (jadi tiap "bintang" tampak spt bercak kotak/pipih
	// pucat, bukan titik bulat berkilau). Sekarang tiap sel yg lolos diberi
	// 1 titik bulat (posisi & ukuran acak per-sel dari hash, spt magnitudo
	// bintang sungguhan — kebanyakan kecil, sesekali agak besar) + halo
	// lembut tipis di sekitarnya. JUMLAH bintang TETAP SEDIKIT (star_density
	// & ambang tak diubah, sesuai permintaan sebelumnya) — cuma bentuknya
	// yg dibetulkan jadi titik nyata, bukan ditambah banyak.
	if (star_visibility > 0.003 && y > 0.015) {
		vec2 cell_uv = EYEDIR.xz / (y + 0.15) * star_density;
		vec2 cell = floor(cell_uv);
		vec2 f = fract(cell_uv);
		float h = star_hash(cell);
		float on = step(0.992, h);   // ambang lebih tinggi drpd versi awal -> lebih sedikit yg jadi bintang
		// titik tak selalu pas di tengah sel -> taburan terasa alami, bukan grid kaku
		vec2 star_pt = vec2(star_hash(cell + 3.1), star_hash(cell + 9.7));
		float d = length(f - star_pt);
		float size = mix(0.045, 0.15, pow(star_hash(cell + 13.0), 3.0));
		float dot_core = smoothstep(size, size * 0.15, d);       // inti tajam bulat
		float dot_glow = smoothstep(size * 2.6, 0.0, d) * 0.30;  // halo tipis di sekitarnya
		float fade_horizon = smoothstep(0.02, 0.22, y);
		float brightness = mix(0.6, 1.0, star_hash(cell + 7.0));
		float shape = clamp(dot_core + dot_glow, 0.0, 1.0);
		COLOR += vec3(0.92, 0.95, 1.0) * on * brightness * shape * fade_horizon * star_visibility;
	}

	// Cakram matahari/bulan + corona. PERBAIKAN "bulan kurang indah": dulu
	// cuma 1 lapis halo SANGAT sempit (pow(d,24), nyaris tak kelihatan
	// kecuali nempel persis cakram) & cakram warna rata datar. Sekarang
	// ditambah 1 lapis corona LEBAR+lembut (pow(d,5)) biar ada aura cahaya
	// menyebar di sekitarnya (kesan "bersinar", bukan cuma bulatan solid),
	// plus gradasi halus di dalam cakram sendiri (tepi sedikit meredup)
	// biar tak terlihat flat. Mekanisme sun/moon TETAP SAMA (dipakai
	// bersama, cuma beda uniform dari world.gd sesuai waktu).
	if (LIGHT0_ENABLED) {
		float d = dot(EYEDIR, LIGHT0_DIRECTION);
		float disc = smoothstep(1.0 - sun_size, (1.0 - sun_size) + sun_size * 0.4, d);
		float disc_edge_dim = smoothstep(1.0 - sun_size, 1.0, d) * 0.12;
		vec3 disc_col = sun_color * (1.0 - disc_edge_dim);
		float glow_tight = pow(clamp(d, 0.0, 1.0), 20.0) * halo;
		float glow_wide = pow(clamp(d, 0.0, 1.0), 5.0) * halo * 0.16;
		COLOR += disc_col * disc * max(LIGHT0_ENERGY, 0.0);
		COLOR += sun_color * (glow_tight + glow_wide) * max(LIGHT0_ENERGY, 0.0);
	}
}
