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
## The spring moved food catches up on, and how far it leans (radians per
## m/s of motion, at most MAX_TILT_RAD) while it does.
const LAG_HZ: float = 6.5
const LAG_DAMPING: float = 0.62
const TILT_PER_MPS: float = 0.9
const MAX_TILT_RAD: float = 0.35
## How hard landing squashes food, and the spring it recovers on.
const LANDING_SQUASH: float = 0.8
const SQUASH_HZ: float = 5.0
const SQUASH_DAMPING: float = 0.35
const MOTION_STEP_S: float = 1.0 / 240.0
## Spice stuck to food shows as flecks: this many to the gram, up to a
## limit, each about this big.
const FLECKS_PER_G: float = 160.0
const MAX_FLECKS: int = 160
const FLECK_M: float = 0.0011

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

var _top: Node3D
## Everything drawn of the food, under one node the motion can lean, lag
## and squash without moving the piece itself.
var _visual: Node3D
## How far the drawn food trails where the piece really is (it was just
## moved there), and how fast that is closing.
var _lag: Vector3 = Vector3.ZERO
var _lag_velocity: Vector3 = Vector3.ZERO
## 1 at rest; below 1 for a moment as the food lands and squashes.
var _squash: float = 1.0
var _squash_velocity: float = 0.0
var _flecks: MultiMeshInstance3D
var _flecks_drawn_g: float = 0.0
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
## The model hangs from the top of the box instead of resting on its floor.
var _hangs: bool = false
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
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_visual.add_child(_body)

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
		_visual.add_child(_heap)
	elif piece.cut_axes.is_empty() and piece.ingredient.whole_model:
		_model = piece.ingredient.whole_model.instantiate()
		_model.name = "Model"
		_visual.add_child(_model)
		for mesh in _model.find_children("*", "MeshInstance3D", true, false):
			_model_meshes.append(mesh)
			_wear_food_shader(mesh)

	grip = Interactable.new()
	grip.name = "Grip"
	# The hand takes food from above, by its top.
	_top = Node3D.new()
	_top.name = "Top"
	add_child(_top)
	grip.hand_anchor = _top
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

## Draws the uncut item with another model of it - a covering draped over
## a rim - its top level with the top of the piece's box, so it hangs below.
func wear_model(scene: PackedScene) -> void:
	if _model:
		_model.queue_free()
	_model_meshes.clear()
	_model = scene.instantiate()
	_model.name = "Model"
	_visual.add_child(_model)
	for mesh in _model.find_children("*", "MeshInstance3D", true, false):
		_model_meshes.append(mesh)
		_wear_food_shader(mesh)
	_hangs = true
	refresh_shape()

## Moves the piece to `local_position` (in its parent's space) straight
## away, as far as the simulation is concerned, while what is drawn
## follows on a spring: carried food trails the hand and sways, and food
## set down drops into place.
func move_to(local_position: Vector3) -> void:
	_lag -= local_position - position
	position = local_position

## The food arrives from `height_m` above where it is, and drops into
## place.
func drop_from(height_m: float) -> void:
	_lag.y += height_m

## The food lands: it squashes and springs back.
func land() -> void:
	_squash = minf(_squash, LANDING_SQUASH)

## How far what is drawn trails the piece itself.
func lag() -> Vector3:
	return _lag

## Call after the piece's size or orientation changes.
func refresh_shape() -> void:
	var size_m: Vector3 = piece.bulk_size_mm() * MM_TO_M
	_top.position = Vector3(size_m.x * 0.5, size_m.y + 0.004, size_m.z * 0.5)
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
			if _hangs:
				_model_rest.y = size_m.y - bounds.end.y
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

