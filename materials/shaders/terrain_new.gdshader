shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_toon, specular_schlick_ggx;

/* ══════════════════════════════════════════════════════════════════════
   Genshin / Anime Style Stylized Gradient Terrain Shader
   - Zero heavy textures (smooth, vibrant anime aesthetic)
   - Smooth non-clashing color gradients
   - Vertex weight & slope blending (Dark Green -> Grass Green -> Earth / Sand)
   ══════════════════════════════════════════════════════════════════════ */

// Stylized Anime Palette (Vibrant, soft & harmonious like Genshin Impact / Zelda BotW)
uniform vec4 grass_dark_color   : source_color = vec4(0.18, 0.45, 0.22, 1.0); // Soft deep forest green
uniform vec4 grass_bright_color : source_color = vec4(0.38, 0.68, 0.28, 1.0); // Vibrant meadow grass green
uniform vec4 grass_light_color  : source_color = vec4(0.55, 0.78, 0.35, 1.0); // Sunlit warm light green
uniform vec4 soil_color         : source_color = vec4(0.52, 0.44, 0.34, 1.0); // Soft warm earth brown
uniform vec4 sand_color         : source_color = vec4(0.76, 0.68, 0.50, 1.0); // Warm sunny sand

// Slope & Height transition thresholds
uniform float slope_threshold   : hint_range(0.0, 1.0) = 0.65;
uniform float slope_smoothness  : hint_range(0.01, 0.5) = 0.20;

// World detail subtle variation (creates soft painterly field patches without texture files)
varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    // 1. Procedural subtle anime color gradation across world space (wind / patch gradient)
    float world_noise = sin(v_world_pos.x * 0.08) * cos(v_world_pos.z * 0.08) * 0.5 + 0.5;
    float micro_noise = sin(v_world_pos.x * 0.25 + v_world_pos.z * 0.25) * 0.5 + 0.5;
    float grass_gradient = clamp(world_noise * 0.7 + micro_noise * 0.3, 0.0, 1.0);

    // 2. Smooth gradient from deep green -> vibrant grass -> sunlit grass
    vec3 lush_grass = mix(grass_dark_color.rgb, grass_bright_color.rgb, grass_gradient);
    vec3 sunny_grass = mix(lush_grass, grass_light_color.rgb, clamp(v_world_pos.y * 0.02, 0.0, 0.4));

    // 3. Slope calculation: Steep slopes smoothly reveal soil / cliff rock
    float up_dot = clamp(v_world_normal.y, 0.0, 1.0);
    float slope_factor = smoothstep(slope_threshold - slope_smoothness, slope_threshold + slope_smoothness, up_dot);

    // 4. Vertex color weights (R = mud/soil, G = grass, B = sand/beach)
    vec3 vtx = COLOR.rgb;
    float grass_weight = vtx.g;
    float soil_weight = vtx.r;
    float sand_weight = vtx.b;
    float total_w = max(grass_weight + soil_weight + sand_weight, 0.001);
    grass_weight /= total_w;
    soil_weight /= total_w;
    sand_weight /= total_w;

    // Blend soil and sand with earth color
    vec3 ground_color = mix(soil_color.rgb, sand_color.rgb, sand_weight);

    // 5. Harmonious final blend: Grass smoothly fades into soil on slopes or where soil vertex weight is high
    vec3 final_color = mix(ground_color, sunny_grass, slope_factor * grass_weight);
    
    // Also blend sand smoothly at low altitudes or where sand weight dominates
    final_color = mix(final_color, sand_color.rgb, sand_weight * 0.6);

    ALBEDO = final_color;
    ROUGHNESS = 0.85;
    SPECULAR = 0.15;
}
