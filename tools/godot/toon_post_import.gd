@tool
extends EditorScenePostImport

## Gives every model imported from the Blender kit the kitchen's cel look:
## toon diffuse bands, a toon specular highlight and a soft rim. Set as the
## import script of each .glb under assets/models/, so a re-exported model
## keeps the look without hand-editing materials.

const RIM: float = 0.25
const RIM_TINT: float = 0.6
## Fully metallic surfaces turn black without strong reflections; cel
## shading reads metal from colour and highlight instead.
const MAX_METALLIC: float = 0.35

func _post_import(scene: Node) -> Object:
	_toon(scene)
	return scene

func _toon(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			if material == null:
				continue
			material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			material.specular_mode = BaseMaterial3D.SPECULAR_TOON
			material.rim_enabled = true
			material.rim = RIM
			material.rim_tint = RIM_TINT
			material.metallic = minf(material.metallic, MAX_METALLIC)
			# Larder models carry their painted shading as vertex colour.
			var arrays := mesh.surface_get_arrays(surface)
			var colours: Variant = arrays[Mesh.ARRAY_COLOR]
			material.vertex_color_use_as_albedo = colours != null and (colours as PackedColorArray).size() > 0
	for child in node.get_children():
		_toon(child)
