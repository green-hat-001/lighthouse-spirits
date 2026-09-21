class_name DishServingStation
extends RefCounted

## The only point of contact between the Culinary module and the Spirit
## FSM. Reads the target spirit's archetype to resolve affinity matching,
## then submits the result exclusively through SpiritEventBus - it never
## calls into SpiritController directly, same as any other feeding source.

const AFFINITY_MATCH_BONUS: float = 1.25

func serve(dish: CraftedDish, target_spirit: SpiritController) -> void:
	if dish.is_empty() or not is_instance_valid(target_spirit):
		return

	var result: FeedingResult = CulinaryCraftingMatrix.compute_feeding_result(dish)
	var dominant: ElementalAffinity.Type = CulinaryCraftingMatrix.dominant_affinity(dish)

	result.matched_affinity = dominant != ElementalAffinity.Type.NONE \
		and target_spirit.archetype != null \
		and dominant == target_spirit.archetype.elemental_affinity
	if result.matched_affinity:
		result.nourishment *= AFFINITY_MATCH_BONUS
		result.calming *= AFFINITY_MATCH_BONUS

	SpiritEventBus.feed_spirit_requested.emit(target_spirit.spirit_id, result)
