class_name SpiritStateMachine
extends RefCounted

## Flat FSM (strategy pattern per state) driving one SpiritController.
## Validates every transition against an explicit legality table so an
## illegal transition fails loudly instead of silently corrupting state.

const LEGAL_TRANSITIONS: Dictionary = {
	SpiritState.State.ARRIVING: [SpiritState.State.SEEKING],
	SpiritState.State.SEEKING: [SpiritState.State.WAITING],
	SpiritState.State.WAITING: [SpiritState.State.FED, SpiritState.State.DISTRESSED],
	SpiritState.State.DISTRESSED: [SpiritState.State.WAITING, SpiritState.State.DEPARTED],
	SpiritState.State.FED: [SpiritState.State.ASCENDING],
	SpiritState.State.ASCENDING: [SpiritState.State.DEPARTED],
	SpiritState.State.DEPARTED: [],
}

var current_state: int = SpiritState.NO_TRANSITION

var _ctx: SpiritController
var _states: Dictionary

func _init(ctx: SpiritController) -> void:
	_ctx = ctx
	_states = {
		SpiritState.State.ARRIVING: StateArriving.new(),
		SpiritState.State.SEEKING: StateSeeking.new(),
		SpiritState.State.WAITING: StateWaiting.new(),
		SpiritState.State.FED: StateFed.new(),
		SpiritState.State.ASCENDING: StateAscending.new(),
		SpiritState.State.DISTRESSED: StateDistressed.new(),
		SpiritState.State.DEPARTED: StateDeparted.new(),
	}

func start(initial_state: int) -> void:
	current_state = initial_state
	_states[current_state].enter(_ctx)

func update(delta: float) -> void:
	if current_state == SpiritState.NO_TRANSITION:
		return
	var next_state: int = _states[current_state].physics_update(_ctx, delta)
	if next_state != SpiritState.NO_TRANSITION:
		transition_to(next_state)

func handle_signal(signal_name: StringName, payload: Variant) -> void:
	if current_state == SpiritState.NO_TRANSITION:
		return
	var next_state: int = _states[current_state].handle_signal(_ctx, signal_name, payload)
	if next_state != SpiritState.NO_TRANSITION:
		transition_to(next_state)

func transition_to(next_state: int) -> void:
	var legal: Array = LEGAL_TRANSITIONS.get(current_state, [])
	if not legal.has(next_state):
		push_error("SpiritStateMachine: illegal transition from %d to %d" % [current_state, next_state])
		return
	var old_state: int = current_state
	_states[old_state].exit(_ctx)
	current_state = next_state
	_states[current_state].enter(_ctx)
	SpiritEventBus.spirit_state_changed.emit(_ctx.spirit_id, old_state, current_state)
