class_name StateDeparted
extends SpiritState

## Terminal state. Broadcasts the final outcome (set by whichever path led
## here - ASCENDING or DISTRESSED) then despawns after a short beat.

var _timer: float = 0.0

func enter(ctx: SpiritController) -> void:
	_timer = ctx.archetype.despawn_seconds
	if ctx.outcome == &"UNFED":
		SpiritEventBus.spirit_departed_unfed.emit(ctx.spirit_id)
	SpiritEventBus.spirit_lifecycle_complete.emit(ctx.spirit_id, ctx.outcome)

func physics_update(ctx: SpiritController, delta: float) -> int:
	_timer -= delta
	if _timer <= 0.0:
		ctx.queue_free()
	return NO_TRANSITION
