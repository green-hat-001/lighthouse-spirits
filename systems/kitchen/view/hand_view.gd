class_name HandView
extends Node3D

## The cook's right hand at the counter: where the pointer is, it is. A
## flat state machine over what the hand is doing:
##
##   AWAY (walking, gliding, looking out to sea) --at the counter--> REACHING
##   REACHING: open, fingertip just above what the mouse is over
##   REACHING --press on something--> HOLDING: closed the way that thing is
##            held (Interactable.hand_pose), on its handle if it has one
##            (Interactable.hand_anchor), else where it was taken
##   HOLDING --release or cancel--> REACHING
##
## The hand follows on a slightly springy damper, so it lags and settles
## like a hand rather than a cursor, leans into its motion, and dips to
## touch whatever it presses. It is only ever drawn: it never takes input
## and nothing collides with it. The cursor hides while it is shown.

enum State { AWAY, REACHING, HOLDING }

## The spring the hand follows on: how quick (Hz) and how damped (1 is no
## overshoot).
const FOLLOW_HZ: float = 7.5
const FOLLOW_DAMPING: float = 0.78
## How high the open hand's fingertip hovers over what it is over.
const HOVER_M: float = 0.018
## How far it dips to touch something it presses, and how fast it recovers.
const TOUCH_DIP_M: float = 0.012
const TOUCH_RECOVER: float = 9.0
## How far it leans into its motion, per metre per second, at most.
const LEAN_PER_MPS: float = 0.5
const MAX_LEAN_RAD: float = 0.3
## Where the right shoulder is, in the eye's space: the arm runs back to it.
const SHOULDER: Vector3 = Vector3(0.2, -0.32, 0.12)
## How steeply the sleeve already rises back toward the elbow in the model.
const ARM_RISE_RAD: float = 0.36
const SPRING_STEP_S: float = 1.0 / 240.0
const HOLDING_STIFFNESS: float = 2.2

@export var kitchen: Kitchen
@export var pointer: KitchenPointer

var state: State = State.AWAY
var _velocity: Vector3 = Vector3.ZERO
var _dip_m: float = 0.0
var _was_holding: bool = false
## Set once the hand has been put where the cook's attention is; after
## that it only ever follows.
var _placed: bool = false

@onready var hand: HandModel = $Hand

func _ready() -> void:
	visible = false

func _process(delta: float) -> void:
	state = _state_now()
	visible = state != State.AWAY
	if not visible:
		_velocity = Vector3.ZERO
		_placed = false
		return
	var holding := state == State.HOLDING
	if holding and not _was_holding:
		_dip_m = TOUCH_DIP_M
	_was_holding = holding
	_dip_m = lerpf(_dip_m, 0.0, 1.0 - exp(-TOUCH_RECOVER * delta))

	var held := pointer.held()
	var target: Vector3 = pointer.hand_point
	if held and held.hand_anchor and is_instance_valid(held.hand_anchor):
		target = held.hand_anchor.global_position
	elif not holding:
		target += Vector3.UP * HOVER_M
	target += Vector3.DOWN * _dip_m
	hand.set_pose(held.hand_pose if held else HandModel.Pose.OPEN)

	# A spring just short of critical damping: quick, with the faintest
	# overshoot. Stepped finely enough to stay stable at any frame rate.
	if not _placed:
		global_position = target
		_placed = true
	# Holding something, the hand keeps hold of it: a stiffer spring.
	var omega: float = TAU * FOLLOW_HZ * (HOLDING_STIFFNESS if holding else 1.0)
	var steps: int = clampi(ceili(delta / SPRING_STEP_S), 1, 16)
	var step: float = minf(delta, SPRING_STEP_S * 16.0) / steps
	for _index in steps:
		_velocity += ((target - global_position) * omega * omega - _velocity * 2.0 * FOLLOW_DAMPING * omega) * step
		global_position += _velocity * step

	# The arm runs back to the shoulder, below and to the right of the eye,
	# so however far the hand reaches the sleeve recedes toward the corner of
	# the view; the hand leans into the way it moves.
	var eye := kitchen.camera.global_transform
	var shoulder: Vector3 = eye * SHOULDER
	var back := shoulder - global_position
	back.y = 0.0
	if back.length() < 0.01:
		back = eye.basis.z
	var yaw: float = atan2(back.x, back.z)
	var facing := Basis(Vector3.UP, yaw)
	var local_velocity := facing.inverse() * _velocity
	var roll: float = clampf(-local_velocity.x * LEAN_PER_MPS, -MAX_LEAN_RAD, MAX_LEAN_RAD)
	var pitch: float = clampf(local_velocity.z * LEAN_PER_MPS, -MAX_LEAN_RAD, MAX_LEAN_RAD)
	# Reaching up and away, the forearm tips down from the shoulder.
	var rise: float = shoulder.y - global_position.y
	var tilt: float = clampf(atan2(rise, maxf(back.length(), 0.05)) - ARM_RISE_RAD, -0.6, 0.6)
	basis = facing * Basis(Vector3.RIGHT, -tilt) * Basis(Vector3.FORWARD, roll) * Basis(Vector3.RIGHT, pitch)

func _state_now() -> State:
	if kitchen.view_mode.mode != KitchenViewMode.Mode.AT_COUNTER or not pointer.enabled \
			or kitchen.counter_views.looking_out:
		return State.AWAY
	return State.HOLDING if pointer.is_holding() else State.REACHING
