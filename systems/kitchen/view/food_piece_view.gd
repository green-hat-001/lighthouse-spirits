class_name FoodPieceView
extends Node3D

## The on-screen body of one FoodPiece. Its origin is the piece's minimum
## corner resting on a surface, and the node itself is never rotated: the
## piece's local axes stay the world's, so what the player sees and what the
## simulation cuts always agree. It reads appearance from the simulation
## every frame and never changes the piece itself.
##
## A whole, uncut item is drawn with its ingredient's model, turned to match
## however it has been rolled, and wears its own materials until cooking
## starts to show. A cut piece is drawn as a box with the food shader - the
## stand-in for the cut-piece kit (kitchen plan 6.3).

const MM_TO_M: float = 0.001
const FOOD_SHADER: Shader = preload("res://shaders/food_cel.gdshader")
## Once a whole item browns, chars or cooks this much, its model switches
## to the food shader so the change shows.
const VISIBLE_COOKING: float = 0.02

## Hot, wet food out in the air gives off wisps of steam. Off in the pot,
## which draws its own.
const STEAM_FROM_C: float = 55.0
const STEAM_FULL_C: float = 95.0

## Glow strength at which awake essences throw light on what is around
## them, not only shine themselves.
const GLOW_LIGHT_FROM: float = 0.4
## How high food lifted beyond its weight hangs above what it rests on.
const MAX_HOVER_M: float = 0.025

var piece: FoodPiece
var grip: Interactable
var steams_in_air: bool = true
## Set by the owner when the piece rests on a surface it could rise off
## (the board, a plate), so lifting food hovers.
var may_hover: bool = true
## The view's height offset for hovering, eased by the view.
var hover_m: float = 0.0

var _glow_light: OmniLight3D

var _steam: GPUParticles3D

var _box_instance: MeshInstance3D
var _box: BoxMesh
var _shape: BoxShape3D
var _collision: CollisionShape3D
var _material: ShaderMaterial
var _model: Node3D
var _model_meshes: Array[MeshInstance3D] = []
var _model_basis: Basis = Basis.IDENTITY
var _model_wears_food_shader: bool = false
var _model_rest: Vector3 = Vector3.ZERO

func _init(p_piece: FoodPiece) -> void:
	piece = p_piece
	name = "FoodPiece_%s" % piece.ingredient.id

	_material = ShaderMaterial.new()
	_material.shader = FOOD_SHADER
	_material.set_shader_parameter("skin_color", piece.ingredient.tint_color)
	_material.set_shader_parameter("flesh_color", piece.ingredient.flesh_color)

	_box = BoxMesh.new()
	_box.material = _material
	_box.subdivide_width = 2
	_box.subdivide_height = 2
	_box.subdivide_depth = 2
	_box_instance = MeshInstance3D.new()
	_box_instance.name = "Box"
	_box_instance.mesh = _box
	add_child(_box_instance)

	if piece.cut_axes.is_empty() and piece.ingredient.whole_model:
		_model = piece.ingredient.whole_model.instantiate()
		_model.name = "Model"
		add_child(_model)
		for mesh in _model.find_children("*", "MeshInstance3D", true, false):
			_model_meshes.append(mesh)

	grip = Interactable.new()
	grip.name = "Grip"
	_shape = BoxShape3D.new()
	_collision = CollisionShape3D.new()
	_collision.shape = _shape
	grip.add_child(_collision)
	add_child(grip)
	refresh_shape()

## Size in metres on the board surface, as Vector2(x, z).
func footprint_m() -> Vector2:
	return Vector2(piece.size_mm.x, piece.size_mm.z) * MM_TO_M

## Turns the whole-item model with the piece after FoodPiece.roll().
func rolled_about(axis: int) -> void:
	var around := Vector3.ZERO
	around[axis] = 1.0
	_model_basis = Basis(around, PI * 0.5) * _model_basis
	refresh_shape()

## Call after the piece's size or orientation changes.
func refresh_shape() -> void:
	var size_m: Vector3 = piece.size_mm * MM_TO_M
	_box.size = size_m
	_box_instance.position = size_m * 0.5
	_shape.size = size_m
	_collision.position = size_m * 0.5

	var show_model: bool = _model != null and piece.cut_axes.is_empty()
	_box_instance.visible = not show_model
	if _model:
		_model.visible = show_model
		if show_model:
			# The model's origin is the centre of its base; seat its turned
			# bounds exactly in the piece's box.
			_model.transform = Transform3D(_model_basis, Vector3.ZERO)
			var bounds := _model_bounds()
			_model_rest = -bounds.position
			_model.position = _model_rest

