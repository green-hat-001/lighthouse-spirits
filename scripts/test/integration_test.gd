extends Node3D

## Automated headless integration test for the full pipeline:
##   kitchen food -> Dish -> DishNourishment -> DishServingStation
##   -> SpiritEventBus -> Spirit FSM -> light awarded back to the lighthouse
##
## Run with:
##   godot --headless --path . res://scenes/integration_test.tscn
##
## After adding or renaming any script that declares a class_name, run an
## editor pass FIRST or every reference to the new type fails to parse - the
## global class cache is only rebuilt by the editor, not by a headless run:
##   godot --headless --editor --quit --path .
##
## Exits with code 0 on pass, 1 on failure, so it can be wired into CI.

const SPIRIT_SCENE: PackedScene = preload("res://scenes/spirit.tscn")
const TEST_ARCHETYPE: SpiritArchetype = preload("res://data/archetypes/example_spirit_basic.tres")

const SEA_KELP: Ingredient = preload("res://data/ingredients/sea_kelp.tres")
const TIDE_POOL_CLAM: Ingredient = preload("res://data/ingredients/tide_pool_clam.tres")
const CLIFF_GARDEN_HERB: Ingredient = preload("res://data/ingredients/cliff_garden_herb.tres")

const KITCHEN_INGREDIENTS: Array[Ingredient] = [
	preload("res://data/ingredients/potato.tres"),
	preload("res://data/ingredients/chilli.tres"),
	preload("res://data/ingredients/sunflower_seeds.tres"),
	preload("res://data/ingredients/water.tres"),
	preload("res://data/ingredients/sunflower_oil.tres"),
	preload("res://data/ingredients/sunflower_seed_cake.tres"),
]
const STARTING_EQUIPMENT: Array[KitchenEquipment] = [
	preload("res://data/equipment/gas_stove.tres"),
	preload("res://data/equipment/pot.tres"),
	preload("res://data/equipment/oil_press.tres"),
]
const AMBIENT_TEMP_C: float = 15.0

const STATE_NAMES: Array[String] = [
	"ARRIVING", "SEEKING", "WAITING", "FED", "ASCENDING", "DISTRESSED", "DEPARTED"
]

const TIME_SCALE: float = 10.0
const FEED_INTERVAL: float = 0.2
# In game-time seconds (deltas are scaled by TIME_SCALE). The slowest path is
# the neglected spirit: ~0.5s travel + 1.5s settle + 25s patience + 10s
# recovery + 1s despawn, so this leaves generous headroom.
const SAFETY_TIMEOUT: float = 90.0
const EPSILON: float = 0.001

var _serving_station := DishServingStation.new()
## The plate served to the fed spirit, cooked once and copied per serving.
var _tide_plate: Array[FoodPiece] = []

var _fed_spirit: SpiritController
var _neglected_spirit: SpiritController

var _fed_transitions: Array[String] = []
var _neglected_transitions: Array[String] = []
var _fed_outcome: String = ""
var _neglected_outcome: String = ""
var _feed_count: int = 0
var _ascended_count: int = 0
var _departed_unfed_count: int = 0
var _feed_cooldown: float = 0.0
var _elapsed: float = 0.0
var _finished: bool = false
var _tested_locked_rejection: bool = false

var _failures: Array[String] = []
var _checks_run: int = 0

func _ready() -> void:
	Engine.time_scale = TIME_SCALE

	LighthouseProgression.reset()
	_tide_plate = _tide_plate_pieces()
	_test_serving_math()
	_test_dominant_affinity()
	_test_ingredient_validation()
	_test_flavour_mixing()
	_test_food_piece_creation()
	_test_cutting_into_sticks()
	_test_unsteadied_cross_cuts()
	_test_cut_limits_and_thin_slices()
	_test_cut_exposes_fresh_surface()
	_test_burner_power()
	_test_pot_heats_and_cools()
	_test_batch_draws_heat_from_oil()
	_test_water_boils_away_at_its_boiling_point()
	_test_thin_pieces_cook_through_first()
	_test_frying_temperature_shapes_the_fry()
	_test_boiling_softens_and_never_browns()
	_test_thin_slice_heating_is_stable()
	_test_simulation_ignores_frame_rate()
	_test_faces_cook_independently()
	_test_cut_faces_are_flesh()
	_test_rolling_turns_faces()
	_test_food_dries_and_cools_in_the_wind()
	_test_resting_fries_cook_on_and_go_limp()
	_test_shallow_fry_browns_underneath()
	_test_the_middle_of_the_base_is_hottest()
	_test_buoyancy_and_displacement()
	_test_frying_oil_wears_out()
	_test_wind_slows_the_pot()
	_test_open_water_evaporates()
	_test_spoon_stirs_and_finds_food()
	_test_full_pot_runs_in_real_time()
	_test_trait_activation()
	_test_lifting_food_floats_and_hovers()
	_test_ember_and_frost()
	_test_char_ward_and_bloom()
	_test_essence_infuses_broth()
	_test_essences_reach_spirits()
	_test_shipped_transformations_validate()
	_test_transformation_validation()
	_test_press_turns_work_into_oil()
	_test_chilli_infuses_oil()
	_test_flavour_follows_solubility()
	_test_fried_food_picks_up_flavoured_oil()
	_test_equipment_gating()
	_test_texture_reads_physical_state()
	_test_appearance_reads_physical_state()
	_test_bite_sounds()
	_test_dish_fingerprints()
	_test_dish_nourishment()
	_test_synthesised_sounds()
	_test_rolling_a_piece()
	_test_mezzaluna_gesture()
	_test_kitchen_input_actions()
	_test_kitchen_board_wiring()
	_test_view_mode_transitions()
	_test_counter_reach()
	_test_peek_mapping()
	_test_mouse_is_always_locked()
	_test_progression_economy()
	_test_progression_unlocks()
	_test_progression_persistence()

	# Progression tests above leave upgrades purchased; start the lifecycle
	# run from a clean lighthouse so station multipliers are back to 1.0.
	LighthouseProgression.reset()

	SpiritEventBus.spirit_state_changed.connect(_on_state_changed)
	SpiritEventBus.spirit_lifecycle_complete.connect(_on_lifecycle_complete)
	SpiritEventBus.spirit_ascended.connect(func(_id: StringName) -> void: _ascended_count += 1)
	SpiritEventBus.spirit_departed_unfed.connect(func(_id: StringName) -> void: _departed_unfed_count += 1)

	_fed_spirit = _spawn(Vector3(0.0, 1.0, 0.0))
	_neglected_spirit = _spawn(Vector3(1.0, 1.0, 0.0))

func _process(delta: float) -> void:
	if _finished:
		return

	_elapsed += delta
	if _elapsed > SAFETY_TIMEOUT:
		_failures.append("safety timeout: test did not finish within %.0fs" % SAFETY_TIMEOUT)
		_finish()
		return

	_feed_cooldown -= delta
	if _feed_cooldown <= 0.0 and is_instance_valid(_fed_spirit) \
			and _fed_spirit.state_machine.current_state == SpiritState.State.WAITING:
		if not _tested_locked_rejection:
			_tested_locked_rejection = true
			var locked_dish := CookedPlates.plate([FoodPiece.from_ingredient(CLIFF_GARDEN_HERB, AMBIENT_TEMP_C)])
			_expect_equal(
				"a dish using un-foraged content is refused at the pass",
				_serving_station.serve(locked_dish, _fed_spirit),
				false
			)
		_expect_equal("an unlocked dish is served", _serve_tide_dish(_fed_spirit), true)
		_feed_count += 1
		_feed_cooldown = FEED_INTERVAL

	if _fed_outcome != "" and _neglected_outcome != "":
		_finish()

# --- Serving checks ---------------------------------------------------------

func _test_serving_math() -> void:
	var plate := CookedPlates.plate(_tide_plate_pieces())
	var result := DishNourishment.feeding_result_of(plate)
	_expect_equal("a cooked plate nourishes", result.nourishment > 20.0, true)
	_expect_equal("and calms", result.calming > 20.0, true)
	_expect_near("an empty plate feeds nothing at the pass", DishNourishment.feeding_result_of(Dish.new()).nourishment, 0.0)
	_expect_equal("an empty plate can't be served", _serving_station.serve(Dish.new(), null), false)

func _test_dominant_affinity() -> void:
	var tide := _make_test_ingredient()
	tide.id = &"test_tide"
	tide.elemental_affinity = ElementalAffinity.Type.TIDE
	var wind := _make_test_ingredient()
	wind.id = &"test_wind"
	wind.elemental_affinity = ElementalAffinity.Type.WIND
	var big_tide := FoodPiece.from_ingredient(tide, AMBIENT_TEMP_C)
	var two_small_wind: Array[FoodPiece] = FoodCutting.cut(FoodPiece.from_ingredient(wind, AMBIENT_TEMP_C), Vector3.AXIS_X, 20.0, true)
	var mixed := CookedPlates.plate([big_tide, two_small_wind[0], two_small_wind[1]])
	_expect_equal("a plate's affinity is the one carrying the most food", mixed.dominant_affinity(), ElementalAffinity.Type.TIDE)
	var only_wind := CookedPlates.plate([two_small_wind[0]])
	_expect_equal("a plate of one ingredient carries its affinity", only_wind.dominant_affinity(), ElementalAffinity.Type.WIND)
	_expect_equal("an empty plate carries none", Dish.new().dominant_affinity(), ElementalAffinity.Type.NONE)
	var oil_drizzle := Dish.new()
	oil_drizzle.add_liquid(LiquidPortion.new(_make_test_oil(), 20.0, null))
	_expect_equal("a plate of something with no affinity carries none", oil_drizzle.dominant_affinity(), ElementalAffinity.Type.NONE)

# --- Food model checks --------------------------------------------------------
# These build their ingredients in code, so tuning the shipped .tres files
# never breaks them. Only the validation check reads the shipped content.

func _test_ingredient_validation() -> void:
	for ingredient in KITCHEN_INGREDIENTS:
		_expect_equal("shipped %s validates" % ingredient.id, ingredient.validate(), PackedStringArray())

	_expect_equal("a well-formed test ingredient validates", _make_test_ingredient().validate(), PackedStringArray())

	var over_composed := _make_test_ingredient()
	over_composed.starch_fraction = 0.5
	_expect_equal("composition above 1 is rejected", over_composed.validate().size(), 1)

	var weightless := _make_test_ingredient()
	weightless.density_g_per_cm3 = 0.0
	_expect_equal("zero density is rejected", weightless.validate().size(), 1)

	var sizeless := _make_test_ingredient()
	sizeless.whole_size_mm = Vector3(80.0, 0.0, 60.0)
	_expect_equal("a SOLID without a whole size is rejected", sizeless.validate().size(), 1)

	var tasteless := _make_test_ingredient()
	tasteless.flavour = null
	_expect_equal("a missing flavour profile is rejected", tasteless.validate().size(), 1)

	var granular := _make_test_ingredient()
	granular.physical_form = Ingredient.PhysicalForm.GRANULAR
	granular.whole_size_mm = Vector3.ZERO
	_expect_equal("a GRANULAR ingredient needs no whole size", granular.validate(), PackedStringArray())

func _test_flavour_mixing() -> void:
	var sweet_mild := FlavourProfile.new()
	sweet_mild.sweet = 0.2
	var fiery := FlavourProfile.new()
	fiery.sweet = 0.6
	fiery.heat = 1.0

	var even := FlavourProfile.mix_by_mass(sweet_mild, 50.0, fiery, 50.0)
	_expect_near("equal masses mix sweetness to the midpoint", even.sweet, 0.4)
	_expect_near("equal masses mix heat to the midpoint", even.heat, 0.5)

	var mostly_fiery := FlavourProfile.mix_by_mass(sweet_mild, 10.0, fiery, 30.0)
	_expect_near("mixing is weighted by mass", mostly_fiery.heat, 0.75)
	_expect_near("mixing leaves its inputs untouched", fiery.heat, 1.0)

	var nothing := FlavourProfile.mix_by_mass(sweet_mild, 0.0, fiery, 0.0)
	_expect_near("mixing no mass gives no flavour", nothing.heat, 0.0)

func _test_food_piece_creation() -> void:
	var ingredient := _make_test_ingredient()
	var piece := FoodPiece.from_ingredient(ingredient, AMBIENT_TEMP_C)
	_expect_equal("a whole piece takes the ingredient's size", piece.size_mm.is_equal_approx(Vector3(80.0, 40.0, 60.0)), true)
	# 80 * 40 * 60 mm = 192 cm^3 at 1.0 g/cm^3
	_expect_near("a whole piece's mass comes from volume and density", piece.mass_g(), 192.0)
	_expect_near("a whole piece starts at the ingredient's water content", piece.moisture(), 0.8)
	_expect_near("a whole piece's surface is as wet as its core", piece.surface_moisture, piece.core_moisture())
	_expect_near("a whole piece starts at ambient temperature", piece.core_temp_c, AMBIENT_TEMP_C)
	_expect_near("a whole piece starts raw", piece.core_doneness, 0.0)
	_expect_near("a whole piece starts intact", piece.integrity, 1.0)
	_expect_equal("a whole piece has never been cut", piece.cut_axes.is_empty(), true)

	piece.flavour.heat = 0.9
	_expect_near("a piece's flavour is its own copy, not the ingredient's", ingredient.flavour.heat, 0.0)

