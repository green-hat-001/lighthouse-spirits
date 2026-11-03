class_name PressView
extends Node3D

## The hand-cranked oil press. The player turns the crank by circling the
## mouse round its axle; each forward turn works the press (the
## ManualProcessor decides what that presses), oil runs from the spout into
## the cup below - or onto the counter, if the cup has been taken away -
## and seed cake is pushed out of the end of the barrel. Turning backwards
## does nothing: the screw only presses one way. The hopper shows the seeds
## still in it, and the cake piles up where it falls.

signal pressed_oil(grams: float)
## The crank turned forward this many turns.
signal cranked(turns: float)

const SEEDS_PER_GRAM: float = 0.5
const MAX_SEEDS_SHOWN: int = 140
const CAKE_PELLET_G: float = 6.0
const MAX_PELLETS_SHOWN: int = 30
## Oil (g/s) for the fullest drip, and how fast the drip dies away.
const FULL_DRIP_G_PER_S: float = 8.0
const DRIP_DECAY_PER_S: float = 3.0
## The hopper's funnel, in the press's space: its axis, the height and
## radius of its narrow neck, and the height and radius of its mouth.
const HOPPER_AXIS: Vector2 = Vector2(0.045, 0.0)
const HOPPER_NECK_Y: float = 0.2
const HOPPER_NECK_RADIUS_M: float = 0.012
const HOPPER_MOUTH_Y: float = 0.295
const HOPPER_MOUTH_RADIUS_M: float = 0.052
## A full load fills the funnel this far up.
const HOPPER_FULL_SHARE: float = 0.85

@export var simulation: KitchenSimulation
## The cup that catches the oil; it has to be sitting under the spout.
@export var cup: PourVesselView

var crank_angle: float = 0.0

var _drag := CircularDrag.new()
var _drip_rate: float = 0.0
var _seeds_multimesh := MultiMesh.new()
var _cake_multimesh := MultiMesh.new()
var _drip_material := StandardMaterial3D.new()

## Where the crank's wooden grip is, from its pivot.
const CRANK_HANDLE: Vector3 = Vector3(0.035, 0.078, 0.0)

@onready var _crank: Node3D = $Model/crank
@onready var _grip: Interactable = $CrankGrip
@onready var _spout: Node3D = $Model/oil_spout
@onready var _outlet: Node3D = $Model/cake_outlet
@onready var _seeds: MultiMeshInstance3D = $HopperSeeds
@onready var _cake: MultiMeshInstance3D = $CakePile
@onready var _drip: MeshInstance3D = $Drip

func _ready() -> void:
	# The hand closes on the crank's wooden grip and goes round with it.
	var handle := Node3D.new()
	handle.name = "Handle"
	handle.position = CRANK_HANDLE
	_crank.add_child(handle)
	_grip.hand_anchor = handle
	_grip.pressed.connect(_on_pressed)
	_grip.dragged.connect(_on_dragged)
	for pair in [[_seeds_multimesh, _seeds, simulation.seeds, MAX_SEEDS_SHOWN], [_cake_multimesh, _cake, simulation.seed_cake, MAX_PELLETS_SHOWN]]:
		var multimesh: MultiMesh = pair[0]
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _first_mesh((pair[2] as Ingredient).whole_model)
		multimesh.instance_count = pair[3]
		multimesh.visible_instance_count = 0
		(pair[1] as MultiMeshInstance3D).multimesh = multimesh
	_drip_material.albedo_color = Color(0.95, 0.78, 0.3, 0.8)
	_drip_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_drip_material.roughness = 0.1
	var drip_mesh := CylinderMesh.new()
	drip_mesh.top_radius = 1.0
	drip_mesh.bottom_radius = 0.6
	drip_mesh.height = 1.0
	drip_mesh.radial_segments = 6
	drip_mesh.material = _drip_material
	_drip.mesh = drip_mesh
	_drip.visible = false

## Applies turns of the crank, forward positive, as the player's hand would.
func turn_crank(turns: float) -> float:
	crank_angle += turns * TAU
	_crank.rotation = Vector3(crank_angle, 0.0, 0.0)
	if turns <= 0.0:
		return 0.0
	cranked.emit(turns)
	var oil_g: float = simulation.crank(turns, cup != null and cup.is_home())
	if oil_g > 0.0:
		pressed_oil.emit(oil_g)
		_drip_rate += oil_g
	return oil_g

