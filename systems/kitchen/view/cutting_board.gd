class_name CuttingBoard
extends Node3D

## The board and every piece resting on it. Its origin is the centre of the
## board's top surface. It owns its pieces while they are here: it places
## them, moves them, rolls them and cuts them, always through the pure
## simulation (FoodCutting, MezzalunaGesture, FoodPiece.roll).
##
## Each piece on the board is in one of two states:
##   RESTING --press on the piece--> CARRIED --drag--> CARRIED --release--> RESTING
## A right press on a RESTING piece rolls it onto its side. Pressed while
## steadying (holding "kitchen_steady"), a piece is lifted together with
## every piece touching it - a whole cut potato at once - and carried in the
## hand above the counter:
##   RESTING --steady press--> LIFTED --drag--> LIFTED --release over the pot--> (gone)
##   LIFTED --release anywhere else--> RESTING, set down below where it was
##
## Food on the board is in the board's RestingSurface, so it keeps cooking
## from its own heat, cools and dries in the air while it sits here.
##
## The mezzaluna stroke is its own two-state machine:
##   IDLE --press on the bare board--> STROKING --drag--> STROKING --release--> IDLE
## On release, every piece the stroke crosses is cut. Holding
## "kitchen_steady" during the stroke holds the food still. The first
## stroke through a whole creature dresses it instead: it opens into all of
## its parts (see dress()).

signal piece_placed(view: FoodPieceView)
signal pieces_cut(count: int, steadied: bool)
signal piece_tasted(note: String)
## A bite was taken, sounding like this.
signal bitten(sound: BiteSound)
## A whole creature was opened into its parts.
signal dressed(creature: Creature)
## Something needed more room than the board has.
signal board_crowded
signal liquids_changed

## The cutting board's own size: what a board model is made at.
const SIZE_M: Vector2 = Vector2(0.40, 0.28)
## Space between the two halves of a fresh cut, so the cut shows.
const CUT_GAP_M: float = 0.0015
## How far pieces slide apart after a perpendicular cut made without
## steadying them.
const SCATTER_M: float = 0.006
## Gap kept between a newly placed whole item and anything already here.
const PLACEMENT_MARGIN_M: float = 0.01
const PLACEMENT_STEP_M: float = 0.01
## Parts of a dressed creature are laid out close together.
const DRESSED_MARGIN_M: float = 0.003
const DRESSED_STEP_M: float = 0.005
## Height above the board that lifted food is carried at: clear of the
## pot's rim.
const CARRY_HEIGHT_M: float = 0.22
## Pieces closer than this count as touching, for lifting together.
const TOUCHING_M: float = 0.003
## A bite takes this much off the end of a piece, in mm.
const BITE_MM: float = 12.0
## A taste of a heap of grain takes this much of it, in g.
const HEAP_MOUTHFUL_G: float = 8.0
## How long the two sides of a cut take to ease apart.
const SLIDE_APART_S: float = 0.14
## A cut that costs more integrity than this sheds crumbs.
const CRUMB_INTEGRITY_LOSS: float = 0.1
const BLADE_LINE_WIDTH_M: float = 0.0008
const MAX_BLADE_LINES: int = 64

@export var ambient_temp_c: float = 15.0
## The surface food can rest on, in metres (x, z).
@export var size_m: Vector2 = SIZE_M
## False for a serving board: food is arranged and plated on it, never cut.
@export var allows_cutting: bool = true

## Liquids poured over what is on it - a drizzle of chilli oil, a ladle of
## broth - for a serving board.
var liquids: Array[LiquidPortion] = []

## The simulation the board's food rests in. Set before food arrives.
var rest: RestingSurface
## Offered food the player lets go of while lifted, with where each piece's
## centre was held; returns true if it took it (the pot, when it was let go
## over the pot).
var drop_target: Callable

var _views: Array[FoodPieceView] = []
var _puddles: Array[MeshInstance3D] = []
var _lifted: Array[FoodPieceView] = []
var _lift_offsets: Array[Vector3] = []
var _carried: FoodPieceView
var _carry_offset: Vector3
var _stroking: bool = false
var _stroke_start: Vector3

