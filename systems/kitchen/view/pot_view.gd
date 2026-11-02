class_name PotView
extends Node3D

## The pot on the stove and everything in it, drawn from the CookingPot:
## the liquid surface at its true level and colour, every piece of food
## where PotLayout put it, the sizzle foam ringing each piece as much as it
## is steaming, steam and smoke drifting off downwind, and the spatter when
## wet food hits hot oil. The slotted spoon is the hand in the pot:
##
##   IDLE --press in the pot--> STIRRING --drag inside--> STIRRING (stirs)
##   STIRRING --drag out over the rim--> LIFTING (what the bowl caught
##                                       comes up out of the liquid)
##   STIRRING --release--> IDLE
##   LIFTING --release--> IDLE (lifted_out reports where it was released)
##
## A right-click on a piece in the pot turns it over.

## The spoon let go of what it lifted, at this world point. The kitchen
## decides where it lands; whatever it doesn't place is returned with
## return_to_pot().
signal lifted_out(pieces: Array[FoodPiece], world_point: Vector3)
signal pieces_dropped_in(count: int)

enum SpoonState { IDLE, STIRRING, LIFTING }

## Height of the pot's floor inside, in its local space (where the model's
## liquid surface rests when empty).
const FLOOR_Y_M: float = 0.0035
const RIM_Y_M: float = 0.123
const MM_TO_M: float = 0.001
## The spoon's bowl catches food this near its centre, in mm, up to this
## much footprint.
const SPOON_REACH_MM: float = 14.0
const SPOON_CAPACITY_MM2: float = 5200.0
## How far the stroke stirs food beside the bowl, in mm.
const STIR_REACH_MM: float = 20.0
## Height the spoon lifts food to above the rim, in metres.
const LIFT_HEIGHT_M: float = 0.06
const VIEW_EASE: float = 12.0
const FOAM_INSTANCES: int = 700
## Foam bubbles drawn per g/s of steam off a piece.
const FOAM_PER_G_PER_S: float = 8000.0
const FOAM_PER_PIECE: int = 50
const BOIL_BUBBLES: int = 160
## Steam (g/s) for full steam, and oil temperature for full shimmer.
const FULL_STEAM_G_PER_S: float = 0.6
const SHIMMER_FROM_C: float = 60.0
const SHIMMER_FULL_C: float = 190.0
const WATER_COLOR: Color = Color(0.62, 0.74, 0.8, 1.0)

@export var simulation: KitchenSimulation

var spoon_state: SpoonState = SpoonState.IDLE
var lifted: Array[FoodPiece] = []

var _views: Dictionary[FoodPiece, FoodPieceView] = {}
var _lifted_views: Array[FoodPieceView] = []
var _spoon_mm: Vector2
var _spoon_world: Vector3
var _surface_material := ShaderMaterial.new()
var _foam_multimesh := MultiMesh.new()

@onready var _surface: MeshInstance3D = $Model/liquid_surface
@onready var _mouth: Interactable = $Mouth
@onready var _pieces: Node3D = $Pieces
@onready var _foam: MultiMeshInstance3D = $Foam
@onready var _steam: GPUParticles3D = $Steam
@onready var _smoke: GPUParticles3D = $Smoke
@onready var _spatter: GPUParticles3D = $Spatter
@onready var _spoon: Node3D = $Spoon
@onready var _spoon_home: Transform3D = _spoon.transform

func _ready() -> void:
	_surface_material.shader = preload("res://shaders/cooking_liquid.gdshader")
	_surface.material_override = _surface_material
	_mouth.drag_plane = _rim_plane()
	_mouth.pressed.connect(_on_spoon_pressed)
	_mouth.dragged.connect(_on_spoon_dragged)
	_mouth.released.connect(_on_spoon_released)
	_mouth.cancelled.connect(_on_spoon_cancelled)
	_foam_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_foam_multimesh.mesh = _foam_bubble_mesh()
	_foam_multimesh.instance_count = FOAM_INSTANCES
	_foam_multimesh.visible_instance_count = 0
	_foam.multimesh = _foam_multimesh

func pot() -> CookingPot:
	return simulation.pot

## A world point as millimetres from the pot's centre on its floor.
func to_pot_mm(world_point: Vector3) -> Vector2:
	var local := to_local(world_point)
	return Vector2(local.x, local.z) / MM_TO_M

## True if a world point lies over the inside of the pot.
func is_over(world_point: Vector3) -> bool:
	return to_pot_mm(world_point).length() <= pot().vessel.interior_radius_mm()

func view_of(piece: FoodPiece) -> FoodPieceView:
	return _views.get(piece)

