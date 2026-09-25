class_name CameraRig
extends Node3D

## The cook's eyes. Every view is a Marker3D pose - where the eyes are and
## where they look - and the rig glides between them:
##
##   VISTA --opening hold ends, or camera_look_back--> STATION(i)
##   STATION(i) --camera_pan_left/right--> STATION(i -/+ 1)
##   STATION(i) --camera_look_out--> VISTA
##
## Stations are the counter's working views, the children of `stations` in
## scene order. The vista looks up from the counter and out to sea; the
## scene opens on it, because the player should always be free to stop and
## look at the sea.

const GLIDE_SPEED: float = 3.5

@export var stations: Node3D
@export var vista: Marker3D
## Seconds the opening view rests on the vista before settling on the first
## station.
@export var opening_hold_s: float = 3.0

var station_index: int = 0
var looking_out: bool = true

var _anchors: Array[Marker3D] = []
var _hold_s: float

func _ready() -> void:
	for child in stations.get_children():
		if child is Marker3D:
			_anchors.append(child)
	_hold_s = opening_hold_s
	global_transform = vista.global_transform

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_pan_left"):
		_settle_on(maxi(station_index - 1, 0))
	elif event.is_action_pressed("camera_pan_right"):
		_settle_on(mini(station_index + 1, _anchors.size() - 1))
	elif event.is_action_pressed("camera_look_out"):
		looking_out = true
		_hold_s = 0.0
	elif event.is_action_pressed("camera_look_back"):
		_settle_on(station_index)

func current_pose() -> Transform3D:
	if looking_out or _anchors.is_empty():
		return vista.global_transform
	return _anchors[station_index].global_transform

func _settle_on(index: int) -> void:
	station_index = index
	looking_out = false
	_hold_s = 0.0

func _process(delta: float) -> void:
	if _hold_s > 0.0:
		_hold_s -= delta
		if _hold_s <= 0.0:
			looking_out = false
	var target := current_pose()
	var weight: float = 1.0 - exp(-GLIDE_SPEED * delta)
	global_transform = Transform3D(
		global_transform.basis.get_rotation_quaternion().slerp(target.basis.get_rotation_quaternion(), weight),
		global_transform.origin.lerp(target.origin, weight)
	)
