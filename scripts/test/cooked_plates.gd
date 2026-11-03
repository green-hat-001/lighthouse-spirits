class_name CookedPlates
extends RefCounted

## Plates of food cooked in code through the real food simulation, for the
## test suite and the spirit harness, which need something to serve without
## a cook at the counter. Nothing here is a recipe the game knows: it is the
## same physics the kitchen runs, driven by a script instead of hands.

## Whole items of an ingredient held in a liquid at a fixed temperature for
## a while, as if the cook kept the flame exactly right.
static func cooked_whole(ingredient: Ingredient, count: int, medium: Ingredient, temp_c: float, seconds: float, ambient_c: float = 15.0) -> Array[FoodPiece]:
	var pieces: Array[FoodPiece] = []
	for index in count:
		pieces.append(FoodPiece.from_ingredient(ingredient, ambient_c))
	_hold(pieces, medium, temp_c, seconds)
	return pieces

## A whole item cut into square sticks, then cooked.
static func cooked_sticks(ingredient: Ingredient, thickness_mm: float, medium: Ingredient, temp_c: float, seconds: float, ambient_c: float = 15.0) -> Array[FoodPiece]:
	var sticks: Array[FoodPiece] = []
	for plank in _slices(FoodPiece.from_ingredient(ingredient, ambient_c), Vector3.AXIS_Z, thickness_mm):
		sticks.append_array(_slices(plank, Vector3.AXIS_Y, thickness_mm))
	_hold(sticks, medium, temp_c, seconds)
	return sticks

static func plate(pieces: Array[FoodPiece]) -> Dish:
	var dish := Dish.new()
	for piece in pieces:
		dish.add_piece(piece)
	return dish

static func _hold(pieces: Array[FoodPiece], medium: Ingredient, temp_c: float, seconds: float) -> void:
	var exposure := HeatExposure.new()
	exposure.temp_c = temp_c
	exposure.heat_transfer_w_per_m2_k = medium.medium_heat_transfer_w_per_m2_k
	exposure.fat_fraction = medium.fat_fraction
	exposure.water_fraction = medium.water_fraction
	exposure.flavour = medium.flavour.copy()
	exposure.medium_mass_g = 1000.0
	for piece in pieces:
		var elapsed: float = 0.0
		while elapsed < seconds:
			FoodHeating.step(piece, exposure, 0.25)
			elapsed += 0.25

static func _slices(piece: FoodPiece, axis: int, step_mm: float) -> Array[FoodPiece]:
	var slices: Array[FoodPiece] = []
	var remainder := piece
	while remainder.size_mm[axis] >= step_mm + FoodCutting.MIN_PIECE_THICKNESS_MM:
		var parts := FoodCutting.cut(remainder, axis, step_mm, true)
		slices.append(parts[0])
		remainder = parts[1]
	slices.append(remainder)
	return slices
