class_name WaterPlane
extends MeshInstance3D

## ============================================================
## WATER PLANE — permukaan air. (Port dari WaterPlane.cs.)
##
## Satu quad DATAR 1 segmen (4 verteks) yang mengikuti karakter.
## SEMUA gelombang dihitung di fragment shader dari posisi dunia
## + waktu (lihat shaders/aurelia_water.gdshader).
##
## Posisinya di-SNAP ke kelipatan ukuran quad. Tanpa ini, quad yang
## mengikuti karakter membuat pola gelombang "berenang" mundur —
## artefak klasik yang sangat terlihat.
## ============================================================

@export var target: Node3D
## Panjang sisi quad dalam meter. Harus >= 2x jangkauan pandang.
@export var size: float = 1400.0
@export var water_material: Material
## Offset kecil ke atas supaya tidak z-fighting dengan dasar air
## yang persis di y=0.
@export var height_bias: float = 0.02

func _ready() -> void:
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Node3D
	_ensure_mesh()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if water_material == null:
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/aurelia_water.gdshader") as Shader
		water_material = mat
	material_override = water_material

func _ensure_mesh() -> void:
	if mesh != null:
		return
	# Satu quad: gelombang tidak butuh tessellasi karena murni
	# dihitung di fragment (normal analitik).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts := [
		Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5),
		Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5),
	]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]
	var idx := [0, 2, 1, 2, 3, 1]   # normal +Y (sama winding TerrainMesh)
	for i in idx:
		st.set_uv(uvs[i])
		st.add_vertex(verts[i])
	st.generate_normals()
	mesh = st.commit()

func _process(_delta: float) -> void:
	if target == null:
		return
	var p := target.global_position
	# snap ke kelipatan size supaya shader (yang memakai posisi dunia)
	# tidak terlihat bergeser saat quad mengikuti karakter
	var sx: float = roundf(p.x / size) * size
	var sz: float = roundf(p.z / size) * size
	global_position = Vector3(sx, WorldData.WATER_LEVEL + height_bias, sz)
	scale = Vector3(size, 1.0, size)
