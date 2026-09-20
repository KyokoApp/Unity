shader_type sky;
// Langit kartun: gradasi 3-stop + cakram & halo matahari.
// Nilai di-lerp oleh skrip siang-malam (daynight.gd).

<<<<<<< HEAD
uniform vec3 horizon_color : source_color = vec3(0.75, 0.85, 0.95);
uniform vec3 zenith_color : source_color = vec3(0.22, 0.50, 0.85);
uniform vec3 ground_color : source_color = vec3(0.28, 0.32, 0.38);
=======
uniform vec3 horizon_color : source_color = vec3(0.86, 0.95, 0.86);
uniform vec3 zenith_color : source_color = vec3(0.30, 0.74, 0.69);
uniform vec3 ground_color : source_color = vec3(0.36, 0.44, 0.44);
>>>>>>> a7dedaa (style: palet turquoise pastel seluruh game + pratinjau eksposur CPU (siang/senja/malam))
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.72);
uniform float sun_size = 0.035;
uniform float halo = 0.22;

void sky() {
	float y = EYEDIR.y;
	vec3 base = mix(horizon_color, zenith_color, clamp(y * 1.6, 0.0, 1.0));
	if (y < 0.0) {
		base = mix(horizon_color, ground_color, clamp(-y * 3.0, 0.0, 1.0));
	}
	COLOR = base;
	if (LIGHT0_ENABLED) {
		float d = dot(EYEDIR, LIGHT0_DIRECTION);
		float disc = smoothstep(1.0 - sun_size, (1.0 - sun_size) + sun_size * 0.4, d);
		float glow = pow(clamp(d, 0.0, 1.0), 24.0) * halo;
		COLOR += sun_color * (disc + glow) * max(LIGHT0_ENERGY, 0.0);
	}
}