## Drops food in at a world point. A handful falls as it was held: give
## each piece's world centre in `held_at` and they land in the same layout
## around the point where they were let go. Wet food in hot oil spatters.
func drop_in(pieces: Array[FoodPiece], world_point: Vector3, held_at: Array[Vector3] = []) -> int:
	var centre := to_pot_mm(world_point)
	var radius: float = pot().vessel.interior_radius_mm() * 0.7
	if centre.length() > radius:
		centre = centre.normalized() * radius
	var middle := Vector2.ZERO
	if held_at.size() == pieces.size() and not held_at.is_empty():
		for spot in held_at:
			middle += Vector2(spot.x, spot.z)
		middle /= held_at.size()
	var dropped: int = 0
	var wet_g: float = 0.0
	for index in pieces.size():
		var piece := pieces[index]
		var offset := Vector2(fmod(index * 7.3, 5.0) - 2.5, fmod(index * 3.7, 5.0) - 2.5) * 4.0
		if held_at.size() == pieces.size():
			offset = (Vector2(held_at[index].x, held_at[index].z) - middle) / MM_TO_M
		if pot().add_piece(piece, centre + offset):
			dropped += 1
			wet_g += piece.surface_water_g()
	if dropped > 0:
		_splash(world_point, wet_g)
		pieces_dropped_in.emit(dropped)
	return dropped

## Returns food the spoon lifted that the kitchen didn't place elsewhere.
func return_to_pot(pieces: Array[FoodPiece]) -> void:
	for piece in pieces:
		simulation.held.remove_piece(piece)
		pot().add_piece(piece, _spoon_mm)

## Turns a piece in the pot over.
func turn(piece: FoodPiece) -> void:
	var axis: int = pot().turn(piece)
	var view: FoodPieceView = _views.get(piece)
	if view and axis >= 0:
		view.rolled_about(axis)

func _process(delta: float) -> void:
	_sync_views(delta)
	_draw_liquid()
	_draw_foam()
	_draw_air()
	_place_spoon(delta)

func _sync_views(delta: float) -> void:
	var cooking := pot()
	for piece in _views.keys():
		if not cooking.pieces.has(piece):
			_views[piece].queue_free()
			_views.erase(piece)
	var ease: float = 1.0 - exp(-VIEW_EASE * delta)
	var now: float = Time.get_ticks_msec() * 0.001
	for placement in cooking.placements:
		var piece := placement.piece
		var view: FoodPieceView = _views.get(piece)
		var target := _view_position(placement)
		if placement.resting == PotPlacement.Resting.FLOATING:
			# Floating food rides the bubbling.
			target.y += sin(now * 9.0 + placement.centre_mm.x) * 0.0006 * maxf(cooking.bubbling, 0.15)
		if view == null:
			view = _make_view(piece)
			view.position = target + Vector3(0.0, 0.03, 0.0)
		view.position = view.position.lerp(target, ease)

func _view_position(placement: PotPlacement) -> Vector3:
	var size: Vector3 = placement.piece.size_mm
	return Vector3(
		(placement.centre_mm.x - size.x * 0.5) * MM_TO_M,
		FLOOR_Y_M + placement.bottom_mm * MM_TO_M,
		(placement.centre_mm.y - size.z * 0.5) * MM_TO_M)

func _make_view(piece: FoodPiece) -> FoodPieceView:
	var view := FoodPieceView.new(piece)
	view.steams_in_air = false
	_pieces.add_child(view)
	view.grip.drag_plane = _rim_plane()
	view.grip.pressed.connect(_on_spoon_pressed)
	view.grip.dragged.connect(_on_spoon_dragged)
	view.grip.released.connect(_on_spoon_released)
	view.grip.cancelled.connect(_on_spoon_cancelled)
	view.grip.secondary_pressed.connect(func(_point: Vector3) -> void: turn(piece))
	_views[piece] = view
	return view

func _draw_liquid() -> void:
	var cooking := pot()
	_surface.visible = cooking.medium != null and cooking.medium_mass_g > 0.0
	if not _surface.visible:
		return
	_surface.position.y = FLOOR_Y_M + maxf(cooking.liquid_level_mm, 0.4) * MM_TO_M
	var medium := cooking.medium
	var oily: bool = medium.fat_fraction > 0.5
	var color: Color = medium.tint_color if oily else WATER_COLOR
	if oily:
		color = color.lerp(medium.spent_color, cooking.medium_breakdown)
		if cooking.medium_flavour:
			color = color.lerp(Color(0.85, 0.22, 0.08), clampf(cooking.medium_flavour.heat, 0.0, 1.0) * 0.6)
	_surface_material.set_shader_parameter("liquid_color", color)
	_surface_material.set_shader_parameter("clarity", 0.5 if oily else 0.7)
	_surface_material.set_shader_parameter("gloss", 0.9 if oily else 0.7)
	var shimmer: float = clampf((cooking.temp_c - SHIMMER_FROM_C) / (SHIMMER_FULL_C - SHIMMER_FROM_C), 0.0, 1.0) if oily else 0.0
	_surface_material.set_shader_parameter("shimmer", shimmer)
	var trembling: float = 0.0
	if not oily and medium.boiling_point_c > 0.0:
		trembling = clampf((cooking.temp_c - 70.0) / 30.0, 0.0, 1.0) * 0.3
	_surface_material.set_shader_parameter("agitation", maxf(cooking.bubbling, trembling))

