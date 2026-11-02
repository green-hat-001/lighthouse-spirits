class_name PourVesselView
extends Node3D

## Something the player pours from: the water jug, the oil bottle, the oil
## cup under the press. Lifting it carries it over the counter; held over
## the pot (or, for the cup, over the bottle) it tips towards it, and
## liquid runs once it tips past the angle where the liquid reaches the
## spout - a full vessel pours at a slight tilt, a nearly empty one has to
## be tipped right over. Letting go sets it back down. A corked bottle
## pours nothing until the cork is pulled (right-click).
##
##   RESTING --press--> CARRIED --over a target--> POURING --away--> CARRIED
##   CARRIED/POURING --release--> RESTING

signal poured(grams: float)

enum State { RESTING, CARRIED, POURING }
enum Store { JUG, BOTTLE, CUP }

## Lifted this high above where it rests, clear of the pot's rim.
const CARRY_HEIGHT_M: float = 0.24
const TILT_DEG_PER_S: float = 55.0
const MAX_TILT_DEG: float = 115.0
## Tilt at which the liquid reaches the spout, from full to nearly empty.
const POUR_TILT_FULL_DEG: float = 25.0
const POUR_TILT_EMPTY_DEG: float = 95.0
## Tilt past the pouring angle at which the stream is at its fullest.
const FULL_STREAM_DEG: float = 25.0
const FOLLOW_EASE: float = 10.0
## How close the pour point must be to another vessel to pour into it.
const VESSEL_REACH_M: float = 0.05

@export var simulation: KitchenSimulation
@export var store_kind: Store = Store.JUG
@export var max_pour_g_per_s: float = 60.0
## Where it can pour into.
@export var pot_view: PotView
@export var receiving_vessel: PourVesselView
## A liquid-surface mesh inside the vessel that rises with the fill, and how
## high it rises when full (relative to its empty height).
@export var fill_surface: MeshInstance3D
@export var fill_rise_m: float = 0.0
## A surface of the body mesh drawn as the liquid inside (clear glass), cut
## off at the fill, from empty to full height in the mesh's space.
@export var fill_body: MeshInstance3D
@export var fill_body_surface: int = -1
@export var fill_body_empty_m: float = 0.0
@export var fill_body_full_m: float = 0.0

var state: State = State.RESTING
var tilt_deg: float = 0.0
var corked: bool = false

var _home: Transform3D
var _home_y: float
var _target_point: Vector3
var _fill_surface_rest_y: float
var _fill_material: ShaderMaterial
var _stream_material := StandardMaterial3D.new()

@onready var _tilt: Node3D = $Tilt
@onready var _grip: Interactable = $Grip
@onready var _pour_point: Node3D = $Tilt/Model/pour_point
@onready var _cork: Node3D = get_node_or_null("Tilt/Model/cork")
@onready var _stream: MeshInstance3D = $Stream

func _ready() -> void:
	_home = transform
	_home_y = global_position.y
	corked = _cork != null
	_grip.pressed.connect(_on_pressed)
	_grip.dragged.connect(func(point: Vector3) -> void: _target_point = point)
	_grip.released.connect(func(_point: Vector3) -> void: _set_down())
	_grip.cancelled.connect(_set_down)
	_grip.secondary_pressed.connect(func(_point: Vector3) -> void: toggle_cork())
	if fill_surface:
		_fill_surface_rest_y = fill_surface.position.y
	if fill_body and fill_body_surface >= 0:
		_fill_material = ShaderMaterial.new()
		_fill_material.shader = preload("res://shaders/fill_cutoff.gdshader")
		fill_body.set_surface_override_material(fill_body_surface, _fill_material)
	_stream_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_stream_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_stream_material.roughness = 0.1
	var stream_mesh := CylinderMesh.new()
	stream_mesh.top_radius = 1.0
	stream_mesh.bottom_radius = 0.8
	stream_mesh.height = 1.0
	stream_mesh.radial_segments = 8
	stream_mesh.material = _stream_material
	_stream.mesh = stream_mesh
	_stream.visible = false

func store() -> LiquidStore:
	match store_kind:
		Store.BOTTLE:
			return simulation.bottle
		Store.CUP:
			return simulation.cup
	return simulation.jug

func is_home() -> bool:
	return state == State.RESTING and transform.origin.distance_to(_home.origin) < 0.01

func toggle_cork() -> void:
	if _cork == null:
		return
	corked = not corked
	_cork.position = Vector3.ZERO if corked else Vector3(0.05, -0.2, 0.06)
	_cork.rotation = Vector3.ZERO if corked else Vector3(0.0, 0.0, PI * 0.5)

## The tilt at which liquid reaches the spout, for how full it is.
func pour_tilt_deg() -> float:
	return lerpf(POUR_TILT_EMPTY_DEG, POUR_TILT_FULL_DEG, store().fill_fraction())

