class_name FoodCutting
extends RefCounted

## Pure geometry behind the mezzaluna. A cut is a plane perpendicular to one
## of the piece's local axes, placed offset_mm along that axis from the
## piece's minimum face, and it always turns one piece into two. The 3D
## layer is responsible for snapping the player's drag to a piece axis.
##
## Across a cut:
##   - size, and the grams of solids, water and oil, split in proportion
##     along the cut axis, so mass is conserved exactly;
##   - bulk state (core temperature, doneness, flavour) is inherited
##     unchanged;
##   - each side gains a fresh interior face, which dilutes surface
##     browning and char and pulls surface temperature and moisture towards
##     the core's;
##   - a side thinner than the ingredient's stable thickness crumbles in
##     proportion to how thin it is;
##   - a perpendicular cut made without steadying the food costs both sides
##     the ingredient's unsteadied-cut integrity loss.

## The thinnest slice a mezzaluna can take. A cut that would leave a thinner
## side is refused, not performed.
const MIN_PIECE_THICKNESS_MM: float = 1.5

## The two resulting pieces, ordered from the minimum face outward, or an
## empty array when the cut cannot be made because it misses the piece or
## would leave a side thinner than MIN_PIECE_THICKNESS_MM. The input piece
## is never modified.
static func cut(piece: FoodPiece, axis: int, offset_mm: float, steadied: bool) -> Array[FoodPiece]:
	var pieces: Array[FoodPiece] = []
	if piece == null or axis < Vector3.AXIS_X or axis > Vector3.AXIS_Z:
		push_error("FoodCutting: a cut needs a piece and an axis of X, Y or Z")
		return pieces

	var length: float = piece.size_mm[axis]
	if offset_mm < MIN_PIECE_THICKNESS_MM or length - offset_mm < MIN_PIECE_THICKNESS_MM:
		return pieces

	var unsteadied_perpendicular: bool = not steadied and is_perpendicular(piece, axis)
	for side_length in [offset_mm, length - offset_mm]:
		pieces.append(_make_side(piece, axis, side_length, length, unsteadied_perpendicular))
	return pieces

## True when the piece has already been cut along some other axis, so this
## cut would need the food held steady.
static func is_perpendicular(piece: FoodPiece, axis: int) -> bool:
	for previous_axis in piece.cut_axes:
		if previous_axis != axis:
			return true
	return false

static func _make_side(
		parent: FoodPiece, axis: int, side_length: float, parent_length: float,
		unsteadied_perpendicular: bool) -> FoodPiece:
	var side := parent.clone()
	var size := parent.size_mm
	size[axis] = side_length
	side.size_mm = size
	var share: float = side_length / parent_length
	side.solids_g = parent.solids_g * share
	side.water_g = parent.water_g * share
	side.oil_g = parent.oil_g * share

	var total_area: float = side.surface_area_mm2()
	var fresh_area: float = side.cross_section_mm2(axis)
	var old_area: float = total_area - fresh_area
	side.surface_browning = parent.surface_browning * old_area / total_area
	side.surface_char = parent.surface_char * old_area / total_area
	side.surface_temp_c = (parent.surface_temp_c * old_area + parent.core_temp_c * fresh_area) / total_area
	side.surface_moisture = (parent.surface_moisture * old_area + parent.core_moisture() * fresh_area) / total_area
	side.clamp_surface_moisture()

	var stable_thickness: float = parent.ingredient.stable_thickness_mm
	if side_length < stable_thickness:
		side.integrity *= side_length / stable_thickness
	if unsteadied_perpendicular:
		side.integrity *= 1.0 - parent.ingredient.unsteadied_cut_integrity_loss

	if not side.cut_axes.has(axis):
		side.cut_axes.append(axis)
	return side
