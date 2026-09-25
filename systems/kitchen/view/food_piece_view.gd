class_name FoodPieceView
extends Node3D

## The on-screen body of one FoodPiece. Its origin is the piece's minimum
## corner resting on a surface, and it is never rotated: the piece's local
## axes stay the world's, so what the player sees and what the simulation
## cuts always agree. It reads appearance from the simulation every frame
## and never changes the piece itself.
##
## The box mesh stands in for the cut-piece kit (kitchen plan 6.3), which
## will be swapped in by nearest match on size.

const MM_TO_M: float = 0.001
const FOOD_SHADER: Shader = preload("res://shaders/food_cel.gdshader")
## Share of a cut piece's surface drawn as flesh rather than skin.
const CUT_FLESH_SHARE: float = 0.85

var piece: FoodPiece
var grip: Interactable

var _mesh_instance: MeshInstance3D
var _box: BoxMesh
var _shape: BoxShape3D
var _collision: CollisionShape3D
var _material: ShaderMaterial

func _init(p_piece: FoodPiece) -> void:
	piece = p_piece
	name = "FoodPiece_%s" % piece.ingredient.id

	_material = ShaderMaterial.new()
	_material.shader = FOOD_SHADER
	_material.set_shader_parameter("skin_color", piece.ingredient.tint_color)
	_material.set_shader_parameter("flesh_color", piece.ingredient.flesh_color)

	_box = BoxMesh.new()
	_box.material = _material
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Mesh"
	_mesh_instance.mesh = _box
	add_child(_mesh_instance)

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

## Call after the piece's size or orientation changes.
func refresh_shape() -> void:
	var size_m: Vector3 = piece.size_mm * MM_TO_M
	_box.size = size_m
	# Enough vertices for the crumble displacement to break up the edges.
	_box.subdivide_width = 2
	_box.subdivide_height = 2
	_box.subdivide_depth = 2
	_mesh_instance.position = size_m * 0.5
	_shape.size = size_m
	_collision.position = size_m * 0.5
	_material.set_shader_parameter("cut_share", 0.0 if piece.cut_axes.is_empty() else CUT_FLESH_SHARE)

func _process(_delta: float) -> void:
	var appearance := FoodPerception.appearance_of(piece)
	_material.set_shader_parameter("browning", appearance.browning)
	_material.set_shader_parameter("char_amount", appearance.charring)
	_material.set_shader_parameter("gloss", appearance.gloss)
	_material.set_shader_parameter("translucency", appearance.translucency)
	_material.set_shader_parameter("crumble", appearance.crumble)
