shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.35, 0.04, 1.0);
uniform float energy = 2.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring_r = mix(0.08, 0.95, progress);
	float width = mix(0.14, 0.03, progress);
	float ring = 1.0 - smoothstep(0.0, width, abs(r - ring_r));
	float inner = (1.0 - smoothstep(0.0, max(ring_r, 0.001), r)) * 0.18;
	float mask = step(r, 1.0);
	float fade = (1.0 - progress) * (1.0 - progress);
	ALBEDO = tint.rgb * energy;
	ALPHA = (ring + inner) * tint.a * fade * mask;
}
