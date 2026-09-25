class_name CutIntent
extends RefCounted

## One cut the player has asked for: along which of the piece's axes, and
## how far from its minimum face.

var axis: int
var offset_mm: float

func _init(p_axis: int, p_offset_mm: float) -> void:
	axis = p_axis
	offset_mm = p_offset_mm
