@tool
extends EditorScenePostImport

## Gives every model imported from the Blender kit the kitchen's cel look:
## toon diffuse bands, a toon specular highlight and a soft rim, and - on
## the surfaces a painter would texture by hand (wood, wicker, burlap,
## clay, paint) - a soft painted grain, so flat colour doesn't read as
## plastic. Set as the
## import script of each .glb under assets/models/, so a re-exported model
## keeps the look without hand-editing materials.

const RIM: float = 0.25
const RIM_TINT: float = 0.6
## Fully metallic surfaces turn black without strong reflections; cel
## shading reads metal from colour and highlight instead.
const MAX_METALLIC: float = 0.35
## Glossy surfaces mirror the bright coastal sky and wash out to white; a
## cel look reads gloss from its highlight band, not from reflections.
const MIN_ROUGHNESS: float = 0.62
const SPECULAR: float = 0.3

## Painted grain by material slot name: how dark its strokes go, how many
## times it repeats across the surface's UVs along U and V (unequal for a
## stretched grain like wood), and how fine its noise is.
const PAINTED := {
	"wood": [0.78, Vector2(2.0, 14.0), 0.09],
	"top": [0.9, Vector2(3.0, 12.0), 0.08],
	"wicker": [0.72, Vector2(10.0, 10.0), 0.2],
	"burlap": [0.74, Vector2(14.0, 14.0), 0.3],
	"straw": [0.7, Vector2(4.0, 24.0), 0.2],
	"twine": [0.75, Vector2(6.0, 6.0), 0.2],
	"cork": [0.8, Vector2(6.0, 6.0), 0.25],
	"clay": [0.85, Vector2(4.0, 4.0), 0.12],
	"ceramic": [0.95, Vector2(2.0, 2.0), 0.04],
	"glaze": [0.95, Vector2(2.0, 2.0), 0.04],
	"enamel": [0.9, Vector2(3.0, 3.0), 0.05],
	"paint": [0.86, Vector2(3.0, 10.0), 0.06],
	"base": [0.88, Vector2(3.0, 10.0), 0.06],
	"iron": [0.8, Vector2(5.0, 5.0), 0.15],
	"zinc": [0.86, Vector2(4.0, 4.0), 0.1],
	"label": [0.9, Vector2(3.0, 3.0), 0.2],
}

static var _grains: Dictionary = {}

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
			material.roughness = maxf(material.roughness, MIN_ROUGHNESS)
			material.metallic_specular = SPECULAR
			# Larder models carry their painted shading as vertex colour.
			var arrays := mesh.surface_get_arrays(surface)
			var colours: Variant = arrays[Mesh.ARRAY_COLOR]
			material.vertex_color_use_as_albedo = colours != null and (colours as PackedColorArray).size() > 0
			_paint(material)
	for child in node.get_children():
		_toon(child)

## Lays a painted grain over a hand-textured material: a multiply of soft
## noise, stretched along the grain for wood. The material's base colour
## has no texture, so its UV scale only shapes the grain.
static func _paint(material: StandardMaterial3D) -> void:
	var slot := material.resource_name.to_lower()
	if not PAINTED.has(slot):
		return
	var spec: Array = PAINTED[slot]
	material.detail_enabled = true
	material.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	material.detail_albedo = _grain(spec[0], spec[2])
	material.uv1_scale = Vector3(spec[1].x, spec[1].y, 1.0)

## A seamless grey noise from `darkest` to white.
static func _grain(darkest: float, frequency: float) -> NoiseTexture2D:
	var key := "%s_%s" % [darkest, frequency]
	if _grains.has(key):
		return _grains[key]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = 3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(darkest, darkest, darkest))
	ramp.set_color(1, Color.WHITE)
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	texture.color_ramp = ramp
	_grains[key] = texture
	return texture