@onready var _surface: Interactable = $Surface
@onready var _pieces: Node3D = $Pieces
@onready var _mezzaluna: MezzalunaView = $Mezzaluna
@onready var _steady_hand: Node3D = $SteadyHand
@onready var _crumbs: GPUParticles3D = $Crumbs
@onready var _blade_lines: MultiMeshInstance3D = $BladeLines

func _ready() -> void:
	if not allows_cutting:
		_mezzaluna.visible = false
	liquids_changed.connect(_draw_liquids)
	var lines := MultiMesh.new()
	lines.transform_format = MultiMesh.TRANSFORM_3D
	var line_mesh := BoxMesh.new()
	line_mesh.size = Vector3(1.0, 0.0006, 1.0)
	var line_material := StandardMaterial3D.new()
	line_material.albedo_color = Color(0.1, 0.08, 0.07, 0.55)
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mesh.material = line_material
	lines.mesh = line_mesh
	lines.instance_count = MAX_BLADE_LINES
	lines.visible_instance_count = 0
	_blade_lines.multimesh = lines
	_surface.drag_plane = _top_plane()
	_surface.pressed.connect(_on_surface_pressed)
	_surface.dragged.connect(_on_surface_dragged)
	_surface.released.connect(_on_surface_released)
	_surface.cancelled.connect(_on_surface_cancelled)
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

## Sets food down on the board as near a world point as there is room for,
## and returns whatever didn't fit.
func receive(pieces: Array[FoodPiece], world_point: Vector3) -> Array[FoodPiece]:
	var rejected: Array[FoodPiece] = []
	var target := to_local(world_point)
	for piece in pieces:
		var bulk := piece.bulk_size_mm()
		var footprint := Vector2(bulk.x, bulk.z) * FoodPieceView.MM_TO_M
		var spot: Variant = _free_spot(footprint, Vector2(target.x, target.z) - footprint * 0.5)
		if spot == null:
			rejected.append(piece)
			continue
		piece_placed.emit(_add_view(piece, Vector3(spot.x, 0.0, spot.y)))
	return rejected

## Takes a piece off the board and hands it over.
func take(view: FoodPieceView) -> FoodPiece:
	_remove_view(view)
	return view.piece

## Takes a bite of a piece: the caretaker notices how it is, and the bite
## comes off the end of it - a real cut, so what is left has a fresh face.
## A piece too small to bite twice is eaten whole. Returns what they
## noticed.
func taste(view: FoodPieceView) -> String:
	if not _views.has(view):
		return ""
	var piece := view.piece
	var note := TasteNote.describe(piece)
	bitten.emit(FoodPerception.bite_of(piece))
	if piece.is_heap():
		# A mouthful of a heap is a spoonful of its kernels.
		var eaten: int = maxi(roundi(HEAP_MOUTHFUL_G / piece.mass_g()), 1)
		piece.count -= eaten
		if piece.count <= 0:
			_remove_view(view)
		else:
			view.refresh_shape()
		piece_tasted.emit(note)
		return note
	var axis: int = Vector3.AXIS_X
	for candidate in [Vector3.AXIS_Y, Vector3.AXIS_Z]:
		if piece.size_mm[candidate] > piece.size_mm[axis]:
			axis = candidate
	var origin := view.position
	_remove_view(view)
	var sides := FoodCutting.cut(piece, axis, piece.size_mm[axis] - BITE_MM, true)
	if not sides.is_empty():
		_add_view(sides[0], origin)
	piece_tasted.emit(note)
	return note

## Pieces whose footprint lies within reach of a world point - what a
## pinch scattered there lands on.
func pieces_near(world_point: Vector3, reach_m: float) -> Array[FoodPiece]:
	var local := to_local(world_point)
	var at := Vector2(local.x, local.z)
	var found: Array[FoodPiece] = []
	for view in _views:
		if _footprint_rect(view).grow(reach_m).has_point(at):
			found.append(view.piece)
	return found

