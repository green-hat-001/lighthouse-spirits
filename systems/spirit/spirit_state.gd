class_name SpiritState
extends RefCounted

## Abstract base for one FSM state (strategy pattern). Concrete states
## override only the hooks they need; the no-op defaults below are the
## correct behavior for a state that doesn't react to that hook.

enum State { ARRIVING, SEEKING, WAITING, FED, ASCENDING, DISTRESSED, DEPARTED }

const NO_TRANSITION: int = -1

func enter(_ctx: SpiritController) -> void:
	pass

func exit(_ctx: SpiritController) -> void:
	pass

## Called every physics frame. Return the next state to transition into,
## or NO_TRANSITION to remain in this state.
func physics_update(_ctx: SpiritController, _delta: float) -> int:
	return NO_TRANSITION

## Called when an external signal (e.g. "feed") is routed to this spirit.
## Return the next state, or NO_TRANSITION if this state ignores the signal.
func handle_signal(_ctx: SpiritController, _signal_name: StringName, _payload: Variant) -> int:
	return NO_TRANSITION
