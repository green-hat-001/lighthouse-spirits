class_name PotPlacement
extends RefCounted

## Where one piece of food is in a pot and how it sits there. Updated by
## PotLayout every step from buoyancy and the pieces around it; read by
## CookingPot to decide which of the piece's faces touch metal, oil or air,
## and by the view to draw it.

enum Resting {
	## On the bottom of the pot, touching the metal.
	FLOOR,
	## Sunk, but lying on other food rather than the metal.
	ON_FOOD,
	## Floating in the liquid.
	FLOATING,
}

var piece: FoodPiece
## Centre of the piece's footprint, from the pot's centre, in mm (x, z).
var centre_mm: Vector2 = Vector2.ZERO
## Height of the piece's bottom face above the pot's floor, in mm.
var bottom_mm: float = 0.0
var resting: Resting = Resting.FLOOR
## Share of the piece's height below the liquid line, 0-1.
var immersion: float = 0.0
## How much of the piece's bottom is over the hot middle of the base, 0-1
## (the rest is over the cooler rim).
var over_burner: float = 1.0
## Steam bubbling off the piece's wetted faces, g/s, from the last step.
## Bubbles clinging to food lift it.
var steam_g_per_s: float = 0.0

func _init(p_piece: FoodPiece, p_centre_mm: Vector2) -> void:
	piece = p_piece
	centre_mm = p_centre_mm

## The box it takes up in the pot: the piece, or for a heap of grain, the
## layer its kernels make.
func size_mm() -> Vector3:
	return piece.bulk_size_mm()

func top_mm() -> float:
	return bottom_mm + size_mm().y

func footprint() -> Rect2:
	var size := Vector2(size_mm().x, size_mm().z)
	return Rect2(centre_mm - size * 0.5, size)
