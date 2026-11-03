class_name FoodPieceView
extends Node3D

## The on-screen body of one FoodPiece. Its origin is the piece's minimum
## corner resting on a surface, and the node itself is never rotated: the
## piece's local axes stay the world's, so what the player sees and what the
## simulation cuts always agree. It reads appearance from the simulation
## every frame and never changes the piece itself.
##
## A whole, uncut item is drawn with its ingredient's model, turned to match
## however it has been rolled. A cut piece is drawn with a mesh built for its
## own size and skin (FoodPieceMesh). Both wear the food shader from the
## start - one material per surface of a model, each keeping that surface's
## colour - so cooking shows the moment it begins. A heap of grain or spice
## is its kernel model, instanced.

const MM_TO_M: float = 0.001
const FOOD_SHADER: Shader = preload("res://shaders/food_cel.gdshader")
## A cut piece's mesh is rebuilt once the piece has shrunk or swollen this
## much since it was built; smaller changes just scale it.
const REBUILD_DRIFT: float = 0.04

## Hot, wet food out in the air gives off wisps of steam. Off in the pot,
## which draws its own.
const STEAM_FROM_C: float = 55.0
const STEAM_FULL_C: float = 95.0

## Glow strength at which awake essences throw light on what is around
## them, not only shine themselves.
const GLOW_LIGHT_FROM: float = 0.4
## How high food lifted beyond its weight hangs above what it rests on.
const MAX_HOVER_M: float = 0.025
## The most kernels of a heap drawn one by one.
const MAX_KERNELS_DRAWN: int = 400

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

var _body: MeshInstance3D
var _built_size_mm: Vector3 = Vector3.ZERO
var _built_skin := PackedFloat64Array()
var _shape: BoxShape3D
var _collision: CollisionShape3D
var _material: ShaderMaterial
## Every food material this view drives: the cut body's, and one per
## surface of a whole model.
var _materials: Array[ShaderMaterial] = []
var _look: FoodLook
## Where in its pattern this piece sits, so neighbouring pieces differ.
var _pattern_offset := Vector3(randf(), randf(), randf())
var _model: Node3D
var _model_meshes: Array[MeshInstance3D] = []
var _model_basis: Basis = Basis.IDENTITY
var _model_rest: Vector3 = Vector3.ZERO
var _heap: MultiMeshInstance3D
var _heap_laid_size: Vector3 = Vector3.ZERO

func _init(p_piece: FoodPiece) -> void:
	piece = p_piece
	name = "FoodPiece_%s" % piece.ingredient.id

	_look = FoodLook.of(piece.ingredient)
	_material = _food_material(piece.ingredient.tint_color, false)
	_material.set_shader_parameter("vertex_data", true)

	_body = MeshInstance3D.new()
	_body.name = "Body"
	_body.material_override = _material
	add_child(_body)

	if piece.is_heap():
		_heap = MultiMeshInstance3D.new()
		_heap.name = "Heap"
		var kernels := MultiMesh.new()
		kernels.transform_format = MultiMesh.TRANSFORM_3D
		var kernel_mesh: Mesh = _kernel_mesh()
		if kernel_mesh:
			_heap.material_override = _food_material(piece.ingredient.tint_color, true)
		else:
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			kernel_mesh = box
			_heap.material_override = _material
		kernels.mesh = kernel_mesh
		kernels.instance_count = mini(piece.count, MAX_KERNELS_DRAWN)
		_heap.multimesh = kernels
		add_child(_heap)
	elif piece.cut_axes.is_empty() and piece.ingredient.whole_model:
		_model = piece.ingredient.whole_model.instantiate()
		_model.name = "Model"
		add_child(_model)
		for mesh in _model.find_children("*", "MeshInstance3D", true, false):
			_model_meshes.append(mesh)
			_wear_food_shader(mesh)

	grip = Interactable.new()
	grip.name = "Grip"
	_shape = BoxShape3D.new()
	_collision = CollisionShape3D.new()
	_collision.shape = _shape
	grip.add_child(_collision)
	add_child(grip)
	refresh_shape()

## Size in metres on the board surface, as Vector2(x, z) - for a heap of
## grain, the layer its kernels make.
func footprint_m() -> Vector2:
	var size := piece.bulk_size_mm()
	return Vector2(size.x, size.z) * MM_TO_M

## Turns the whole-item model with the piece after FoodPiece.roll().
func rolled_about(axis: int) -> void:
	var around := Vector3.ZERO
	around[axis] = 1.0
	_model_basis = Basis(around, PI * 0.5) * _model_basis
	refresh_shape()

## Call after the piece's size or orientation changes.
func refresh_shape() -> void:
	var size_m: Vector3 = piece.bulk_size_mm() * MM_TO_M
	_shape.size = size_m
	_collision.position = size_m * 0.5
	if _heap:
		_body.visible = false
		_lay_kernels()
		return

	var show_model: bool = _model != null and piece.cut_axes.is_empty()
	_body.visible = not show_model
	if _body.visible:
		_rebuild_body()
	if _model:
		_model.visible = show_model
		if show_model:
			# The model's origin is the centre of its base; seat its turned
			# bounds exactly in the piece's box.
			_model.transform = Transform3D(_model_basis, Vector3.ZERO)
			var bounds := _model_bounds()
			_model_rest = -bounds.position
			_model.position = _model_rest

