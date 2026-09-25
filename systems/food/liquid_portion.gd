class_name LiquidPortion
extends RefCounted

## An amount of a liquid on a plate - a drizzle of chilli oil, a ladle of
## broth - carrying whatever flavour it picked up in the kitchen.

var ingredient: Ingredient
var grams: float
var flavour: FlavourProfile

func _init(p_ingredient: Ingredient, p_grams: float, p_flavour: FlavourProfile) -> void:
	ingredient = p_ingredient
	grams = p_grams
	flavour = p_flavour.copy() if p_flavour else p_ingredient.flavour.copy()
