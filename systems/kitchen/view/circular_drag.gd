class_name CircularDrag
extends RefCounted

## Reads a drag around a pivot as turning it, the way a hand turns a knob
## or a crank: the angle swept around the pivot, in the plane facing the
## player. Angles are accumulated step by step, so circling round and round
## keeps adding up and never jumps across the half-turn.

## Closer to the pivot than this, in metres, the angle is too jittery to
## read and the step is ignored.
const DEAD_RADIUS_M: float = 0.004

var pivot: Vector3
var plane: Plane
var _axis_u: Vector3
var _axis_v: Vector3
var _last_angle: float = 0.0
var _has_angle: bool = false

## Starts a drag about `pivot`, turning about `axis` (the side of the
## plane the player looks at). Positive turns are counter-clockwise as the
## player sees them.
func begin(p_pivot: Vector3, axis: Vector3, start_point: Vector3) -> void:
	pivot = p_pivot
	var normal := axis.normalized()
	plane = Plane(normal, pivot)
	_axis_u = normal.cross(Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD).normalized()
	_axis_v = normal.cross(_axis_u).normalized()
	_has_angle = false
	update(start_point)

## The angle swept since the last point, in radians.
func update(point: Vector3) -> float:
	var offset: Vector3 = plane.project(point) - pivot
	if offset.length() < DEAD_RADIUS_M:
		return 0.0
	var angle: float = atan2(offset.dot(_axis_v), offset.dot(_axis_u))
	if not _has_angle:
		_has_angle = true
		_last_angle = angle
		return 0.0
	var step: float = wrapf(angle - _last_angle, -PI, PI)
	_last_angle = angle
	return step
