class_name MezzalunaView
extends Node3D

## The mezzaluna in the hand. It lies at rest beside the board, follows the
## player's stroke across it with the blade along the stroke, and rocks
## through the food when the cut is made. Purely visual: the cut itself is
## made by the CuttingBoard.

const ROCK_ANGLE_DEG: float = 14.0
const ROCK_SECONDS: float = 0.12

## Where the blade lies when not in use, in the board's local space.
@export var rest_position: Vector3 = Vector3(0.26, -0.02, 0.0)

var _tween: Tween

@onready var _blade_pivot: Node3D = $BladePivot

func _ready() -> void:
	rest()

## Stands the blade on the board along the stroke, centred on it.
func show_stroke(start: Vector3, end: Vector3) -> void:
	_stop_tween()
	position = (start + end) * 0.5
	var stroke := end - start
	rotation = Vector3(0.0, atan2(-stroke.z, stroke.x) if stroke.length() > 0.001 else rotation.y, 0.0)
	_blade_pivot.rotation = Vector3.ZERO

## Rocks the curved blade end to end, the way a mezzaluna cuts, then lays
## it back at rest.
func rock() -> void:
	_stop_tween()
	_tween = create_tween()
	for angle in [ROCK_ANGLE_DEG, -ROCK_ANGLE_DEG, ROCK_ANGLE_DEG * 0.5, 0.0]:
		_tween.tween_property(_blade_pivot, "rotation:z", deg_to_rad(angle), ROCK_SECONDS)
	_tween.tween_interval(0.25)
	_tween.tween_callback(_settle)

func rest() -> void:
	_stop_tween()
	_settle()

func _settle() -> void:
	position = rest_position
	# Lies along the right-hand side of the board, handles towards the cook.
	rotation = Vector3(0.0, PI * 0.5, 0.0)
	_blade_pivot.rotation = Vector3.ZERO

func _stop_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
