class_name CuttingBoard
extends Node3D

## The board and every piece resting on it. Its origin is the centre of the
## board's top surface. It owns its pieces while they are here: it places
## them, moves them, rolls them and cuts them, always through the pure
## simulation (FoodCutting, MezzalunaGesture, FoodPiece.roll).
##
## Each piece on the board is in one of two states:
##   RESTING --press on the piece--> CARRIED --drag--> CARRIED --release--> RESTING
## A right press on a RESTING piece rolls it onto its side.
##
## The mezzaluna stroke is its own two-state machine:
##   IDLE --press on the bare board--> STROKING --drag--> STROKING --release--> IDLE
## On release, every piece the stroke crosses is cut. Holding
## "kitchen_steady" during the stroke holds the food still.

signal piece_placed(view: FoodPieceView)
signal pieces_cut(count: int, steadied: bool)

const SIZE_M: Vector2 = Vector2(0.40, 0.28)
## Space between the two halves of a fresh cut, so the cut shows.
const CUT_GAP_M: float = 0.0015
## How far pieces slide apart after a perpendicular cut made without
## steadying them.
const SCATTER_M: float = 0.006
## Gap kept between a newly placed whole item and anything already here.
const PLACEMENT_MARGIN_M: float = 0.01
const PLACEMENT_STEP_M: float = 0.01

@export var ambient_temp_c: float = 15.0

var _views: Array[FoodPieceView] = []
var _carried: FoodPieceView
var _carry_offset: Vector3
var _stroking: bool = false
var _stroke_start: Vector3

@onready var _surface: Interactable = $Surface
@onready var _pieces: Node3D = $Pieces
@onready var _mezzaluna: MezzalunaView = $Mezzaluna
@onready var _steady_hand: Node3D = $SteadyHand

func _ready() -> void:
	_surface.drag_plane = _top_plane()
	_surface.pressed.connect(_on_surface_pressed)
	_surface.dragged.connect(_on_surface_dragged)
	_surface.released.connect(_on_surface_released)
	_steady_hand.visible = false

func views() -> Array[FoodPieceView]:
	return _views

## Puts a whole item from the pantry on the first free spot. Returns null
## when there is no room left on the board.
func add_whole(ingredient: Ingredient) -> FoodPieceView:
	var piece := FoodPiece.from_ingredient(ingredient, ambient_temp_c)
	if piece == null:
		return null
	var footprint := Vector2(piece.size_mm.x, piece.size_mm.z) * FoodPieceView.MM_TO_M
	var spot: Variant = _free_spot(footprint)
	if spot == null:
		return null
	var view := _add_view(piece, Vector3(spot.x, 0.0, spot.y))
	piece_placed.emit(view)
	return view

## Cuts every piece a mezzaluna stroke from start to end crosses, both in
## board-local metres. Returns how many pieces were cut.
func cut_stroke(start: Vector3, end: Vector3, steadied: bool) -> int:
	var start_mm := Vector2(start.x, start.z) / FoodPieceView.MM_TO_M
	var end_mm := Vector2(end.x, end.z) / FoodPieceView.MM_TO_M
	var cut_count: int = 0
	for view in _views.duplicate():
		var footprint_min := Vector2(view.position.x, view.position.z) / FoodPieceView.MM_TO_M
		var footprint_size := Vector2(view.piece.size_mm.x, view.piece.size_mm.z)
		var intent := MezzalunaGesture.resolve(footprint_min, footprint_size, start_mm, end_mm)
		if intent == null:
			continue
		var scatter: bool = not steadied and FoodCutting.is_perpendicular(view.piece, intent.axis)
		var sides := FoodCutting.cut(view.piece, intent.axis, intent.offset_mm, steadied)
		if sides.is_empty():
			continue
		_replace_with_sides(view, sides, intent.axis, scatter)
		cut_count += 1
	if cut_count > 0:
		pieces_cut.emit(cut_count, steadied)
	return cut_count

## Tips a piece onto its side where it lies.
func roll(view: FoodPieceView) -> void:
	view.rolled_about(view.piece.roll())
	view.position = _clamped(view.position, view.footprint_m())

