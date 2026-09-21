class_name StateArriving
extends SpiritState

## Drifts toward the sanctuary's arrival anchor. Transitions once close
## enough to settle.

const ARRIVAL_THRESHOLD: float = 0.15

func physics_update(ctx: SpiritController, delta: float) -> int:
	if not ctx.arrival_anchor:
		return State.SEEKING
	var to_target: Vector3 = ctx.arrival_anchor.global_position - ctx.global_position
	if to_target.length() <= ARRIVAL_THRESHOLD:
		return State.SEEKING
	ctx.global_position += to_target.normalized() * ctx.move_speed * delta
	return NO_TRANSITION
