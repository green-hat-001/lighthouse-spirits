class_name KitchenViewMode
extends RefCounted

## Whether the caretaker is walking about or working at the counter. Flat:
##
##   WALKING --step in, within reach--> STEPPING_IN --arrived--> AT_COUNTER
##   AT_COUNTER --step out--> STEPPING_OUT --arrived--> WALKING
##   STEPPING_IN --step out--> STEPPING_OUT   (changed their mind mid-glide)
##
## Only WALKING takes movement input; only AT_COUNTER takes the mouse hand
## and the counter's camera keys. The glides take no input at all.

enum Mode { WALKING, STEPPING_IN, AT_COUNTER, STEPPING_OUT }

## How close to the counter's edge, in metres, the caretaker must stand.
const REACH_M: float = 0.9
## How squarely they must face it (cosine of the widest angle allowed).
const MIN_FACING: float = 0.5

var mode: Mode = Mode.WALKING

## True if a caretaker standing at `position` and facing `facing` (both on
## the ground plane, x/z) can work at a counter whose footprint is `counter`.
static func within_reach(position: Vector2, facing: Vector2, counter: Rect2) -> bool:
	var nearest := Vector2(
		clampf(position.x, counter.position.x, counter.end.x),
		clampf(position.y, counter.position.y, counter.end.y)
	)
	var to_counter := nearest - position
	if to_counter.length() > REACH_M:
		return false
	if to_counter.length() < 0.001:
		return true
	return facing.normalized().dot(to_counter.normalized()) >= MIN_FACING

func step_in(reachable: bool) -> bool:
	if mode != Mode.WALKING or not reachable:
		return false
	mode = Mode.STEPPING_IN
	return true

func step_out() -> bool:
	if mode != Mode.AT_COUNTER and mode != Mode.STEPPING_IN:
		return false
	mode = Mode.STEPPING_OUT
	return true

## The camera has finished gliding to where the current step was heading.
func arrived() -> void:
	if mode == Mode.STEPPING_IN:
		mode = Mode.AT_COUNTER
	elif mode == Mode.STEPPING_OUT:
		mode = Mode.WALKING
