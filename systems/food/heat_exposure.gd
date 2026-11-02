class_name HeatExposure
extends RefCounted

## What surrounds a FoodPiece while it cooks, face by face. Each of the
## piece's six faces can draw heat through three channels at once:
##
##   liquid   the medium it is wetted by (oil, water), at temp_c
##   contact  something solid it rests on - the hot bottom of the pot, the
##            board - at that face's contact temperature
##   air      open air at air_temp_c, which also dries a wet face
##
## A fry lying in shallow oil has its bottom face in contact with the pot
## through a film of oil, its sides partly wetted, and its top in the air.
## The owner of the medium (a pot, the board) fills this in; FoodHeating
## reads it, and writes the flavour the food releases back into `flavour`.
##
## Without per-face values (`per_face` false) every face is fully immersed
## in the medium at temp_c with heat_transfer_w_per_m2_k - a piece held
## deep in a well-stirred liquid.

## The liquid medium's temperature (or, uniformly, the surroundings').
var temp_c: float = 20.0
## Uniform heat transfer from the medium into every face, in W/(m^2 K).
var heat_transfer_w_per_m2_k: float = 0.0
## Fat as a fraction of the medium. Food can soak up fat, never water.
var fat_fraction: float = 0.0
## The medium's own flavour, mutated as flavour moves in and out of food.
## Null when there is no liquid medium to exchange with.
var flavour: FlavourProfile
var medium_mass_g: float = 0.0
## Chemistry of a worn medium: oil that has broken down browns food faster
## and soaks into it more readily. 1 for a fresh medium.
var browning_boost: float = 1.0
var uptake_boost: float = 1.0

var air_temp_c: float = 20.0
## Water vapour already in the air, in kg/m^3 (see KitchenAir).
var air_vapour_kg_m3: float = 0.0

var per_face: bool = false
## Per face, indexed by FoodPiece.Face. Coefficients are already scaled by
## the share of the face they act on.
var face_liquid_share := PackedFloat64Array()
var face_liquid_h := PackedFloat64Array()
var face_contact_h := PackedFloat64Array()
var face_contact_temp_c := PackedFloat64Array()
var face_air_h := PackedFloat64Array()

## Switches to per-face values, with every face starting out exposed to
## nothing at all.
func use_per_face() -> void:
	per_face = true
	for array in [&"face_liquid_share", &"face_liquid_h", &"face_contact_h", &"face_contact_temp_c", &"face_air_h"]:
		var values := PackedFloat64Array()
		values.resize(FoodPiece.FACE_COUNT)
		values.fill(0.0)
		set(array, values)

## Sets how one face is exposed. `liquid_share` (0-1) is how much of it the
## liquid wets; the other share, less any contact, is in the air.
func set_face(
		face: int, liquid_share: float, liquid_h: float,
		contact_h: float, contact_temp_c: float, air_h: float) -> void:
	face_liquid_share[face] = clampf(liquid_share, 0.0, 1.0)
	face_liquid_h[face] = liquid_h
	face_contact_h[face] = contact_h
	face_contact_temp_c[face] = contact_temp_c
	face_air_h[face] = air_h

func has_liquid() -> bool:
	return flavour != null or fat_fraction > 0.0

func liquid_share(face: int) -> float:
	if per_face:
		return face_liquid_share[face]
	return 1.0 if has_liquid() else 0.0

func liquid_h(face: int) -> float:
	return face_liquid_h[face] if per_face else heat_transfer_w_per_m2_k

func contact_h(face: int) -> float:
	return face_contact_h[face] if per_face else 0.0

func contact_temp_c(face: int) -> float:
	return face_contact_temp_c[face] if per_face else temp_c

func air_h(face: int) -> float:
	return face_air_h[face] if per_face else 0.0
