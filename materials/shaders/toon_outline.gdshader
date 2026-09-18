shader_type spatial;
render_mode unshaded, cull_front, depth_draw_always;

uniform vec4 outline_color : source_color = vec4(0.08, 0.08, 0.1, 1.0);
uniform float outline_width : hint_range(0.0, 10.0) = 2.2;

void vertex() {
    // Inverted hull toon outline expansion along vertex normal
    vec4 clip_pos = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
    vec3 clip_normal = mat3(PROJECTION_MATRIX) * (mat3(MODELVIEW_MATRIX) * NORMAL);
    if (length(clip_normal.xy) > 0.0001) {
        clip_pos.xy += normalize(clip_normal.xy) / VIEWPORT_SIZE * clip_pos.w * outline_width * 2.0;
    }
    POSITION = clip_pos;
}

void fragment() {
    ALBEDO = outline_color.rgb;
    ALPHA = outline_color.a;
}
