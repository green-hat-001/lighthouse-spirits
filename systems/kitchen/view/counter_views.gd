class_name CounterViews
extends Node

## The views of a cook working at the counter: one Marker3D pose per
## station (children of `stations`, in order), and a vista that lifts the
## eyes out to sea. It supplies poses; the Kitchen moves the camera.
##
##   STATION(i) --camera_pan_left/right--> STATION(i -/+ 1)
##   STATION(i) --camera_look_out--> VISTA --camera_look_back--> STATION(i)
##
## Pushing the mouse towards either edge of the screen turns the view a
## little that way, to glance at what's beside the station without moving.
## At a station in front of the pantry, pushing it to the top edge lifts the
## eyes to the shelves, and they stay lifted - so the hand can move about
## the shelves - until the mouse goes down into the lower part of the
## screen:
##
##   LEVEL --mouse at the top edge--> LIFTED --mouse low on the screen--> LEVEL
##   LIFTED --another station, or out to sea--> LEVEL

## Only the outer part of the screen on each side peeks, so reaching for
## something near the edge doesn't swing the view.
const PEEK_DEAD_ZONE: float = 0.62
const PEEK_MAX_DEG: float = 26.0
## The mouse this near the top edge (-1) lifts the eyes to the shelves, and
## this far down the screen (1 is the bottom) lowers them again.
const LIFT_AT: float = -0.9
const LOWER_AT: float = 0.45
## How far the eyes lift.
const GLANCE_MAX_DEG: float = 34.0

@export var stations: Node3D
@export var vista: Marker3D
## The stations (by index) standing in front of the pantry shelves.
@export var below_shelves: PackedInt32Array = PackedInt32Array()

## Keys and peeking are only live while the Kitchen says so.
var active: bool = false
var station_index: int = 0
var looking_out: bool = false
## The eyes are lifted to the pantry shelves.
var looking_up: bool = false

var _anchors: Array[Marker3D] = []

func _ready() -> void:
	for child in stations.get_children():
		if child is Marker3D:
			_anchors.append(child)

## The station whose view is centred nearest the given x - where the
## caretaker is standing when they step in.
func nearest_station(x: float) -> int:
	var best: int = 0
	for index in _anchors.size():
		if absf(_anchors[index].global_position.x - x) < absf(_anchors[best].global_position.x - x):
			best = index
	return best

## The pose to show, turned by `peek_deg` about the vertical and lifted by
## `glance_deg` toward the shelves.
func pose(peek_deg: float, glance_deg: float = 0.0) -> Transform3D:
	var base := vista.global_transform if looking_out or _anchors.is_empty() else _anchors[station_index].global_transform
	return Transform3D(Basis(Vector3.UP, deg_to_rad(peek_deg)) * base.basis * Basis(Vector3.RIGHT, deg_to_rad(glance_deg)), base.origin)

## Whether the eyes can lift to the shelves from where the cook stands.
func can_glance_up() -> bool:
	return not looking_out and below_shelves.has(station_index)

## Lifts or lowers the eyes for a mouse at `mouse_y_norm` (-1 top edge, 1
## bottom), and returns how far they should be lifted, in degrees.
func glance(mouse_y_norm: float) -> float:
	if not can_glance_up():
		looking_up = false
	elif not looking_up and mouse_y_norm <= LIFT_AT:
		looking_up = true
	elif looking_up and mouse_y_norm >= LOWER_AT:
		looking_up = false
	return GLANCE_MAX_DEG if looking_up else 0.0

## Degrees to turn for a mouse at `mouse_x_norm` (-1 left edge, 1 right
## edge): nothing in the middle, easing up to PEEK_MAX_DEG at the edges.
## Positive turns left.
static func peek_degrees(mouse_x_norm: float) -> float:
	var outward: float = smoothstep(PEEK_DEAD_ZONE, 1.0, absf(mouse_x_norm))
	return -signf(mouse_x_norm) * outward * PEEK_MAX_DEG

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("camera_pan_left"):
		station_index = maxi(station_index - 1, 0)
		looking_out = false
		looking_up = false
	elif event.is_action_pressed("camera_pan_right"):
		station_index = mini(station_index + 1, _anchors.size() - 1)
		looking_out = false
		looking_up = false
	elif event.is_action_pressed("camera_look_out"):
		looking_out = true
	elif event.is_action_pressed("camera_look_back"):
		looking_out = false