## A whole test potato cut at 10mm steps along Z into planks, then each plank
## cut at 10mm steps along Y (perpendicular, held steady) into sticks.
func _test_cutting_into_sticks() -> void:
	var whole := FoodPiece.from_ingredient(_make_test_ingredient(), AMBIENT_TEMP_C)
	var planks := _slice_at_steps(whole, Vector3.AXIS_Z, 10.0, false)
	_expect_equal("a 60mm potato gives six 10mm planks", planks.size(), 6)
	_expect_equal("the first pass along one axis needs no steadying", _all_intact(planks), true)

	var sticks: Array[FoodPiece] = []
	for plank in planks:
		sticks.append_array(_slice_at_steps(plank, Vector3.AXIS_Y, 10.0, true))
	_expect_equal("six 40mm planks give twenty-four sticks", sticks.size(), 24)
	_expect_equal("steadied cross-cuts leave the sticks intact", _all_intact(sticks), true)

	var all_sticks_sized := true
	var total_mass: float = 0.0
	var total_water: float = 0.0
	var total_solids: float = 0.0
	for stick in sticks:
		all_sticks_sized = all_sticks_sized and stick.size_mm.is_equal_approx(Vector3(80.0, 10.0, 10.0))
		total_mass += stick.mass_g()
		total_water += stick.water_g
		total_solids += stick.solids_g
	_expect_equal("every stick is 80 x 10 x 10mm", all_sticks_sized, true)
	_expect_near("cutting conserves mass", total_mass, whole.mass_g())
	_expect_near("cutting conserves water", total_water, whole.water_g)
	_expect_near("cutting conserves solids", total_solids, whole.solids_g)
	_expect_equal("a stick remembers both cut axes", sticks[0].cut_axes.size(), 2)

## Every cut of the perpendicular pass needs the food held, not only the first.
func _test_unsteadied_cross_cuts() -> void:
	var whole := FoodPiece.from_ingredient(_make_test_ingredient(), AMBIENT_TEMP_C)
	var plank: FoodPiece = FoodCutting.cut(whole, Vector3.AXIS_Z, 10.0, false)[0]

	var remainder := plank
	var every_cut_damaged := true
	for cut_index in 3:
		var parts := FoodCutting.cut(remainder, Vector3.AXIS_Y, 10.0, false)
		every_cut_damaged = every_cut_damaged \
			and parts[0].integrity < remainder.integrity \
			and parts[1].integrity < remainder.integrity
		remainder = parts[1]
	_expect_equal("each unsteadied cross-cut damages its pieces", every_cut_damaged, true)

	var first_cross := FoodCutting.cut(plank, Vector3.AXIS_Y, 10.0, false)
	# The test ingredient loses half its integrity to an unsteadied cross-cut.
	_expect_near("an unsteadied cross-cut costs the ingredient's integrity loss", first_cross[0].integrity, 0.5)
	_expect_near("cutting leaves the original piece untouched", plank.integrity, 1.0)

func _test_cut_limits_and_thin_slices() -> void:
	var whole := FoodPiece.from_ingredient(_make_test_ingredient(), AMBIENT_TEMP_C)
	_expect_equal("a cut outside the piece is refused", FoodCutting.cut(whole, Vector3.AXIS_X, 95.0, true).size(), 0)
	_expect_equal("a cut thinner than a mezzaluna can take is refused", FoodCutting.cut(whole, Vector3.AXIS_X, 1.0, true).size(), 0)
	_expect_equal("a cut leaving a too-thin remainder is refused", FoodCutting.cut(whole, Vector3.AXIS_X, 79.0, true).size(), 0)

	var thin_slice: FoodPiece = FoodCutting.cut(whole, Vector3.AXIS_X, 2.0, true)[0]
	# 2mm against a 4mm stable thickness keeps half its integrity.
	_expect_near("a slice below stable thickness starts to crumble", thin_slice.integrity, 0.5)

func _test_cut_exposes_fresh_surface() -> void:
	var piece := FoodPiece.from_ingredient(_make_test_ingredient(), AMBIENT_TEMP_C)
	piece.surface_browning = 1.0
	piece.surface_temp_c = 180.0
	piece.core_temp_c = 80.0

	var halves := FoodCutting.cut(piece, Vector3.AXIS_X, 40.0, true)
	# Each half is 40 x 40 x 60: surface 12800mm^2, of which the 40 x 60 cut
	# face (2400mm^2) is fresh. Browning keeps 10400 / 12800 of its level.
	_expect_near("a fresh cut face dilutes browning", halves[0].surface_browning, 0.8125)
	_expect_near(
		"a fresh cut face pulls surface temperature towards the core",
		halves[0].surface_temp_c,
		(180.0 * 10400.0 + 80.0 * 2400.0) / 12800.0
	)
	_expect_near("bulk state is inherited across a cut", halves[1].core_temp_c, 80.0)

	var fried := FoodPiece.from_ingredient(_make_test_ingredient(), AMBIENT_TEMP_C)
	fried.oil_g = 12.0
	fried.surface_moisture = 0.0
	var fried_halves := FoodCutting.cut(fried, Vector3.AXIS_X, 20.0, true)
	_expect_near("cutting conserves absorbed oil", fried_halves[0].oil_g + fried_halves[1].oil_g, 12.0)
	_expect_equal(
		"a fresh cut face wets a dried surface",
		fried_halves[0].surface_moisture > 0.0 and fried_halves[0].surface_moisture < fried.core_moisture(),
		true
	)

	halves[0].flavour.salty = 1.0
	_expect_near("each half owns its flavour", halves[1].flavour.salty, 0.0)

# --- Heat and cooking checks ---------------------------------------------------
# Relational where the outcome is a matter of tuning: thinner cooks first,
# hotter oil browns more. Exact where physics demands it: energy and mass.

func _test_burner_power() -> void:
	var stove := _make_test_stove()
	_expect_near("an unlit burner gives no heat", stove.power_at(0.0), 0.0)
	_expect_near("a flame below the lowest level burns at the lowest level", stove.power_at(0.05), 300.0)
	_expect_near("full flame gives full power", stove.power_at(1.0), 2000.0)

func _test_pot_heats_and_cools() -> void:
	var pot := _make_test_oil_pot()
	pot.set_flame(1.0)
	var seconds := _heat_until(pot, 180.0, 1800.0)
	_expect_equal("oil at full flame reaches frying heat within minutes, not instantly", seconds > 120.0 and seconds < 900.0, true)

	_expect_equal("the metal under the oil runs hotter than the oil", pot.base_temp_c > pot.temp_c + 10.0, true)
	pot.set_flame(0.2)
	var peak: float = pot.temp_c
	for second in 600:
		pot.advance(1.0)
		peak = maxf(peak, pot.temp_c)
	_expect_equal("hot metal carries the oil on a little after the flame drops", peak > 180.5, true)
	_expect_equal("lowering the flame lets the oil cool", pot.temp_c < 180.0, true)

func _test_batch_draws_heat_from_oil() -> void:
	var empty_pot := _make_test_oil_pot()
	var batch_pot := _make_test_oil_pot()
	for pot in [empty_pot, batch_pot]:
		pot.set_flame(1.0)
		_heat_until(pot, 180.0, 1800.0)
		pot.set_flame(0.5)

	var whole := FoodPiece.from_ingredient(_make_test_ingredient(), AMBIENT_TEMP_C)
	for plank in _slice_at_steps(whole, Vector3.AXIS_Z, 10.0, false):
		for stick in _slice_at_steps(plank, Vector3.AXIS_Y, 10.0, true):
			batch_pot.add_piece(stick)
	var oil_before: float = batch_pot.medium_mass_g
	empty_pot.advance(60.0)
	batch_pot.advance(60.0)

	_expect_equal("a cold batch drops the oil's temperature", batch_pot.temp_c < empty_pot.temp_c - 5.0, true)
	# The two pots differ only by the batch, so the heat the batch took is
	# the heat the oil and metal are missing - less the extra the cooler pot
	# didn't lose to the air.
	var missing_heat_j: float = empty_pot.thermal_energy_j() - batch_pot.thermal_energy_j()
	_expect_equal(
		"heat drawn by the food is heat the oil lost",
		absf(missing_heat_j - batch_pot.energy_to_food_j) < 0.1 * batch_pot.energy_to_food_j,
		true
	)
	var oil_in_food: float = 0.0
	for piece in batch_pot.pieces:
		oil_in_food += piece.oil_g
	_expect_equal("frying food soaks up some oil", oil_in_food > 0.0, true)
	_expect_near("oil soaked up by food leaves the pot", batch_pot.medium_mass_g + oil_in_food, oil_before)

func _test_water_boils_away_at_its_boiling_point() -> void:
	var pot := CookingPot.new(_make_test_vessel(), AMBIENT_TEMP_C)
	pot.burner = _make_test_stove()
	pot.add_medium(_make_test_water(), 1500.0, AMBIENT_TEMP_C)
	pot.set_flame(1.0)
	var hottest: float = pot.temp_c
	for second in 1800:
		pot.advance(1.0)
		hottest = maxf(hottest, pot.temp_c)
	_expect_equal("boiling water never rises past its boiling point", hottest <= 100.0 + EPSILON, true)
	_expect_equal("water at a rolling boil boils away", pot.boiled_off_g > 0.0, true)
	_expect_near("boiled-off water leaves the pot", pot.medium_mass_g + pot.boiled_off_g, 1500.0)

func _test_thin_pieces_cook_through_first() -> void:
	var thin := _cut_stick(5.0)
	var thick := _cut_stick(15.0)
	var exposure := _held_exposure(_make_test_oil(), 170.0)
	var thin_done_at := _seconds_until_cooked(thin, exposure)
	var thick_done_at := _seconds_until_cooked(thick, exposure)
	_expect_equal("a 5mm stick cooks through before a 15mm stick", thin_done_at < thick_done_at, true)

	# Conduction time grows with thickness squared, convection time with
	# thickness, so tripling thickness must slow the core by well over 3x.
	var thin_warm_at := _seconds_until_core_reaches(_cut_stick(5.0), exposure, 60.0)
	var thick_warm_at := _seconds_until_core_reaches(_cut_stick(15.0), exposure, 60.0)
	_expect_equal("tripling thickness slows the core's warming by more than 4x", thick_warm_at > 4.0 * thin_warm_at, true)

func _test_frying_temperature_shapes_the_fry() -> void:
	var fries := {}
	for temp in [130.0, 180.0, 220.0]:
		var fry := _cut_stick(10.0)
		var exposure := _held_exposure(_make_test_oil(), temp)
		for step in 7200:
			FoodHeating.step(fry, exposure, 0.05)
		fries[temp] = fry
	var cool: FoodPiece = fries[130.0]
	var right: FoodPiece = fries[180.0]
	var hot: FoodPiece = fries[220.0]
	_expect_equal("fries at 180C cook through in six minutes", right.core_doneness >= 1.0, true)
	_expect_equal("fries at 180C are golden at six minutes", right.surface_browning > 0.4 and right.surface_browning < 0.85, true)
	_expect_equal("fries at 180C are still moist inside at six minutes", right.core_moisture() > 0.2, true)
	# Blanching: the first fry of a double fry cooks the inside through and
	# leaves the outside pale.
	_expect_equal("fries blanched at 130C cook through", cool.core_doneness >= 1.0, true)
	_expect_equal("but stay pale", cool.surface_browning < 0.1, true)
	_expect_equal("a wet core never passes boiling", right.core_temp_c <= 100.0 + EPSILON, true)
	_expect_equal("hotter oil browns fries more", right.surface_browning > cool.surface_browning + 0.2, true)
	_expect_equal("fries at 180C do not burn in six minutes", right.surface_char < 0.05, true)
	_expect_equal("fries at 220C burn", hot.surface_char > right.surface_char + 0.1, true)
	_expect_equal("cool oil makes greasier fries", cool.oil_fraction() > right.oil_fraction(), true)
	_expect_equal("burning makes food bitter", hot.flavour.bitter > right.flavour.bitter, true)
	_expect_equal("browning adds aroma", right.flavour.aroma > cool.flavour.aroma, true)

func _test_boiling_softens_and_never_browns() -> void:
	var cube := _cut_cube(25.0)
	var water := _held_exposure(_make_test_water(), 100.0)
	for step in 30000:
		FoodHeating.step(cube, water, 0.05)
	_expect_near("boiled food never browns", cube.surface_browning, 0.0)
	_expect_equal("long-overcooked boiled potato falls apart", cube.integrity < 0.5, true)

	var fry := _cut_stick(10.0)
	var oil := _held_exposure(_make_test_oil(), 180.0)
	for step in 10800:
		FoodHeating.step(fry, oil, 0.05)
	_expect_equal("an overcooked fry's dry crust holds it together", fry.core_doneness > 1.5 and fry.integrity > 0.9, true)

