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

var piece: FoodPiece
var grip: Interactable

var _box_instance: MeshInstance3D
var _box: BoxMesh
var _shape: BoxShape3D
var _collision: CollisionShape3D
var _material: ShaderMaterial
var _model: Node3D
var _model_meshes: Array[MeshInstance3D] = []
var _model_basis: Basis = Basis.IDENTITY
var _model_wears_food_shader: bool = false

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
			_model.position = -bounds.position

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

func _process(_delta: float) -> void:
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