## The player aims the spout: drags are read on a plane at the spout's
## carrying height, and the vessel follows so its spout is under the mouse.
func _on_pressed(point: Vector3) -> void:
	state = State.CARRIED
	_grip.drag_plane = Plane(Vector3.UP, _home_y + CARRY_HEIGHT_M + _spout_height())
	_target_point = point

func _set_down() -> void:
	state = State.RESTING

func _spout_height() -> float:
	return _pour_point.position.y

func _process(delta: float) -> void:
	var ease: float = 1.0 - exp(-FOLLOW_EASE * delta)
	var target: Variant = _pour_target()
	if state == State.RESTING:
		transform = transform.interpolate_with(_home, ease)
		tilt_deg = move_toward(tilt_deg, 0.0, TILT_DEG_PER_S * 2.0 * delta)
	else:
		var spout_offset := _pour_point.global_position - global_position
		var goal := Vector3(_target_point.x - spout_offset.x, _home_y + CARRY_HEIGHT_M, _target_point.z - spout_offset.z)
		global_position = global_position.lerp(goal, ease)
		state = State.POURING if target != null else State.CARRIED
		if state == State.POURING:
			# Turn the spout to face what it pours into, then tip.
			var to_target := (target as Vector3) - global_position
			var facing: float = atan2(-to_target.z, to_target.x)
			rotation.y = lerp_angle(rotation.y, facing, ease)
			tilt_deg = move_toward(tilt_deg, MAX_TILT_DEG, TILT_DEG_PER_S * delta)
		else:
			tilt_deg = move_toward(tilt_deg, 0.0, TILT_DEG_PER_S * 2.0 * delta)
	_tilt.rotation = Vector3(0.0, 0.0, -deg_to_rad(tilt_deg))
	_pour(delta)
	_draw_fill()

## Where the liquid would land, or null if the spout is over nothing that
## takes it.
func _pour_target() -> Variant:
	if state == State.RESTING:
		return null
	var spout := _pour_point.global_position
	if pot_view and pot_view.is_over(spout):
		return pot_view.global_position + Vector3(0.0, PotView.FLOOR_Y_M, 0.0) + Vector3(spout.x - pot_view.global_position.x, 0.0, spout.z - pot_view.global_position.z) * 0.5
	if receiving_vessel and Vector2(spout.x - receiving_vessel.global_position.x, spout.z - receiving_vessel.global_position.z).length() < VESSEL_REACH_M:
		return receiving_vessel.global_position
	return null

func _pour(delta: float) -> void:
	var rate: float = 0.0
	var liquid := store()
	if state == State.POURING and not corked and not liquid.is_empty():
		rate = max_pour_g_per_s * clampf((tilt_deg - pour_tilt_deg()) / FULL_STREAM_DEG, 0.0, 1.0)
	var grams: float = 0.0
	var landing_y: float = 0.0
	if rate > 0.0:
		var spout := _pour_point.global_position
		if pot_view and pot_view.is_over(spout):
			grams = simulation.pour_into_pot(liquid, rate, delta)
			landing_y = pot_view.global_position.y + PotView.FLOOR_Y_M + pot_view.pot().liquid_level_mm * 0.001
		elif receiving_vessel:
			grams = simulation.pour_into(liquid, receiving_vessel.store(), rate, delta)
			landing_y = receiving_vessel.global_position.y + 0.02
	if grams > 0.0:
		poured.emit(grams)
		_draw_stream(rate, landing_y, liquid)
	else:
		_stream.visible = false

func _draw_stream(rate: float, landing_y: float, liquid: LiquidStore) -> void:
	var top := _pour_point.global_position
	var length: float = maxf(top.y - landing_y, 0.005)
	var radius: float = 0.0012 + 0.0035 * sqrt(rate / max_pour_g_per_s)
	_stream.visible = true
	_stream.global_transform = Transform3D(Basis.from_scale(Vector3(radius, length, radius)), top - Vector3(0.0, length * 0.5, 0.0))
	var color: Color = liquid.ingredient.tint_color if liquid.ingredient else Color.WHITE
	color.a = 0.75 if liquid.ingredient and liquid.ingredient.fat_fraction > 0.5 else 0.45
	_stream_material.albedo_color = color

func _draw_fill() -> void:
	var liquid := store()
	var fill: float = liquid.fill_fraction() if liquid.ingredient else 0.0
	if fill_surface:
		fill_surface.visible = fill > 0.001
		fill_surface.position.y = _fill_surface_rest_y + fill * fill_rise_m
		if liquid.ingredient:
			var material := fill_surface.get_active_material(0) as StandardMaterial3D
			if material == null:
				material = StandardMaterial3D.new()
				material.roughness = 0.15
				fill_surface.material_override = material
			material.albedo_color = liquid.ingredient.tint_color
	if _fill_material:
		_fill_material.set_shader_parameter("fill_height", lerpf(fill_body_empty_m, fill_body_full_m, fill) if fill > 0.001 else -1.0)
		if liquid.ingredient:
			_fill_material.set_shader_parameter("liquid_color", liquid.ingredient.tint_color)