## Glow and hover, from the essences awake in the piece.
func _draw_essences(delta: float) -> void:
	var glow := TraitEffects.glow(piece)
	_material.set_shader_parameter("glow_energy", glow.a * 1.5)
	if glow.a > 0.0:
		_material.set_shader_parameter("glow_color", Color(glow.r, glow.g, glow.b))
	if glow.a >= GLOW_LIGHT_FROM:
		if _glow_light == null:
			_glow_light = OmniLight3D.new()
			_glow_light.shadow_enabled = false
			_glow_light.omni_range = 0.25
			add_child(_glow_light)
		_glow_light.light_color = Color(glow.r, glow.g, glow.b)
		_glow_light.light_energy = clampf(glow.a, 0.0, 2.0) * 0.6
		_glow_light.position = piece.size_mm * MM_TO_M * 0.5
	elif _glow_light:
		_glow_light.queue_free()
		_glow_light = null
	var lift: float = TraitEffects.lift_share(piece) if may_hover else 0.0
	var target: float = clampf(lift - 1.0, 0.0, 1.0) * MAX_HOVER_M
	if target > 0.0:
		target += sin(Time.get_ticks_msec() * 0.002 + piece.size_mm.x) * 0.002
	hover_m = lerpf(hover_m, target, 1.0 - exp(-3.0 * delta))
	var lifted := Vector3(0.0, hover_m, 0.0)
	_box_instance.position = piece.size_mm * MM_TO_M * 0.5 + lifted
	if _model and _model.visible:
		_model.position = _model_rest + lifted

func _draw_steam() -> void:
	var heat: float = clampf((piece.surface_temp_c - STEAM_FROM_C) / (STEAM_FULL_C - STEAM_FROM_C), 0.0, 1.0)
	var strength: float = heat * (1.0 - piece.surface_dryness() * 0.7) if steams_in_air else 0.0
	if strength <= 0.02:
		if _steam:
			_steam.emitting = false
		return
	if _steam == null:
		_steam = _make_steam()
		add_child(_steam)
	_steam.position = piece.size_mm * MM_TO_M * Vector3(0.5, 1.0, 0.5)
	_steam.amount_ratio = strength
	_steam.emitting = true

static func _make_steam() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Steam"
	particles.amount = 6
	particles.lifetime = 1.6
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.01, 0.001, 0.005)
	process.direction = Vector3.UP
	process.spread = 10.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.05
	process.gravity = Vector3(0.01, 0.03, 0.0)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0)])
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture
	process.scale_min = 0.5
	process.scale_max = 1.0
	particles.process_material = process
	var soft := Gradient.new()
	soft.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var soft_texture := GradientTexture2D.new()
	soft_texture.gradient = soft
	soft_texture.fill = GradientTexture2D.FILL_RADIAL
	soft_texture.fill_from = Vector2(0.5, 0.5)
	soft_texture.fill_to = Vector2(1.0, 0.5)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = soft_texture
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	quad.material = material
	particles.draw_pass_1 = quad
	particles.visibility_aabb = AABB(Vector3(-0.2, -0.05, -0.2), Vector3(0.4, 0.5, 0.4))
	return particles

## Hands one per-face value to the shader as its (+X, +Y, +Z) and
## (-X, -Y, -Z) pair.
func _set_faces(name: String, values: PackedFloat64Array) -> void:
	_material.set_shader_parameter(name + "_pos", Vector3(values[FoodPiece.Face.POS_X], values[FoodPiece.Face.POS_Y], values[FoodPiece.Face.POS_Z]))
	_material.set_shader_parameter(name + "_neg", Vector3(values[FoodPiece.Face.NEG_X], values[FoodPiece.Face.NEG_Y], values[FoodPiece.Face.NEG_Z]))

## The model's bounds in this view's space, with its current turn applied.
func _model_bounds() -> AABB:
	var turn := Transform3D(_model_basis, Vector3.ZERO)
	var bounds := AABB()
	for index in _model_meshes.size():
		var mesh := _model_meshes[index]
		var to_model := Transform3D.IDENTITY
		var node: Node = mesh
		while node != _model:
			to_model = (node as Node3D).transform * to_model
			node = node.get_parent()
		var local: AABB = turn * to_model * mesh.get_aabb()
		bounds = local if index == 0 else bounds.merge(local)
	return bounds

func _process(delta: float) -> void:
	_draw_steam()
	_draw_essences(delta)
	var appearance := FoodPerception.appearance_of(piece)
	_set_faces("browning", appearance.face_browning)
	_set_faces("char", appearance.face_char)
	_set_faces("skin", appearance.face_skin)
	_set_faces("wet", appearance.face_wetness)
	_material.set_shader_parameter("gloss", appearance.gloss)
	_material.set_shader_parameter("translucency", appearance.translucency)
	_material.set_shader_parameter("crumble", appearance.crumble)
	if _model and not _model_wears_food_shader \
			and maxf(appearance.browning, maxf(appearance.charring, piece.core_doneness)) > VISIBLE_COOKING:
		_model_wears_food_shader = true
		for mesh in _model_meshes:
			mesh.material_override = _material