func _draw_foam() -> void:
	var cooking := pot()
	var count: int = 0
	var now: float = Time.get_ticks_msec() * 0.001
	var surface_y: float = FLOOR_Y_M + cooking.liquid_level_mm * MM_TO_M
	if cooking.has_pool():
		for placement in cooking.placements:
			if placement.immersion <= 0.0:
				continue
			var bubbles: int = mini(int(placement.steam_g_per_s * FOAM_PER_G_PER_S), FOAM_PER_PIECE)
			var size: Vector3 = placement.piece.size_mm * MM_TO_M
			var centre := Vector3(placement.centre_mm.x * MM_TO_M, surface_y, placement.centre_mm.y * MM_TO_M)
			for bubble in bubbles:
				if count >= FOAM_INSTANCES:
					break
				var seed: float = float(bubble) * 12.9898 + placement.centre_mm.x * 0.37
				var life: float = fmod(now * (2.0 + fmod(seed, 1.7)) + seed, 1.0)
				var around: float = fmod(seed * 0.618, 1.0)
				var edge := _perimeter_point(Vector2(size.x, size.z), around)
				var out: float = 0.001 + life * 0.004
				var position := centre + Vector3(edge.x * (1.0 + out / maxf(size.x, 0.001)), 0.0, edge.y * (1.0 + out / maxf(size.z, 0.001)))
				var scale: float = (0.0009 + 0.0014 * fmod(seed * 0.33, 1.0)) * sin(life * PI)
				_foam_multimesh.set_instance_transform(count, Transform3D(Basis.from_scale(Vector3(scale, scale * 0.6, scale)), position))
				count += 1
		# A rolling boil bubbles over the whole surface.
		var boiling: int = int(cooking.bubbling * BOIL_BUBBLES) if cooking.medium.boiling_point_c > 0.0 else 0
		var radius: float = cooking.vessel.interior_radius_mm() * MM_TO_M * 0.92
		for bubble in boiling:
			if count >= FOAM_INSTANCES:
				break
			var seed: float = float(bubble) * 7.77
			var life: float = fmod(now * (1.4 + fmod(seed, 1.1)) + seed * 0.1, 1.0)
			var spot := Vector2(fmod(seed * 0.618, 1.0) * 2.0 - 1.0, fmod(seed * 0.414, 1.0) * 2.0 - 1.0)
			if spot.length() > 1.0:
				spot = spot.normalized() * fmod(seed * 0.27, 1.0)
			var scale: float = 0.003 * sin(life * PI)
			_foam_multimesh.set_instance_transform(count,
				Transform3D(Basis.from_scale(Vector3(scale, scale * 0.5, scale)), Vector3(spot.x * radius, surface_y, spot.y * radius)))
			count += 1
	_foam_multimesh.visible_instance_count = count

## A point on the edge of a footprint centred on the origin, `around` (0-1)
## of the way round it.
static func _perimeter_point(size: Vector2, around: float) -> Vector2:
	var half := size * 0.5
	var perimeter: float = 2.0 * (size.x + size.y)
	var distance: float = around * perimeter
	if distance < size.x:
		return Vector2(-half.x + distance, -half.y)
	distance -= size.x
	if distance < size.y:
		return Vector2(half.x, -half.y + distance)
	distance -= size.y
	if distance < size.x:
		return Vector2(half.x - distance, half.y)
	distance -= size.x
	return Vector2(-half.x, half.y - distance)

func _draw_air() -> void:
	var cooking := pot()
	var surface_y: float = FLOOR_Y_M + cooking.liquid_level_mm * MM_TO_M
	for emitter in [_steam, _smoke]:
		(emitter as GPUParticles3D).position.y = surface_y
	_steam.amount_ratio = clampf(cooking.steam_g_per_s / FULL_STEAM_G_PER_S, 0.0, 1.0)
	_steam.emitting = _steam.amount_ratio > 0.02
	_smoke.amount_ratio = cooking.smoke
	_smoke.emitting = cooking.smoke > 0.02
	var wind := Vector3(simulation.air.wind_mps, 0.0, simulation.air.wind_mps * 0.3) * 0.02
	for emitter in [_steam, _smoke]:
		var process := (emitter as GPUParticles3D).process_material as ParticleProcessMaterial
		if process:
			process.gravity = Vector3(wind.x, process.gravity.y, wind.z)

