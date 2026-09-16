shader_type spatial;
render_mode cull_disabled, specular_disabled;

// ============================================================
// aurelia_prop.gdshader — pohon/batu dari WorldScatter, digambar
// sebagai 4 MultiMesh (batang, kanopi, pinus, batu).
//
// Warna per instance: COLOR MultiMesh — kanopi/pinus diwarnai
// region.foliage (0xRRGGBB, sama seperti JS), batang & batu putih
// (memakai tint material). Sama seperti versi three.js-nya.
//
// Pencahayaan: half-Lambert posterize lembut seperti terrain,
// ambient datar proyek, kabut linear konsisten lintas shader.
// ============================================================

global uniform vec4 aurelia_fog_color : source_color;
global uniform float aurelia_fog_near;
global uniform float aurelia_fog_far;
global uniform vec4 aurelia_ambient_color : source_color;

uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float toon_steps : hint_range(2.0, 5.0) = 3.0;
uniform float toon_softness : hint_range(0.0, 0.5) = 0.30;

varying vec3 albedo_v;

void vertex() {
	// Warna instance MultiMesh (putih untuk batang/batu).
	albedo_v = COLOR.rgb * albedo_tint.rgb;
}

void fragment() {
	ALBEDO = albedo_v;
	float depth = -VERTEX.z;
	float fogf = clamp((depth - aurelia_fog_near)
					   / max(1.0, aurelia_fog_far - aurelia_fog_near), 0.0, 1.0);
	EMISSION = albedo_v * aurelia_ambient_color.rgb * (1.0 - fogf);
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		return;
	}
	vec3 n = normalize(NORMAL);
	float ndl = dot(n, LIGHT);
	float diffuse = clamp(ndl * 0.5 + 0.5, 0.0, 1.0);
	diffuse = diffuse * diffuse;

	float tx = diffuse * toon_steps;
	float tb = floor(tx) + smoothstep(0.5 - toon_softness,
									  0.5 + toon_softness, fract(tx));
	diffuse = tb / toon_steps;

	vec3 lit = ALBEDO * LIGHT_COLOR * diffuse * SHADOW * ATTENUATION;

	float depth = -VERTEX.z;
	float fog = clamp((depth - aurelia_fog_near)
					  / max(1.0, aurelia_fog_far - aurelia_fog_near), 0.0, 1.0);
	DIFFUSE_LIGHT += mix(lit, aurelia_fog_color.rgb, fog);
}
