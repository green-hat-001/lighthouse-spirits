class_name DishServingStation
extends RefCounted

## The only point of contact between the kitchen and the Spirit FSM. Takes a
## plated Dish, turns it into a FeedingResult through DishNourishment (real
## food, judged against each ingredient's own ideal, never a recipe), adds
## the affinity bonus when the dish's dominant affinity matches the spirit,
## applies the lighthouse's station quality, then submits the result
## exclusively through SpiritEventBus - it never calls into
## SpiritController directly.

const AFFINITY_MATCH_BONUS: float = 1.25

## Returns false if the dish could not be served: nothing on the plate, no
## valid recipient, or it uses ingredients the lighthouse has not unlocked.
func serve(dish: Dish, target_spirit: SpiritController) -> bool:
	if dish == null or dish.is_empty() or not is_instance_valid(target_spirit):
		return false
	if not is_dish_unlocked(dish):
		return false

	var result: FeedingResult = DishNourishment.feeding_result_of(dish)
	var dominant: ElementalAffinity.Type = dish.dominant_affinity()
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

static func is_dish_unlocked(dish: Dish) -> bool:
	for piece in dish.pieces:
		if not LighthouseProgression.is_ingredient_unlocked(piece.ingredient):
			return false
	for portion in dish.liquids:
		if not LighthouseProgression.is_ingredient_unlocked(portion.ingredient):
			return false
	return true
