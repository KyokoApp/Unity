// Screen-Space Cartoon / Anime Edge Outline Shader & Post-Processing
// Detects depth & color edges to give all 3D objects a crisp cartoon comic/anime outline!

shader_type canvas_item;
render_mode unshaded;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_nearest;

uniform float outline_thickness : hint_range(0.5, 4.0) = 1.2;
uniform float outline_threshold : hint_range(0.01, 1.0) = 0.08;
uniform vec4 outline_color : source_color = vec4(0.08, 0.08, 0.12, 1.0);

void fragment() {
    vec2 texel = vec2(outline_thickness) / vec2(textureSize(SCREEN_TEXTURE, 0));
    vec3 center_color = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;

    // Sample neighbors in 4 orthogonal directions
    vec3 c_up    = texture(SCREEN_TEXTURE, SCREEN_UV + vec2(0.0,  texel.y)).rgb;
    vec3 c_down  = texture(SCREEN_TEXTURE, SCREEN_UV + vec2(0.0, -texel.y)).rgb;
    vec3 c_left  = texture(SCREEN_TEXTURE, SCREEN_UV + vec2(-texel.x, 0.0)).rgb;
    vec3 c_right = texture(SCREEN_TEXTURE, SCREEN_UV + vec2( texel.x, 0.0)).rgb;

    // Sobel/Laplacian gradient for color edge detection
    vec3 diff = abs(c_left - c_right) + abs(c_up - c_down);
    float edge = max(diff.r, max(diff.g, diff.b));

    // Depth edge detection (silhouettes around characters, trees, buildings, and ground)
    float d_c     = texture(DEPTH_TEXTURE, SCREEN_UV).r;
    float d_up    = texture(DEPTH_TEXTURE, SCREEN_UV + vec2(0.0,  texel.y)).r;
    float d_down  = texture(DEPTH_TEXTURE, SCREEN_UV + vec2(0.0, -texel.y)).r;
    float d_left  = texture(DEPTH_TEXTURE, SCREEN_UV + vec2(-texel.x, 0.0)).r;
    float d_right = texture(DEPTH_TEXTURE, SCREEN_UV + vec2( texel.x, 0.0)).r;
    float depth_diff = (abs(d_left - d_right) + abs(d_up - d_down)) * 100.0;

    float is_edge = smoothstep(outline_threshold, outline_threshold * 2.0, max(edge, depth_diff));

    // Mix cartoon outline over the clean vibrant screen color
    vec3 final_color = mix(center_color, outline_color.rgb, is_edge * outline_color.a);
    COLOR = vec4(final_color, 1.0);
}
