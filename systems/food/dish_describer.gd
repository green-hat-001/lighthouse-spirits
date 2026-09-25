class_name DishDescriber
extends RefCounted

## Buckets a piece's physical state into the coarse words a cook would use -
## a thin golden stick, a burnt chunk, a spicy oil - so that dishes made the
## same way share a fingerprint despite small differences.

const THIN_MM: float = 6.0
const THICK_MM: float = 14.0
const STICK_LENGTH_RATIO: float = 2.5
const SQUARE_RATIO: float = 1.6
const SLICE_RATIO: float = 3.0
const PALE_BELOW: float = 0.15
const GOLDEN_BELOW: float = 0.5
const BROWN_BELOW: float = 0.85
const BURNT_CHAR: float = 0.2
## How far a liquid's flavour must rise above its own raw flavour on an axis
## to count as infused with it.
const INFUSED_ABOVE: float = 0.05

static func describe_piece(piece: FoodPiece) -> String:
	return "%s:%s:%s:%s:%s" % [
		piece.ingredient.id, _shape(piece), _thickness(piece), _doneness(piece), _colour(piece)
	]

static func describe_liquid(portion: LiquidPortion) -> String:
	var infusions: Array[String] = []
	for axis in FlavourProfile.AXES:
		if float(portion.flavour.get(axis)) > float(portion.ingredient.flavour.get(axis)) + INFUSED_ABOVE:
			infusions.append(str(axis))
	return "%s:%s" % [portion.ingredient.id, "+".join(infusions) if not infusions.is_empty() else "plain"]

## The most frequent entry; ties go to the alphabetically first.
static func most_common(descriptions: Array) -> String:
	var counts: Dictionary[String, int] = {}
	for description in descriptions:
		counts[description] = counts.get(description, 0) + 1
	var best: String = ""
	var best_count: int = 0
	for description in counts:
		if counts[description] > best_count or (counts[description] == best_count and description < best):
			best = description
			best_count = counts[description]
	return best

static func _shape(piece: FoodPiece) -> String:
	if piece.cut_axes.is_empty():
		return "whole"
	var dims: Array[float] = [piece.size_mm.x, piece.size_mm.y, piece.size_mm.z]
	dims.sort()
	var shortest: float = dims[0]
	var middle: float = dims[1]
	var longest: float = dims[2]
	if longest <= SQUARE_RATIO * shortest:
		return "dice"
	if longest >= STICK_LENGTH_RATIO * middle and middle <= SQUARE_RATIO * shortest:
		return "stick"
	if middle >= SLICE_RATIO * shortest:
		return "slice"
	return "chunk"

static func _thickness(piece: FoodPiece) -> String:
	var shortest: float = piece.min_dimension_mm()
	if shortest < THIN_MM:
		return "thin"
	if shortest < THICK_MM:
		return "medium"
	return "thick"

static func _doneness(piece: FoodPiece) -> String:
	if piece.core_doneness < 0.5:
		return "raw"
	if piece.core_doneness < piece.ingredient.ideal_doneness_min:
		return "underdone"
	if piece.core_doneness <= piece.ingredient.ideal_doneness_max:
		return "cooked"
	return "overcooked"

static func _colour(piece: FoodPiece) -> String:
	if piece.surface_char >= BURNT_CHAR:
		return "burnt"
	if piece.surface_browning < PALE_BELOW:
		return "pale"
	if piece.surface_browning < GOLDEN_BELOW:
		return "golden"
	if piece.surface_browning < BROWN_BELOW:
		return "brown"
	return "dark"