## True if a world point lies over the board.
func is_over(world_point: Vector3) -> bool:
	var local := to_local(world_point)
	return absf(local.x) <= size_m.x * 0.5 and absf(local.z) <= size_m.y * 0.5

## The pieces touching a piece, and the pieces touching those, and so on -
## everything that lifts with it.
func touching_cluster(view: FoodPieceView) -> Array[FoodPieceView]:
	var cluster: Array[FoodPieceView] = [view]
	var index: int = 0
	while index < cluster.size():
		var rect := _footprint_rect(cluster[index]).grow(TOUCHING_M)
		for other in _views:
			if not cluster.has(other) and rect.intersects(_footprint_rect(other)):
				cluster.append(other)
		index += 1
	return cluster

func is_lifting() -> bool:
	return not _lifted.is_empty()

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
		if is_carcass(view.piece):
			if dress(view):
				cut_count += 1
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

## True for a whole creature not yet opened up.
static func is_carcass(piece: FoodPiece) -> bool:
	return piece.ingredient.creature != null and piece.cut_axes.is_empty()

## Opens a whole creature into every one of its parts, laid out packed
## across the board. Each part takes the carcass's temperature
## and how cooked it was. Refused, leaving it whole, when the board has no
## room for all of them.
func dress(view: FoodPieceView) -> bool:
	if not _views.has(view) or not is_carcass(view.piece):
		return false
	var carcass := view.piece
	var near := Vector2(view.position.x, view.position.z) + view.footprint_m() * 0.5
	_views.erase(view)
	var parts: Array[FoodPiece] = []
	for part in carcass.ingredient.creature.parts:
		for index in part.count:
			var piece := FoodPiece.from_ingredient(part.ingredient, carcass.core_temp_c)
			piece.core_doneness = carcass.core_doneness
			piece.surface_temp_c = carcass.surface_temp_c
			parts.append(piece)
	# Largest first, so the big cuts get the room.
	parts.sort_custom(func(a: FoodPiece, b: FoodPiece) -> bool:
		return a.size_mm.x * a.size_mm.z > b.size_mm.x * b.size_mm.z)
	var spots: Array[Vector2] = []
	var placed: Array[FoodPieceView] = []
	for piece in parts:
		var footprint := Vector2(piece.size_mm.x, piece.size_mm.z) * FoodPieceView.MM_TO_M
		var spot: Variant = _free_spot(footprint, near - footprint * 0.5, DRESSED_MARGIN_M, DRESSED_STEP_M, true)
		if spot == null:
			for undo in placed:
				_remove_view(undo)
			_views.append(view)
			board_crowded.emit()
			return false
		placed.append(_add_view(piece, Vector3(spot.x, 0.0, spot.y)))
	if rest:
		rest.remove_piece(carcass)
	view.queue_free()
	dressed.emit(carcass.ingredient.creature)
	return true

## Tips a piece onto its side where it lies.
func roll(view: FoodPieceView) -> void:
	view.rolled_about(view.piece.roll())
	view.position = _clamped(view.position, view.footprint_m())

func _remove_view(view: FoodPieceView) -> void:
	_views.erase(view)
	if rest:
		rest.remove_piece(view.piece)
	if _carried == view:
		_carried = null
	view.queue_free()

func _footprint_rect(view: FoodPieceView) -> Rect2:
	return Rect2(Vector2(view.position.x, view.position.z), view.footprint_m())

func _add_view(piece: FoodPiece, local_position: Vector3) -> FoodPieceView:
	if rest:
		rest.add_piece(piece)
	var view := FoodPieceView.new(piece)
	_pieces.add_child(view)
	view.position = _clamped(local_position, view.footprint_m())
	view.grip.drag_plane = _top_plane()
	view.grip.pressed.connect(_on_piece_pressed.bind(view))
	view.grip.dragged.connect(_on_piece_dragged.bind(view))
	view.grip.released.connect(_on_piece_released.bind(view))
	view.grip.secondary_pressed.connect(func(_point: Vector3) -> void: roll(view))
	view.grip.cancelled.connect(func() -> void: _on_piece_cancelled(view))
	_views.append(view)
	return view

