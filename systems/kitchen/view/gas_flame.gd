class_name GasFlame
extends MeshInstance3D

## The burner's flame, drawn from the burner's own state: a ring of
## flickering tongues whose reach and height follow the flame level, lit
## and put out with it, and pushed about by the wind. A small light under
## the pot glows with it.

const TONGUES: int = 32
const SEGMENTS: int = 4
const SHADER: Shader = preload("res://shaders/gas_flame.gdshader")
## Height of a tongue at the lowest and at full flame, in metres. The pot
## sits just above the burner, so a bigger flame spreads out under it
## rather than growing taller.
const LOW_HEIGHT_M: float = 0.006
const FULL_HEIGHT_M: float = 0.014
## Toon shading lights anything in range at full strength, so the flame's
## glow is kept small and close: it should blue the burner and the pot's
## base, not bleach the whole stove.
const LIGHT_ENERGY_AT_FULL: float = 0.12

var source: HeatSource
var air: KitchenAir
var level: float = 0.0

var _material := ShaderMaterial.new()
var _light := OmniLight3D.new()

func _ready() -> void:
	mesh = _build_mesh()
	_material.shader = SHADER
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 0.2
	_light.light_color = Color(0.45, 0.6, 1.0)
	_light.omni_range = 0.12
	_light.omni_attenuation = 2.2
	_light.light_specular = 0.1
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 0.01, 0.0)
	add_child(_light)
	_apply()

func _process(_delta: float) -> void:
	_apply()

func _apply() -> void:
	var effective: float = source.effective_level(level) if source else level
	var lit: bool = effective > 0.0
	visible = lit
	_light.visible = lit
	if not lit:
		return
	var reach: float = source.flame_radius_mm(level) * 0.001 if source else 0.06
	var inner: float = (source.burner_radius_mm * 0.001 if source else 0.035) * 0.9
	_material.set_shader_parameter("level", effective)
	_material.set_shader_parameter("inner_radius", inner)
	_material.set_shader_parameter("outer_radius", maxf(reach * 0.75, inner + 0.004))
	_material.set_shader_parameter("tongue_height", lerpf(LOW_HEIGHT_M, FULL_HEIGHT_M, effective))
	var wind := Vector2.ZERO
	if air:
		wind = Vector2(air.wind_mps, air.wind_mps * 0.3)
	_material.set_shader_parameter("wind", wind)
	_light.light_energy = LIGHT_ENERGY_AT_FULL * effective

static func _build_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	for tongue in TONGUES:
		var around: float = float(tongue) / TONGUES
		var base_index: int = vertices.size()
		for segment in SEGMENTS + 1:
			var up: float = float(segment) / SEGMENTS
			for side in [-1.0, 1.0]:
				# Real positions come from the shader; these only keep the
				# bounds honest.
				vertices.append(Vector3(cos(around * TAU) * 0.08, up * 0.04, sin(around * TAU) * 0.08))
				uvs.append(Vector2(around, up))
				uv2s.append(Vector2(side, 0.0))
		for segment in SEGMENTS:
			var row: int = base_index + segment * 2
			indices.append_array([row, row + 1, row + 2, row + 1, row + 3, row + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built