func _on_pressed(point: Vector3) -> void:
	# Circle round the axle as the player sees it.
	var camera := get_viewport().get_camera_3d()
	var axis: Vector3 = (camera.global_position - _crank.global_position).normalized() if camera else Vector3.BACK
	_grip.drag_plane = Plane(axis, _crank.global_position)
	_drag.begin(_crank.global_position, axis, point)

func _on_dragged(point: Vector3) -> void:
	var step: float = _drag.update(point)
	# Clockwise on screen winds the screw in.
	if step != 0.0:
		turn_crank(-step / TAU)

func _process(delta: float) -> void:
	_draw_seeds()
	_draw_cake()
	_draw_drip(delta)

func _draw_seeds() -> void:
	var count: int = mini(int(simulation.press.loaded_g * SEEDS_PER_GRAM), MAX_SEEDS_SHOWN)
	var fill: float = simulation.press.loaded_g / simulation.hopper_capacity_g
	var top_y: float = lerpf(HOPPER_NECK_Y, HOPPER_MOUTH_Y, fill * HOPPER_FULL_SHARE)
	for index in count:
		# Seeds settle into the funnel from the neck up, filling it out to
		# its walls at each height.
		var around: float = index * 2.39996
		var y: float = lerpf(HOPPER_NECK_Y, top_y, fmod(index * 0.414, 1.0))
		var wall: float = lerpf(HOPPER_NECK_RADIUS_M, HOPPER_MOUTH_RADIUS_M, (y - HOPPER_NECK_Y) / (HOPPER_MOUTH_Y - HOPPER_NECK_Y)) * 0.85
		var out: float = sqrt(fmod(index * 0.618034, 1.0)) * wall
		var turn := Basis(Vector3.UP, around) * Basis(Vector3.RIGHT, fmod(index * 1.3, 0.6))
		_seeds_multimesh.set_instance_transform(index, Transform3D(turn, Vector3(HOPPER_AXIS.x + cos(around) * out, y, HOPPER_AXIS.y + sin(around) * out)))
	_seeds_multimesh.visible_instance_count = count

func _draw_cake() -> void:
	var count: int = mini(int(simulation.cake_g / CAKE_PELLET_G), MAX_PELLETS_SHOWN)
	var base := _outlet.position
	for index in count:
		var spot := Vector3(-0.015 - fmod(index * 0.37, 1.0) * 0.05, -base.y + 0.004 * (index / 10), (fmod(index * 0.618, 1.0) - 0.5) * 0.06)
		_cake_multimesh.set_instance_transform(index, Transform3D(Basis(Vector3.UP, index * 1.7), base + spot))
	_cake_multimesh.visible_instance_count = count

func _draw_drip(delta: float) -> void:
	_drip_rate = maxf(_drip_rate - _drip_rate * DRIP_DECAY_PER_S * delta, 0.0)
	var strength: float = clampf(_drip_rate / FULL_DRIP_G_PER_S, 0.0, 1.0)
	_drip.visible = strength > 0.02
	if not _drip.visible:
		return
	var top := _spout.global_position
	var bottom_y: float = global_position.y + 0.01
	if cup and cup.is_home():
		bottom_y = cup.global_position.y + 0.01 + cup.store().fill_fraction() * cup.fill_rise_m
	var length: float = maxf(top.y - bottom_y, 0.005)
	var radius: float = 0.0006 + 0.0018 * strength
	_drip.global_transform = Transform3D(Basis.from_scale(Vector3(radius, length, radius)), top - Vector3(0.0, length * 0.5, 0.0))

static func _first_mesh(scene: PackedScene) -> Mesh:
	if scene == null:
		return BoxMesh.new()
	var instance := scene.instantiate()
	var meshes := instance.find_children("*", "MeshInstance3D", true, false)
	var found: Mesh = (meshes[0] as MeshInstance3D).mesh if not meshes.is_empty() else BoxMesh.new()
	instance.free()
	return found
