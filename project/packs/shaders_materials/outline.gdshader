shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;
// Outline inverted-hull: paling murah & stabil di GPU mobile.

<<<<<<< HEAD
uniform vec4 outline_color : source_color = vec4(0.07, 0.05, 0.10, 1.0);
=======
uniform vec4 outline_color : source_color = vec4(0.24, 0.15, 0.14, 1.0);
>>>>>>> a7dedaa (style: palet turquoise pastel seluruh game + pratinjau eksposur CPU (siang/senja/malam))
uniform float thickness = 0.012; // meter (ruang dunia)

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
