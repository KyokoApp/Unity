shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// ============================================================
// aurelia_sparkle.gdshader — partikel anime (sparkle, sihir,
// skill). (Port dari AureliaSparkle.shader Unity.)
//
// Unlit additive: inti bersinar + garis silang 4-titik (model
// "kilau" ala anime), tanpa tekstur — bentuknya murni dari UV.
// Warna PER PARTIKEL lewat warna instance MultiMesh (diisi
// runtime/anime_vfx.gd). Billboard dikerjakan DI SHADER di sini
// (di Unity dikerjakan CPU): sumbu X/Y kamera dibaca dari
// VIEW_MATRIX invers, jadi CPU hanya menulis matriks posisi+ukuran.
//
// SATU quad + SATU material + SATU draw call instanced untuk SEMUA
// partikel — jalan di semua perangkat, setara desain Unity-nya.
// ============================================================

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 2.0;

varying vec2 part_uv;
varying vec4 part_color;

void vertex() {
	// Pusat partikel = origin instance (MODEL_MATRIX[3]).
	vec3 center_ws = MODEL_MATRIX[3].xyz;
	// Ukuran dari skala kolom pertama (instance seragam di-scale).
	float size = length(MODEL_MATRIX[0].xyz);

	// Billboard bola: sumbu layar = baris X/Y dari VIEW_MATRIX
	// (transpose dari matriks pandang = matriks kamera).
	vec3 cam_right = INV_VIEW_MATRIX[0].xyz;
	vec3 cam_up = INV_VIEW_MATRIX[1].xyz;

	vec3 ws = center_ws + (cam_right * VERTEX.x + cam_up * VERTEX.y) * size;

	part_uv = UV;
	// Warna & alpha fade per partikel dari warna instance.
	part_color = COLOR;

	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(ws, 1.0));
}

void fragment() {
	vec2 p = part_uv - 0.5;
	float core = pow(clamp(1.0 - length(p) * 2.4, 0.0, 1.0), 2.0);
	float sx = pow(clamp(1.0 - abs(p.y) * 7.0, 0.0, 1.0), 2.0)
			 * pow(clamp(1.0 - abs(p.x) * 2.0, 0.0, 1.0), 1.5);
	float sy = pow(clamp(1.0 - abs(p.x) * 7.0, 0.0, 1.0), 2.0)
			 * pow(clamp(1.0 - abs(p.y) * 2.0, 0.0, 1.0), 1.5);
	float a = core + (sx + sy) * 0.8;

	// Additive: kembalikan hitam saat alpha 0 (tidak menambah apa pun).
	vec3 col = part_color.rgb * tint.rgb * (a * intensity * part_color.a);
	ALBEDO = col;
}
