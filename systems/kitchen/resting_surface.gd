class_name RestingSurface
extends RefCounted

## A surface out in the open where food rests between steps - the cutting
## board, or a spoon held in the air. Food here keeps changing: a hot fry
## lifted from the oil cooks on from the heat in its own core, steams dry,
## cools in the wind, and slowly goes limp as water creeps back out to its
## crust. The face a piece lies on touches the surface; every other face is
## in the air.
##
## Advances in fixed steps like the pot, but coarser: food in air changes
## slowly, and FoodHeating subdivides wherever it needs to.

const FIXED_STEP_S: float = 0.25

var air: KitchenAir
## Heat transfer into the face lying on the surface, in W/(m^2 K): wood
## conducts poorly, so a board barely takes heat out of food.
var contact_w_per_m2_k: float
## How much of the wind the surface is kept out of, 0-1.
var shelter: float
var pieces: Array[FoodPiece] = []

var _accumulator_s: float = 0.0

func _init(p_air: KitchenAir, p_contact_w_per_m2_k: float = 60.0, p_shelter: float = 0.2) -> void:
	air = p_air
	contact_w_per_m2_k = p_contact_w_per_m2_k
	shelter = p_shelter

func add_piece(piece: FoodPiece) -> bool:
	if piece == null or pieces.has(piece):
		return false
	pieces.append(piece)
	return true

func remove_piece(piece: FoodPiece) -> bool:
	var index: int = pieces.find(piece)
	if index < 0:
		return false
	pieces.remove_at(index)
	return true

## True when the piece's essences lift more than its weight, so it rises
## off the surface and hangs in the air above it.
static func is_hovering(piece: FoodPiece) -> bool:
	return TraitEffects.lift_share(piece) > 1.0

## The exposure of one piece lying here - or hovering above it, all in air.
func exposure_for(piece: FoodPiece) -> HeatExposure:
	var exposure := HeatExposure.new()
	exposure.use_per_face()
	exposure.temp_c = air.temp_c
	exposure.air_temp_c = air.temp_c
	exposure.air_vapour_kg_m3 = air.vapour_density_kg_m3()
	var air_h: float = air.convective_w_per_m2_k(shelter)
	for face in FoodPiece.FACE_COUNT:
		if face == FoodPiece.BOTTOM and not is_hovering(piece):
			exposure.set_face(face, 0.0, 0.0, contact_w_per_m2_k, air.temp_c, 0.0)
		else:
			exposure.set_face(face, 0.0, 0.0, 0.0, 0.0, air_h)
	return exposure

func advance(delta_s: float) -> void:
	_accumulator_s += delta_s
	while _accumulator_s >= FIXED_STEP_S:
		_accumulator_s -= FIXED_STEP_S
		for piece in pieces:
			FoodHeating.step(piece, exposure_for(piece), FIXED_STEP_S)
