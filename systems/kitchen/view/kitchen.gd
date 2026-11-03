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
## The mouse is always locked: captured while walking and gliding back to
## the eyes, confined to the window at the counter (where the cursor is the
## hand and must not slip off-screen while peeking). The mode is re-asserted
## every frame while the window has focus, because a capture requested
## before the window is focused can be dropped. Esc while walking is the one
## deliberate way to free it, so the window and editor stay reachable; a
## click locks it again.
##
## It also wires the stations together, routing food between them without
## knowing anything about cooking: baskets put whole items on the board,
## food lifted off the board can be let go into the pot, the spoon's catch
## is set down on the board, the sunflower head fills the press's hopper,
## and "kitchen_taste" bites whatever piece on the board is under the hand.
## Food plated on the serving board is the dish: "kitchen_name_dish" names
## it (DishBook) and "kitchen_menu" puts it up for service.

const GLIDE_SPEED: float = 5.0
const PEEK_EASE: float = 6.0
## Horizontal field of view: wider while walking, narrower at the counter
## so small food is legible.
const WALK_FOV_DEG: float = 80.0
const COUNTER_FOV_DEG: float = 62.0
## A glide has arrived once the camera is this close to its target.
const ARRIVED_M: float = 0.005
const ARRIVED_DEG: float = 0.8

## How long a taste caption stays up, in seconds.
const CAPTION_SECONDS: float = 6.0
const CAPTION_FADE_SECONDS: float = 1.2

## The counter's footprint on the ground, relative to the Counter prop.
@export var counter_footprint: Rect2 = Rect2(-0.8, -0.3, 1.6, 0.6)

var view_mode := KitchenViewMode.new()

var _peek_deg: float = 0.0
## Set when the player frees the mouse with Esc while walking.
var _mouse_freed: bool = false

var _caption_left_s: float = 0.0
var _label_timer_s: float = 0.0
## How often the plate's label re-reads the dish, in seconds.
const PLATE_LABEL_EVERY_S: float = 0.5

@onready var simulation: KitchenSimulation = $Simulation
@onready var board: CuttingBoard = $CuttingBoard
@onready var plate: CuttingBoard = $ServingBoard
@onready var _plate_label: Label3D = $ServingBoard/DishLabel
@onready var _name_field: LineEdit = $Hud/DishName
@onready var stove: StoveView = $Stove
@onready var pot_view: PotView = $Pot
@onready var press_view: PressView = $OilPress
@onready var seed_source: SeedSource = $SunflowerHead
@onready var audio: KitchenAudio = $Audio
@onready var _caption: Label = $Hud/Caption
@onready var camera: Camera3D = $Camera3D
@onready var caretaker: Caretaker = $Caretaker
@onready var counter_views: CounterViews = $CounterViews
@onready var pointer: KitchenPointer = $Pointer
@onready var _counter: Node3D = $Props/Counter
@onready var _prompt: Label = $Hud/Prompt
@onready var _hint: Label = $Hud/CounterHint
@onready var _crosshair: Control = $Hud/Crosshair

func _ready() -> void:
	board.ambient_temp_c = simulation.air.temp_c
	board.rest = simulation.board
	plate.ambient_temp_c = simulation.air.temp_c
	plate.rest = simulation.plate
	for surface in surfaces():
		surface.drop_target = release_lifted.bind(surface)
		surface.piece_tasted.connect(show_caption)
	_name_field.visible = false
	_name_field.text_submitted.connect(_on_dish_named)
	board.dressed.connect(func(creature: Creature) -> void: show_caption(_dressing_note(creature)))
	board.board_crowded.connect(func() -> void: show_caption("There's no room on the board for that. Clear some space first."))
	pot_view.lifted_out.connect(_on_lifted_out)
	pot_view.covering_lifted.connect(func(piece: FoodPiece) -> void:
		if not board.receive([piece], board.global_position).is_empty():
			simulation.pot.cover_with(piece, true)
			show_caption("There's no room on the board to set the covering down."))
	seed_source.taken.connect(func(_ingredient: Ingredient, grams: float) -> void: simulation.load_seeds(grams))
	for source in find_children("*", "IngredientSource", true, false):
		(source as IngredientSource).taken.connect(func(ingredient: Ingredient) -> void: board.add_whole(ingredient))
		(source as IngredientSource).scooped.connect(let_go_of_scoop)
	_caption.modulate.a = 0.0
	pointer.enabled = false
	counter_views.active = false
	camera.fov = WALK_FOV_DEG
	camera.global_transform = caretaker.eye_transform()
	_lock_mouse()