func _splash(world_point: Vector3, wet_g: float) -> void:
	var cooking := pot()
	if not cooking.has_pool() or cooking.medium.fat_fraction < 0.5 or cooking.temp_c < 120.0:
		return
	_spatter.global_position = Vector3(world_point.x, global_position.y + FLOOR_Y_M + cooking.liquid_level_mm * MM_TO_M, world_point.z)
	_spatter.amount_ratio = clampf(wet_g / 3.0, 0.15, 1.0) * clampf((cooking.temp_c - 120.0) / 60.0, 0.2, 1.0)
	_spatter.restart()
	_spatter.emitting = true

func _rim_plane() -> Plane:
	return Plane(Vector3.UP, global_position.y + RIM_Y_M)

func _on_spoon_pressed(point: Vector3) -> void:
	spoon_state = SpoonState.STIRRING
	_spoon_mm = to_pot_mm(point)
	_spoon_world = point

func _on_spoon_dragged(point: Vector3) -> void:
	_spoon_world = point
	var at_mm := to_pot_mm(point)
	match spoon_state:
		SpoonState.STIRRING:
			if at_mm.length() <= pot().vessel.interior_radius_mm() - 6.0:
				pot().stir(_spoon_mm, at_mm, STIR_REACH_MM)
				_spoon_mm = at_mm
			else:
				_lift()
		SpoonState.LIFTING:
			pass

func _on_spoon_released(point: Vector3) -> void:
	if spoon_state == SpoonState.LIFTING:
		var carried := lifted.duplicate()
		_clear_lifted()
		spoon_state = SpoonState.IDLE
		lifted_out.emit(carried, point)
	else:
		spoon_state = SpoonState.IDLE

func _on_spoon_cancelled() -> void:
	if spoon_state == SpoonState.LIFTING:
		var carried := lifted.duplicate()
		_clear_lifted()
		return_to_pot(carried)
	spoon_state = SpoonState.IDLE

## Brings up what the bowl is under, draining it into the air.
func _lift() -> void:
	spoon_state = SpoonState.LIFTING
	var footprint: float = 0.0
	for piece in pot().pieces_near(_spoon_mm, SPOON_REACH_MM):
		var area: float = piece.cross_section_mm2(Vector3.AXIS_Y)
		if footprint + area > SPOON_CAPACITY_MM2 and not lifted.is_empty():
			break
		footprint += area
		var placement := pot().placement_of(piece)
		var offset := Vector3((placement.centre_mm.x - _spoon_mm.x) * MM_TO_M, 0.0, (placement.centre_mm.y - _spoon_mm.y) * MM_TO_M)
		pot().remove_piece(piece)
		simulation.held.add_piece(piece)
		lifted.append(piece)
		var view := FoodPieceView.new(piece)
		_spoon.add_child(view)
		view.set_meta(&"offset", offset.limit_length(0.03))
		_lifted_views.append(view)

func _clear_lifted() -> void:
	for view in _lifted_views:
		view.queue_free()
	_lifted_views.clear()
	lifted.clear()

func _place_spoon(delta: float) -> void:
	var ease: float = 1.0 - exp(-VIEW_EASE * delta)
	if spoon_state == SpoonState.IDLE:
		_spoon.transform = _spoon.transform.interpolate_with(_spoon_home, ease)
		return
	var bowl_world := _spoon_world
	if spoon_state == SpoonState.STIRRING:
		bowl_world.y = global_position.y + FLOOR_Y_M + maxf(pot().liquid_level_mm * MM_TO_M, 0.01)
	else:
		bowl_world.y = global_position.y + RIM_Y_M + LIFT_HEIGHT_M
	# The handle reaches back towards the cook and up out of the pot.
	var bowl_local := to_local(bowl_world)
	# The spoon model runs along +X from the grip to the bowl.
	var x_axis := -Vector3(-0.35, 0.55, 0.75).normalized()
	var z_axis := x_axis.cross(Vector3.UP).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)
	var target := Transform3D(basis, bowl_local - x_axis * 0.28)
	_spoon.transform = _spoon.transform.interpolate_with(target, ease)
	for view in _lifted_views:
		var offset: Vector3 = view.get_meta(&"offset")
		var size: Vector3 = view.piece.size_mm * MM_TO_M
		view.global_transform = Transform3D(Basis.IDENTITY,
			global_transform * (bowl_local + offset - Vector3(size.x, 0.0, size.z) * 0.5 + Vector3(0.0, 0.004, 0.0)))

static func _foam_bubble_mesh() -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 1.0, 0.97, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = material
	return sphere
