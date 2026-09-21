class_name StateDistressed
extends SpiritState

## Grace window after neglect. Any feeding attempt rescues the spirit back
## to WAITING; if the recovery window elapses unfed, the spirit departs.

func enter(ctx: SpiritController) -> void:
	ctx.runtime.recovery_timer = ctx.archetype.recovery_window_seconds

func physics_update(ctx: SpiritController, delta: float) -> int:
	ctx.runtime.recovery_timer -= delta
	if ctx.runtime.recovery_timer <= 0.0:
		ctx.outcome = &"UNFED"
		return State.DEPARTED
	return NO_TRANSITION

func handle_signal(ctx: SpiritController, signal_name: StringName, payload: Variant) -> int:
	if signal_name != &"feed":
		return NO_TRANSITION
	var result: FeedingResult = payload
	ctx.runtime.apply_feeding(result)
	return State.WAITING