## The two sides of a cut start where the whole piece was and ease apart:
## a clean gap along the cut, or a jolt sideways when the food wasn't held
## steady. Food that crumbled at the cut sheds crumbs.
func _replace_with_sides(view: FoodPieceView, sides: Array[FoodPiece], axis: int, scatter: bool) -> void:
	var origin := view.position
	var integrity_before: float = view.piece.integrity
	_remove_view(view)
	var near_side := _add_view(sides[0], origin)
	var far_start := origin
	far_start[axis] += sides[0].size_mm[axis] * FoodPieceView.MM_TO_M
	var far_side := _add_view(sides[1], far_start)
	var targets: Array[Vector3] = [origin, far_start]
	targets[1][axis] += CUT_GAP_M
	if scatter:
		for index in 2:
			var jolt := Vector3(randf_range(-SCATTER_M, SCATTER_M), 0.0, randf_range(-SCATTER_M, SCATTER_M))
			targets[index] = targets[index] + jolt
	var side_views: Array[FoodPieceView] = [near_side, far_side]
	for index in 2:
		var side := side_views[index]
		var target := _clamped(targets[index], side.footprint_m())
		var tween := side.create_tween()
		tween.tween_property(side, "position", target, SLIDE_APART_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var lost: float = integrity_before - minf(sides[0].integrity, sides[1].integrity)
	if lost > CRUMB_INTEGRITY_LOSS:
		_shed_crumbs(far_start, sides[0], axis, lost)

func _shed_crumbs(at: Vector3, piece: FoodPiece, axis: int, lost: float) -> void:
	var size: Vector3 = piece.size_mm * FoodPieceView.MM_TO_M
	var centre := at + Vector3(size.x * 0.5, size.y * 0.5, size.z * 0.5)
	centre[axis] = at[axis]
	_crumbs.position = centre
	_crumbs.amount_ratio = clampf(lost * 2.0, 0.2, 1.0)
	var material := _crumbs.draw_pass_1.surface_get_material(0) as StandardMaterial3D
	if material:
		material.albedo_color = piece.ingredient.flesh_color
	_crumbs.restart()
	_crumbs.emitting = true

## Shows, on every piece the stroke would cut, the line the blade will
## come down on - snapped exactly as the cut will be.
func _show_blade_line(start: Vector3, end: Vector3) -> void:
	var start_mm := Vector2(start.x, start.z) / FoodPieceView.MM_TO_M
	var end_mm := Vector2(end.x, end.z) / FoodPieceView.MM_TO_M
	var count: int = 0
	for view in _views:
		if count >= _blade_lines.multimesh.instance_count:
			break
		var footprint_min := Vector2(view.position.x, view.position.z) / FoodPieceView.MM_TO_M
		var footprint_size := Vector2(view.piece.size_mm.x, view.piece.size_mm.z)
		var intent := MezzalunaGesture.resolve(footprint_min, footprint_size, start_mm, end_mm)
		if intent == null:
			continue
		var size: Vector3 = view.piece.size_mm * FoodPieceView.MM_TO_M
		var line_centre := view.position + Vector3(size.x * 0.5, size.y + 0.0004, size.z * 0.5)
		var scale := Vector3(size.x + 0.002, 1.0, size.z + 0.002)
		line_centre[intent.axis] = view.position[intent.axis] + intent.offset_mm * FoodPieceView.MM_TO_M
		scale[intent.axis] = BLADE_LINE_WIDTH_M
		_blade_lines.multimesh.set_instance_transform(count, Transform3D(Basis.from_scale(scale), line_centre))
		count += 1
	_blade_lines.multimesh.visible_instance_count = count

func _hide_blade_line() -> void:
	_blade_lines.multimesh.visible_instance_count = 0

## The free spot nearest a point on the board (its middle by default), as
## the minimum corner of the footprint, or null if nothing fits.
func _free_spot(footprint: Vector2, near: Vector2 = Vector2.ZERO, margin: float = PLACEMENT_MARGIN_M, step: float = PLACEMENT_STEP_M, row_by_row: bool = false) -> Variant:
	var half := size_m * 0.5
	var candidates: Array[Vector2] = []
	var z := -half.y
	while z + footprint.y <= half.y:
		var x := -half.x
		while x + footprint.x <= half.x:
			candidates.append(Vector2(x, z))
			x += step
		z += step
	if row_by_row:
		# Fill from the far corner, row by row, so what is laid out packs
		# tight and leaves the free room in one piece.
		candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			return a.y < b.y or (is_equal_approx(a.y, b.y) and a.x < b.x))
	else:
		candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			return (a + footprint * 0.5 - near).length_squared() < (b + footprint * 0.5 - near).length_squared())
	for corner in candidates:
		var candidate := Rect2(corner, footprint).grow(margin)
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
	var half := size_m * 0.5
	return Vector3(
		clampf(local_position.x, -half.x, maxf(half.x - footprint.x, -half.x)),
		0.0,
		clampf(local_position.z, -half.y, maxf(half.y - footprint.y, -half.y))
	)

