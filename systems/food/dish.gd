class_name Dish
extends RefCounted

## What ends up on a plate: cooked pieces and any liquids poured over them.
## A dish is never authored. Its identity is a fingerprint of what went into
## it and how it was cooked, so the player can recognise, name and repeat
## their own dishes.

var pieces: Array[FoodPiece] = []
var liquids: Array[LiquidPortion] = []

func add_piece(piece: FoodPiece) -> void:
	pieces.append(piece)

func add_liquid(portion: LiquidPortion) -> void:
	liquids.append(portion)

func is_empty() -> bool:
	return pieces.is_empty() and liquids.is_empty()

## The affinity carrying the most mass on the plate, pieces and liquids
## together, or NONE for an empty plate or one where nothing carries one.
func dominant_affinity() -> ElementalAffinity.Type:
	var mass_by_affinity: Dictionary[ElementalAffinity.Type, float] = {}
	for piece in pieces:
		var affinity: ElementalAffinity.Type = piece.ingredient.elemental_affinity
		mass_by_affinity[affinity] = mass_by_affinity.get(affinity, 0.0) + piece.total_mass_g()
	for portion in liquids:
		var affinity: ElementalAffinity.Type = portion.ingredient.elemental_affinity
		mass_by_affinity[affinity] = mass_by_affinity.get(affinity, 0.0) + portion.grams
	var best: ElementalAffinity.Type = ElementalAffinity.Type.NONE
	var best_mass: float = 0.0
	for affinity in mass_by_affinity:
		if affinity != ElementalAffinity.Type.NONE and mass_by_affinity[affinity] > best_mass:
			best = affinity
			best_mass = mass_by_affinity[affinity]
	return best

## The same dish cooked the same way again gives the same fingerprint;
## cutting it differently, cooking it to a different degree or burning it
## gives a different one. Each ingredient contributes the most common
## description among its pieces, so one stray fry doesn't change the dish.
func fingerprint() -> String:
	var descriptions_by_ingredient: Dictionary[StringName, Array] = {}
	for piece in pieces:
		var id: StringName = piece.ingredient.id
		if not descriptions_by_ingredient.has(id):
			descriptions_by_ingredient[id] = []
		descriptions_by_ingredient[id].append(DishDescriber.describe_piece(piece))
	var parts: Array[String] = []
	for id in descriptions_by_ingredient:
		parts.append(DishDescriber.most_common(descriptions_by_ingredient[id]))
	for portion in liquids:
		parts.append(DishDescriber.describe_liquid(portion))
	parts.sort()
	return "|".join(parts)
