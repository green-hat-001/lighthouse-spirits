class_name IngredientSource
extends Node3D

## One spot on a pantry shelf, offering one ingredient without end - the
## pantry is unlimited until foraging exists. What is shown is a sample of
## it, scaled to fit the spot and turned so its length runs back into the
## shelf; what is taken is the real, full-size thing.
##
##   IDLE --press, whole item--> IDLE (taken: one whole item to the board;
##                                     a fresh one settles into the spot)
##   IDLE --press, spice or grain--> SCOOPING (a pinch or a handful in the hand)
##   SCOOPING --drag--> SCOOPING --release--> IDLE (scooped: let go at a point)
##   SCOOPING --cancelled--> IDLE (put back)
##
## The empty hand over the spot lifts its item a touch and shows its name;
## a right-click reads its label (read). The ingredient, the spot's size
## and its container (a crock, a sack) are data, so a new spot is a new
## instance, never new code.

signal taken(ingredient: Ingredient)
## A pinch or handful let go at a world point.
signal scooped(ingredient: Ingredient, grams: float, world_point: Vector3)
## The player turned the label to read it.
signal read(ingredient: Ingredient)

enum State { IDLE, SCOOPING }

## World height the hand carries a scoop at: above the counter and clear of
## the pot, and below every station's eye, so it can be carried along the
## counter.
const CARRY_HEIGHT_M: float = 0.24
## Grams shown heaped in a container.
const DISPLAY_HEAP_G: float = 30.0
## Most of the spot the shown item fills.
const FILL: float = 0.88
## Small things (berries, a clam) are shown a few at a time, up to this
## many, when one would leave the spot looking empty.
const MAX_SHOWN: int = 5
## How far a hovered item lifts, and how fast it eases there.
const HOVER_LIFT_M: float = 0.008
const HOVER_EASE: float = 14.0
## How long a taken item takes to lift away, and its replacement to settle.
const TAKE_AWAY_S: float = 0.18
const RESTOCK_S: float = 0.32

@export var ingredient: Ingredient
## The spot on the shelf, in metres: width (X), clear height (Y), depth (Z),
## centred on this node with its floor at Y = 0.
@export var slot_size_m: Vector3 = Vector3(0.09, 0.12, 0.25)
## What the ingredient is kept in, if anything, and the height of its mouth,
## where its heap shows.
@export var container: PackedScene
@export var mouth_height_m: float = 0.0

var state: State = State.IDLE
var hovered: bool = false

var _scoop_view: FoodPieceView
var _shown: Node3D
var _lift_m: float = 0.0

@onready var _grip: Interactable = $Grip
@onready var _label: Label3D = $Label
@onready var _contents: Node3D = $Contents
@onready var _shape: CollisionShape3D = $Grip/Shape

func _ready() -> void:
	var box := BoxShape3D.new()
	box.size = slot_size_m
	_shape.shape = box
	_shape.position = Vector3(0.0, slot_size_m.y * 0.5, 0.0)
	_label.position = Vector3(0.0, slot_size_m.y * 0.9, -slot_size_m.z * 0.2)
	_label.visible = false
	if container:
		var holder: Node3D = container.instantiate()
		holder.name = "Container"
		add_child(holder)
	if ingredient and is_scooped(ingredient):
		_grip.hand_pose = HandModel.Pose.PINCH
	_grip.pressed.connect(_on_pressed)
	_grip.dragged.connect(_on_dragged)
	_grip.released.connect(_on_released)
	_grip.cancelled.connect(_end_scoop)
	_grip.secondary_pressed.connect(func(_point: Vector3) -> void:
		if ingredient:
			read.emit(ingredient))
	_grip.hover_entered.connect(func() -> void: _set_hovered(true))
	_grip.hover_exited.connect(func() -> void: _set_hovered(false))
	_show()

static func is_scooped(item: Ingredient) -> bool:
	return item.physical_form == Ingredient.PhysicalForm.GRANULAR and item.scoop_g > 0.0

## The uniform scale and quarter-turn that fit an item of `size_m` (X, Y, Z)
## into a spot: its longer side runs along the longer side of the spot, and
## it shrinks to fit, never grows.
static func fit(size_m: Vector3, slot_m: Vector3) -> Dictionary:
	var turn: bool = (size_m.x > size_m.z) != (slot_m.x > slot_m.z)
	var footprint := Vector3(size_m.z, size_m.y, size_m.x) if turn else size_m
	var scale: float = 1.0
	for axis in 3:
		scale = minf(scale, slot_m[axis] * FILL / maxf(footprint[axis], 0.0001))
	return {"scale": scale, "turn": turn, "footprint": footprint * scale}

func _set_hovered(on: bool) -> void:
	hovered = on and state == State.IDLE
	_label.visible = hovered and ingredient != null

func _process(delta: float) -> void:
	_lift_m = lerpf(_lift_m, HOVER_LIFT_M if hovered else 0.0, 1.0 - exp(-HOVER_EASE * delta))
	_contents.position.y = _lift_m