func _test_thin_slice_heating_is_stable() -> void:
	var whole := FoodPiece.from_ingredient(_make_test_ingredient(), AMBIENT_TEMP_C)
	var slice: FoodPiece = FoodCutting.cut(whole, Vector3.AXIS_X, FoodCutting.MIN_PIECE_THICKNESS_MM, true)[0]
	var exposure := _held_exposure(_make_test_oil(), 220.0)
	var in_bounds := true
	for step in 2400:
		FoodHeating.step(slice, exposure, 0.05)
		for temp in [slice.surface_temp_c, slice.core_temp_c]:
			in_bounds = in_bounds and not is_nan(temp) and temp >= AMBIENT_TEMP_C - EPSILON and temp <= 220.0 + EPSILON
	_expect_equal("the thinnest slice heats without overshooting its oil", in_bounds, true)

func _test_simulation_ignores_frame_rate() -> void:
	var smooth := _make_test_oil_pot()
	var choppy := _make_test_oil_pot()
	for pot in [smooth, choppy]:
		pot.set_flame(0.8)
		pot.add_piece(_cut_stick(10.0))
	for frame in 7200:
		smooth.advance(1.0 / 60.0)
	for frame in 720:
		choppy.advance(1.0 / 6.0)
	# Both have seen 120s; a final half step keeps float rounding from
	# landing either one on the other side of a step boundary.
	smooth.advance(CookingPot.FIXED_STEP_S * 0.5)
	choppy.advance(CookingPot.FIXED_STEP_S * 0.5)
	_expect_near("oil temperature is independent of frame rate", smooth.temp_c, choppy.temp_c)
	_expect_near("food is independent of frame rate", smooth.pieces[0].core_temp_c, choppy.pieces[0].core_temp_c)

# --- Per-face and pot interaction checks ---------------------------------------
# Each face of a piece sees what it actually touches. These pin the
# consequences: shallow frying browns underneath, turning evens it out, the
# middle of the base is the hot spot, food sinks and floats by buoyancy,
# displaces the oil, and the oil itself wears out when abused.

func _test_faces_cook_independently() -> void:
	var stick := _cut_stick(10.0)
	var exposure := HeatExposure.new()
	exposure.use_per_face()
	exposure.air_temp_c = AMBIENT_TEMP_C
	for face in FoodPiece.FACE_COUNT:
		if face == FoodPiece.BOTTOM:
			exposure.set_face(face, 0.0, 0.0, 400.0, 200.0, 0.0)
		else:
			exposure.set_face(face, 0.0, 0.0, 0.0, 0.0, 10.0)
	for step in 6000:
		FoodHeating.step(stick, exposure, 0.05)
	_expect_equal("the face on hot metal browns", stick.face_browning[FoodPiece.BOTTOM] > 0.3, true)
	_expect_equal("the face in the air above stays pale", stick.face_browning[FoodPiece.TOP] < 0.02, true)
	_expect_equal("the hot face is hotter than the face in the air", stick.face_temp_c[FoodPiece.BOTTOM] > stick.face_temp_c[FoodPiece.TOP] + 30.0, true)
	_expect_equal("heat from the one hot face still cooks the core", stick.core_temp_c > 60.0, true)

func _test_cut_faces_are_flesh() -> void:
	var whole := FoodPiece.from_ingredient(_make_test_ingredient(), AMBIENT_TEMP_C)
	_expect_near("a whole item is all skin", whole.skin_share(), 1.0)
	var halves := FoodCutting.cut(whole, Vector3.AXIS_X, 30.0, true)
	_expect_near("the near half's cut face is flesh", halves[0].face_skin[FoodPiece.Face.POS_X], 0.0)
	_expect_near("the far half's cut face is flesh", halves[1].face_skin[FoodPiece.Face.NEG_X], 0.0)
	_expect_near("the near half's other end is still skin", halves[0].face_skin[FoodPiece.Face.NEG_X], 1.0)
	_expect_near("its top is still skin", halves[0].face_skin[FoodPiece.TOP], 1.0)

func _test_rolling_turns_faces() -> void:
	var plank: FoodPiece = FoodCutting.cut(FoodPiece.from_ingredient(_make_test_ingredient(), AMBIENT_TEMP_C), Vector3.AXIS_Z, 10.0, true)[0]
	plank.face_browning[FoodPiece.BOTTOM] = 1.0
	plank.roll()
	_expect_near("rolling turns the browned underside to a side", plank.face_browning[FoodPiece.Face.NEG_Z], 1.0)
	_expect_near("and off the bottom", plank.face_browning[FoodPiece.BOTTOM], 0.0)
	plank.roll()
	_expect_near("rolling twice turns the underside to the top", plank.face_browning[FoodPiece.TOP], 1.0)
	var total: float = 0.0
	for face in FoodPiece.FACE_COUNT:
		total += plank.face_browning[face]
	_expect_near("rolling moves faces, never makes or loses them", total, 1.0)

func _test_food_dries_and_cools_in_the_wind() -> void:
	var calm_air := KitchenAir.new()
	calm_air.temp_c = AMBIENT_TEMP_C
	calm_air.wind_mps = 0.0
	var gale := calm_air.duplicate() as KitchenAir
	gale.wind_mps = 12.0
	var still_cube := _boil(25.0, 600.0)
	var windy_cube := still_cube.clone()
	var water_before: float = still_cube.water_g
	var still_rest := RestingSurface.new(calm_air)
	var windy_rest := RestingSurface.new(gale)
	still_rest.add_piece(still_cube)
	windy_rest.add_piece(windy_cube)
	still_rest.advance(120.0)
	windy_rest.advance(120.0)
	_expect_equal("hot boiled potato steams dry in the air", still_cube.water_g < water_before - 0.05, true)
	_expect_equal("it dries faster in the wind", windy_cube.water_g < still_cube.water_g, true)
	_expect_equal("and cools faster in the wind", windy_cube.core_temp_c < still_cube.core_temp_c - 2.0, true)

func _test_resting_fries_cook_on_and_go_limp() -> void:
	var fry := _fry(180.0, 150.0)
	var doneness_out: float = fry.core_doneness
	var rest := RestingSurface.new(KitchenAir.still(AMBIENT_TEMP_C))
	rest.add_piece(fry)
	rest.advance(60.0)
	_expect_equal("a fry lifted from the oil keeps cooking from its own heat", fry.core_doneness > doneness_out + 0.02, true)
	var crisp_soon := FoodPerception.texture_of(fry).crispness
	rest.advance(1800.0)
	_expect_equal("left out, it cools to the air", fry.core_temp_c < AMBIENT_TEMP_C + 5.0, true)
	_expect_equal("and its crust goes limp as water creeps back out", FoodPerception.texture_of(fry).crispness < crisp_soon - 0.1, true)

func _test_shallow_fry_browns_underneath() -> void:
	var pot := _make_test_oil_pot_with(200.0)
	_heat_until(pot, 180.0, 1800.0)
	var stick := _cut_stick(10.0)
	pot.add_piece(stick)
	var placement := pot.placement_of(stick)
	_expect_equal("a raw stick sinks to the bottom", placement.resting, PotPlacement.Resting.FLOOR)
	_expect_equal("a 10mm stick stands proud of 200g of oil", placement.immersion < 1.0, true)
	_hold_temperature(pot, 180.0, 300.0)
	var underside: float = stick.face_browning[FoodPiece.BOTTOM]
	var top: float = stick.face_browning[FoodPiece.TOP]
	_expect_equal("shallow-fried food browns underneath first", underside > top + 0.2, true)
	pot.turn(stick)
	pot.turn(stick)
	_hold_temperature(pot, 180.0, 300.0)
	_expect_equal("turning it browns the other side", stick.face_browning[FoodPiece.BOTTOM] > top + 0.2, true)

func _test_the_middle_of_the_base_is_hottest() -> void:
	var pot := CookingPot.new(_make_test_vessel(), AMBIENT_TEMP_C, KitchenAir.still(AMBIENT_TEMP_C))
	pot.burner = _make_test_stove()
	pot.set_flame(0.3)
	pot.advance(240.0)
	_expect_equal("a small flame heats the middle of a dry pot more than its rim", pot.base_temp_c > pot.rim_temp_c + 20.0, true)
	var middle := _cut_cube(15.0)
	var edge := _cut_cube(15.0)
	pot.add_piece(middle, Vector2.ZERO)
	pot.add_piece(edge, Vector2(65.0, 0.0))
	_expect_near("food at the edge is mostly over the rim", pot.placement_of(edge).over_burner, 0.0)
	pot.advance(60.0)
	_expect_equal("food in the middle browns faster than food by the wall",
		middle.face_browning[FoodPiece.BOTTOM] > edge.face_browning[FoodPiece.BOTTOM] + 0.05, true)

func _test_buoyancy_and_displacement() -> void:
	var pot := _make_test_oil_pot()
	var level_before: float = pot.liquid_level_mm
	var sticks: Array[FoodPiece] = []
	for index in 6:
		var stick := _cut_stick(10.0)
		sticks.append(stick)
		pot.add_piece(stick, Vector2(-30.0 + index * 12.0, 0.0))
	_expect_equal("food lowered into oil raises the oil", pot.liquid_level_mm > level_before + 0.5, true)
	_expect_equal("raw potato sinks in oil", pot.placement_of(sticks[0]).resting, PotPlacement.Resting.FLOOR)
	_expect_equal("pieces dropped side by side don't overlap",
		pot.placement_of(sticks[0]).footprint().intersects(pot.placement_of(sticks[1]).footprint()), false)
	pot.set_flame(1.0)
	_heat_until(pot, 175.0, 1800.0)
	_hold_temperature(pot, 180.0, 420.0)
	_expect_equal("a fry that has given up its water floats", pot.placement_of(sticks[0]).resting, PotPlacement.Resting.FLOATING)

	var bubbling := PotPlacement.new(_cut_stick(10.0), Vector2.ZERO)
	var density_still: float = PotLayout.effective_density(bubbling)
	bubbling.steam_g_per_s = 0.03
	_expect_equal("clinging steam bubbles lighten food", PotLayout.effective_density(bubbling) < density_still, true)

func _test_frying_oil_wears_out() -> void:
	var fresh_pot := _make_test_oil_pot_with(1000.0, _make_test_frying_oil())
	var abused_pot := _make_test_oil_pot_with(1000.0, _make_test_frying_oil())
	_heat_until(fresh_pot, 180.0, 1800.0)
	abused_pot.set_flame(1.0)
	var smoked := false
	for second in 1500:
		abused_pot.advance(1.0)
		smoked = smoked or abused_pot.smoke > 0.5
	_expect_equal("oil left on full flame smokes", smoked, true)
	_expect_equal("smoking breaks the oil down", abused_pot.medium_breakdown > 0.3, true)
	_expect_equal("broken-down oil tastes acrid", abused_pot.medium_flavour.bitter > fresh_pot.medium_flavour.bitter + 0.1, true)
	_expect_equal("worn oil smokes at a lower temperature",
		MediumChemistry.smoke_point_c(abused_pot.medium, abused_pot.medium_breakdown) < MediumChemistry.smoke_point_c(fresh_pot.medium, 0.0) - 20.0, true)

	abused_pot.set_flame(0.0)
	for second in 3000:
		abused_pot.advance(1.0)
		if abused_pot.temp_c <= 180.0:
			break
	var fresh_fry := _cut_stick(10.0)
	var abused_fry := _cut_stick(10.0)
	fresh_pot.add_piece(fresh_fry)
	abused_pot.add_piece(abused_fry)
	_hold_temperature(fresh_pot, 180.0, 240.0)
	_hold_temperature(abused_pot, 180.0, 240.0)
	_expect_equal("fries from abused oil come out bitter", abused_fry.flavour.bitter > fresh_fry.flavour.bitter + 0.05, true)
	_expect_equal("and greasier", abused_fry.oil_fraction() > fresh_fry.oil_fraction(), true)

	var water_pot := CookingPot.new(_make_test_vessel(), AMBIENT_TEMP_C)
	water_pot.burner = _make_test_stove()
	water_pot.add_medium(_make_test_water(), 1500.0, AMBIENT_TEMP_C)
	water_pot.set_flame(1.0)
	water_pot.advance(1200.0)
	_expect_near("water never smokes or breaks down", water_pot.medium_breakdown + water_pot.smoke, 0.0)

func _test_wind_slows_the_pot() -> void:
	var calm := KitchenAir.still(AMBIENT_TEMP_C)
	var gale := KitchenAir.still(AMBIENT_TEMP_C)
	gale.wind_mps = 14.0
	var seconds := {}
	for air in [calm, gale]:
		var pot := CookingPot.new(_make_test_vessel(), AMBIENT_TEMP_C, air)
		pot.burner = _make_test_stove()
		pot.add_medium(_make_test_oil(), 1000.0, AMBIENT_TEMP_C)
		pot.set_flame(1.0)
		seconds[air] = _heat_until(pot, 180.0, 3600.0)
	_expect_equal("oil takes longer to heat in a gale", seconds[gale] > seconds[calm] * 1.3, true)

