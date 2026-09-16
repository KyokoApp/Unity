class_name ToonCharacterSetup
extends RefCounted

## ============================================================
## TOON CHARACTER SETUP — menukar material GLTF/VRM karakter menjadi
## shader toon Aurelia (aurelia_toon untuk yang buram,
## aurelia_toon_lite untuk yang transparan lipat — alis, bulu mata,
## iris — supaya wajah tetap rapi tanpa tumpukan outline).
## (Port dari ToonCharacterSetup.cs.)
##
## Outline dipasang sebagai material `next_pass` pada material toon
## (inverted-hull aurelia_toon_outline) — padanan Pass "Outline" di
## shader Unity.
## ============================================================

const OPTS_KEYS := ["skin_color", "hair_color"]

static func apply(root: Node3D, opts: Dictionary = {}) -> void:
	if root == null:
		return
	var shader_body: Shader = opts.get("shader_body")
	var shader_face: Shader = opts.get("shader_face")
	var shader_outline: Shader = opts.get("outline_shader")
	if shader_body == null:
		return

	for mesh_inst in _mesh_instances(root):
		var mesh: Mesh = mesh_inst.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var src := mesh_inst.get_active_material(s)
			var src_name := ""
			var albedo: Texture2D = null
			var tint := Color.WHITE
			var transparent := false
			var emission := Color.BLACK
			if src is StandardMaterial3D:
				var sm := src as StandardMaterial3D
				src_name = (sm.resource_name + mesh_inst.name).to_lower()
				albedo = sm.albedo_texture
				tint = sm.albedo_color
				transparent = sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
				if sm.emission_enabled:
					emission = sm.emission

			# Material "hair/*" & *_in (iris) adalah wajah/rambut khas
			# VRM-KK; yang transparan memakai lite (tanpa outline),
			# yang buram memakai toon penuh + next_pass outline.
			var face := transparent \
				or src_name.find("eye") >= 0 or src_name.find("face") >= 0 \
				or src_name.find("brow") >= 0 or src_name.find("iris") >= 0
			var mat := ShaderMaterial.new()
			mat.shader = shader_face if face and shader_face != null else shader_body
			if albedo != null:
				mat.set_shader_parameter("base_map", albedo)
			mat.set_shader_parameter("base_color", tint)
			var n := src_name
			if n.find("hair") >= 0 or n.find("rambut") >= 0:
				mat.set_shader_parameter("rim_strength", 0.35)
				mat.set_shader_parameter("spec_strength", 0.45)
			if emission != Color.BLACK:
				mat.set_shader_parameter("emission_color", emission)
				mat.set_shader_parameter("emission_strength", 1.0)

			if not face and shader_outline != null:
				var outline := ShaderMaterial.new()
				outline.shader = shader_outline
				mat.next_pass = outline

			mesh_inst.set_surface_override_material(s, mat)

## Nyalakan/matikan seluruh outline di bawah root (dipakai
## quality_applier — preset Rendah mematikan 1 pass ini).
static func set_outline_visible(root: Node3D, on: bool) -> void:
	if root == null:
		return
	for mesh_inst in _mesh_instances(root):
		var mesh: Mesh = mesh_inst.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var m := mesh_inst.get_active_material(s)
			if m is ShaderMaterial:
				var np: Material = (m as ShaderMaterial).next_pass
				if np is ShaderMaterial \
				and (np as ShaderMaterial).shader != null \
				and (np as ShaderMaterial).shader.resource_path.find("outline") >= 0:
					(np as ShaderMaterial).set_shader_parameter("outline_width",
						0.0 if not on else 0.008)

static func _mesh_instances(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_mesh_instances(c))
	return out
