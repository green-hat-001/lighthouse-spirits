class_name DishComponent
extends RefCounted

## One ingredient as prepared by one technique within a CraftedDish.

var ingredient: Ingredient
var technique: PreparationTechnique

func _init(p_ingredient: Ingredient, p_technique: PreparationTechnique) -> void:
	ingredient = p_ingredient
	technique = p_technique