func _test_open_water_evaporates() -> void:
	var pot := CookingPot.new(_make_test_vessel(), AMBIENT_TEMP_C)
	pot.burner = _make_test_stove()
	pot.add_medium(_make_test_water(), 1500.0, 85.0)
	pot.set_flame(0.0)
	pot.advance(120.0)
	_expect_equal("hot water steams off before it boils", pot.boiled_off_g > 1.0, true)
	_expect_near("steamed-off water leaves the pot", pot.medium_mass_g + pot.boiled_off_g, 1500.0)

func _test_spoon_stirs_and_finds_food() -> void:
	var pot := _make_test_oil_pot()
	var stick := _cut_stick(10.0)
	pot.add_piece(stick, Vector2(-40.0, 0.0))
	_expect_equal("the spoon finds food where it is pressed", pot.pieces_near(Vector2(-40.0, 0.0), 5.0).has(stick), true)
	_expect_equal("and not where it isn't", pot.pieces_near(Vector2(60.0, 60.0), 5.0).is_empty(), true)
	pot.stir(Vector2(-40.0, 0.0), Vector2(0.0, 0.0), 12.0)
	_expect_equal("a stroke of the spoon carries food along", pot.placement_of(stick).centre_mm.x > -15.0, true)

func _test_full_pot_runs_in_real_time() -> void:
	var pot := _make_test_oil_pot()
	pot.set_flame(1.0)
	_heat_until(pot, 180.0, 1800.0)
	var whole := FoodPiece.from_ingredient(_make_test_ingredient(), AMBIENT_TEMP_C)
	var count: int = 0
	for plank in _slice_at_steps(whole, Vector3.AXIS_Z, 10.0, true):
		for stick in _slice_at_steps(plank, Vector3.AXIS_Y, 10.0, true):
			pot.add_piece(stick, Vector2(randf_range(-50.0, 50.0), randf_range(-50.0, 50.0)))
			count += 1
	var started := Time.get_ticks_usec()
	pot.advance(10.0)
	var cost_ms: float = (Time.get_ticks_usec() - started) / 1000.0 / 10.0
	print("pot with %d fries: %.2f ms per simulated second" % [count, cost_ms])
	_expect_equal("a full batch simulates many times faster than real time", cost_ms < 100.0, true)

# --- Mystical essence checks ---------------------------------------------------
# Traits built in code, each against the same food without it.

func _test_trait_activation() -> void:
	var lift := _make_trait(MysticTrait.Effect.LIFT, 1.5, MysticTrait.Trigger.COOKED, 1.0)
	var raw := FoodPiece.from_ingredient(_with_trait(_make_test_ingredient(), lift, 1.0), AMBIENT_TEMP_C)
	_expect_near("an essence that wakes when cooked sleeps in raw food", TraitEffects.lift_share(raw), 0.0)
	raw.core_doneness = 1.0
	_expect_near("and is fully awake once cooked", TraitEffects.lift_share(raw), 1.5)
	var cut: FoodPiece = FoodCutting.cut(raw, Vector3.AXIS_X, 20.0, true)[0]
	_expect_near("cut pieces keep the essence", cut.traits.get_dose(lift), 1.0)
	var hot := _make_trait(MysticTrait.Effect.GLOW, 1.0, MysticTrait.Trigger.HOT, 80.0)
	var warmed := FoodPiece.from_ingredient(_with_trait(_make_test_ingredient(), hot, 1.0), AMBIENT_TEMP_C)
	_expect_near("a heat-woken glow is dark cold", TraitEffects.glow(warmed).a, 0.0)
	warmed.core_temp_c = 85.0
	_expect_near("and bright hot", TraitEffects.glow(warmed).a, 1.0)
	_expect_equal("a bloom trait without its flavour is rejected", _make_trait(MysticTrait.Effect.BLOOM, 1.0, MysticTrait.Trigger.ALWAYS, 1.0).validate().size(), 1)

func _test_lifting_food_floats_and_hovers() -> void:
	var lift := _make_trait(MysticTrait.Effect.LIFT, 1.5, MysticTrait.Trigger.COOKED, 1.0)
	var buoyant := _with_trait(_make_test_ingredient(), lift, 1.0)
	var pot := _make_test_oil_pot()
	_heat_until(pot, 175.0, 1800.0)
	var stick := _cut_stick_of(buoyant, 10.0)
	pot.add_piece(stick)
	_expect_equal("raw, it sinks like any potato", pot.placement_of(stick).resting, PotPlacement.Resting.FLOOR)
	_hold_temperature(pot, 180.0, 400.0)
	_expect_equal("cooked, its essence floats it", pot.placement_of(stick).resting, PotPlacement.Resting.FLOATING)
	_expect_equal("riding high in the oil", pot.placement_of(stick).immersion < 0.2, true)
	_expect_equal("lifted past its weight, it hovers off the board", RestingSurface.is_hovering(stick), true)
	var rest := RestingSurface.new(KitchenAir.still(AMBIENT_TEMP_C))
	_expect_near("hovering food touches nothing beneath it", rest.exposure_for(stick).contact_h(FoodPiece.BOTTOM), 0.0)

func _test_ember_and_frost() -> void:
	var ember := _make_trait(MysticTrait.Effect.EMBER, 0.5, MysticTrait.Trigger.ALWAYS, 1.0)
	ember.fuel_j_per_g = 600.0
	var warm := _cut_cube_of(_with_trait(_make_test_ingredient(), ember, 1.0), 20.0)
	var plain := _cut_cube(20.0)
	var rest := RestingSurface.new(KitchenAir.still(AMBIENT_TEMP_C))
	rest.add_piece(warm)
	rest.add_piece(plain)
	rest.advance(300.0)
	_expect_equal("an ember essence warms food from inside", warm.core_temp_c > plain.core_temp_c + 5.0, true)
	_expect_equal("and spends its fuel doing it", warm.traits.get_dose(ember) < 1.0, true)
	rest.advance(3600.0)
	# It burns down: the less there is left, the less it gives.
	_expect_equal("until it is all but spent", warm.traits.get_dose(ember) < 0.05, true)

	var frost := _make_trait(MysticTrait.Effect.FROST, 2.0, MysticTrait.Trigger.HOT, 40.0)
	var chilled := _cut_cube_of(_with_trait(_make_test_ingredient(), frost, 1.0), 20.0)
	var control := _cut_cube(20.0)
	var water := _held_exposure(_make_test_water(), 100.0)
	for step in 4800:
		FoodHeating.step(chilled, water, 0.05)
		FoodHeating.step(control, water, 0.05)
	_expect_equal("a frost essence holds food back from cooking", chilled.core_doneness < control.core_doneness - 0.2, true)

func _test_char_ward_and_bloom() -> void:
	var ward := _make_trait(MysticTrait.Effect.CHAR_WARD, 0.9, MysticTrait.Trigger.ALWAYS, 1.0)
	var warded := _cut_stick_of(_with_trait(_make_test_ingredient(), ward, 1.0), 10.0)
	var bare := _cut_stick(10.0)
	var hot_oil := _held_exposure(_make_test_oil(), 220.0)
	for step in 7200:
		FoodHeating.step(warded, hot_oil, 0.05)
		FoodHeating.step(bare, hot_oil, 0.05)
	_expect_equal("a char ward keeps food from burning", warded.surface_char < bare.surface_char * 0.3, true)
	_expect_equal("but it still browns", warded.surface_browning > 0.5, true)

	var honey := FlavourProfile.new()
	honey.sweet = 0.9
	var bloom := _make_trait(MysticTrait.Effect.BLOOM, 0.2, MysticTrait.Trigger.BROWNED, 0.3)
	bloom.bloom_flavour = honey
	var blooming := _cut_stick_of(_with_trait(_make_test_ingredient(), bloom, 1.0), 10.0)
	var oil := _held_exposure(_make_test_oil(), 180.0)
	for step in 7200:
		FoodHeating.step(blooming, oil, 0.05)
	_expect_equal("a bloom essence turns sweet once toasted", blooming.flavour.sweet > 0.5, true)

func _test_essence_infuses_broth() -> void:
	var calm := _make_trait(MysticTrait.Effect.SOOTHE, 1.0, MysticTrait.Trigger.ALWAYS, 1.0)
	calm.water_solubility = 1.0
	var pot := CookingPot.new(_make_test_vessel(), AMBIENT_TEMP_C)
	pot.burner = _make_test_stove()
	pot.add_medium(_make_test_water(), 800.0, AMBIENT_TEMP_C)
	var bones := _with_trait(_make_test_ingredient(), calm, 1.0)
	bones.edible_share = 0.0
	var bone := FoodPiece.from_ingredient(bones, AMBIENT_TEMP_C)
	pot.add_piece(bone)
	pot.set_flame(0.6)
	pot.advance(1800.0)
	_expect_equal("a water-soluble essence boils out into broth", pot.medium_traits.get_dose(calm) > 0.02, true)
	var broth := Dish.new()
	broth.add_liquid(LiquidPortion.new(pot.medium, 200.0, pot.medium_flavour, pot.medium_traits, pot.temp_c))
	var water := Dish.new()
	water.add_liquid(LiquidPortion.new(_make_test_water(), 200.0, null))
	_expect_equal("and the broth soothes a spirit as plain water doesn't",
		DishNourishment.feeding_result_of(broth).calming > DishNourishment.feeding_result_of(water).calming + 1.0, true)
	var only_bone := CookedPlates.plate([bone])
	_expect_near("bones themselves feed no one", DishNourishment.feeding_result_of(only_bone).nourishment, 0.0)

	var fat_only := _make_trait(MysticTrait.Effect.GLOW, 1.0, MysticTrait.Trigger.ALWAYS, 1.0)
	fat_only.fat_solubility = 1.0
	var glowing := _cut_cube_of(_with_trait(_make_test_ingredient(), fat_only, 1.0), 20.0)
	var boiling := _held_exposure(_make_test_water(), 100.0)
	boiling.traits = TraitDoses.new()
	for step in 6000:
		FoodHeating.step(glowing, boiling, 0.05)
	_expect_near("a fat-soluble essence stays put in water", boiling.traits.get_dose(fat_only), 0.0)

func _test_essences_reach_spirits() -> void:
	var lift := _make_trait(MysticTrait.Effect.LIFT, 1.5, MysticTrait.Trigger.COOKED, 1.0)
	var buoyant := _with_trait(_make_test_ingredient(), lift, 1.0)
	var light_fries: Array[FoodPiece] = []
	var plain_fries: Array[FoodPiece] = []
	for index in 4:
		light_fries.append(_fry_of(buoyant, 180.0, 360.0))
		plain_fries.append(_fry(180.0, 360.0))
	var light := DishNourishment.feeding_result_of(CookedPlates.plate(light_fries))
	var plain := DishNourishment.feeding_result_of(CookedPlates.plate(plain_fries))
	_expect_equal("food that lifts lightens the spirit", light.buoyancy_delta > plain.buoyancy_delta + 0.05, true)
	_expect_equal("and carries it more surely to the moon", light.ascension_strength > plain.ascension_strength, true)
	_expect_equal("a lifting essence changes the dish", CookedPlates.plate(light_fries).fingerprint() != CookedPlates.plate(plain_fries).fingerprint(), true)
	var feeding := _make_trait(MysticTrait.Effect.NOURISH, 0.5, MysticTrait.Trigger.COOKED, 1.0)
	var hearty := DishNourishment.feeding_result_of(CookedPlates.plate([_fry_of(_with_trait(_make_test_ingredient(), feeding, 1.0), 180.0, 360.0)]))
	var ordinary := DishNourishment.feeding_result_of(CookedPlates.plate([_fry(180.0, 360.0)]))
	_expect_equal("a nourishing essence feeds a spirit more", hearty.nourishment > ordinary.nourishment + 1.0, true)
	var noted := _make_trait(MysticTrait.Effect.LIFT, 1.5, MysticTrait.Trigger.COOKED, 1.0)
	noted.taste_note = "It lifts off the tongue."
	var tasted := _fry_of(_with_trait(_make_test_ingredient(), noted, 1.0), 180.0, 360.0)
	_expect_equal("tasting notices an awake essence", TasteNote.describe(tasted).contains("It lifts off the tongue."), true)

# --- Equipment and transformation checks ---------------------------------------

func _test_shipped_transformations_validate() -> void:
	var catalog := Transformation.load_catalog()
	_expect_equal("the transformation catalog is not empty", catalog.is_empty(), false)
	for transformation in catalog:
		_expect_equal("shipped %s validates" % transformation.id, transformation.validate(), PackedStringArray())

func _test_transformation_validation() -> void:
	_expect_equal("a well-formed test press validates", _make_test_press_transformation().validate(), PackedStringArray())

	var greedy := _make_test_press_transformation()
	greedy.output_yields = [0.5, 0.6]
	_expect_equal("yields above 1 are rejected", greedy.validate().has("yields sum to 1.100, above 1"), true)

	var alchemical := _make_test_press_transformation()
	alchemical.output_yields = [0.6, 0.3]
	_expect_equal(
		"a press that makes more fat than the seeds hold is rejected",
		alchemical.validate().has("outputs hold more fat than the input"),
		true
	)

	var unbalanced := _make_test_press_transformation()
	unbalanced.output_yields = [0.35]
	_expect_equal("every output needs a yield", unbalanced.validate().size(), 1)

