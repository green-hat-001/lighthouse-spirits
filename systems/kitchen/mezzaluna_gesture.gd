class_name MezzalunaGesture
extends RefCounted

## Reads a drag of the mezzaluna across the board as a cut through one
## piece. Everything is in millimetres on the board's surface, as Vector2(x,
## z): pieces sit axis-aligned on the board, so a piece's local X and Z are
## the board's.
##
## The drag snaps to the nearer of the two board axes. A drag running mostly
## along X is a blade line along X, which cuts across Z; and vice versa.
## The blade's position is read where the drag line passes the piece's
## centre, so a slightly slanted stroke still cuts where the player aimed.
## A stroke that misses the piece, or skims less than MIN_COVERAGE of it, is
## not a cut.

const MIN_COVERAGE: float = 0.5
## Shorter strokes are treated as a slip of the hand.
const MIN_STROKE_MM: float = 5.0

## The cut the stroke makes through the piece, or null if it makes none.
static func resolve(footprint_min: Vector2, footprint_size: Vector2, start: Vector2, end: Vector2) -> CutIntent:
	var stroke: Vector2 = end - start
	if stroke.length() < MIN_STROKE_MM:
		return null
	var centre: Vector2 = footprint_min + footprint_size * 0.5
	if absf(stroke.x) >= absf(stroke.y):
		if not _covers(start.x, end.x, footprint_min.x, footprint_size.x):
			return null
		var line_z: float = start.y + (centre.x - start.x) * stroke.y / stroke.x
		return _intent_within(Vector3.AXIS_Z, line_z - footprint_min.y, footprint_size.y)
	if not _covers(start.y, end.y, footprint_min.y, footprint_size.y):
		return null
	var line_x: float = start.x + (centre.y - start.y) * stroke.x / stroke.y
	return _intent_within(Vector3.AXIS_X, line_x - footprint_min.x, footprint_size.x)

static func _covers(stroke_a: float, stroke_b: float, piece_min: float, piece_length: float) -> bool:
	var overlap: float = minf(maxf(stroke_a, stroke_b), piece_min + piece_length) - maxf(minf(stroke_a, stroke_b), piece_min)
	return overlap >= MIN_COVERAGE * piece_length

static func _intent_within(axis: int, offset_mm: float, length_mm: float) -> CutIntent:
	if offset_mm <= 0.0 or offset_mm >= length_mm:
		return null
	return CutIntent.new(axis, offset_mm)
