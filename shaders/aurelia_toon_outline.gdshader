shader_type spatial;
render_mode cull_front, unshaded;

// ============================================================
// aurelia_toon_outline.gdshader — outline karakter inverted-hull.
// (Padanan Pass "Outline" di AureliaToon.shader Unity.)
//
// Inverted hull klasik: kembangkan mesh sepanjang normal ruang
// model (aman untuk skinned mesh — di Godot VERTEX/NORMAL di
// vertex() masih pra-skinning... lihat catatan), lalu gambar
// sisi belakangnya saja (cull_front).
//
// Dipasang sebagai material `next_pass` pada material toon oleh
// runtime/toon_character_setup.gd; outline_width = 0 mematikannya
// tanpa mengganti material (setara skenario QualityApplier yang
// menukar shader toon -> lite di preset Rendah).
// ============================================================

global uniform vec4 aurelia_fog_color : source_color;
global uniform float aurelia_fog_near;
global uniform float aurelia_fog_far;

uniform vec4 outline_color : source_color = vec4(0.08, 0.07, 0.10, 1.0);
uniform float outline_width : hint_range(0.0, 0.05) = 0.008;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	float depth = -VERTEX.z;
	float fog = clamp((depth - aurelia_fog_near)
					  / max(1.0, aurelia_fog_far - aurelia_fog_near), 0.0, 1.0);
	ALBEDO = mix(outline_color.rgb, aurelia_fog_color.rgb, fog);
}