func _test_press_turns_work_into_oil() -> void:
	var transformation := _make_test_press_transformation()
	var press := ManualProcessor.new(transformation.equipment, [transformation])
	var seeds: Ingredient = transformation.input
	var oil: Ingredient = transformation.outputs[0]
	var cake: Ingredient = transformation.outputs[1]

	_expect_equal("the press refuses what it cannot press", press.load_input(_make_test_ingredient(), 100.0), false)
	_expect_equal("the press takes seeds", press.load_input(seeds, 100.0), true)
	_expect_near("nothing is pressed without work", press.outputs_g.get(oil, 0.0), 0.0)

	# 0.5 turns per gram: 25 turns press 50g.
	_expect_near("work presses seeds in proportion", press.work(25.0), 50.0)
	_expect_near("pressed seeds yield oil", press.outputs_g[oil], 17.5)
	_expect_near("more work than the load needs is wasted", press.work(1000.0), 50.0)
	_expect_near("100g of seeds yields 35g of oil", press.take_output(oil), 35.0)
	_expect_near("and 60g of seed cake", press.take_output(cake), 60.0)
	_expect_near("taken output leaves the press", press.take_output(oil), 0.0)
	_expect_equal("an emptied press takes a new load", press.loaded == null, true)

func _test_chilli_infuses_oil() -> void:
	var oil_flavours := {}
	for temp in [100.0, 200.0]:
		var exposure := _held_exposure(_make_test_oil(), temp)
		exposure.medium_mass_g = 50.0
		var rings := _slice_at_steps(FoodPiece.from_ingredient(_make_test_chilli(), AMBIENT_TEMP_C), Vector3.AXIS_X, 3.0, true)
		for step in 3600:
			for ring in rings:
				FoodHeating.step(ring, exposure, 0.05)
		oil_flavours[temp] = exposure.flavour
	var gentle: FlavourProfile = oil_flavours[100.0]
	var scorching: FlavourProfile = oil_flavours[200.0]
	_expect_equal("chilli held in warm oil makes chilli oil", gentle.heat > 0.1, true)
	_expect_equal("chilli burnt in hot oil turns the oil bitter", scorching.bitter > 2.0 * gentle.bitter, true)

func _test_flavour_follows_solubility() -> void:
	var salted := _make_test_water()
	salted.flavour.salty = 0.5
	var in_brine := _cut_cube(20.0)
	var brine := _held_exposure(salted, 100.0)
	var salted_then_fried := _cut_cube(20.0)
	salted_then_fried.flavour.salty = 0.5
	var salted_then_boiled := _cut_cube(20.0)
	salted_then_boiled.flavour.salty = 0.5
	var oil := _held_exposure(_make_test_oil(), 100.0)
	var water := _held_exposure(_make_test_water(), 100.0)
	for step in 6000:
		FoodHeating.step(in_brine, brine, 0.05)
		FoodHeating.step(salted_then_fried, oil, 0.05)
		FoodHeating.step(salted_then_boiled, water, 0.05)
	_expect_equal("salted water seasons what boils in it", in_brine.flavour.salty > 0.1, true)
	_expect_equal("salt stays in food cooked in oil, which can't dissolve it", salted_then_fried.flavour.salty > 0.4, true)
	_expect_equal("but leaches out into boiling water", salted_then_boiled.flavour.salty < 0.25, true)

	var chilli_in_water := _held_exposure(_make_test_water(), 100.0)
	chilli_in_water.medium_mass_g = 50.0
	var rings := _slice_at_steps(FoodPiece.from_ingredient(_make_test_chilli(), AMBIENT_TEMP_C), Vector3.AXIS_X, 3.0, true)
	for step in 3600:
		for ring in rings:
			FoodHeating.step(ring, chilli_in_water, 0.05)
	_expect_equal("chilli barely heats water: capsaicin dissolves in fat, not water", chilli_in_water.flavour.heat < 0.05, true)

func _test_fried_food_picks_up_flavoured_oil() -> void:
	var chilli_oil := _make_test_oil()
	chilli_oil.flavour.heat = 0.5
	var in_plain := _cut_stick(10.0)
	var in_chilli := _cut_stick(10.0)
	var plain_exposure := _held_exposure(_make_test_oil(), 180.0)
	var chilli_exposure := _held_exposure(chilli_oil, 180.0)
	for step in 6000:
		FoodHeating.step(in_plain, plain_exposure, 0.05)
		FoodHeating.step(in_chilli, chilli_exposure, 0.05)
	_expect_equal("fries fried in chilli oil come out spicy", in_chilli.flavour.heat > in_plain.flavour.heat + 0.05, true)

func _test_equipment_gating() -> void:
	LighthouseProgression.reset()
	for equipment in STARTING_EQUIPMENT:
		_expect_equal("%s is installed from the start" % equipment.id, LighthouseProgression.is_equipment_unlocked(equipment), true)
	var retrofit_only := KitchenEquipment.new()
	retrofit_only.id = &"test_smoker"
	_expect_equal("equipment not installed from the start is locked", LighthouseProgression.is_equipment_unlocked(retrofit_only), false)

# --- Perception and outcome checks ---------------------------------------------

func _test_texture_reads_physical_state() -> void:
	var raw := FoodPerception.texture_of(_cut_stick(10.0))
	var cooked := FoodPerception.texture_of(_fry(180.0, 360.0))
	var soggy := FoodPerception.texture_of(_fry(130.0, 300.0))
	_expect_equal("raw food is firmer than cooked", raw.firmness > cooked.firmness + 0.5, true)
	_expect_equal("cooked food is softer inside than raw", cooked.softness > raw.softness + 0.5, true)
	_expect_equal("hot-fried food is crisp, cool-fried is not", cooked.crispness > soggy.crispness + 0.4, true)
	_expect_equal("cool-fried food is greasier", soggy.greasiness > cooked.greasiness, true)

func _test_appearance_reads_physical_state() -> void:
	var raw := FoodPerception.appearance_of(_cut_stick(10.0))
	var cooked := FoodPerception.appearance_of(_fry(180.0, 360.0))
	var burnt := FoodPerception.appearance_of(_fry(220.0, 360.0))
	_expect_equal("frying browns food visibly", cooked.browning > raw.browning + 0.3, true)
	_expect_equal("cooked flesh turns translucent", cooked.translucency > raw.translucency + 0.5, true)
	_expect_equal("burnt food shows char", burnt.charring > cooked.charring + 0.1, true)
	_expect_equal("fried food glistens", cooked.gloss > 0.3, true)

func _test_bite_sounds() -> void:
	var raw := FoodPerception.bite_of(_cut_stick(10.0))
	var crisp := FoodPerception.bite_of(_fry(180.0, 360.0))
	var soggy := FoodPerception.bite_of(_fry(130.0, 300.0))
	var tender := FoodPerception.bite_of(_boil(25.0, 600.0))
	var mush := FoodPerception.bite_of(_boil(25.0, 1500.0))
	_expect_equal("raw potato crunches", raw.dominant_layer(), BiteSound.Layer.CRUNCH)
	_expect_equal("a well-fried fry is crisp", crisp.dominant_layer(), BiteSound.Layer.CRISP)
	_expect_equal("greasy undercooked fries squelch", soggy.dominant_layer(), BiteSound.Layer.SQUELCH)
	_expect_equal("tender boiled potato bites softly", tender.dominant_layer(), BiteSound.Layer.SOFT)
	_expect_equal("boiled-to-mush potato squelches", mush.dominant_layer(), BiteSound.Layer.SQUELCH)

	var total: float = 0.0
	for layer in crisp.weights:
		total += crisp.weights[layer]
	_expect_near("bite layer weights sum to 1", total, 1.0)
	var thin := FoodPerception.bite_of(_cut_stick(5.0))
	var thick := FoodPerception.bite_of(_cut_stick(15.0))
	_expect_equal("thin pieces bite at a higher pitch", thin.pitch > thick.pitch, true)

func _test_dish_fingerprints() -> void:
	var first_batch := _plate([_fry(180.0, 360.0), _fry(180.0, 360.0), _fry(180.0, 360.0)])
	var second_batch := _plate([_fry(180.0, 360.0), _fry(180.0, 360.0), _fry(180.0, 360.0)])
	_expect_equal("the same dish cooked the same way is recognised", first_batch.fingerprint(), second_batch.fingerprint())

	var burnt := _plate([_fry(220.0, 360.0), _fry(220.0, 360.0)])
	_expect_equal("burnt fries are a different dish", burnt.fingerprint() != first_batch.fingerprint(), true)
	var raw := _plate([_cut_stick(10.0)])
	_expect_equal("raw sticks are a different dish", raw.fingerprint() != first_batch.fingerprint(), true)

	var one_stray := _plate([_fry(180.0, 360.0), _fry(180.0, 360.0), _cut_stick(10.0)])
	_expect_equal("one stray piece doesn't change the dish", one_stray.fingerprint(), first_batch.fingerprint())

	var spicy_oil := _make_test_oil()
	var infused := spicy_oil.flavour.copy()
	infused.heat = 0.3
	var with_plain_oil := _plate([_fry(180.0, 360.0)])
	with_plain_oil.add_liquid(LiquidPortion.new(spicy_oil, 10.0, spicy_oil.flavour))
	var with_chilli_oil := _plate([_fry(180.0, 360.0)])
	with_chilli_oil.add_liquid(LiquidPortion.new(spicy_oil, 10.0, infused))
	_expect_equal("a chilli-oil drizzle makes a different dish", with_chilli_oil.fingerprint() != with_plain_oil.fingerprint(), true)

func _test_dish_nourishment() -> void:
	var perfect := DishNourishment.feeding_result_of(_plate([_fry(180.0, 360.0), _fry(180.0, 360.0)]))
	var burnt := DishNourishment.feeding_result_of(_plate([_fry(220.0, 360.0), _fry(220.0, 360.0)]))
	var raw := DishNourishment.feeding_result_of(_plate([_cut_stick(10.0), _cut_stick(10.0)]))
	_expect_equal("perfect fries carry a spirit further than burnt ones", perfect.ascension_strength > burnt.ascension_strength + 0.2, true)
	_expect_equal("burnt fries still beat raw potato", burnt.ascension_strength > raw.ascension_strength, true)
	_expect_equal("burnt fries still feed a spirit", burnt.nourishment > 0.0 and burnt.ascension_strength >= DishNourishment.QUALITY_FLOOR, true)
	_expect_equal("well-made food nourishes more", perfect.nourishment > burnt.nourishment, true)

	var hot_fry := _fry(180.0, 360.0)
	var cold_fry := hot_fry.clone()
	cold_fry.core_temp_c = AMBIENT_TEMP_C
	cold_fry.surface_temp_c = AMBIENT_TEMP_C
	var hot := DishNourishment.feeding_result_of(_plate([hot_fry]))
	var cold := DishNourishment.feeding_result_of(_plate([cold_fry]))
	_expect_equal("hot food comforts more than cold", hot.calming > cold.calming, true)

	var nothing := DishNourishment.feeding_result_of(Dish.new())
	_expect_near("an empty plate feeds nothing", nothing.nourishment, 0.0)
	_expect_near("legacy feeding results carry full strength", FeedingResult.new().ascension_strength, 1.0)

# --- Kitchen scene checks -------------------------------------------------------

func _test_synthesised_sounds() -> void:
	for bed in SoundSynth.Bed.values():
		var wav := SoundSynth.bed(bed)
		_expect_equal("sound bed %d loops" % bed, wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and wav.loop_end > SoundSynth.MIX_RATE / 2, true)
		_expect_equal("sound bed %d isn't silent" % bed, _peak(wav) > 0.5, true)
	for layer in BiteSound.Layer.values():
		_expect_equal("bite layer %d sounds" % layer, _peak(SoundSynth.bite(layer)) > 0.5, true)

func _peak(wav: AudioStreamWAV) -> float:
	var peak: int = 0
	for offset in range(0, wav.data.size(), 2):
		peak = maxi(peak, absi(wav.data.decode_s16(offset)))
	return peak / 32767.0

func _test_rolling_a_piece() -> void:
	var whole := FoodPiece.from_ingredient(_make_test_ingredient(), AMBIENT_TEMP_C)
	var plank: FoodPiece = FoodCutting.cut(whole, Vector3.AXIS_Z, 10.0, false)[0]
	var mass_before := plank.mass_g()
	plank.roll()
	_expect_equal("rolling a standing plank lays it flat", plank.size_mm.is_equal_approx(Vector3(80.0, 10.0, 40.0)), true)
	_expect_near("rolling doesn't change mass", plank.mass_g(), mass_before)
	_expect_equal("a rolled plank's cut turns with it", plank.cut_axes, [Vector3.AXIS_Y] as Array[int])

	# The fries flow: planks cut along Z, laid flat, cut along Z again. The
	# second pass crosses the first, so it needs the food held steady.
	var sticks := FoodCutting.cut(plank, Vector3.AXIS_Z, 10.0, false)
	_expect_equal("cutting a laid-flat plank into sticks needs steadying", sticks[0].integrity < 1.0, true)

	var long_side := FoodPiece.from_ingredient(_make_test_ingredient(), AMBIENT_TEMP_C)
	long_side.size_mm = Vector3(20.0, 30.0, 70.0)
	long_side.roll()
	_expect_equal("a piece rolls about its longer horizontal axis", long_side.size_mm.is_equal_approx(Vector3(30.0, 20.0, 70.0)), true)

