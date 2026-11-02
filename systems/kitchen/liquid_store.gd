class_name LiquidStore
extends RefCounted

## Liquid held in something the player pours from: the oil cup under the
## press, the oil bottle, the water jug. It holds one liquid at a time, by
## mass, with its own flavour and temperature. An unlimited store (the jug,
## filled from the well) never runs dry.

var ingredient: Ingredient
var grams: float = 0.0
var capacity_g: float
var temp_c: float
var flavour: FlavourProfile
var unlimited: bool = false

func _init(p_capacity_g: float, p_temp_c: float, p_ingredient: Ingredient = null, p_unlimited: bool = false) -> void:
	capacity_g = p_capacity_g
	temp_c = p_temp_c
	unlimited = p_unlimited
	if p_ingredient:
		ingredient = p_ingredient
		flavour = p_ingredient.flavour.copy() if p_ingredient.flavour else FlavourProfile.new()
		if unlimited:
			grams = capacity_g

func is_empty() -> bool:
	return grams <= 0.0 and not unlimited

func fill_fraction() -> float:
	return 1.0 if unlimited else clampf(grams / capacity_g, 0.0, 1.0)

## Takes in up to `amount_g` of a liquid and returns how much fitted.
## Refused for a different liquid than the one already held.
func receive(liquid: Ingredient, amount_g: float, liquid_flavour: FlavourProfile, liquid_temp_c: float) -> float:
	if liquid == null or amount_g <= 0.0 or unlimited:
		return 0.0
	if ingredient != null and grams > 0.0 and ingredient != liquid:
		return 0.0
	var accepted: float = minf(amount_g, capacity_g - grams)
	if accepted <= 0.0:
		return 0.0
	var incoming: FlavourProfile = liquid_flavour if liquid_flavour else (liquid.flavour if liquid.flavour else FlavourProfile.new())
	if ingredient == null or grams <= 0.0:
		ingredient = liquid
		flavour = incoming.copy()
		temp_c = liquid_temp_c
	else:
		flavour = FlavourProfile.mix_by_mass(flavour, grams, incoming, accepted)
		temp_c = (temp_c * grams + liquid_temp_c * accepted) / (grams + accepted)
	grams += accepted
	return accepted

## Takes up to `amount_g` out and returns how much came.
func draw(amount_g: float) -> float:
	if ingredient == null or amount_g <= 0.0:
		return 0.0
	if unlimited:
		return amount_g
	var drawn: float = minf(amount_g, grams)
	grams -= drawn
	return drawn
