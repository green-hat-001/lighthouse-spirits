extends SceneTree

## Renders a contact sheet of model scenes through the game's own import and
## toon look, for checking the larder by eye:
##
##   godot --path . -s res://tools/godot/larder_sheet.gd -- <out.png> [folder_or_glb ...]
##
## With no paths it shows every ingredient's whole_model. Each model is scaled
## to fit its cell and labelled with its name and true size. Needs a display
## (run under xvfb-run on a headless machine).

const CELL_M: float = 1.0
const COLUMNS: int = 8
const WIDTH_PX: int = 2400

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://larder_sheet.png"
	var scenes: Array[PackedScene] = []
	var names: Array[String] = []
	if args.size() > 1:
		for path in args.slice(1):
			_collect(path, scenes, names)
	else:
		IngredientCatalog.ensure_loaded()
		for ingredient in IngredientCatalog.all():
			if ingredient.whole_model:
				scenes.append(ingredient.whole_model)
				names.append(String(ingredient.id))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(WIDTH_PX, int(WIDTH_PX / float(COLUMNS) * 2.0 * 0.5) * ceili(float(scenes.size()) / COLUMNS) + 40)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	_build(viewport, scenes, names)
	for _frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png(out)
	print("wrote %s (%d models)" % [out, scenes.size()])
	quit()

func _collect(path: String, scenes: Array[PackedScene], names: Array[String]) -> void:
	if path.ends_with(".glb"):
		scenes.append(load(path))
		names.append(path.get_file().get_basename())
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".glb"):
			_collect(path.path_join(file), scenes, names)
	for sub in dir.get_directories():
		_collect(path.path_join(sub), scenes, names)

func _build(viewport: SubViewport, scenes: Array[PackedScene], names: Array[String]) -> void:
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.86, 0.84, 0.78)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	environment.ambient_light_energy = 0.25
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 1.4
	var holder := WorldEnvironment.new()
	holder.environment = environment
	world.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	world.add_child(sun)

	var rows: int = ceili(float(scenes.size()) / COLUMNS)
	for index in scenes.size():
		var model: Node3D = scenes[index].instantiate()
		var cell := Node3D.new()
		world.add_child(cell)
		cell.add_child(model)
		var bounds := _bounds(model)
		var longest: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		var fit: float = CELL_M * 0.8 / maxf(longest, 0.0001)
		model.scale = Vector3.ONE * fit
		model.position = -(bounds.position + bounds.size * 0.5) * fit + Vector3(0, bounds.size.y * 0.5 * fit, 0)
		cell.position = Vector3((index % COLUMNS) * CELL_M * 1.15, 0.0, (index / COLUMNS) * CELL_M * 2.0)
		var label := Label3D.new()
		label.text = "%s\n%d x %d x %d mm" % [names[index], roundi(bounds.size.x * 1000), roundi(bounds.size.y * 1000), roundi(bounds.size.z * 1000)]
		label.font_size = 36
		label.pixel_size = 0.0025
		label.modulate = Color(0.15, 0.13, 0.12)
		label.outline_size = 0
		label.rotation_degrees = Vector3(-60, 0, 0)
		label.position = Vector3(0, 0.01, CELL_M * 0.52)
		cell.add_child(label)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var width: float = COLUMNS * CELL_M * 1.15
	camera.size = width * float(viewport.size.y) / viewport.size.x * 1.02
	camera.rotation_degrees = Vector3(-35, 0, 0)
	var centre := Vector3((COLUMNS - 1) * CELL_M * 1.15 * 0.5, 0.0, (rows - 1) * CELL_M * 2.0 * 0.5)
	camera.position = centre + camera.basis.z * 20.0
	world.add_child(camera)
	camera.make_current()

func _bounds(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var to_root := Transform3D.IDENTITY
		var walk: Node = mesh
		while walk != node:
			to_root = (walk as Node3D).transform * to_root
			walk = walk.get_parent()
		var box: AABB = to_root * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