func _test_mezzaluna_gesture() -> void:
	var footprint_min := Vector2(100.0, 200.0)
	var footprint_size := Vector2(80.0, 60.0)
	var across := MezzalunaGesture.resolve(footprint_min, footprint_size, Vector2(80.0, 230.0), Vector2(200.0, 230.0))
	_expect_equal("a stroke along X cuts across Z", across.axis, Vector3.AXIS_Z)
	_expect_near("the cut lands where the stroke crosses", across.offset_mm, 30.0)

	var down := MezzalunaGesture.resolve(footprint_min, footprint_size, Vector2(125.0, 180.0), Vector2(125.0, 280.0))
	_expect_equal("a stroke along Z cuts across X", down.axis, Vector3.AXIS_X)
	_expect_near("its offset is measured from the piece's near face", down.offset_mm, 25.0)

	var slanted := MezzalunaGesture.resolve(footprint_min, footprint_size, Vector2(80.0, 220.0), Vector2(200.0, 240.0))
	_expect_near("a slanted stroke cuts where it passes the piece's centre", slanted.offset_mm, 30.0)

	_expect_equal("a stroke beside the piece cuts nothing",
		MezzalunaGesture.resolve(footprint_min, footprint_size, Vector2(80.0, 300.0), Vector2(200.0, 300.0)) == null, true)
	_expect_equal("a stroke that barely enters the piece cuts nothing",
		MezzalunaGesture.resolve(footprint_min, footprint_size, Vector2(60.0, 230.0), Vector2(120.0, 230.0)) == null, true)
	_expect_equal("a tiny slip of the hand cuts nothing",
		MezzalunaGesture.resolve(footprint_min, footprint_size, Vector2(140.0, 230.0), Vector2(142.0, 230.0)) == null, true)

func _test_kitchen_input_actions() -> void:
	for action in [&"kitchen_steady", &"kitchen_taste", &"camera_pan_left", &"camera_pan_right", &"camera_look_out", &"camera_look_back",
			&"move_forward", &"move_back", &"move_left", &"move_right", &"interact", &"leave_view"]:
		_expect_equal("input action %s is defined" % action, InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(), true)

func _test_kitchen_board_wiring() -> void:
	var kitchen: Kitchen = load("res://scenes/kitchen/kitchen.tscn").instantiate()
	add_child(kitchen)
	var board := kitchen.board
	var potato: Ingredient = KITCHEN_INGREDIENTS[0]
	var view := board.add_whole(potato)
	_expect_equal("a potato from the basket lands on the board", view != null and board.views().size() == 1, true)

	var piece_min := view.position
	var footprint := view.footprint_m()
	var across_middle_z := piece_min.z + footprint.y * 0.5
	var cuts := board.cut_stroke(
		Vector3(piece_min.x - 0.02, 0.0, across_middle_z), Vector3(piece_min.x + footprint.x + 0.02, 0.0, across_middle_z), false
	)
	_expect_equal("a stroke across the potato cuts it in two", cuts == 1 and board.views().size() == 2, true)

	var half: FoodPieceView = board.views()[0]
	var height_before := half.piece.size_mm.y
	board.roll(half)
	_expect_equal("rolling a piece on the board turns it", not is_equal_approx(half.piece.size_mm.y, height_before), true)

	var many := 0
	while board.add_whole(potato) != null and many < 50:
		many += 1
	_expect_equal("the board refuses more potatoes once it is full", many < 50, true)
	kitchen.queue_free()

func _test_view_mode_transitions() -> void:
	var mode := KitchenViewMode.new()
	_expect_equal("the caretaker starts out walking", mode.mode, KitchenViewMode.Mode.WALKING)
	_expect_equal("stepping in out of reach does nothing", mode.step_in(false), false)
	_expect_equal("stepping in within reach starts the glide", mode.step_in(true), true)
	_expect_equal("a second step in mid-glide is ignored", mode.step_in(true), false)
	mode.arrived()
	_expect_equal("the glide in ends at the counter", mode.mode, KitchenViewMode.Mode.AT_COUNTER)
	_expect_equal("Esc at the counter steps back out", mode.step_out(), true)
	mode.arrived()
	_expect_equal("the glide out ends walking", mode.mode, KitchenViewMode.Mode.WALKING)
	_expect_equal("Esc while walking is not a step out", mode.step_out(), false)
	mode.step_in(true)
	_expect_equal("Esc during the glide in turns straight back", mode.step_out(), true)
	_expect_equal("and glides back out", mode.mode, KitchenViewMode.Mode.STEPPING_OUT)

func _test_counter_reach() -> void:
	var counter := Rect2(-0.8, -0.3, 1.6, 0.6)
	_expect_equal("standing at the counter facing it is within reach",
		KitchenViewMode.within_reach(Vector2(0.0, 0.8), Vector2(0.0, -1.0), counter), true)
	_expect_equal("standing at the counter facing away is not",
		KitchenViewMode.within_reach(Vector2(0.0, 0.8), Vector2(0.0, 1.0), counter), false)
	_expect_equal("standing across the terrace is not",
		KitchenViewMode.within_reach(Vector2(0.0, 2.5), Vector2(0.0, -1.0), counter), false)
	_expect_equal("the ends of the counter can be worked at too",
		KitchenViewMode.within_reach(Vector2(1.4, 0.0), Vector2(-1.0, 0.0), counter), true)

func _test_peek_mapping() -> void:
	_expect_near("the mouse in the middle doesn't peek", CounterViews.peek_degrees(0.0), 0.0)
	_expect_near("reaching towards the edge doesn't peek yet", CounterViews.peek_degrees(0.55), 0.0)
	_expect_near("the right edge peeks fully right", CounterViews.peek_degrees(1.0), -CounterViews.PEEK_MAX_DEG)
	_expect_near("the left edge peeks fully left", CounterViews.peek_degrees(-1.0), CounterViews.PEEK_MAX_DEG)
	var monotonic := true
	var previous := 0.0
	for step in range(1, 21):
		var turn := -CounterViews.peek_degrees(step / 20.0)
		monotonic = monotonic and turn >= previous - EPSILON
		previous = turn
	_expect_equal("peeking grows steadily towards the edge", monotonic, true)

func _test_mouse_is_always_locked() -> void:
	_expect_equal("walking captures the mouse",
		Kitchen.mouse_mode_for(KitchenViewMode.Mode.WALKING, false), Input.MOUSE_MODE_CAPTURED)
	_expect_equal("the counter confines the cursor to the window",
		Kitchen.mouse_mode_for(KitchenViewMode.Mode.AT_COUNTER, false), Input.MOUSE_MODE_CONFINED)
	_expect_equal("gliding in keeps it confined",
		Kitchen.mouse_mode_for(KitchenViewMode.Mode.STEPPING_IN, false), Input.MOUSE_MODE_CONFINED)
	_expect_equal("gliding back out captures it again",
		Kitchen.mouse_mode_for(KitchenViewMode.Mode.STEPPING_OUT, false), Input.MOUSE_MODE_CAPTURED)
	_expect_equal("only Esc while walking frees it",
		Kitchen.mouse_mode_for(KitchenViewMode.Mode.WALKING, true), Input.MOUSE_MODE_VISIBLE)
	_expect_equal("and even then the counter still confines it",
		Kitchen.mouse_mode_for(KitchenViewMode.Mode.AT_COUNTER, true), Input.MOUSE_MODE_CONFINED)

## Physics needs real frames, so this runs after the lifecycle simulation,
## at normal time scale.
func _test_caretaker_in_the_kitchen() -> void:
	var kitchen: Kitchen = load("res://scenes/kitchen/kitchen.tscn").instantiate()
	add_child(kitchen)
	var caretaker := kitchen.caretaker
	for frame in 60:
		await get_tree().physics_frame
	_expect_equal("the caretaker stands on the cliff top",
		caretaker.is_on_floor() and absf(caretaker.global_position.y - (-0.9)) < 0.2, true)

	# Walk inland across the terrace, then let go: full speed, then a stop
	# with no sliding.
	caretaker.rotation = Vector3(0.0, PI, 0.0)
	Input.action_press("move_forward")
	for frame in 45:
		await get_tree().physics_frame
	var walking_speed := Vector2(caretaker.velocity.x, caretaker.velocity.z).length()
	Input.action_release("move_forward")
	_expect_near("the caretaker walks at their full pace", walking_speed, caretaker.walk_speed_mps)
	for frame in 9:
		await get_tree().physics_frame
	_expect_equal("letting go stops them within a few frames, without sliding",
		Vector2(caretaker.velocity.x, caretaker.velocity.z).length() < 0.01, true)

	# Walk straight at the cliff edge for longer than it takes to reach it.
	caretaker.global_position = Vector3(2.5, -0.7, 0.0)
	caretaker.rotation = Vector3.ZERO
	for frame in 20:
		await get_tree().physics_frame
	var start_z := caretaker.global_position.z
	Input.action_press("move_forward")
	for frame in 360:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	_expect_equal("walking at the cliff edge gets the caretaker there", caretaker.global_position.z < start_z - 1.0, true)
	_expect_equal("but never over it", caretaker.is_on_floor() and caretaker.global_position.y > -1.6, true)

	# Step up to the board, work, and step back.
	caretaker.global_position = Vector3(-0.2, -0.9, 0.75)
	caretaker.rotation = Vector3.ZERO
	for frame in 10:
		await get_tree().physics_frame
	_expect_equal("standing at the counter puts it within reach", kitchen.counter_in_reach(), true)
	_expect_equal("E steps in", kitchen.step_in(), true)
	await _wait_for_mode(kitchen, KitchenViewMode.Mode.AT_COUNTER)
	_expect_equal("the view settles at the counter", kitchen.view_mode.mode, KitchenViewMode.Mode.AT_COUNTER)
	_expect_equal("at the counter the hand is live and the feet are still",
		kitchen.pointer.enabled and not kitchen.caretaker.control_enabled, true)
	_expect_equal("stepping in faces the station you stood at", kitchen.counter_views.station_index, 0)
	_expect_equal("Esc steps back", kitchen.step_out(), true)
	await _wait_for_mode(kitchen, KitchenViewMode.Mode.WALKING)
	_expect_equal("the view returns to the caretaker's eyes",
		kitchen.view_mode.mode == KitchenViewMode.Mode.WALKING and kitchen.caretaker.control_enabled and not kitchen.pointer.enabled, true)
	kitchen.queue_free()

