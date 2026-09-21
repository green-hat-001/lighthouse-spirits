class_name StateSeeking
extends SpiritState

## Brief settle beat before the spirit is ready to be attended to.

var _timer: float = 0.0

func enter(ctx: SpiritController) -> void:
	_timer = ctx.archetype.settle_seconds

func physics_update(_ctx: SpiritController, delta: float) -> int:
	_timer -= delta
	if _timer <= 0.0:
		return State.WAITING
	return NO_TRANSITION
