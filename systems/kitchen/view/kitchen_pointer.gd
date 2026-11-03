class_name KitchenPointer
extends Node

## The player's hand. A flat two-state machine:
##
##   IDLE --left press on an Interactable--> HOLDING
##   HOLDING --mouse motion--> HOLDING (reports a drag)
##   HOLDING --left release--> IDLE
##
## A right press on an Interactable is a one-shot action and never leaves
## IDLE. While IDLE the hand also says what it is over (hover_entered and
## hover_exited), so things can show they can be picked up. Only one Interactable is held at a time, so a drag can never be
## split between two owners. While disabled the hand ignores the mouse
## entirely; disabling it mid-drag cancels the hold.

enum State { IDLE, HOLDING }

const RAY_LENGTH_M: float = 5.0

@export var camera: Camera3D

var state: State = State.IDLE
var enabled: bool = true:
	set(value):
		enabled = value
		if not enabled:
			cancel()
			_hover(null)
var _held: Interactable
var _hovered: Interactable

## Where the hand is on the world: the last point it pressed or dragged
## to, or what it is over.
var hand_point: Vector3 = Vector3.ZERO
## Whether hand_point lies on something (false: on nothing, out in the air).
var on_something: bool = false

func is_holding() -> bool:
	return state == State.HOLDING

## What the hand holds, while holding.
func held() -> Interactable:
	return _held if state == State.HOLDING and is_instance_valid(_held) else null

## Lets go of whatever is held without releasing it onto anything.
func cancel() -> void:
	if state != State.HOLDING:
		return
	var held := _held
	state = State.IDLE
	_held = null
	if is_instance_valid(held):
		held.cancelled.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed and state == State.IDLE:
				_press(button.position)
			elif not button.pressed and state == State.HOLDING:
				_release(button.position)
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed and state == State.IDLE:
			var hit := pick(button.position)
			if hit.interactable:
				hit.interactable.secondary_pressed.emit(hit.point)
	elif event is InputEventMouseMotion and state == State.HOLDING:
		var point: Variant = _project(event.position, _held.drag_plane)
		if point != null:
			hand_point = point
			_held.dragged.emit(point)
	elif event is InputEventMouseMotion:
		var hit := pick(event.position)
		_hover(hit.interactable)
		_track(event.position, hit)

## Moves the hover from whatever it was over to `over`.
func _hover(over: Interactable) -> void:
	if over == _hovered:
		return
	if is_instance_valid(_hovered):
		_hovered.hover_exited.emit()
	_hovered = over
	if is_instance_valid(_hovered):
		_hovered.hover_entered.emit()

func _press(screen_position: Vector2) -> void:
	var hit := pick(screen_position)
	if hit.interactable == null:
		return
	hand_point = hit.point
	_hover(null)
	state = State.HOLDING
	_held = hit.interactable
	_held.pressed.emit(hit.point)

func _release(screen_position: Vector2) -> void:
	var held := _held
	state = State.IDLE
	_held = null
	if not is_instance_valid(held):
		return
	var point: Variant = _project(screen_position, held.drag_plane)
	held.released.emit(point if point != null else held.global_position)

## Keeps the hand over what the mouse is over, or over the counter when it
## is over nothing.
func _track(screen_position: Vector2, hit: PointerHit) -> void:
	on_something = hit.interactable != null
	if on_something:
		hand_point = hit.point
		return
	var counter: Variant = _project(screen_position, Plane(Vector3.UP, 0.0))
	if counter != null:
		hand_point = counter

## The Interactable under a point on the screen, and where the ray meets it.
func pick(screen_position: Vector2) -> PointerHit:
	var hit := PointerHit.new()
	var origin := camera.project_ray_origin(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen_position) * RAY_LENGTH_M)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return hit
	hit.interactable = result.collider as Interactable
	hit.point = result.position
	return hit

## What is under the mouse right now.
func pick_under_mouse() -> PointerHit:
	return pick(camera.get_viewport().get_mouse_position())

func _project(screen_position: Vector2, plane: Plane) -> Variant:
	return plane.intersects_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))

class PointerHit:
	var interactable: Interactable
	var point: Vector3