## A food material in the ingredient's colours. `painted` reads a model's
## vertex-colour shading.
func _food_material(skin_color: Color, painted: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FOOD_SHADER
	material.set_shader_parameter("skin_color", skin_color)
	material.set_shader_parameter("flesh_color", piece.ingredient.flesh_color)
	material.set_shader_parameter("vertex_tint", painted)
	material.set_shader_parameter("pattern", _look.pattern)
	material.set_shader_parameter("pattern_color", _look.pattern_color)
	material.set_shader_parameter("pattern_strength", _look.pattern_strength)
	material.set_shader_parameter("pattern_size", _look.pattern_size_mm * MM_TO_M)
	material.set_shader_parameter("crust_blister", _look.crust_blister)
	material.set_shader_parameter("pattern_offset", _pattern_offset)
	_materials.append(material)
	return material

## Gives every surface of a whole model its own food material in that
## surface's colour, so a fish's fins and eyes stay theirs as it cooks.
func _wear_food_shader(mesh: MeshInstance3D) -> void:
	for surface in mesh.mesh.get_surface_count():
		var original := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
		var colour: Color = original.albedo_color if original else piece.ingredient.tint_color
		mesh.set_surface_override_material(surface, _food_material(colour, true))

## The kernel model's mesh for a heap, if the ingredient has one.
func _kernel_mesh() -> Mesh:
	if piece.ingredient.whole_model == null:
		return null
	var scene: Node = piece.ingredient.whole_model.instantiate()
	var found: Array[Node] = scene.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (found[0] as MeshInstance3D).mesh if not found.is_empty() else null
	scene.free()
	return mesh

## Builds the cut body for the piece as it is now, or rescales the last
## one if the piece has only shrunk or swollen a little.
func _rebuild_body() -> void:
	var size: Vector3 = piece.size_mm
	var drift: float = 0.0
	for axis in 3:
		if _built_size_mm[axis] <= 0.0:
			drift = INF
			break
		drift = maxf(drift, absf(size[axis] / _built_size_mm[axis] - 1.0))
	if drift > REBUILD_DRIFT or _built_skin != piece.face_skin:
		_body.mesh = FoodPieceMesh.build(size, piece.face_skin, _look)
		_built_size_mm = size
		_built_skin = piece.face_skin.duplicate()
	_body.scale = Vector3(size.x / _built_size_mm.x, size.y / _built_size_mm.y, size.z / _built_size_mm.z)
	_material.set_shader_parameter("piece_size", _built_size_mm * MM_TO_M)

## Scatters the drawn kernels through the heap's layer, the same way each
## time for the same heap.
func _lay_kernels() -> void:
	var bulk: Vector3 = piece.bulk_size_mm() * MM_TO_M
	var kernel: Vector3 = piece.size_mm * MM_TO_M
	var drawn: int = _heap.multimesh.instance_count
	var layers: float = maxf(bulk.y / maxf(kernel.y, 0.0001), 1.0)
	for index in drawn:
		var a: float = fmod(index * 0.618034, 1.0)
		var b: float = fmod(index * 0.414214, 1.0)
		var c: float = fmod(index * 0.732051, 1.0)
		# Kernels pile higher in the middle of the heap.
		var centred := Vector2(a - 0.5, b - 0.5)
		var height: float = floor(c * layers * (1.0 - centred.length())) * kernel.y
		var turn := Basis(Vector3.UP, index * 2.4)
		var spot := Vector3(a * (bulk.x - kernel.x) + kernel.x * 0.5, height, b * (bulk.z - kernel.z) + kernel.z * 0.5)
		_heap.multimesh.set_instance_transform(index, Transform3D(turn * Basis.from_scale(_kernel_scale(kernel)), spot))
	_heap_laid_size = piece.size_mm

## The scale that takes a kernel's mesh to a kernel of `kernel` metres: a
## kernel model is at the ingredient's whole size, with its origin at the
## centre of its base; the stand-in box is a unit cube about its centre.
func _kernel_scale(kernel: Vector3) -> Vector3:
	if piece.ingredient.whole_model == null:
		return kernel
	var native: Vector3 = piece.ingredient.whole_size_mm * MM_TO_M
	return Vector3(kernel.x / maxf(native.x, 1e-6), kernel.y / maxf(native.y, 1e-6), kernel.z / maxf(native.z, 1e-6))

## Glow and hover, from the essences awake in the piece.
func _draw_essences(delta: float) -> void:
	var glow := TraitEffects.glow(piece)
	_set_all("glow_energy", glow.a * 1.5)
	if glow.a > 0.0:
		_set_all("glow_color", Color(glow.r, glow.g, glow.b))
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
	_body.position = lifted
	if _heap:
		_heap.position = lifted
		# Swelling grain grows its heap.
		if not piece.size_mm.is_equal_approx(_heap_laid_size):
			refresh_shape()
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
	_set_all(name + "_pos", Vector3(values[FoodPiece.Face.POS_X], values[FoodPiece.Face.POS_Y], values[FoodPiece.Face.POS_Z]))
	_set_all(name + "_neg", Vector3(values[FoodPiece.Face.NEG_X], values[FoodPiece.Face.NEG_Y], values[FoodPiece.Face.NEG_Z]))

func _set_all(name: String, value: Variant) -> void:
	for material in _materials:
		material.set_shader_parameter(name, value)

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
	_set_all("gloss", appearance.gloss)
	_set_all("translucency", appearance.translucency)
	_set_all("crumble", appearance.crumble)
	_set_all("curl", _look.curl_when_cooked * clampf(piece.core_doneness, 0.0, 1.0))
	if _body.visible and not piece.size_mm.is_equal_approx(_built_size_mm * _body.scale):
		_rebuild_body()
