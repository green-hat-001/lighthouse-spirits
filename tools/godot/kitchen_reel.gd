extends Node

## A scripted turn at the counter, played through the kitchen's real input
## (mouse motion, clicks, Space, the station keys) so every system answers
## exactly as it would to a player. Record it with Godot's movie writer:
##
##   godot --path . --write-movie reel.avi --fixed-fps 30 res://tools/godot/kitchen_reel.tscn
##
## It glances up at the pantry, takes a potato, halves it with the food
## steadied, carries a half about, lifts both halves together, carries them
## along to the stove and drops them into hot oil, fetches a pinch of salt
## from the shelf and sprinkles it in, stirs, and looks out to sea. Then it
## quits.

var kitchen: Kitchen
var _mouse := Vector2(640, 360)

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	kitchen = (load("res://scenes/kitchen/kitchen.tscn") as PackedScene).instantiate()
	add_child(kitchen)
	await _frames(2)
	_play.call_deferred()

func _play() -> void:
	# Arrive at the board, straight from the start of the scene.
	kitchen.caretaker.global_position = Vector3(-0.22, kitchen.caretaker.global_position.y, 0.75)
	kitchen.caretaker.rotation.y = 0.0
	kitchen.step_in()
	var oil := kitchen.simulation.oil
	kitchen.simulation.pot.add_medium(oil, 500.0, 175.0)
	kitchen.stove.set_knob(210.0)
	await _seconds(1.6)

	# Look up at the shelves and take a potato.
	var potato_spot := kitchen.pantry.source_of(IngredientCatalog.by_id(&"potato"))
	await _move_to(Vector2(640, 6), 0.8)
	await _seconds(0.9)
	await _move_to(_screen(potato_spot.global_position + Vector3(0.0, 0.03, 0.0)), 0.8)
	await _seconds(0.7)
	await _click()
	await _move_to(Vector2(640, 600), 0.9)
	await _seconds(0.9)
	if kitchen.board.views().is_empty():
		_fail("the potato never reached the board")
		return

	# Halve it, holding it steady.
	var potato: FoodPieceView = kitchen.board.views()[kitchen.board.views().size() - 1]
	var middle := potato.global_position + Vector3(potato.footprint_m().x * 0.5, 0.0, 0.0)
	var from := middle + Vector3(0.0, 0.0, -0.03)
	var to := middle + Vector3(0.0, 0.0, potato.footprint_m().y + 0.03)
	await _move_to(_screen(from), 0.6)
	Input.action_press(&"kitchen_steady")
	await _press()
	await _move_to(_screen(to), 0.9)
	await _release()
	Input.action_release(&"kitchen_steady")
	await _seconds(0.9)

	# Carry one half about, and set it back down.
	var half: FoodPieceView = kitchen.board.views()[kitchen.board.views().size() - 1]
	var grab := half.global_position + Vector3(half.footprint_m().x * 0.5, 0.02, half.footprint_m().y * 0.5)
	await _move_to(_screen(grab), 0.5)
	await _press()
	await _move_to(_screen(grab + Vector3(0.08, 0.0, 0.05)), 0.5)
	await _move_to(_screen(grab + Vector3(-0.02, 0.0, 0.07)), 0.45)
	await _move_to(_screen(grab + Vector3(0.0, 0.0, 0.0)), 0.4)
	await _release()
	await _seconds(0.7)

	# Lift both halves together, carry them along to the stove, and let
	# them go into the oil.
	grab = half.global_position + Vector3(half.footprint_m().x * 0.5, 0.02, half.footprint_m().y * 0.5)
	await _move_to(_screen(grab), 0.4)
	Input.action_press(&"kitchen_steady")
	await _press()
	Input.action_release(&"kitchen_steady")
	await _move_to(_screen(grab + Vector3(0.12, 0.2, -0.02)), 0.6)
	await _key(KEY_D)
	await _seconds(1.0)
	await _move_to(_screen(kitchen.pot_view.global_position + Vector3(0.0, 0.22, 0.0)), 0.8)
	await _seconds(0.3)
	await _release()
	await _seconds(2.0)

	# Back along for a pinch of salt, and over to the pot with it.
	await _key(KEY_A)
	await _seconds(0.9)
	var salt_spot := kitchen.pantry.source_of(IngredientCatalog.by_id(&"tidewater_salt"))
	await _move_to(Vector2(640, 6), 0.7)
	await _seconds(0.9)
	await _move_to(_screen(salt_spot.global_position + Vector3(0.0, 0.08, 0.0)), 0.7)
	await _seconds(0.5)
	await _press()
	await _move_to(Vector2(760, 620), 0.8)
	await _seconds(0.5)
	await _key(KEY_D)
	await _seconds(1.0)
	await _move_to(_screen(kitchen.pot_view.global_position + Vector3(0.0, IngredientSource.CARRY_HEIGHT_M, 0.0)), 0.7)
	await _seconds(0.3)
	await _release()
	await _seconds(1.0)

	# A stir, round the pot.
	var centre := kitchen.pot_view.global_position + Vector3(0.0, PotView.RIM_Y_M, 0.0)
	await _move_to(_screen(centre + Vector3(0.05, 0.0, 0.0)), 0.4)
	await _press()
	for step in 24:
		var angle: float = TAU * step / 24.0
		await _move_to(_screen(centre + Vector3(cos(angle), 0.0, sin(angle)) * 0.05), 0.06)
	await _release()
	await _move_to(Vector2(640, 600), 0.5)
	await _seconds(2.5)

	# And look out to sea.
	await _key(KEY_W)
	await _seconds(3.0)
	get_tree().quit()

## Stops the reel rather than letting it run on with nothing happening.
func _fail(why: String) -> void:
	push_error("kitchen reel: %s" % why)
	get_tree().quit(1)

func _screen(world: Vector3) -> Vector2:
	return kitchen.camera.unproject_position(world)

func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame

func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

## Moves the mouse there over `seconds`, easing in and out like a hand.
func _move_to(target: Vector2, seconds: float) -> void:
	var start := _mouse
	var elapsed: float = 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		var t: float = smoothstep(0.0, 1.0, clampf(elapsed / seconds, 0.0, 1.0))
		_motion(start.lerp(target, t))

func _motion(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = at - _mouse
	_mouse = at
	Input.warp_mouse(at)
	Input.parse_input_event(event)

func _button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = _mouse
	event.global_position = _mouse
	Input.parse_input_event(event)

func _press() -> void:
	_button(true)
	await _frames(2)

func _release() -> void:
	_button(false)
	await _frames(2)

func _click() -> void:
	await _press()
	await _release()

func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)