func _add_view(piece: FoodPiece, local_position: Vector3) -> FoodPieceView:
	var view := FoodPieceView.new(piece)
	_pieces.add_child(view)
	view.position = _clamped(local_position, view.footprint_m())
	view.grip.drag_plane = _top_plane()
	view.grip.pressed.connect(_on_piece_pressed.bind(view))
	view.grip.dragged.connect(_on_piece_dragged.bind(view))
	view.grip.released.connect(_on_piece_released.bind(view))
	view.grip.secondary_pressed.connect(func(_point: Vector3) -> void: roll(view))
	_views.append(view)
	return view

func _replace_with_sides(view: FoodPieceView, sides: Array[FoodPiece], axis: int, scatter: bool) -> void:
	var origin := view.position
	_views.erase(view)
	view.queue_free()
	var near_side := _add_view(sides[0], origin)
	var far_origin := origin
	far_origin[axis] += sides[0].size_mm[axis] * FoodPieceView.MM_TO_M + CUT_GAP_M
	var far_side := _add_view(sides[1], far_origin)
	if scatter:
		for side in [near_side, far_side]:
			var jolt := Vector3(randf_range(-SCATTER_M, SCATTER_M), 0.0, randf_range(-SCATTER_M, SCATTER_M))
			side.position = _clamped(side.position + jolt, side.footprint_m())

## The free spot nearest the middle of the board, as the minimum corner of
## the footprint, or null if nothing fits.
func _free_spot(footprint: Vector2) -> Variant:
	var half := SIZE_M * 0.5
	var candidates: Array[Vector2] = []
	var z := -half.y
	while z + footprint.y <= half.y:
		var x := -half.x
		while x + footprint.x <= half.x:
			candidates.append(Vector2(x, z))
			x += PLACEMENT_STEP_M
		z += PLACEMENT_STEP_M
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return (a + footprint * 0.5).length_squared() < (b + footprint * 0.5).length_squared())
	for corner in candidates:
		var candidate := Rect2(corner, footprint).grow(PLACEMENT_MARGIN_M)
		var clear := true
		for view in _views:
			if candidate.intersects(Rect2(Vector2(view.position.x, view.position.z), view.footprint_m())):
				clear = false
				break
		if clear:
			return corner
	return null

## Keeps a piece's footprint on the board.
func _clamped(local_position: Vector3, footprint: Vector2) -> Vector3:
	var half := SIZE_M * 0.5
	return Vector3(
		clampf(local_position.x, -half.x, maxf(half.x - footprint.x, -half.x)),
		0.0,
		clampf(local_position.z, -half.y, maxf(half.y - footprint.y, -half.y))
	)

func _top_plane() -> Plane:
	return Plane(Vector3.UP, global_position.y)

func _on_piece_pressed(point: Vector3, view: FoodPieceView) -> void:
	_carried = view
	_carry_offset = view.position - to_local(point)

func _on_piece_dragged(point: Vector3, view: FoodPieceView) -> void:
	if view == _carried:
		view.position = _clamped(to_local(point) + _carry_offset, view.footprint_m())

func _on_piece_released(_point: Vector3, view: FoodPieceView) -> void:
	if view == _carried:
		_carried = null

func _on_surface_pressed(point: Vector3) -> void:
	_stroking = true
	_stroke_start = to_local(point)
	_mezzaluna.show_stroke(_stroke_start, _stroke_start)

func _on_surface_dragged(point: Vector3) -> void:
	if not _stroking:
		return
	var end := to_local(point)
	_mezzaluna.show_stroke(_stroke_start, end)
	_steady_hand.visible = Input.is_action_pressed("kitchen_steady")
	if _steady_hand.visible:
		_steady_hand.position = (_stroke_start + end) * 0.5

func _on_surface_released(point: Vector3) -> void:
	if not _stroking:
		return
	_stroking = false
	_steady_hand.visible = false
	var steadied := Input.is_action_pressed("kitchen_steady")
	if cut_stroke(_stroke_start, to_local(point), steadied) > 0:
		_mezzaluna.rock()
	else:
		_mezzaluna.rest()
