class_name Kitchen
extends Node3D

## Root of the outdoor kitchen. Owns the one camera and the KitchenViewMode
## that decides where it looks:
##
##   WALKING       the camera is the caretaker's eyes; WASD walks, the
##                 mouse looks (captured). E at the counter steps in.
##   STEPPING_IN   the camera glides from the eyes to the nearest station.
##   AT_COUNTER    the caretaker stands still; the mouse is the hand, the
##                 counter keys move between stations, and pushing the mouse
##                 to a screen edge peeks sideways. Esc steps back out.
##   STEPPING_OUT  the camera glides back to the eyes.
##
## Esc while walking frees the mouse (so the window and the editor stay
## reachable); a click captures it again. Also wires the pantry baskets to
## the board and sets the kitchen's ambient temperature.

const GLIDE_SPEED: float = 5.0
const PEEK_EASE: float = 6.0
## Horizontal field of view: wider while walking, narrower at the counter
## so small food is legible.
const WALK_FOV_DEG: float = 80.0
const COUNTER_FOV_DEG: float = 62.0
## A glide has arrived once the camera is this close to its target.
const ARRIVED_M: float = 0.005
const ARRIVED_DEG: float = 0.8

@export var ambient_temp_c: float = 15.0
## The counter's footprint on the ground, relative to the Counter prop.
@export var counter_footprint: Rect2 = Rect2(-0.8, -0.3, 1.6, 0.6)

var view_mode := KitchenViewMode.new()

var _peek_deg: float = 0.0

@onready var board: CuttingBoard = $CuttingBoard
@onready var camera: Camera3D = $Camera3D
@onready var caretaker: Caretaker = $Caretaker
@onready var counter_views: CounterViews = $CounterViews
@onready var pointer: KitchenPointer = $Pointer
@onready var _counter: Node3D = $Props/Counter
@onready var _prompt: Label = $Hud/Prompt
@onready var _hint: Label = $Hud/CounterHint
@onready var _crosshair: Control = $Hud/Crosshair

func _ready() -> void:
	board.ambient_temp_c = ambient_temp_c
	for source in find_children("*", "IngredientSource", true, false):
		(source as IngredientSource).taken.connect(func(ingredient: Ingredient) -> void: board.add_whole(ingredient))
	pointer.enabled = false
	counter_views.active = false
	camera.fov = WALK_FOV_DEG
	camera.global_transform = caretaker.eye_transform()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## True when the caretaker is standing at the counter, facing it.
func counter_in_reach() -> bool:
	var origin := _counter.global_position
	var footprint := Rect2(counter_footprint.position + Vector2(origin.x, origin.z), counter_footprint.size)
	var feet := Vector2(caretaker.global_position.x, caretaker.global_position.z)
	return KitchenViewMode.within_reach(feet, caretaker.facing(), footprint)

func step_in() -> bool:
	if not view_mode.step_in(counter_in_reach()):
		return false
	counter_views.station_index = counter_views.nearest_station(caretaker.global_position.x)
	counter_views.looking_out = false
	caretaker.control_enabled = false
	_peek_deg = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true

func step_out() -> bool:
	if not view_mode.step_out():
		return false
	pointer.enabled = false
	counter_views.active = false
	return true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and view_mode.mode == KitchenViewMode.Mode.WALKING:
		step_in()
	elif event.is_action_pressed("leave_view"):
		if not step_out() and view_mode.mode == KitchenViewMode.Mode.WALKING:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and view_mode.mode == KitchenViewMode.Mode.WALKING and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	var walking := view_mode.mode == KitchenViewMode.Mode.WALKING
	_prompt.visible = walking and counter_in_reach()
	_crosshair.visible = walking
	_hint.visible = view_mode.mode == KitchenViewMode.Mode.AT_COUNTER
	match view_mode.mode:
		KitchenViewMode.Mode.WALKING:
			camera.global_transform = caretaker.eye_transform()
			camera.fov = WALK_FOV_DEG
		KitchenViewMode.Mode.STEPPING_IN:
			if _glide(counter_views.pose(0.0), COUNTER_FOV_DEG, delta):
				view_mode.arrived()
				pointer.enabled = true
				counter_views.active = true
		KitchenViewMode.Mode.AT_COUNTER:
			if not pointer.is_holding():
				var peek_target := CounterViews.peek_degrees(_mouse_x_norm())
				_peek_deg = lerpf(_peek_deg, peek_target, 1.0 - exp(-PEEK_EASE * delta))
			_glide(counter_views.pose(_peek_deg), COUNTER_FOV_DEG, delta)
		KitchenViewMode.Mode.STEPPING_OUT:
			if _glide(caretaker.eye_transform(), WALK_FOV_DEG, delta):
				view_mode.arrived()
				caretaker.control_enabled = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Eases the camera towards a pose and field of view. Returns true once it
## has arrived.
func _glide(target: Transform3D, target_fov: float, delta: float) -> bool:
	var weight: float = 1.0 - exp(-GLIDE_SPEED * delta)
	var from := camera.global_transform
	var rotation_now := from.basis.get_rotation_quaternion()
	var rotation_target := target.basis.get_rotation_quaternion()
	camera.global_transform = Transform3D(Basis(rotation_now.slerp(rotation_target, weight)), from.origin.lerp(target.origin, weight))
	camera.fov = lerpf(camera.fov, target_fov, weight)
	var close := camera.global_position.distance_to(target.origin) < ARRIVED_M \
		and rad_to_deg(camera.global_transform.basis.get_rotation_quaternion().angle_to(rotation_target)) < ARRIVED_DEG
	if close:
		camera.global_transform = target
		camera.fov = target_fov
	return close

## The mouse's horizontal position across the visible screen, -1 to 1.
func _mouse_x_norm() -> float:
	var rect := get_viewport().get_visible_rect()
	if rect.size.x <= 0.0:
		return 0.0
	return clampf((get_viewport().get_mouse_position().x - rect.position.x) / rect.size.x * 2.0 - 1.0, -1.0, 1.0)
