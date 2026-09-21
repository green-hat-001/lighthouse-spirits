class_name StateAscending
extends SpiritState

## Rises toward the upper atmosphere for a fixed duration, then departs
## with a successful outcome.

var _timer: float = 0.0

func enter(ctx: SpiritController) -> void:
	_timer = ctx.archetype.ascension_seconds
	SpiritEventBus.spirit_ascended.emit(ctx.spirit_id)

func physics_update(ctx: SpiritController, delta: float) -> int:
	_timer -= delta
	ctx.global_position.y += ctx.rise_speed * delta
	if _timer <= 0.0:
		ctx.outcome = &"ASCENDED"
		return State.DEPARTED
	return NO_TRANSITION
