class_name DishServingStation
extends RefCounted

## The only point of contact between the Culinary module and the Spirit
## FSM. Reads the target spirit's archetype to resolve affinity matching,
## applies the lighthouse's current station quality, then submits the
## result exclusively through SpiritEventBus - it never calls into
## SpiritController directly, same as any other feeding source.

const AFFINITY_MATCH_BONUS: float = 1.25

## Returns false if the dish could not be served: nothing in it, no valid
## recipient, or it uses content the lighthouse has not unlocked yet.
func serve(dish: CraftedDish, target_spirit: SpiritController) -> bool:
	if dish.is_empty() or not is_instance_valid(target_spirit):
		return false
	if not _is_dish_unlocked(dish):
		return false

	var result: FeedingResult = CulinaryCraftingMatrix.compute_feeding_result(dish)
	var dominant: ElementalAffinity.Type = CulinaryCraftingMatrix.dominant_affinity(dish)

	result.matched_affinity = dominant != ElementalAffinity.Type.NONE \
		and target_spirit.archetype != null \
		and dominant == target_spirit.archetype.elemental_affinity
	if result.matched_affinity:
		result.nourishment *= AFFINITY_MATCH_BONUS
		result.calming *= AFFINITY_MATCH_BONUS

	result.nourishment *= LighthouseProgression.station_nourishment_multiplier()
	result.calming *= LighthouseProgression.station_calming_multiplier()

	SpiritEventBus.feed_spirit_requested.emit(target_spirit.spirit_id, result)
	return true

func _is_dish_unlocked(dish: CraftedDish) -> bool:
	for component in dish.components:
		if not LighthouseProgression.is_ingredient_unlocked(component.ingredient):
			return false
		if not LighthouseProgression.is_technique_unlocked(component.technique):
			return false
	return true
