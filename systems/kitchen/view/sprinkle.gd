class_name Sprinkle
extends CPUParticles3D

## A pinch of spice let go from the fingers: a little shower of flecks in
## the spice's colour that falls to whatever is below and is gone. Purely
## drawn - where the spice lands, and how much sticks, is Seasoning's.

## Flecks in a pinch, and how wide the fingers scatter them.
const FLECKS: int = 40
const SPREAD_M: float = 0.012

## Lets a pinch fall from `from` (world) onto a surface at height
## `surface_y`, under `parent`.
static func fall(parent: Node, from: Vector3, surface_y: float, color: Color) -> Sprinkle:
	var shower := Sprinkle.new()
	parent.add_child(shower)
	shower.global_position = from
	var height: float = maxf(from.y - surface_y, 0.02)
	shower.lifetime = sqrt(2.0 * height / 9.8) * 1.05
	shower.one_shot = true
	shower.explosiveness = 0.75
	shower.amount = FLECKS
	shower.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	shower.emission_sphere_radius = SPREAD_M * 0.4
	shower.direction = Vector3.DOWN
	shower.spread = 12.0
	shower.initial_velocity_min = 0.05
	shower.initial_velocity_max = 0.25
	shower.gravity = Vector3(0.0, -9.8, 0.0)
	shower.scale_amount_min = 0.6
	shower.scale_amount_max = 1.4
	shower.color = color
	var fleck := BoxMesh.new()
	fleck.size = Vector3(0.0012, 0.0006, 0.0012)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	fleck.material = material
	shower.mesh = fleck
	shower.emitting = true
	shower.finished.connect(shower.queue_free)
	return shower
