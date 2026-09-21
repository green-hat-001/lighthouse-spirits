class_name StateWaiting
extends SpiritState

## Spirit is present and needy. Each feeding attempt applies the result
## and refreshes patience; if deficits fall below the archetype's
## ascension thresholds the spirit is fully fed. Left unattended for too
## long, patience runs out and the spirit becomes distressed.

func enter(ctx: SpiritController) -> void:
	ctx.runtime.patience_timer = ctx.archetype.patience_seconds

func physics_update(ctx: SpiritController, delta: float) -> int:
	ctx.runtime.patience_timer -= delta
	if ctx.runtime.patience_timer <= 0.0:
		return State.DISTRESSED
	return NO_TRANSITION

func handle_signal(ctx: SpiritController, signal_name: StringName, payload: Variant) -> int:
	if signal_name != &"feed":
		return NO_TRANSITION
	var result: FeedingResult = payload
	ctx.runtime.apply_feeding(result)
	ctx.runtime.patience_timer = ctx.archetype.patience_seconds
	if ctx.runtime.meets_ascension(ctx.archetype):
		return State.FED
	return NO_TRANSITION