## The working stations in the real kitchen scene, driven through the same
## signals and calls the player's hands produce.
func _test_kitchen_stations() -> void:
	var kitchen: Kitchen = load("res://scenes/kitchen/kitchen.tscn").instantiate()
	add_child(kitchen)
	await get_tree().process_frame
	var sim := kitchen.simulation
	var pot := sim.pot

	# Turning the knob by hand: a quarter circle round it, counter-clockwise
	# as the cook sees it.
	var knob_grip: Interactable = kitchen.stove.get_node("KnobGrip")
	var knob: Node3D = kitchen.stove.get_node("Model/knob")
	var centre := knob.global_position
	knob_grip.pressed.emit(centre + Vector3(0.02, 0.0, 0.0))
	for step in 9:
		var angle := deg_to_rad(10.0 * (step + 1))
		knob_grip.dragged.emit(centre + Vector3(cos(angle), sin(angle), 0.0) * 0.02)
	knob_grip.released.emit(centre)
	_expect_equal("a quarter circle round the knob turns it a quarter turn", absf(kitchen.stove.knob_deg - 90.0) < 0.5, true)
	_expect_near("and opens the gas a third of the way", pot.flame_level, 90.0 / 270.0)
	for step in 30:
		var angle := deg_to_rad(90.0 + 15.0 * (step + 1))
		knob_grip.dragged.emit(centre + Vector3(cos(angle), sin(angle), 0.0) * 0.02)
	_expect_near("the knob stops at full", kitchen.stove.knob_deg, StoveView.FULL_TURN_DEG)

	kitchen.stove.set_knob(135.0)
	_expect_near("half the knob's travel is half the gas", pot.flame_level, 0.5)
	kitchen.stove.set_knob(0.0)
	_expect_near("turning the knob back to off puts the flame out", pot.flame_level, 0.0)

	var poured := sim.pour_into_pot(sim.jug, 80.0, 5.0)
	_expect_equal("the jug pours water into the pot", poured > 0.0 and is_equal_approx(pot.medium_mass_g, poured), true)
	_expect_near("the jug never runs dry", sim.jug.fill_fraction(), 1.0)
	_expect_near("oil can't be poured into a pot of water", sim.pour_into_pot(sim.cup, 25.0, 1.0), 0.0)
	kitchen.pot_view.get_node("Mouth").secondary_pressed.emit(kitchen.pot_view.global_position)
	_expect_equal("right-clicking the pot tips its water out", pot.medium == null, true)

	var seeds: Ingredient = sim.seeds
	kitchen.seed_source.taken.emit(seeds, 50.0)
	_expect_near("rubbing the sunflower head fills the hopper", sim.press.loaded_g, 50.0)
	_expect_near("turning the crank backwards presses nothing", kitchen.press_view.turn_crank(-1.0), 0.0)
	kitchen.press_view.turn_crank(2.5)
	_expect_near("two and a half turns press 50g of seed into 17.5g of oil in the cup", sim.cup.grams, 17.5)
	_expect_near("and push out the seed cake", sim.cake_g, 30.0)
	sim.pour_into(sim.cup, sim.bottle, 25.0, 10.0)
	_expect_equal("the cup pours into the bottle", is_equal_approx(sim.bottle.grams, 17.5) and sim.cup.is_empty(), true)

	# Pouring by hand: lift the corked bottle over the pot, then uncork it.
	var bottle: PourVesselView = kitchen.get_node("OilBottle")
	var bottle_grip: Interactable = bottle.get_node("Grip")
	var over_pot := kitchen.pot_view.global_position + Vector3(0.02, 0.0, 0.0)
	bottle_grip.pressed.emit(bottle.global_position)
	bottle_grip.dragged.emit(Vector3(over_pot.x, 0.0, over_pot.z))
	for frame in 90:
		await get_tree().process_frame
	_expect_equal("a corked bottle held over the pot pours nothing", pot.medium == null, true)
	bottle_grip.secondary_pressed.emit(bottle.global_position)
	var waited: int = 0
	while sim.bottle.grams > 0.0 and waited < 600:
		await get_tree().process_frame
		waited += 1
	bottle_grip.released.emit(bottle.global_position)
	_expect_equal("uncorked and tipped, the bottle pours its oil into the pot",
		pot.medium == sim.oil and is_equal_approx(pot.medium_mass_g, 17.5), true)

	# Cranking by hand: two full circles round the axle, clockwise on screen.
	kitchen.seed_source.taken.emit(seeds, 50.0)
	var crank_grip: Interactable = kitchen.press_view.get_node("CrankGrip")
	var crank: Node3D = kitchen.press_view.get_node("Model/crank")
	crank_grip.pressed.emit(crank.global_position + Vector3(0.03, 0.0, 0.0))
	var plane: Plane = crank_grip.drag_plane
	var u := plane.normal.cross(Vector3.UP).normalized()
	var v := plane.normal.cross(u).normalized()
	var cup_before: float = sim.cup.grams
	for step in 72:
		var angle := -deg_to_rad(10.0 * (step + 1))
		crank_grip.dragged.emit(crank.global_position + (u * cos(angle) + v * sin(angle)) * 0.03)
	_expect_equal("circling the crank presses oil into the cup", sim.cup.grams > cup_before + 10.0, true)

	pot.add_medium(sim.oil, 300.0, AMBIENT_TEMP_C)
	var board := kitchen.board
	var whole := board.add_whole(KITCHEN_INGREDIENTS[0])
	_expect_equal("food on the board rests in the board's simulation", sim.board.pieces.has(whole.piece), true)
	var across := whole.position.z + whole.footprint_m().y * 0.5
	board.cut_stroke(Vector3(whole.position.x - 0.02, 0.0, across), Vector3(whole.position.x + whole.footprint_m().x + 0.02, 0.0, across), true)
	var halves := board.touching_cluster(board.views()[0])
	_expect_equal("a freshly cut potato's halves lift together", halves.size(), 2)
	var lifted: Array[FoodPiece] = []
	for view in halves:
		lifted.append(view.piece)
	_expect_equal("food let go beside the pot stays out of it", kitchen.drop_into_pot(lifted, board.global_position), false)
	_expect_equal("food let go over the pot is taken", kitchen.drop_into_pot(lifted, kitchen.pot_view.global_position + Vector3(0.0, 0.2, 0.0)), true)
	_expect_equal("and lands in it", pot.pieces.size(), 2)
	for frame in 3:
		await get_tree().process_frame
	_expect_equal("the pot draws the food in it", kitchen.pot_view.view_of(lifted[0]) != null, true)

	# The spoon: press in the pot over a piece, drag out over the rim, let
	# go over the board.
	var mouth: Interactable = kitchen.pot_view.get_node("Mouth")
	var placement := pot.placement_of(lifted[0])
	var in_pot := kitchen.pot_view.to_global(Vector3(placement.centre_mm.x * 0.001, PotView.RIM_Y_M, placement.centre_mm.y * 0.001))
	mouth.pressed.emit(in_pot)
	mouth.dragged.emit(kitchen.pot_view.to_global(Vector3(0.2, PotView.RIM_Y_M, 0.0)))
	_expect_equal("dragging the spoon out over the rim lifts what it caught", kitchen.pot_view.lifted.size() >= 1, true)
	_expect_equal("lifted food drains in the air", sim.held.pieces.has(kitchen.pot_view.lifted[0]), true)
	var on_board_before := board.views().size()
	mouth.released.emit(board.global_position)
	_expect_equal("letting the spoon go over the board sets the food down there",
		board.views().size() > on_board_before and pot.pieces.size() < 2 and sim.held.pieces.is_empty(), true)

	var taste_view: FoodPieceView = board.views()[board.views().size() - 1]
	var mass_before := taste_view.piece.mass_g()
	var note := board.taste(taste_view)
	_expect_equal("tasting raw potato says it's raw", note.contains("raw"), true)
	_expect_equal("and says how hot it is", note.contains("Cold"), true)
	var bitten: FoodPieceView = board.views()[board.views().size() - 1]
	_expect_equal("a bite comes off the piece", bitten.piece.mass_g() < mass_before - 1.0, true)

	kitchen.stove.set_knob(270.0)
	var oil_before: float = pot.temp_c
	for frame in 30:
		await get_tree().physics_frame
	_expect_equal("the kitchen's simulation runs while you play", pot.temp_c > oil_before, true)
	_expect_equal("the burner roars while it's lit", kitchen.audio.gas.playing, true)
	kitchen.stove.set_knob(0.0)
	# process_frame fires before nodes process, so give the sound a frame.
	for frame in 2:
		await get_tree().process_frame
	_expect_equal("and falls quiet when it's out", kitchen.audio.gas.playing, false)
	_expect_equal("cold oil doesn't sizzle", kitchen.audio.sizzle.playing, false)
	kitchen.queue_free()

func _wait_for_mode(kitchen: Kitchen, mode: KitchenViewMode.Mode) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while kitchen.view_mode.mode != mode and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

## A 10mm fry of the test ingredient, held in oil at the given temperature.
func _fry(temp_c: float, seconds: float) -> FoodPiece:
	var fry := _cut_stick(10.0)
	var exposure := _held_exposure(_make_test_oil(), temp_c)
	for step in roundi(seconds / 0.05):
		FoodHeating.step(fry, exposure, 0.05)
	return fry

func _boil(size_mm: float, seconds: float) -> FoodPiece:
	var cube := _cut_cube(size_mm)
	var exposure := _held_exposure(_make_test_water(), 100.0)
	for step in roundi(seconds / 0.05):
		FoodHeating.step(cube, exposure, 0.05)
	return cube

func _plate(pieces: Array[FoodPiece]) -> Dish:
	var dish := Dish.new()
	for piece in pieces:
		dish.add_piece(piece)
	return dish

func _make_test_press_transformation() -> Transformation:
	var seeds := Ingredient.new()
	seeds.id = &"test_seeds"
	seeds.physical_form = Ingredient.PhysicalForm.GRANULAR
	seeds.fat_fraction = 0.5
	seeds.protein_fraction = 0.2
	seeds.flavour = FlavourProfile.new()

	var cake := Ingredient.new()
	cake.id = &"test_cake"
	cake.physical_form = Ingredient.PhysicalForm.GRANULAR
	cake.fat_fraction = 0.25
	cake.protein_fraction = 0.3
	cake.flavour = FlavourProfile.new()

	var press := KitchenEquipment.new()
	press.id = &"test_press"

	var transformation := Transformation.new()
	transformation.id = &"test_press_seeds"
	transformation.equipment = press
	transformation.input = seeds
	transformation.outputs = [_make_test_oil(), cake]
	transformation.output_yields = [0.35, 0.6]
	transformation.work_per_gram = 0.5
	return transformation

func _make_test_chilli() -> Ingredient:
	var chilli := Ingredient.new()
	chilli.id = &"test_chilli"
	chilli.physical_form = Ingredient.PhysicalForm.SOLID
	chilli.whole_size_mm = Vector3(70.0, 18.0, 18.0)
	chilli.density_g_per_cm3 = 0.6
	chilli.water_fraction = 0.88
	chilli.sugar_fraction = 0.05
	chilli.protein_fraction = 0.019
	chilli.stable_thickness_mm = 1.5
	chilli.specific_heat_j_per_g_k = 3.9
	chilli.thermal_conductivity_w_per_m_k = 0.5
	chilli.cook_temp_c = 60.0
	chilli.cook_seconds = 60.0
	chilli.overcook_softening_per_s = 0.003
	chilli.char_susceptibility = 6.0
	chilli.flavour = FlavourProfile.new()
	chilli.flavour.heat = 0.9
	chilli.flavour.aroma = 0.5
	return chilli

func _make_test_stove() -> HeatSource:
	var stove := HeatSource.new()
	stove.id = &"test_stove"
	stove.max_power_w = 2000.0
	stove.min_flame_level = 0.15
	return stove

func _make_test_vessel() -> CookingVessel:
	var vessel := CookingVessel.new()
	vessel.id = &"test_pot"
	vessel.mass_g = 1500.0
	vessel.specific_heat_j_per_g_k = 0.5
	vessel.capacity_ml = 3000.0
	vessel.dry_contact_w_per_m2_k = 400.0
	return vessel

func _make_test_oil() -> Ingredient:
	var oil := Ingredient.new()
	oil.id = &"test_oil"
	oil.physical_form = Ingredient.PhysicalForm.LIQUID
	oil.density_g_per_cm3 = 0.92
	oil.fat_fraction = 1.0
	oil.specific_heat_j_per_g_k = 2.0
	oil.medium_heat_transfer_w_per_m2_k = 350.0
	oil.flavour = FlavourProfile.new()
	return oil

func _make_test_water() -> Ingredient:
	var water := Ingredient.new()
	water.id = &"test_water"
	water.physical_form = Ingredient.PhysicalForm.LIQUID
	water.density_g_per_cm3 = 1.0
	water.water_fraction = 1.0
	water.specific_heat_j_per_g_k = 4.18
	water.boiling_point_c = 100.0
	water.latent_heat_j_per_g = 2257.0
	water.medium_heat_transfer_w_per_m2_k = 600.0
	water.flavour = FlavourProfile.new()
	return water

func _make_test_oil_pot() -> CookingPot:
	var pot := CookingPot.new(_make_test_vessel(), AMBIENT_TEMP_C)
	pot.burner = _make_test_stove()
	pot.add_medium(_make_test_oil(), 1000.0, AMBIENT_TEMP_C)
	return pot

func _make_test_oil_pot_with(grams: float, oil: Ingredient = null) -> CookingPot:
	var pot := CookingPot.new(_make_test_vessel(), AMBIENT_TEMP_C)
	pot.burner = _make_test_stove()
	pot.add_medium(oil if oil else _make_test_oil(), grams, AMBIENT_TEMP_C)
	pot.set_flame(1.0)
	return pot

## Oil with a smoke point and breakdown, like sunflower oil.
func _make_test_frying_oil() -> Ingredient:
	var oil := _make_test_oil()
	oil.smoke_point_c = 210.0
	oil.breakdown_per_hour_at_180c = 0.1
	oil.breakdown_per_g_steam_per_kg = 0.000125
	return oil

