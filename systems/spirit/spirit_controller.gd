class_name SpiritController
extends Node3D

## Drives one Warawara's lifecycle: owns its runtime stats and FSM, and
## turns deficit changes into the physical feedback (buoyancy,
## luminescence) the game concept calls for.

@export var archetype: SpiritArchetype
@export var arrival_anchor: Node3D
@export var move_speed: float = 2.0
@export var rise_speed: float = 1.5

var spirit_id: StringName
var runtime: SpiritRuntimeState
var state_machine: SpiritStateMachine
var outcome: StringName = &""

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D

func _ready() -> void:
	spirit_id = StringName("spirit_%d" % Time.get_ticks_usec())
	runtime = SpiritRuntimeState.new(archetype)
	state_machine = SpiritStateMachine.new(self)
	_setup_visual()
	SpiritEventBus.feed_spirit_requested.connect(_on_feed_spirit_requested)
	state_machine.start(SpiritState.State.ARRIVING)

func _exit_tree() -> void:
	if SpiritEventBus.feed_spirit_requested.is_connected(_on_feed_spirit_requested):
		SpiritEventBus.feed_spirit_requested.disconnect(_on_feed_spirit_requested)

func _physics_process(delta: float) -> void:
	state_machine.update(delta)
	apply_visual_feedback()

func apply_visual_feedback() -> void:
	if not _material or not archetype:
		return
	var hunger_ratio: float = 1.0 - (runtime.current_hunger / 100.0)
	var instability_ratio: float = 1.0 - (runtime.current_instability / 100.0)
	var nourishment_level: float = clampf((hunger_ratio + instability_ratio) * 0.5, 0.0, 1.0)
	_material.emission_energy_multiplier = _sample_curve_or_lerp(
		archetype.luminescence_curve, nourishment_level, 0.1, 3.5
	)
	if _mesh_instance:
		var weight_ratio: float = clampf(runtime.current_weight / maxf(archetype.base_weight, 0.001), 0.0, 1.0)
		_mesh_instance.position.y = _sample_curve_or_lerp(
			archetype.buoyancy_curve, 1.0 - weight_ratio, 0.0, 0.4
		)

func _on_feed_spirit_requested(target_id: StringName, feeding_result: FeedingResult) -> void:
	if target_id != spirit_id:
		return
	state_machine.handle_signal(&"feed", feeding_result)

func _sample_curve_or_lerp(curve: Curve, t: float, fallback_min: float, fallback_max: float) -> float:
	if curve and curve.point_count > 0:
		return curve.sample(t)
	return lerpf(fallback_min, fallback_max, t)

func _setup_visual() -> void:
	_mesh_instance = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	_mesh_instance.mesh = sphere
	add_child(_mesh_instance)

	_material = StandardMaterial3D.new()
	_material.albedo_color = archetype.tint_color
	_material.emission_enabled = true
	_material.emission = archetype.tint_color
	_material.emission_energy_multiplier = 0.0
	_mesh_instance.material_override = _material