func _top_plane() -> Plane:
	return Plane(Vector3.UP, global_position.y)

func _on_piece_pressed(point: Vector3, view: FoodPieceView) -> void:
	if Input.is_action_pressed("kitchen_steady"):
		_lift(view, point)
		return
	view.grip.drag_plane = _top_plane()
	_carried = view
	_carry_offset = view.position - to_local(point)

func _on_piece_dragged(point: Vector3, view: FoodPieceView) -> void:
	if not _lifted.is_empty() and _lifted[0] == view:
		var hand := to_local(point)
		for index in _lifted.size():
			var offset: Vector3 = _lift_offsets[index]
			_lifted[index].position = Vector3(hand.x + offset.x, CARRY_HEIGHT_M, hand.z + offset.z)
	elif view == _carried:
		view.position = _clamped(to_local(point) + _carry_offset, view.footprint_m())

func _on_piece_released(point: Vector3, view: FoodPieceView) -> void:
	if not _lifted.is_empty() and _lifted[0] == view:
		_let_go(point)
	elif view == _carried:
		_carried = null

## Lifts a piece and everything touching it into the hand.
func _lift(view: FoodPieceView, point: Vector3) -> void:
	_lifted = touching_cluster(view)
	_lift_offsets.clear()
	var lift_plane := Plane(Vector3.UP, global_position.y + CARRY_HEIGHT_M)
	view.grip.drag_plane = lift_plane
	var hand := to_local(point)
	for lifted in _lifted:
		_lift_offsets.append(Vector3(lifted.position.x - hand.x, 0.0, lifted.position.z - hand.z))
		lifted.position.y = CARRY_HEIGHT_M

## Lets go of what is lifted: into the pot if it takes it, otherwise
## straight down onto the board.
func _let_go(point: Vector3) -> void:
	var lifted := _lifted.duplicate()
	_lifted.clear()
	_lift_offsets.clear()
	var pieces: Array[FoodPiece] = []
	var held_at: Array[Vector3] = []
	for view in lifted:
		pieces.append(view.piece)
		held_at.append(view.to_global(view.piece.size_mm * FoodPieceView.MM_TO_M * 0.5))
	if drop_target.is_valid() and drop_target.call(pieces, point, held_at):
		for view in lifted:
			_remove_view(view)
		return
	for view in lifted:
		view.grip.drag_plane = _top_plane()
		view.position = _clamped(Vector3(view.position.x, 0.0, view.position.z), view.footprint_m())

func _on_piece_cancelled(view: FoodPieceView) -> void:
	if not _lifted.is_empty() and _lifted[0] == view:
		for lifted in _lifted:
			lifted.position = _clamped(Vector3(lifted.position.x, 0.0, lifted.position.z), lifted.footprint_m())
		_lifted.clear()
		_lift_offsets.clear()
	_carried = null

