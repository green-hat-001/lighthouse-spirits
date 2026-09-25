class_name CameraRig
extends Node3D

## The fixed three-quarter view of a cook standing at the counter, looking
## down at one station at a time. "camera_pan_left" and "camera_pan_right"
## glide between the Marker3D children of Stations, left to right by x.

const GLIDE_SPEED: float = 6.0

@export var stations: Node3D

var station_index: int = 0
var _anchors: Array[Marker3D] = []

func _ready() -> void:
	for child in stations.get_children():
		if child is Marker3D:
			_anchors.append(child)
	_anchors.sort_custom(func(a: Marker3D, b: Marker3D) -> bool: return a.global_position.x < b.global_position.x)
	if not _anchors.is_empty():
		global_position = _anchors[station_index].global_position

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_pan_left"):
		station_index = maxi(station_index - 1, 0)
	elif event.is_action_pressed("camera_pan_right"):
		station_index = mini(station_index + 1, _anchors.size() - 1)

func _process(delta: float) -> void:
	if _anchors.is_empty():
		return
	var target := _anchors[station_index].global_position
	global_position = global_position.lerp(target, 1.0 - exp(-GLIDE_SPEED * delta))
