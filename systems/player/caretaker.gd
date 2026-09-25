class_name Caretaker
extends CharacterBody3D

## The lighthouse caretaker, seen through their own eyes. They walk at an
## unhurried pace and look around with the mouse; there is no running and
## no jumping. They will not step off an edge - the cliff, or the end of the
## land - so the player can stand right at the lip and look down at the sea.
##
## Movement is read only while `control_enabled`; the kitchen turns it off
## while the caretaker works at the counter, where they stand still.

const EYE_HEIGHT_M: float = 1.62
const MAX_PITCH_DEG: float = 80.0
## How far ahead the ledge guard looks for ground, and how far below the
## feet ground may be before the step counts as a drop.
const LEDGE_PROBE_AHEAD_M: float = 0.45
const LEDGE_MAX_DROP_M: float = 0.9

@export var walk_speed_mps: float = 1.6
@export var acceleration: float = 8.0
@export var mouse_sensitivity: float = 0.0025

var control_enabled: bool = true

@onready var head: Node3D = $Head

func _unhandled_input(event: InputEvent) -> void:
	if not control_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x - motion.relative.y * mouse_sensitivity,
			deg_to_rad(-MAX_PITCH_DEG), deg_to_rad(MAX_PITCH_DEG))

## Where the eyes are and where they look.
func eye_transform() -> Transform3D:
	return head.global_transform

## Horizontal facing, as a unit Vector2(x, z).
func facing() -> Vector2:
	var forward := -global_transform.basis.z
	return Vector2(forward.x, forward.z).normalized()

func _physics_process(delta: float) -> void:
	var wish := Vector3.ZERO
	if control_enabled:
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		wish = (global_transform.basis * Vector3(input.x, 0.0, input.y))
		wish.y = 0.0
		if wish.length() > 1.0:
			wish = wish.normalized()
	var target := wish * walk_speed_mps
	if target.length() > 0.0 and not _ground_ahead(target.normalized()):
		target = Vector3.ZERO
	var weight: float = clampf(acceleration * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, target.x, weight)
	velocity.z = lerpf(velocity.z, target.z, weight)
	if not is_on_floor():
		velocity += get_gravity() * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	# Never carry momentum over an edge the guard has already refused.
	var drift := Vector3(velocity.x, 0.0, velocity.z)
	if drift.length() > 0.01 and not _ground_ahead(drift.normalized()):
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()

## True if there is ground within a safe step below the spot just ahead.
func _ground_ahead(direction: Vector3) -> bool:
	var probe := global_position + direction * LEDGE_PROBE_AHEAD_M + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(probe, probe + Vector3.DOWN * (0.5 + LEDGE_MAX_DROP_M))
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
