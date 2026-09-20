shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;
// Outline inverted-hull: paling murah & stabil di GPU mobile.

uniform vec4 outline_color : source_color = vec4(0.24, 0.15, 0.14, 1.0);
uniform float thickness = 0.012; // meter (ruang dunia)

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
