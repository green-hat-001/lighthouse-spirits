extends Node

## Stages scenes in the real kitchen and saves a screenshot of each, from
## the station the player would be standing at:
##
##   godot --path . res://tools/godot/kitchen_shots.tscn -- <out_dir> [scenario ...]
##
## Every scenario drives the kitchen through the same calls the player's
## hands make (cutting, dressing, dropping into the pot), and the
## simulation runs for real, sped up, so what is shown is what the game
## would show. Needs a display (xvfb-run on a headless machine). With no
## scenarios it runs them all.

const SHOT_SIZE := Vector2i(1280, 720)
const SCENARIOS: Array[String] = ["board", "dressed", "fries", "pantry", "pass", "dum", "closeup"]

var kitchen: Kitchen

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://shots"
	var wanted: Array[String] = []
	for name in args.slice(1):
		wanted.append(name)
	if wanted.is_empty():
		wanted = SCENARIOS
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = SHOT_SIZE
	for scenario in wanted:
		await _stage(scenario)
		var path := out_dir.path_join("kitchen_%s.png" % scenario)
		await _settle_frames(6)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path)
		print("wrote ", path)
		kitchen.queue_free()
		await get_tree().process_frame
	get_tree().quit()

func _settle_frames(count: int) -> void:
	for _frame in count:
		await get_tree().process_frame

## A fresh kitchen with the camera at one station.
func _open(station: int) -> void:
	kitchen = (load("res://scenes/kitchen/kitchen.tscn") as PackedScene).instantiate()
	add_child(kitchen)
	await get_tree().process_frame
	kitchen.view_mode.mode = KitchenViewMode.Mode.AT_COUNTER
	kitchen.caretaker.control_enabled = false
	kitchen.counter_views.station_index = station
	kitchen.camera.global_transform = kitchen.counter_views.pose(0.0)
	kitchen.camera.fov = Kitchen.COUNTER_FOV_DEG

## Runs the kitchen's simulation for `seconds` of game time, quickly.
func _run(seconds: float) -> void:
	var step: float = 1.0 / 30.0
	var elapsed: float = 0.0
	while elapsed < seconds:
		kitchen.simulation.pot.advance(step)
		kitchen.simulation.board.advance(step)
		elapsed += step

## Moves the camera in close over a point, looking down at `pitch_deg`.
func _close_on(target: Vector3, distance_m: float, pitch_deg: float = 55.0) -> void:
	# The kitchen would glide the camera back to the station.
	kitchen.set_process(false)
	(kitchen.get_node("Hud") as CanvasLayer).visible = false
	var basis := Basis(Vector3.RIGHT, deg_to_rad(-pitch_deg))
	kitchen.camera.global_transform = Transform3D(basis, target + basis.z * distance_m)

func _ingredient(id: StringName) -> Ingredient:
	return IngredientCatalog.by_id(id)

func _stage(scenario: String) -> void:
	IngredientCatalog.ensure_loaded()
	match scenario:
		"board":
			await _open(1)
			for id: StringName in [&"potato", &"cliff_carrot", &"tide_leek", &"stonecap", &"chilli"]:
				kitchen.board.add_whole(_ingredient(id))
			var potato := kitchen.board.views()[0]
			var across := potato.position.z + potato.footprint_m().y * 0.5
			kitchen.board.cut_stroke(Vector3(potato.position.x - 0.02, 0.0, across),
				Vector3(potato.position.x + potato.footprint_m().x + 0.02, 0.0, across), true)
		"dressed":
			await _open(1)
			var bream := kitchen.board.add_whole(_ingredient(&"driftback_bream_whole"))
			kitchen.board.dress(bream)
		"fries":
			await _open(2)
			var pot := kitchen.simulation.pot
			pot.add_medium(kitchen.simulation.oil, 400.0, 180.0)
			kitchen.stove.set_knob(200.0)
			for stick in CookedPlates.cooked_sticks(_ingredient(&"potato"), 10.0, kitchen.simulation.oil, 180.0, 0.0):
				pot.add_piece(stick)
			_run(150.0)
		"pantry":
			await _open(1)
			kitchen.set_process(false)
			kitchen.camera.global_transform = kitchen.counter_views.pose(0.0, CounterViews.GLANCE_MAX_DEG)
		"pass":
			await _open(0)
			var plate := kitchen.plate
			var fries := CookedPlates.cooked_sticks(_ingredient(&"potato"), 10.0, kitchen.simulation.oil, 180.0, 360.0)
			plate.receive(fries.slice(0, 8), plate.global_position)
			var fillet := CookedPlates.cooked_whole(_ingredient(&"driftback_bream_fillet"), 1, kitchen.simulation.water, 95.0, 240.0)
			plate.receive(fillet, plate.global_position + Vector3(0.06, 0.0, 0.0))
		"dum":
			await _open(2)
			var pot := kitchen.simulation.pot
			pot.add_medium(kitchen.simulation.water, 800.0, 90.0)
			kitchen.stove.set_knob(60.0)
			var hide := FoodPiece.from_ingredient(_ingredient(&"gale_ram_hide"), 15.0)
			pot.cover_with(hide, true)
			_run(30.0)
		"closeup":
			await _open(1)
			var board := kitchen.board
			var origin := board.global_position
			var potato := board.add_whole(_ingredient(&"potato"))
			var mid := potato.position.x + potato.footprint_m().x * 0.5
			board.cut_stroke(Vector3(mid, 0.0, potato.position.z - 0.02), Vector3(mid, 0.0, potato.position.z + potato.footprint_m().y + 0.02), true)
			for stick in CookedPlates.cooked_sticks(_ingredient(&"potato"), 10.0, kitchen.simulation.oil, 180.0, 330.0).slice(0, 5):
				board.receive([stick], origin + Vector3(0.05, 0.0, 0.06))
			for stick in CookedPlates.cooked_sticks(_ingredient(&"potato"), 10.0, kitchen.simulation.oil, 180.0, 0.0).slice(0, 3):
				board.receive([stick], origin + Vector3(-0.1, 0.0, 0.07))
			_close_on(origin + Vector3(0.0, 0.0, 0.03), 0.32)
	await _settle_frames(4)
