shader_type spatial;
render_mode unshaded, cull_front, depth_draw_always;

uniform vec4 outline_color : source_color = vec4(0.12, 0.12, 0.15, 1.0);
uniform float outline_width : hint_range(0.0, 10.0) = 2.5;

void vertex() {
    // Inverted hull outline method (standard anime cartoon technique)
    vec4 clip_pos = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
    vec3 clip_normal = mat3(PROJECTION_MATRIX) * (mat3(MODELVIEW_MATRIX) * NORMAL);
    clip_pos.xy += normalize(clip_normal.xy) / VIEWPORT_SIZE * clip_pos.w * outline_width * 2.0;
    POSITION = clip_pos;
}

void fragment() {
    ALBEDO = outline_color.rgb;
    ALPHA = outline_color.a;
}