## The mouse mode each view mode wants.
static func mouse_mode_for(mode: KitchenViewMode.Mode, freed_by_player: bool) -> Input.MouseMode:
	match mode:
		KitchenViewMode.Mode.WALKING:
			return Input.MOUSE_MODE_VISIBLE if freed_by_player else Input.MOUSE_MODE_CAPTURED
		KitchenViewMode.Mode.STEPPING_OUT:
			return Input.MOUSE_MODE_CAPTURED
		_:
			return Input.MOUSE_MODE_CONFINED

## True when the caretaker is standing at the counter, facing it.
func counter_in_reach() -> bool:
	var origin := _counter.global_position
	var footprint := Rect2(counter_footprint.position + Vector2(origin.x, origin.z), counter_footprint.size)
	var feet := Vector2(caretaker.global_position.x, caretaker.global_position.z)
	return KitchenViewMode.within_reach(feet, caretaker.facing(), footprint)

## The surfaces food rests on at the counter: the cutting board and the
## serving board.
func surfaces() -> Array[CuttingBoard]:
	return [board, plate]

## Where food lifted off a surface lands when let go: into the pot (or
## across it, as a covering), or onto another surface. Returns true if it
## was taken; otherwise it is set straight back down where it was lifted.
func release_lifted(pieces: Array[FoodPiece], world_point: Vector3, held_at: Array[Vector3], from: CuttingBoard) -> bool:
	if drop_into_pot(pieces, world_point, held_at):
		return true
	for surface in surfaces():
		if surface != from and surface.is_over(world_point):
			var refused := surface.receive(pieces, world_point)
			if not refused.is_empty():
				from.receive.call_deferred(refused, from.global_position)
			return true
	return false

## Lets food go into the pot if it was let go over it. Returns true when
## the pot took it; anything that would overflow the pot goes back on the
## board.
func drop_into_pot(pieces: Array[FoodPiece], world_point: Vector3, held_at: Array[Vector3] = []) -> bool:
	if not pot_view.is_over(world_point):
		return false
	# A single sheet wide enough to span the rim is laid across it, not
	# dropped in. Steadying while letting go stretches it taut.
	if pieces.size() == 1 and simulation.pot.covering == null and simulation.pot.can_cover(pieces[0]):
		simulation.pot.cover_with(pieces[0], Input.is_action_pressed("kitchen_steady"))
		show_caption(_seal_note(simulation.pot.seal))
		return true
	pot_view.drop_in(pieces, world_point, held_at)
	var spilled: Array[FoodPiece] = []
	for piece in pieces:
		if not simulation.pot.pieces.has(piece):
			spilled.append(piece)
	if not spilled.is_empty():
		board.receive.call_deferred(spilled, board.global_position)
	return true

## Where a pinch or handful from the pantry lands. A spice seasons
## whatever it is scattered over - the pot's liquid, or the food it falls
## on - and a handful of grain goes into the pot or sits as a heap on the
## board. Let go anywhere else, it is put back. Returns true if it landed.
const PINCH_REACH_M: float = 0.03

func let_go_of_scoop(ingredient: Ingredient, grams: float, world_point: Vector3) -> bool:
	var spice: bool = ingredient.pantry_shelf == Ingredient.Shelf.SPICE
	if pot_view.is_over(world_point):
		if spice:
			return Seasoning.season_pot(simulation.pot, ingredient, grams) > 0.0
		return simulation.pot.add_piece(FoodPiece.handful(ingredient, grams, simulation.air.temp_c), pot_view.to_pot_mm(world_point))
	for surface in surfaces():
		if not surface.is_over(world_point):
			continue
		if spice:
			var under: Array[FoodPiece] = surface.pieces_near(world_point, PINCH_REACH_M)
			return not under.is_empty() and Seasoning.season_pieces(under, ingredient, grams) > 0.0
		return surface.receive([FoodPiece.handful(ingredient, grams, simulation.air.temp_c)], world_point).is_empty()
	return false

## Bites whatever piece on the board is under the hand.
func taste_under_hand() -> String:
	var hit := pointer.pick_under_mouse()
	if hit.interactable == null or not (hit.interactable.get_parent() is FoodPieceView):
		return ""
	var view := hit.interactable.get_parent() as FoodPieceView
	for surface in surfaces():
		if surface.views().has(view):
			return surface.taste(view)
	if pot_view.view_of(view.piece) == view:
		show_caption("Too hot to reach into the pot. Lift it out with the spoon first.")
	return ""

## How well a covering sits, in words.
static func _seal_note(seal: float) -> String:
	if seal >= 0.85:
		return "Stretched taut over the rim and sealed tight: the steam stays in."
	if seal >= 0.5:
		return "It covers the pot, but the edges lift; steam will find its way out."
	return "It barely covers the pot. Most of the steam will escape."

