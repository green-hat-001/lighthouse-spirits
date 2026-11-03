class_name LiquidPortion
extends RefCounted

## An amount of a liquid on a plate - a drizzle of chilli oil, a ladle of
## broth - carrying whatever flavour it picked up in the kitchen.

var ingredient: Ingredient
var grams: float
var flavour: FlavourProfile
## The mystical essences it carries - a broth that took in what was boiled.
var traits: TraitDoses
var temp_c: float

func _init(p_ingredient: Ingredient, p_grams: float, p_flavour: FlavourProfile, p_traits: TraitDoses = null, p_temp_c: float = 20.0) -> void:
	ingredient = p_ingredient
	grams = p_grams
	flavour = p_flavour.copy() if p_flavour else p_ingredient.flavour.copy()
	traits = p_traits.copy() if p_traits else p_ingredient.trait_doses()
	temp_c = p_temp_c
