class_name CulinaryCraftingMatrix
extends RefCounted

## Pure data transform: CraftedDish -> FeedingResult. Deliberately has no
## knowledge of any specific spirit - affinity matching against a
## recipient happens where the dish is served (see DishServingStation),
## keeping this matrix reusable for any spirit.

static func compute_feeding_result(dish: CraftedDish) -> FeedingResult:
	var result := FeedingResult.new()
	for component in dish.components:
		var ingredient: Ingredient = component.ingredient
		var technique: PreparationTechnique = component.technique
		result.nourishment += ingredient.base_nourishment * technique.nourishment_multiplier \
			+ technique.nourishment_flat_bonus
		result.calming += ingredient.base_calming * technique.calming_multiplier \
			+ technique.calming_flat_bonus
		result.buoyancy_delta += ingredient.base_buoyancy_delta * technique.buoyancy_multiplier
	return result

## The affinity tag that appears most often among the dish's ingredients.
## Ties resolve to whichever affinity was encountered first.
static func dominant_affinity(dish: CraftedDish) -> ElementalAffinity.Type:
	var counts: Dictionary = {}
	var best_affinity: ElementalAffinity.Type = ElementalAffinity.Type.NONE
	var best_count: int = -1
	for component in dish.components:
		var affinity: ElementalAffinity.Type = component.ingredient.elemental_affinity
		var count: int = counts.get(affinity, 0) + 1
		counts[affinity] = count
		if count > best_count:
			best_count = count
			best_affinity = affinity
	return best_affinity
