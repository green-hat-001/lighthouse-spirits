class_name StoveView
extends Node3D

## The gas stove at the counter. The player turns the knob by dragging
## round it; the knob's angle is the gas, from off (pointing straight up)
## through 270 degrees to full, counter-clockwise as the cook sees it.
## Turning it on from off sparks the burner alight. It sets the flame on
## the pot's burner and draws the flame; it holds no heat logic itself.
##
##   OFF --knob turned past off--> LIT --knob turned back to off--> OFF

signal flame_changed(level: float)
## The burner caught: the spark lit it from off.
signal lit

const FULL_TURN_DEG: float = 270.0
## Knob travel below which the gas is off.
const OFF_DEG: float = 2.0

@export var simulation: KitchenSimulation

var knob_deg: float = 0.0

var _drag := CircularDrag.new()

@onready var _knob: Node3D = $Model/knob
@onready var _grip: Interactable = $KnobGrip
@onready var _flame: GasFlame = $Model/flame_anchor/Flame
@onready var _spark: GPUParticles3D = $Model/flame_anchor/Spark

func _ready() -> void:
	_grip.pressed.connect(_on_pressed)
	_grip.dragged.connect(_on_dragged)
	_flame.source = simulation.stove if simulation else null
	_flame.air = simulation.air if simulation else null
	set_knob(0.0)

## 0 off through to 1 full.
func flame_level() -> float:
	return 0.0 if knob_deg < OFF_DEG else knob_deg / FULL_TURN_DEG

## Turns the knob to an angle, as the player's hand would.
func set_knob(degrees: float) -> void:
	var was_off: bool = flame_level() <= 0.0
	knob_deg = clampf(degrees, 0.0, FULL_TURN_DEG)
	_knob.rotation = Vector3(0.0, 0.0, deg_to_rad(knob_deg))
	var level: float = flame_level()
	if simulation:
		simulation.pot.set_flame(level)
	_flame.level = level
	if was_off and level > 0.0:
		_spark.restart()
		_spark.emitting = true
		lit.emit()
	flame_changed.emit(level)

func _on_pressed(point: Vector3) -> void:
	var axis: Vector3 = _knob.global_transform.basis.z
	_grip.drag_plane = Plane(axis, _knob.global_position)
	_drag.begin(_knob.global_position, axis, point)

func _on_dragged(point: Vector3) -> void:
	var step: float = _drag.update(point)
	if step != 0.0:
		set_knob(knob_deg + rad_to_deg(step))
