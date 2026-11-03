class_name IngredientSource
extends Node3D

## A basket, crate, tin or sack in the pantry. The pantry is unlimited until
## foraging exists. A source either holds one ingredient, or is a whole
## shelf (Ingredient.Shelf) of them - every unlocked ingredient authored for
## that shelf - and a right-click turns to the next one.
##
##   IDLE --press, whole item--> IDLE (taken: one whole item to the board)
##   IDLE --press, spice or grain--> SCOOPING (a pinch or a handful in the hand)
##   SCOOPING --drag--> SCOOPING --release--> IDLE (scooped: let go at a point)
##   SCOOPING --cancelled--> IDLE (put back)
##
## The ingredient, the shelf and the scoop size are all data, so a new
## basket is a new instance, never new code.

signal taken(ingredient: Ingredient)
## A pinch or handful let go at a world point.
signal scooped(ingredient: Ingredient, grams: float, world_point: Vector3)
signal changed(ingredient: Ingredient)

enum State { IDLE, SCOOPING }

## Where the items shown in the basket sit, as (x, z, turn about Y), in
## metres and radians on the basket floor.
const DISPLAY_SPOTS: Array[Vector3] = [Vector3(-0.022, -0.015, 0.4), Vector3(0.024, 0.012, 2.1), Vector3(0.0, 0.03, -0.9)]
const BASKET_FLOOR_M: float = 0.012
## Height the hand carries a scoop at, above the basket: clear of the pot.
const CARRY_HEIGHT_M: float = 0.24
## Grams shown heaped in the basket for a bulk ingredient.
const DISPLAY_HEAP_G: float = 40.0

## A single ingredient, for a source that holds just one.
@export var ingredient: Ingredient
## A whole shelf of ingredients, offered one at a time.
@export var shelf: Ingredient.Shelf = Ingredient.Shelf.NONE

var state: State = State.IDLE
var choices: Array[Ingredient] = []
var choice_index: int = 0

var _scoop_view: FoodPieceView

@onready var _grip: Interactable = $Grip
@onready var _label: Label3D = $Label
@onready var _contents: Node3D = $Contents

func _ready() -> void:
	_refresh_choices()
	_grip.pressed.connect(_on_pressed)
	_grip.dragged.connect(_on_dragged)
	_grip.released.connect(_on_released)
	_grip.cancelled.connect(_end_scoop)
	_grip.secondary_pressed.connect(func(_point: Vector3) -> void: cycle())
	_show_current()

## What pressing the source takes right now.
func current() -> Ingredient:
	return choices[choice_index] if not choices.is_empty() else ingredient

## Turns to the next ingredient on the shelf.
func cycle() -> void:
	_refresh_choices()
	if choices.size() <= 1:
		return
	choice_index = (choice_index + 1) % choices.size()
	_show_current()
	changed.emit(current())

static func is_scooped(item: Ingredient) -> bool:
	return item.physical_form == Ingredient.PhysicalForm.GRANULAR and item.scoop_g > 0.0

func _refresh_choices() -> void:
	if shelf == Ingredient.Shelf.NONE:
		choices.clear()
		if ingredient:
			choices.append(ingredient)
		choice_index = 0
		return
	var held: Ingredient = current() if not choices.is_empty() else null
	choices.clear()
	for candidate in IngredientCatalog.on_shelf(shelf):
		if LighthouseProgression.is_ingredient_unlocked(candidate):
			choices.append(candidate)
	choice_index = maxi(choices.find(held), 0)

func _show_current() -> void:
	for child in _contents.get_children():
		child.queue_free()
	var item := current()
	if item == null:
		_label.text = ""
		return
	_label.text = item.display_name
	if is_scooped(item):
		var heap := FoodPieceView.new(FoodPiece.handful(item, DISPLAY_HEAP_G, 15.0))
		heap.steams_in_air = false
		heap.may_hover = false
		heap.grip.input_ray_pickable = false
		_contents.add_child(heap)
		var size: Vector2 = heap.footprint_m()
		heap.position = Vector3(-size.x * 0.5, BASKET_FLOOR_M, -size.y * 0.5)
	elif item.whole_model:
		for spot in DISPLAY_SPOTS:
			var shown: Node3D = item.whole_model.instantiate()
			shown.position = Vector3(spot.x, BASKET_FLOOR_M, spot.y)
			shown.rotation.y = spot.z
			_contents.add_child(shown)
	else:
		# No model yet: show the whole item as the food box it will cut into.
		var piece := FoodPiece.from_ingredient(item, 15.0)
		var shown := FoodPieceView.new(piece)
		shown.steams_in_air = false
		shown.may_hover = false
		shown.grip.input_ray_pickable = false
		var fit: float = minf(1.0, 0.1 / maxf(piece.size_mm.x, piece.size_mm.z) * 1000.0)
		shown.scale = Vector3.ONE * fit
		_contents.add_child(shown)
		shown.position = Vector3(-piece.size_mm.x, 0.0, -piece.size_mm.z) * FoodPieceView.MM_TO_M * 0.5 * fit + Vector3(0.0, BASKET_FLOOR_M, 0.0)

func _on_pressed(point: Vector3) -> void:
	var item := current()
	if item == null:
		return
	if not is_scooped(item):
		taken.emit(item)
		return
	state = State.SCOOPING
	_grip.drag_plane = Plane(Vector3.UP, global_position.y + CARRY_HEIGHT_M)
	_scoop_view = FoodPieceView.new(FoodPiece.handful(item, item.scoop_g, 15.0))
	_scoop_view.steams_in_air = false
	_scoop_view.may_hover = false
	_scoop_view.grip.input_ray_pickable = false
	_scoop_view.top_level = true
	add_child(_scoop_view)
	_on_dragged(_grip.drag_plane.project(point))

func _on_dragged(point: Vector3) -> void:
	if state != State.SCOOPING or _scoop_view == null:
		return
	var size: Vector2 = _scoop_view.footprint_m()
	_scoop_view.global_position = point - Vector3(size.x * 0.5, 0.0, size.y * 0.5)

func _on_released(point: Vector3) -> void:
	if state != State.SCOOPING:
		return
	var item := current()
	_end_scoop()
	scooped.emit(item, item.scoop_g, point)

func _end_scoop() -> void:
	state = State.IDLE
	if _scoop_view:
		_scoop_view.queue_free()
		_scoop_view = null
