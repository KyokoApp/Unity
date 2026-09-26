shader_type sky;
// Langit kartun: gradasi 3-stop + cakram & halo (matahari siang / bulan malam
// — mekanisme SAMA, cuma warna/ukuran ditukar oleh world.gd sesuai waktu),
// ditambah taburan bintang prosedural berkelap-kelip (ronde-46 bag. C: dunia
// malam permanen). Nilai di-lerp oleh world.gd (_apply_daylight).

uniform vec3 horizon_color : source_color = vec3(0.62, 0.88, 0.80);
uniform vec3 zenith_color : source_color = vec3(0.30, 0.74, 0.69);
uniform vec3 ground_color : source_color = vec3(0.36, 0.44, 0.44);
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.72);
uniform float sun_size = 0.035;
uniform float halo = 0.22;
// 0 = siang (tak ada bintang), 1 = malam gelap penuh (bintang penuh terlihat)
uniform float star_visibility : hint_range(0.0, 1.0) = 0.0;
uniform float star_density = 55.0;      // makin besar = makin banyak bintang kecil
uniform float star_twinkle_speed = 2.2;

float star_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void sky() {
	float y = EYEDIR.y;
	vec3 base = mix(horizon_color, zenith_color, clamp(y * 1.6, 0.0, 1.0));
	if (y < 0.0) {
		base = mix(horizon_color, ground_color, clamp(-y * 3.0, 0.0, 1.0));
	}
	COLOR = base;

	// Bintang: proyeksi sederhana arah pandang ke petak-petak, hanya di atas
	// cakrawala & memudar mendekati horizon (bukan hard cutoff yg aneh).
	if (star_visibility > 0.003 && y > 0.015) {
		vec2 cell_uv = EYEDIR.xz / (y + 0.15) * star_density;
		vec2 cell = floor(cell_uv);
		float h = star_hash(cell);
		float on = step(0.984, h);
		float tw = 0.5 + 0.5 * sin(TIME * (star_twinkle_speed + h * 4.0) + h * 41.0);
		float fade_horizon = smoothstep(0.02, 0.22, y);
		float brightness = mix(0.55, 1.0, star_hash(cell + 7.0));
		COLOR += vec3(0.92, 0.95, 1.0) * on * tw * brightness * fade_horizon * star_visibility;
	}

	if (LIGHT0_ENABLED) {
		float d = dot(EYEDIR, LIGHT0_DIRECTION);
		float disc = smoothstep(1.0 - sun_size, (1.0 - sun_size) + sun_size * 0.4, d);
		float glow = pow(clamp(d, 0.0, 1.0), 24.0) * halo;
		COLOR += sun_color * (disc + glow) * max(LIGHT0_ENERGY, 0.0);
	}
}
