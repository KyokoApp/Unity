shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// ============================================================
// aurelia_water.gdshader — air stylized. (Port dari
// AureliaWater.shader Unity.)
//
// Satu quad DATAR 1 segmen (4 verteks) yang mengikuti karakter —
// SEMUA gelombang dihitung di FRAGMENT dari posisi dunia + waktu.
// (Jangan di pindah ke vertex: quad sebesar 1.400 m berarti 1
// verteks tiap 175 m untuk gelombang sepanjang ~110 m.)
//
// Gaya: fresnel lembut + kilau matahari mengeras + glitter anime.
// Tanpa refleksi/refraksi planar — terlalu mahal untuk target HP,
// sama seperti keputusan di versi Unity.
//
// Matahari dibaca dari uniform global (air tidak ikut pass
// LIGHT Godot — bayangan terrain di permukaan air sengaja
// dikorbankan, efeknya nyaris tak terlihat di air stylized).
// ============================================================

global uniform vec4 aurelia_fog_color : source_color;
global uniform float aurelia_fog_near;
global uniform float aurelia_fog_far;
global uniform vec4 aurelia_sun_color : source_color;
global uniform vec3 aurelia_sun_direction;
global uniform vec4 aurelia_ambient_color : source_color;

uniform vec4 shallow_color : source_color = vec4(0.36, 0.58, 0.58, 0.55);
uniform vec4 deep_color : source_color = vec4(0.09, 0.24, 0.32, 0.88);
uniform float wave_height = 0.06;
uniform float wave_scale = 0.055;
// Pasangan water=0 di panel pengaturan: gelombang mati & air
// lebih bening (GfxResolver: water_waves=false, opacity 0.55).
uniform bool waves_enabled = true;
uniform float opacity = 0.86;
uniform float wave_speed = 0.55;
uniform float wave_speed2 = -0.33;
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform float fresnel_boost : hint_range(0.0, 4.0) = 1.6;
uniform float specular : hint_range(0.0, 4.0) = 1.2;
uniform float shininess : hint_range(4.0, 512.0) = 96.0;
uniform float glitter_strength : hint_range(0.0, 2.0) = 0.8;

varying vec3 world_pos;

float wave_h(vec2 wp, float t) {
	float a = sin((wp.x + wp.y) * wave_scale + t * wave_speed);
	float b = sin((wp.x - wp.y * 1.3) * wave_scale * 1.7 + t * wave_speed2);
	float c = sin(wp.y * wave_scale * 0.6 - t * wave_speed * 0.7);
	return (a * 0.5 + b * 0.3 + c * 0.2) * wave_height;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_pos = wp.xyz;
}

void fragment() {
	// Normal analitik dari turunan gelombang (beda terhingga).
	float t = TIME;
	float e = 0.35;
	vec2 wp = world_pos.xz;
	float hx = 0.0;
	float hz = 0.0;
	if (waves_enabled) {
		hx = wave_h(wp + vec2(e, 0.0), t) - wave_h(wp - vec2(e, 0.0), t);
		hz = wave_h(wp + vec2(0.0, e), t) - wave_h(wp - vec2(0.0, e), t);
	}
	vec3 n = normalize(vec3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)));
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);

	float fres = pow(clamp(1.0 - dot(n, v), 0.0, 1.0), fresnel_power);
	vec4 base_col = mix(deep_color, shallow_color, clamp(dot(n, v), 0.0, 1.0));
	vec3 col = base_col.rgb + fres * fresnel_boost * shallow_color.rgb;

	// Kilau matahari mengeras (toon) + glitter berkelip.
	vec3 sun_dir = normalize(aurelia_sun_direction);
	vec3 h = normalize(sun_dir + v);
	float spec = pow(clamp(dot(n, h), 0.0, 1.0), shininess);
	float spec_band = smoothstep(0.25, 0.75, spec);
	col += aurelia_sun_color.rgb * spec_band * specular;

	float cell = hash21(floor(wp * 2.5) + floor(t * 2.0) * 0.37);
	float glitter = step(0.985 - spec_band * 0.05, cell) * spec_band;
	col += aurelia_sun_color.rgb * glitter * glitter_strength;

	// Ambient datar proyek (padanan SampleSH(N) * 0.35).
	col += aurelia_ambient_color.rgb * base_col.rgb * 0.35;

	// Kabut linear manual (konsisten dengan shader lain).
	float depth = length(world_pos - CAMERA_POSITION_WORLD);
	float fog = clamp((depth - aurelia_fog_near)
					  / max(1.0, aurelia_fog_far - aurelia_fog_near), 0.0, 1.0);
	col = mix(col, aurelia_fog_color.rgb, fog);

	ALBEDO = col;
	ALPHA = clamp(base_col.a + fres * 0.35, 0.0, 1.0) * opacity;
}