## Springs the drawn food back onto the piece, leaning it into its motion
## about the middle of its base, and squashing it when it lands.
func _animate(delta: float) -> void:
	if _lag.is_zero_approx() and _lag_velocity.is_zero_approx() and is_equal_approx(_squash, 1.0) and absf(_squash_velocity) < 0.001:
		_visual.transform = Transform3D.IDENTITY
		return
	var steps: int = clampi(ceili(delta / MOTION_STEP_S), 1, 16)
	var step: float = minf(delta, MOTION_STEP_S * 16.0) / steps
	var omega: float = TAU * LAG_HZ
	var squash_omega: float = TAU * SQUASH_HZ
	var was_above: bool = _lag.y > 0.0
	for _index in steps:
		_lag_velocity += (-_lag * omega * omega - _lag_velocity * 2.0 * LAG_DAMPING * omega) * step
		_lag += _lag_velocity * step
		_squash_velocity += ((1.0 - _squash) * squash_omega * squash_omega - _squash_velocity * 2.0 * SQUASH_DAMPING * squash_omega) * step
		_squash += _squash_velocity * step
	# Dropped food that reaches the surface lands on it.
	if was_above and _lag.y <= 0.0 and _lag_velocity.y < -0.2:
		land()
		_lag.y = 0.0
		_lag_velocity.y = 0.0
	if _lag.length() < 0.0002 and _lag_velocity.length() < 0.002:
		_lag = Vector3.ZERO
		_lag_velocity = Vector3.ZERO
	var size: Vector3 = piece.bulk_size_mm() * MM_TO_M
	var base := Vector3(size.x * 0.5, 0.0, size.z * 0.5)
	# The drawn food trails the motion, so it leans back from the way it is
	# being pulled.
	var tilt_x: float = clampf(_lag_velocity.z * TILT_PER_MPS, -MAX_TILT_RAD, MAX_TILT_RAD)
	var tilt_z: float = clampf(-_lag_velocity.x * TILT_PER_MPS, -MAX_TILT_RAD, MAX_TILT_RAD)
	var spread: float = 1.0 / sqrt(maxf(_squash, 0.3))
	var shape := Basis(Vector3.RIGHT, tilt_x) * Basis(Vector3.BACK, tilt_z) * Basis.from_scale(Vector3(spread, _squash, spread))
	_visual.transform = Transform3D(shape, base - shape * base + _lag)

## Scatters flecks of every spice stuck to the piece over its top and,
## more sparsely, its sides - the same way each time for the same piece.
func _draw_flecks() -> void:
	var total: float = 0.0
	for spice in piece.spices:
		total += piece.spices[spice]
	if is_equal_approx(total, _flecks_drawn_g) and (_flecks != null or total <= 0.0):
		return
	_flecks_drawn_g = total
	if _flecks == null:
		_flecks = MultiMeshInstance3D.new()
		_flecks.name = "Flecks"
		var grain := MultiMesh.new()
		grain.transform_format = MultiMesh.TRANSFORM_3D
		grain.use_colors = true
		var fleck := BoxMesh.new()
		fleck.size = Vector3(FLECK_M, FLECK_M * 0.4, FLECK_M)
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		fleck.material = material
		grain.mesh = fleck
		grain.instance_count = MAX_FLECKS
		_flecks.multimesh = grain
		_visual.add_child(_flecks)
	var size: Vector3 = piece.bulk_size_mm() * MM_TO_M
	var drawn: int = 0
	var seed: int = 0
	for spice in piece.spices:
		var count: int = mini(ceili(piece.spices[spice] * FLECKS_PER_G), MAX_FLECKS - drawn)
		for index in count:
			seed += 1
			var a: float = fmod(seed * 0.618034 + _pattern_offset.x, 1.0)
			var b: float = fmod(seed * 0.414214 + _pattern_offset.z, 1.0)
			var spot := Vector3(lerpf(0.12, 0.88, a) * size.x, size.y + FLECK_M * 0.1, lerpf(0.12, 0.88, b) * size.z)
			var turn := Basis(Vector3.UP, seed * 2.4)
			_flecks.multimesh.set_instance_transform(drawn, Transform3D(turn, spot))
			_flecks.multimesh.set_instance_color(drawn, spice.tint_color.darkened(fmod(seed * 0.37, 0.25)))
			drawn += 1
	_flecks.multimesh.visible_instance_count = drawn

func _process(delta: float) -> void:
	_animate(delta)
	_draw_flecks()
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
