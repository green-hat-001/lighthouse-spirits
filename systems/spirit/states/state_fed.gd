class_name StateFed
extends SpiritState

## Short satisfied beat (feedback hook for audio/VFX) before ascension.

var _timer: float = 0.0

func enter(ctx: SpiritController) -> void:
	_timer = ctx.archetype.fed_feedback_seconds
	SpiritEventBus.spirit_fed_fully.emit(ctx.spirit_id)

func physics_update(_ctx: SpiritController, delta: float) -> int:
	_timer -= delta
	if _timer <= 0.0:
		return State.ASCENDING
	return NO_TRANSITION
