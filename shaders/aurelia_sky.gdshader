shader_type sky;

// ============================================================
// aurelia_sky.gdshader — langit gradien stylized + piringan
// matahari. (Port dari AureliaSky.shader Unity.)
//
// Dipasang sebagai Sky di WorldEnvironment oleh scene, lalu
// warnanya digerakkan DayNightCycle per keyframe jam (pagi
// keemasan, siang biru lembut, senja jingga, malam biru tua).
//
// Murah: tanpa tekstur, tanpa noise, satu fungsi gradien + disc.
// Fog TIDAK diterapkan ke langit (langit adalah acuan warna
// kabut, bukan sebaliknya — kabut mengambil warna horizon).
// ============================================================

uniform vec4 top_color : source_color = vec4(0.36, 0.55, 0.82, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.75, 0.82, 0.88, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.55, 0.58, 0.62, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.3);
uniform float sun_size : hint_range(0.001, 0.05) = 0.0035;
uniform float sun_glow : hint_range(0.0, 1.0) = 0.14;

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 top = top_color.rgb;
	vec3 hor = horizon_color.rgb;
	vec3 bot = bottom_color.rgb;

	vec3 col;
	if (d.y >= 0.0) {
		col = mix(hor, top, pow(d.y, 0.55));
	} else {
		col = mix(hor, bot, pow(-d.y, 0.6));
	}

	// Piringan matahari + halo lembut.
	vec3 sun_dir = normalize(sun_direction);
	float s = dot(d, sun_dir);
	float disc = smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.45, s);
	// Halo dibuat rapat (pangkat 32) — tanpa ini kabur glow memenuhi
	// langit seperti matahari raksasa (keluhan visual awal).
	float glow = pow(clamp(s, 0.0, 1.0), 32.0) * sun_glow;
	col += sun_color.rgb * (disc * 1.6 + glow);

	COLOR = col;
}