## Everything plated here as a dish: its pieces and its liquids.
func dish() -> Dish:
	var plated := Dish.new()
	for view in _views:
		plated.add_piece(view.piece)
	for portion in liquids:
		plated.add_liquid(portion)
	return plated

## Pours a liquid over the food here; the same liquid poured again joins
## the first, its flavour and essences mixed in by mass.
func add_liquid(liquid: Ingredient, grams: float, flavour: FlavourProfile, traits: TraitDoses, temp_c: float) -> void:
	for portion in liquids:
		if portion.ingredient == liquid:
			portion.flavour = FlavourProfile.mix_by_mass(portion.flavour, portion.grams, flavour if flavour else liquid.flavour, grams)
			if portion.traits:
				portion.traits.mix_in(portion.grams, traits if traits else liquid.trait_doses(), grams)
			portion.temp_c = (portion.temp_c * portion.grams + temp_c * grams) / (portion.grams + grams)
			portion.grams += grams
			liquids_changed.emit()
			return
	liquids.append(LiquidPortion.new(liquid, grams, flavour, traits, temp_c))
	liquids_changed.emit()

## Depth a liquid pools to on a board, in mm: its puddle spreads to match.
const PUDDLE_DEPTH_MM: float = 1.5

## Pools each liquid on the board, as wide as its volume spreads at a
## shallow depth, coloured by what it is and what it took in.
func _draw_liquids() -> void:
	for puddle in _puddles:
		puddle.queue_free()
	_puddles.clear()
	for index in liquids.size():
		var portion := liquids[index]
		var area_mm2: float = portion.grams / maxf(portion.ingredient.density_g_per_cm3, 0.1) * 1000.0 / PUDDLE_DEPTH_MM
		var radius_m: float = minf(sqrt(area_mm2 / PI) * FoodPieceView.MM_TO_M, size_m.y * 0.45)
		var disc := CylinderMesh.new()
		disc.top_radius = radius_m
		disc.bottom_radius = radius_m
		disc.height = 0.0015
		disc.radial_segments = 24
		var material := StandardMaterial3D.new()
		var color: Color = portion.ingredient.tint_color
		if portion.flavour:
			color = color.lerp(Color(0.85, 0.22, 0.08), clampf(portion.flavour.heat, 0.0, 1.0) * 0.6)
		color.a = 0.75
		material.albedo_color = color
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 0.1
		disc.material = material
		var puddle := MeshInstance3D.new()
		puddle.mesh = disc
		puddle.position = Vector3((index - (liquids.size() - 1) * 0.5) * radius_m * 1.2, 0.0008, 0.0)
		add_child(puddle)
		_puddles.append(puddle)

## Clears everything off: the food and the liquid both.
func clear() -> void:
	for view in _views.duplicate():
		_remove_view(view)
	liquids.clear()
	liquids_changed.emit()

func _on_surface_pressed(point: Vector3) -> void:
	if not allows_cutting:
		return
	_stroking = true
	_stroke_start = to_local(point)
	_mezzaluna.show_stroke(_stroke_start, _stroke_start)

func _on_surface_dragged(point: Vector3) -> void:
	if not _stroking:
		return
	var end := to_local(point)
	_mezzaluna.show_stroke(_stroke_start, end)
	_show_blade_line(_stroke_start, end)
	_steady_hand.visible = Input.is_action_pressed("kitchen_steady")
	if _steady_hand.visible:
		_steady_hand.position = (_stroke_start + end) * 0.5

func _on_surface_cancelled() -> void:
	_stroking = false
	_hide_blade_line()
	_steady_hand.visible = false
	_mezzaluna.rest()

func _on_surface_released(point: Vector3) -> void:
	if not _stroking:
		return
	_stroking = false
	_steady_hand.visible = false
	_hide_blade_line()
	var steadied := Input.is_action_pressed("kitchen_steady")
	if cut_stroke(_stroke_start, to_local(point), steadied) > 0:
		_mezzaluna.rock()
	else:
		_mezzaluna.rest()
