class_name HandModel
extends Node3D

## The caretaker's hand: one of its poses shown at a time (open, grip,
## pinch, press), each authored with its origin at the point it touches
## with, so a pose can be swapped without the hand jumping. `left` mirrors
## it into the other hand. Changing pose pops the hand a touch, as a hand
## does when it closes on something.

enum Pose { OPEN, GRIP, PINCH, PRESS }

const POSE_NAMES: Array[String] = ["hand_open", "hand_grip", "hand_pinch", "hand_press"]
## Hands are drawn a little smaller than life: at the counter the eye is
## only half a metre from them, and a life-size hand hides the work.
const SIZE: float = 0.86
const POP_SCALE: float = 0.93
const POP_EASE: float = 18.0

@export var left: bool = false

var pose: Pose = Pose.OPEN
var _meshes: Array[Node3D] = []
var _pop: float = 1.0

@onready var _model: Node3D = $Model

func _ready() -> void:
	for pose_name in POSE_NAMES:
		_meshes.append(_model.get_node(pose_name))
	_model.scale = Vector3(-SIZE if left else SIZE, SIZE, SIZE)
	_show(pose)

func set_pose(next: Pose) -> void:
	if next == pose:
		return
	pose = next
	_pop = POP_SCALE
	_show(pose)

func _show(shown: Pose) -> void:
	for index in _meshes.size():
		_meshes[index].visible = index == shown

func _process(delta: float) -> void:
	_pop = lerpf(_pop, 1.0, 1.0 - exp(-POP_EASE * delta))
	var size: float = _pop * SIZE
	_model.scale = Vector3(-size if left else size, size, size)