## What dressing a creature lays out, in words.
static func _dressing_note(creature: Creature) -> String:
	var names: PackedStringArray = []
	for part in creature.parts:
		names.append(part.part_name.to_lower() if part.count == 1 else "%d %s" % [part.count, part.part_name.to_lower()])
	return "%s, opened: %s." % [creature.display_name, ", ".join(names)]

## Opens the name field for what is plated on the serving board.
func begin_naming() -> bool:
	if plate.dish().is_empty():
		show_caption("Plate something on the serving board first, then name it.")
		return false
	_name_field.text = DishBook.name_of(plate.dish().fingerprint())
	_name_field.visible = true
	_name_field.grab_focus()
	pointer.enabled = false
	return true

## Puts the plated dish up for service, or takes it off the menu.
func toggle_menu() -> bool:
	var fingerprint := plate.dish().fingerprint()
	if plate.dish().is_empty() or not DishBook.is_named(fingerprint):
		show_caption("Name the dish (N) before putting it on the menu.")
		return false
	var on: bool = not DishBook.is_on_menu(fingerprint)
	DishBook.set_on_menu(fingerprint, on)
	show_caption("%s is %s." % [DishBook.name_of(fingerprint), "on the menu" if on else "off the menu"])
	return true

func _on_dish_named(dish_name: String) -> void:
	var fingerprint := plate.dish().fingerprint()
	DishBook.name_dish(fingerprint, dish_name)
	_end_naming()
	if dish_name.strip_edges() != "":
		show_caption("You'll know it as %s whenever you make it this way again." % dish_name.strip_edges())

func _end_naming() -> void:
	_name_field.visible = false
	_name_field.release_focus()
	pointer.enabled = view_mode.mode == KitchenViewMode.Mode.AT_COUNTER

## The plate's label: the dish's name when the caretaker has named it,
## otherwise what is on it.
func _label_plate() -> void:
	var dish := plate.dish()
	if dish.is_empty():
		_plate_label.text = ""
		return
	var fingerprint := dish.fingerprint()
	var dish_name := DishBook.name_of(fingerprint)
	if dish_name == "":
		_plate_label.text = "an unnamed dish  (N to name it)"
	else:
		_plate_label.text = dish_name + ("  - on the menu" if DishBook.is_on_menu(fingerprint) else "")

func show_caption(text: String) -> void:
	_caption.text = text
	_caption_left_s = CAPTION_SECONDS

## The spoon let go of what it lifted: on the board if it was over the
## board, otherwise it slides back into the pot.
func _on_lifted_out(pieces: Array[FoodPiece], world_point: Vector3) -> void:
	for piece in pieces:
		simulation.held.remove_piece(piece)
	var leftover: Array[FoodPiece] = pieces
	for surface in surfaces():
		if surface.is_over(world_point):
			leftover = surface.receive(pieces, world_point)
			break
	pot_view.return_to_pot(leftover)

func step_in() -> bool:
	if not view_mode.step_in(counter_in_reach()):
		return false
	counter_views.station_index = counter_views.nearest_station(caretaker.global_position.x)
	counter_views.looking_out = false
	caretaker.control_enabled = false
	_peek_deg = 0.0
	# Start the hand in the middle of the screen, not wherever the captured
	# pointer was left.
	Input.warp_mouse(get_viewport().get_visible_rect().get_center())
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
			_mouse_freed = true
	elif _name_field.visible and event.is_action_pressed("leave_view"):
		_end_naming()
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed("kitchen_taste") and view_mode.mode == KitchenViewMode.Mode.AT_COUNTER:
		taste_under_hand()
	elif event.is_action_pressed("kitchen_name_dish") and view_mode.mode == KitchenViewMode.Mode.AT_COUNTER:
		begin_naming()
	elif event.is_action_pressed("kitchen_menu") and view_mode.mode == KitchenViewMode.Mode.AT_COUNTER:
		toggle_menu()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and view_mode.mode == KitchenViewMode.Mode.WALKING and _mouse_freed:
		_mouse_freed = false
		get_viewport().set_input_as_handled()
	_lock_mouse()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_lock_mouse()

func _lock_mouse() -> void:
	var wanted := mouse_mode_for(view_mode.mode, _mouse_freed)
	if Input.mouse_mode != wanted and DisplayServer.window_is_focused():
		Input.mouse_mode = wanted

func _process(delta: float) -> void:
	_lock_mouse()
	_caption_left_s = maxf(_caption_left_s - delta, 0.0)
	_label_timer_s -= delta
	if _label_timer_s <= 0.0:
		_label_timer_s = PLATE_LABEL_EVERY_S
		_label_plate()
	_caption.modulate.a = clampf(_caption_left_s / CAPTION_FADE_SECONDS, 0.0, 1.0)
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