## Works the flame the way a cook would to hold the oil near a temperature.
func _hold_temperature(pot: CookingPot, target_c: float, seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		pot.set_flame(1.0 if pot.temp_c < target_c - 1.0 else (0.0 if pot.temp_c > target_c + 1.0 else 0.4))
		pot.advance(0.5)
		elapsed += 0.5

func _make_trait(effect: MysticTrait.Effect, magnitude: float, trigger: MysticTrait.Trigger, threshold: float) -> MysticTrait:
	var made := MysticTrait.new()
	made.id = StringName("test_%d_%d" % [effect, randi()])
	made.effect = effect
	made.magnitude = magnitude
	made.trigger = trigger
	made.trigger_threshold = threshold
	return made

func _with_trait(ingredient: Ingredient, mystic_trait: MysticTrait, concentration: float) -> Ingredient:
	var dose := TraitDose.new()
	dose.mystic_trait = mystic_trait
	dose.concentration = concentration
	ingredient.traits.append(dose)
	return ingredient

func _cut_stick_of(ingredient: Ingredient, thickness_mm: float) -> FoodPiece:
	var plank: FoodPiece = FoodCutting.cut(FoodPiece.from_ingredient(ingredient, AMBIENT_TEMP_C), Vector3.AXIS_Z, thickness_mm, true)[0]
	return FoodCutting.cut(plank, Vector3.AXIS_Y, thickness_mm, true)[0]

func _cut_cube_of(ingredient: Ingredient, size_mm: float) -> FoodPiece:
	return FoodCutting.cut(_cut_stick_of(ingredient, size_mm), Vector3.AXIS_X, size_mm, true)[0]

func _fry_of(ingredient: Ingredient, temp_c: float, seconds: float) -> FoodPiece:
	var fry := _cut_stick_of(ingredient, 10.0)
	var exposure := _held_exposure(_make_test_oil(), temp_c)
	for step in roundi(seconds / 0.05):
		FoodHeating.step(fry, exposure, 0.05)
	return fry

## Seconds of simulated time until the pot reaches the temperature, or the
## limit if it never does.
func _heat_until(pot: CookingPot, target_c: float, limit_s: float) -> float:
	var seconds: float = 0.0
	while pot.temp_c < target_c and seconds < limit_s:
		pot.advance(1.0)
		seconds += 1.0
	return seconds

## A medium held at a fixed temperature, as if the player were keeping the
## flame exactly right.
func _held_exposure(medium: Ingredient, temp_c: float) -> HeatExposure:
	var exposure := HeatExposure.new()
	exposure.temp_c = temp_c
	exposure.heat_transfer_w_per_m2_k = medium.medium_heat_transfer_w_per_m2_k
	exposure.fat_fraction = medium.fat_fraction
	exposure.water_fraction = medium.water_fraction
	exposure.flavour = medium.flavour.copy()
	exposure.medium_mass_g = 1000.0
	return exposure

func _seconds_until_core_reaches(piece: FoodPiece, exposure: HeatExposure, temp_c: float) -> float:
	var seconds: float = 0.0
	while piece.core_temp_c < temp_c and seconds < 1800.0:
		FoodHeating.step(piece, exposure, 0.05)
		seconds += 0.05
	return seconds

func _seconds_until_cooked(piece: FoodPiece, exposure: HeatExposure) -> float:
	var seconds: float = 0.0
	while piece.core_doneness < 1.0 and seconds < 1800.0:
		FoodHeating.step(piece, exposure, 0.05)
		seconds += 0.05
	return seconds

## A full-length stick of the test ingredient with a square cross-section.
func _cut_stick(thickness_mm: float) -> FoodPiece:
	var whole := FoodPiece.from_ingredient(_make_test_ingredient(), AMBIENT_TEMP_C)
	var plank: FoodPiece = FoodCutting.cut(whole, Vector3.AXIS_Z, thickness_mm, true)[0]
	return FoodCutting.cut(plank, Vector3.AXIS_Y, thickness_mm, true)[0]

func _cut_cube(size_mm: float) -> FoodPiece:
	return FoodCutting.cut(_cut_stick(size_mm), Vector3.AXIS_X, size_mm, true)[0]

func _make_test_ingredient() -> Ingredient:
	var ingredient := Ingredient.new()
	ingredient.id = &"test_potato"
	ingredient.physical_form = Ingredient.PhysicalForm.SOLID
	ingredient.whole_size_mm = Vector3(80.0, 40.0, 60.0)
	ingredient.density_g_per_cm3 = 1.0
	ingredient.water_fraction = 0.8
	ingredient.starch_fraction = 0.15
	ingredient.sugar_fraction = 0.008
	ingredient.protein_fraction = 0.02
	ingredient.stable_thickness_mm = 4.0
	ingredient.unsteadied_cut_integrity_loss = 0.5
	ingredient.specific_heat_j_per_g_k = 3.5
	ingredient.thermal_conductivity_w_per_m_k = 0.55
	ingredient.cook_temp_c = 65.0
	ingredient.cook_seconds = 320.0
	ingredient.overcook_softening_per_s = 0.0015
	ingredient.ideal_doneness_min = 1.0
	ingredient.ideal_doneness_max = 2.0
	ingredient.flavour = FlavourProfile.new()
	return ingredient

## Cuts a piece into slices of step_mm along one axis; the last slice takes
## whatever remains, which is never thinner than a step.
func _slice_at_steps(piece: FoodPiece, axis: int, step_mm: float, steadied: bool) -> Array[FoodPiece]:
	var slices: Array[FoodPiece] = []
	var remainder := piece
	while remainder.size_mm[axis] >= step_mm + FoodCutting.MIN_PIECE_THICKNESS_MM:
		var parts := FoodCutting.cut(remainder, axis, step_mm, steadied)
		slices.append(parts[0])
		remainder = parts[1]
	slices.append(remainder)
	return slices

func _all_intact(pieces: Array[FoodPiece]) -> bool:
	for piece in pieces:
		if not is_equal_approx(piece.integrity, 1.0):
			return false
	return true

# --- Lighthouse progression checks --------------------------------------------

func _test_progression_economy() -> void:
	LighthouseProgression.reset()
	_expect_equal("progression starts dark", LighthouseProgression.light, 0)

	LighthouseProgression.add_light(10)
	_expect_equal("light accrues", LighthouseProgression.light, 10)

	_expect_equal(
		"an affordable prerequisite-free upgrade can be bought",
		LighthouseProgression.can_purchase(&"restored_burner"),
		true
	)
	_expect_equal("purchase succeeds", LighthouseProgression.purchase(&"restored_burner"), true)
	_expect_equal("purchase deducts its cost", LighthouseProgression.light, 4)
	_expect_equal("purchase is recorded", LighthouseProgression.is_purchased(&"restored_burner"), true)

	_expect_equal(
		"an upgrade cannot be bought twice",
		LighthouseProgression.purchase(&"restored_burner"),
		false
	)
	_expect_equal(
		"an unaffordable upgrade is refused",
		LighthouseProgression.purchase(&"cliff_garden_terrace"),
		false
	)
	_expect_equal(
		"an upgrade with unmet prerequisites is refused even when affordable",
		LighthouseProgression.can_purchase(&"drift_net_rigging"),
		false
	)

	LighthouseProgression.add_light(50)
	_expect_equal(
		"prerequisites satisfied by an earlier purchase unblock the next tier",
		LighthouseProgression.can_purchase(&"brewing_retort"),
		true
	)
	_expect_equal(
		"drift nets stay blocked until the terrace is built",
		LighthouseProgression.can_purchase(&"drift_net_rigging"),
		false
	)
	# restored_burner is bought; terrace and retort are now offerable, drift nets are not.
	_expect_equal("offered upgrades respect prerequisites", LighthouseProgression.available_upgrades().size(), 2)

	_expect_near(
		"station nourishment reflects the restored burner",
		LighthouseProgression.station_nourishment_multiplier(),
		1.15
	)
	LighthouseProgression.purchase(&"brewing_retort")
	_expect_near(
		"station calming reflects the brewing retort",
		LighthouseProgression.station_calming_multiplier(),
		1.25
	)

func _test_progression_unlocks() -> void:
	LighthouseProgression.reset()
	_expect_equal(
		"starter ingredients are foraged from the start",
		LighthouseProgression.is_ingredient_unlocked(SEA_KELP),
		true
	)
	_expect_equal(
		"cliff herbs are gated behind the terrace",
		LighthouseProgression.is_ingredient_unlocked(CLIFF_GARDEN_HERB),
		false
	)
	LighthouseProgression.add_light(100)
	LighthouseProgression.purchase(&"restored_burner")
	LighthouseProgression.purchase(&"cliff_garden_terrace")
	_expect_equal(
		"the terrace unlocks cliff herbs",
		LighthouseProgression.is_ingredient_unlocked(CLIFF_GARDEN_HERB),
		true
	)

func _test_progression_persistence() -> void:
	LighthouseProgression.reset()
	LighthouseProgression.add_light(40)
	LighthouseProgression.purchase(&"restored_burner")
	var expected_light: int = LighthouseProgression.light
	_expect_equal("save writes without error", LighthouseProgression.save(), OK)

	LighthouseProgression.reset()
	_expect_equal("reset clears light", LighthouseProgression.light, 0)
	_expect_equal("reset clears purchases", LighthouseProgression.is_purchased(&"restored_burner"), false)

	_expect_equal("load reports success", LighthouseProgression.load_saved(), true)
	_expect_equal("light survives a save/load round trip", LighthouseProgression.light, expected_light)
	_expect_equal(
		"purchases survive a save/load round trip",
		LighthouseProgression.is_purchased(&"restored_burner"),
		true
	)

# --- Scene plumbing -----------------------------------------------------------

func _spawn(spawn_position: Vector3) -> SpiritController:
	var spirit: SpiritController = SPIRIT_SCENE.instantiate()
	spirit.archetype = TEST_ARCHETYPE
	spirit.arrival_anchor = $ArrivalAnchor
	spirit.position = spawn_position
	add_child(spirit)
	return spirit

## Half a potato's fries with simmered kelp and clams: mostly tide by mass,
## so it matches the test spirit, and two plates carry it to the moon.
func _tide_plate_pieces() -> Array[FoodPiece]:
	var pieces: Array[FoodPiece] = []
	var fries := CookedPlates.cooked_sticks(KITCHEN_INGREDIENTS[0], 10.0, _make_test_oil(), 180.0, 360.0)
	pieces.append_array(fries.slice(0, fries.size() / 2))
	pieces.append_array(CookedPlates.cooked_whole(SEA_KELP, 2, KITCHEN_INGREDIENTS[3], 100.0, 150.0))
	pieces.append_array(CookedPlates.cooked_whole(TIDE_POOL_CLAM, 2, KITCHEN_INGREDIENTS[3], 100.0, 180.0))
	return pieces

func _serve_tide_dish(spirit: SpiritController) -> bool:
	var copies: Array[FoodPiece] = []
	for piece in _tide_plate:
		copies.append(piece.clone())
	return _serving_station.serve(CookedPlates.plate(copies), spirit)

func _on_state_changed(spirit_id: StringName, old_state: int, new_state: int) -> void:
	var label := "%s->%s" % [STATE_NAMES[old_state], STATE_NAMES[new_state]]
	if is_instance_valid(_fed_spirit) and spirit_id == _fed_spirit.spirit_id:
		_fed_transitions.append(label)
	elif is_instance_valid(_neglected_spirit) and spirit_id == _neglected_spirit.spirit_id:
		_neglected_transitions.append(label)

func _on_lifecycle_complete(spirit_id: StringName, outcome: StringName) -> void:
	if is_instance_valid(_fed_spirit) and spirit_id == _fed_spirit.spirit_id:
		_fed_outcome = str(outcome)
	elif is_instance_valid(_neglected_spirit) and spirit_id == _neglected_spirit.spirit_id:
		_neglected_outcome = str(outcome)

# --- Assertions and reporting -------------------------------------------------

func _finish() -> void:
	_finished = true
	Engine.time_scale = 1.0

	_expect_equal(
		"fed spirit walks the full ascension path",
		_fed_transitions,
		["ARRIVING->SEEKING", "SEEKING->WAITING", "WAITING->FED", "FED->ASCENDING", "ASCENDING->DEPARTED"]
	)
	_expect_equal("fed spirit outcome", _fed_outcome, "ASCENDED")
	_expect_equal(
		"neglected spirit walks the distress path",
		_neglected_transitions,
		["ARRIVING->SEEKING", "SEEKING->WAITING", "WAITING->DISTRESSED", "DISTRESSED->DEPARTED"]
	)
	_expect_equal("neglected spirit outcome", _neglected_outcome, "UNFED")
	_expect_equal("affinity-matched dish fully feeds in 2 servings", _feed_count, 2)
	# Counted from the spirit_ascended / spirit_departed_unfed signals rather
	# than from the progression total, so the light assertion below is checked
	# against an independent observation instead of restating the constant.
	_expect_equal("exactly one spirit ascended", _ascended_count, 1)
	_expect_equal("exactly one spirit departed unfed", _departed_unfed_count, 1)
	_expect_equal(
		"light is awarded for ascensions only, never for spirits lost",
		LighthouseProgression.light,
		LighthouseProgression.LIGHT_PER_ASCENSION * _ascended_count
	)

	await _test_caretaker_in_the_kitchen()
	await _test_kitchen_stations()

	print("")
	print("fed path:       ", _fed_transitions, " -> ", _fed_outcome)
	print("neglected path: ", _neglected_transitions, " -> ", _neglected_outcome)
	print("servings needed: ", _feed_count)
	print("light earned:    ", LighthouseProgression.light)
	print("")
	if _failures.is_empty():
		print("RESULT: PASS (%d checks)" % _checks_run)
		get_tree().quit(0)
	else:
		for failure in _failures:
			print("FAIL: ", failure)
		print("RESULT: FAIL (%d of %d checks)" % [_failures.size(), _checks_run])
		get_tree().quit(1)

func _expect_equal(what: String, actual: Variant, expected: Variant) -> void:
	_checks_run += 1
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [what, expected, actual])

func _expect_near(what: String, actual: float, expected: float) -> void:
	_checks_run += 1
	if absf(actual - expected) > EPSILON:
		_failures.append("%s: expected %s, got %s" % [what, expected, actual])