## Shows a fresh sample of the ingredient in the spot. `settle` grows it in,
## as if just put there.
func _show(settle: bool = false) -> void:
	if ingredient == null:
		_label.text = ""
		return
	_label.text = ingredient.display_name
	var holder := Node3D.new()
	holder.name = "Shown"
	_contents.add_child(holder)
	_shown = holder
	if is_scooped(ingredient):
		var heap := _still_view(FoodPiece.handful(ingredient, DISPLAY_HEAP_G, 15.0))
		holder.add_child(heap)
		var size: Vector2 = heap.footprint_m()
		heap.position = Vector3(-size.x * 0.5, mouth_height_m, -size.y * 0.5)
	else:
		var size_m: Vector3 = ingredient.whole_size_mm * FoodPieceView.MM_TO_M
		var space := Vector3(slot_size_m.x, slot_size_m.y - mouth_height_m, slot_size_m.z)
		var fitted := fit(size_m, space)
		var footprint: Vector3 = fitted.footprint
		var copies: int = clampi(floori(space.x * space.z * 0.18 / maxf(footprint.x * footprint.z, 1e-6)), 1, MAX_SHOWN)
		for copy in copies:
			# Copies after the first scatter round the middle of the spot.
			var angle: float = copy * 2.39996
			var offset := Vector3(cos(angle), 0.0, sin(angle)) * (0.0 if copy == 0 else footprint.length() * 0.75)
			offset.x = clampf(offset.x, -(space.x - footprint.x) * 0.5, (space.x - footprint.x) * 0.5)
			offset.z = clampf(offset.z, -(space.z - footprint.z) * 0.5, (space.z - footprint.z) * 0.5)
			holder.add_child(_fitted_view(size_m, fitted, offset))
	_cast_no_shadow(self)
	if settle:
		holder.scale = Vector3.ONE * 0.01
		var grow := create_tween()
		grow.tween_interval(TAKE_AWAY_S * 0.6)
		grow.tween_property(holder, "scale", Vector3.ONE, RESTOCK_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## One sample of the whole item, scaled and turned as `fitted` says,
## centred at `offset` in the spot.
func _fitted_view(size_m: Vector3, fitted: Dictionary, offset: Vector3) -> FoodPieceView:
	var view := _still_view(FoodPiece.from_ingredient(ingredient, 4.0))
	var scale: float = fitted.scale
	# The view's origin is its piece's minimum corner; centre it, turned a
	# quarter if that fits better.
	var centre := Vector3(size_m.x * 0.5, 0.0, size_m.z * 0.5) * scale
	if fitted.turn:
		view.basis = Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * scale)
		view.position = Vector3(-centre.z, mouth_height_m, centre.x) + offset
	else:
		view.scale = Vector3.ONE * scale
		view.position = Vector3(-centre.x, mouth_height_m, -centre.z) + offset
	return view

## The pantry stands between the low sun and the counter: what is on its
## shelves must not shade the counter.
static func _cast_no_shadow(node: Node) -> void:
	for geometry: GeometryInstance3D in node.find_children("*", "GeometryInstance3D", true, false):
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## A view of food that only sits there to be looked at.
func _still_view(piece: FoodPiece) -> FoodPieceView:
	var view := FoodPieceView.new(piece)
	view.steams_in_air = false
	view.may_hover = false
	view.grip.input_ray_pickable = false
	return view

## The shown sample lifts away (it is what the hand took) and another
## settles in its place.
func _restock() -> void:
	if _shown:
		var gone := _shown
		var away := create_tween().set_parallel(true)
		away.tween_property(gone, "position", gone.position + Vector3(0.0, 0.05, 0.03), TAKE_AWAY_S).set_ease(Tween.EASE_OUT)
		away.tween_property(gone, "scale", Vector3.ONE * 0.01, TAKE_AWAY_S).set_ease(Tween.EASE_IN)
		away.chain().tween_callback(gone.queue_free)
	_show(true)

func _on_pressed(point: Vector3) -> void:
	if ingredient == null:
		return
	_set_hovered(false)
	if not is_scooped(ingredient):
		taken.emit(ingredient)
		_restock()
		return
	state = State.SCOOPING
	_grip.drag_plane = Plane(Vector3.UP, CARRY_HEIGHT_M)
	_scoop_view = _still_view(FoodPiece.handful(ingredient, ingredient.scoop_g, 15.0))
	_scoop_view.top_level = true
	add_child(_scoop_view)
	_grip.hand_anchor = _scoop_view
	var on_plane: Variant = _grip.drag_plane.intersects_ray(get_viewport().get_camera_3d().global_position,
		(point - get_viewport().get_camera_3d().global_position).normalized()) if get_viewport().get_camera_3d() else null
	_on_dragged(on_plane if on_plane != null else point)

func _on_dragged(point: Vector3) -> void:
	if state != State.SCOOPING or _scoop_view == null:
		return
	var size: Vector2 = _scoop_view.footprint_m()
	_scoop_view.global_position = point - Vector3(size.x * 0.5, 0.0, size.y * 0.5)

func _on_released(point: Vector3) -> void:
	if state != State.SCOOPING:
		return
	_end_scoop()
	scooped.emit(ingredient, ingredient.scoop_g, point)

func _end_scoop() -> void:
	state = State.IDLE
	_grip.hand_anchor = null
	if _scoop_view:
		_scoop_view.queue_free()
		_scoop_view = null
