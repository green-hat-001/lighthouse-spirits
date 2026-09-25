extends Node3D

## Automated headless integration test for the full pipeline:
##   LighthouseProgression -> CulinaryCraftingMatrix -> DishServingStation
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
const SIMMERED: PreparationTechnique = preload("res://data/techniques/simmered.tres")
const RAW: PreparationTechnique = preload("res://data/techniques/raw.tres")
const SEASONED: PreparationTechnique = preload("res://data/techniques/seasoned.tres")

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
	_test_crafting_math()
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
	_test_shipped_transformations_validate()
	_test_transformation_validation()
	_test_press_turns_work_into_oil()
	_test_chilli_infuses_oil()
	_test_fried_food_picks_up_flavoured_oil()
	_test_equipment_gating()
	_test_texture_reads_physical_state()
	_test_appearance_reads_physical_state()
	_test_bite_sounds()
	_test_dish_fingerprints()
	_test_dish_nourishment()
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
			var locked_dish := CraftedDish.new()
			locked_dish.add_component(CLIFF_GARDEN_HERB, SEASONED)
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

# --- Pure unit checks on the crafting matrix ----------------------------------

func _test_crafting_math() -> void:
	var dish := CraftedDish.new()
	dish.add_component(SEA_KELP, SIMMERED)
	dish.add_component(TIDE_POOL_CLAM, RAW)
	var result: FeedingResult = CulinaryCraftingMatrix.compute_feeding_result(dish)

	# kelp: 10*1.3+0 = 13   | clam: 20*1.0+0 = 20   -> 33
	_expect_near("crafting nourishment", result.nourishment, 33.0)
	# kelp: 25*1.5+5 = 42.5 | clam: 10*1.0+0 = 10   -> 52.5
	_expect_near("crafting calming", result.calming, 52.5)
	# kelp: 0.05           | clam: 0.1             -> 0.15
	_expect_near("crafting buoyancy_delta", result.buoyancy_delta, 0.15)

	var empty := CraftedDish.new()
	var empty_result: FeedingResult = CulinaryCraftingMatrix.compute_feeding_result(empty)
	_expect_near("empty dish nourishment", empty_result.nourishment, 0.0)

func _test_dominant_affinity() -> void:
	var tide_dish := CraftedDish.new()
	tide_dish.add_component(SEA_KELP, RAW)
	tide_dish.add_component(TIDE_POOL_CLAM, RAW)
	tide_dish.add_component(CLIFF_GARDEN_HERB, RAW)
	_expect_equal(
		"dominant affinity favours the majority tag",
		CulinaryCraftingMatrix.dominant_affinity(tide_dish),
		ElementalAffinity.Type.TIDE
	)

	var wind_dish := CraftedDish.new()
	wind_dish.add_component(CLIFF_GARDEN_HERB, RAW)
	_expect_equal(
		"dominant affinity of a single-herb dish",
		CulinaryCraftingMatrix.dominant_affinity(wind_dish),
		ElementalAffinity.Type.WIND
	)

	var empty := CraftedDish.new()
	_expect_equal(
		"dominant affinity of an empty dish is NONE",
		CulinaryCraftingMatrix.dominant_affinity(empty),
		ElementalAffinity.Type.NONE
	)

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

	pot.set_flame(0.2)
	pot.advance(120.0)
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
	# the heat the oil is missing - less the extra the cooler pot didn't lose.
	var missing_heat_j: float = (empty_pot.temp_c - batch_pot.temp_c) * batch_pot.heat_capacity_j_per_k()
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
		for step in 6000:
			FoodHeating.step(fry, exposure, 0.05)
		fries[temp] = fry
	var cool: FoodPiece = fries[130.0]
	var right: FoodPiece = fries[180.0]
	var hot: FoodPiece = fries[220.0]
	_expect_equal("fries at 180C cook through in five minutes", right.core_doneness >= 1.0, true)
	_expect_equal("fries at 130C are still raw inside at five minutes", cool.core_doneness < 1.0, true)
	_expect_equal("hotter oil browns fries more", right.surface_browning > cool.surface_browning + 0.2, true)
	_expect_equal("fries at 180C do not burn in five minutes", right.surface_char < 0.05, true)
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
	for step in 7200:
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
	var cooked := FoodPerception.texture_of(_fry(180.0, 300.0))
	var soggy := FoodPerception.texture_of(_fry(130.0, 300.0))
	_expect_equal("raw food is firmer than cooked", raw.firmness > cooked.firmness + 0.5, true)
	_expect_equal("cooked food is softer inside than raw", cooked.softness > raw.softness + 0.5, true)
	_expect_equal("hot-fried food is crisp, cool-fried is not", cooked.crispness > soggy.crispness + 0.4, true)
	_expect_equal("cool-fried food is greasier", soggy.greasiness > cooked.greasiness, true)

func _test_appearance_reads_physical_state() -> void:
	var raw := FoodPerception.appearance_of(_cut_stick(10.0))
	var cooked := FoodPerception.appearance_of(_fry(180.0, 300.0))
	var burnt := FoodPerception.appearance_of(_fry(220.0, 420.0))
	_expect_equal("frying browns food visibly", cooked.browning > raw.browning + 0.3, true)
	_expect_equal("cooked flesh turns translucent", cooked.translucency > raw.translucency + 0.5, true)
	_expect_equal("burnt food shows char", burnt.char > cooked.char + 0.1, true)
	_expect_equal("fried food glistens", cooked.gloss > 0.3, true)

func _test_bite_sounds() -> void:
	var raw := FoodPerception.bite_of(_cut_stick(10.0))
	var crisp := FoodPerception.bite_of(_fry(180.0, 300.0))
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
	var first_batch := _plate([_fry(180.0, 300.0), _fry(180.0, 300.0), _fry(180.0, 300.0)])
	var second_batch := _plate([_fry(180.0, 300.0), _fry(180.0, 300.0), _fry(180.0, 300.0)])
	_expect_equal("the same dish cooked the same way is recognised", first_batch.fingerprint(), second_batch.fingerprint())

	var burnt := _plate([_fry(220.0, 420.0), _fry(220.0, 420.0)])
	_expect_equal("burnt fries are a different dish", burnt.fingerprint() != first_batch.fingerprint(), true)
	var raw := _plate([_cut_stick(10.0)])
	_expect_equal("raw sticks are a different dish", raw.fingerprint() != first_batch.fingerprint(), true)

	var one_stray := _plate([_fry(180.0, 300.0), _fry(180.0, 300.0), _cut_stick(10.0)])
	_expect_equal("one stray piece doesn't change the dish", one_stray.fingerprint(), first_batch.fingerprint())

	var spicy_oil := _make_test_oil()
	var infused := spicy_oil.flavour.copy()
	infused.heat = 0.3
	var with_plain_oil := _plate([_fry(180.0, 300.0)])
	with_plain_oil.add_liquid(LiquidPortion.new(spicy_oil, 10.0, spicy_oil.flavour))
	var with_chilli_oil := _plate([_fry(180.0, 300.0)])
	with_chilli_oil.add_liquid(LiquidPortion.new(spicy_oil, 10.0, infused))
	_expect_equal("a chilli-oil drizzle makes a different dish", with_chilli_oil.fingerprint() != with_plain_oil.fingerprint(), true)

func _test_dish_nourishment() -> void:
	var perfect := DishNourishment.feeding_result_of(_plate([_fry(180.0, 300.0), _fry(180.0, 300.0)]))
	var burnt := DishNourishment.feeding_result_of(_plate([_fry(220.0, 420.0), _fry(220.0, 420.0)]))
	var raw := DishNourishment.feeding_result_of(_plate([_cut_stick(10.0), _cut_stick(10.0)]))
	_expect_equal("perfect fries carry a spirit further than burnt ones", perfect.ascension_strength > burnt.ascension_strength + 0.2, true)
	_expect_equal("burnt fries still beat raw potato", burnt.ascension_strength > raw.ascension_strength, true)
	_expect_equal("burnt fries still feed a spirit", burnt.nourishment > 0.0 and burnt.ascension_strength >= DishNourishment.QUALITY_FLOOR, true)
	_expect_equal("well-made food nourishes more", perfect.nourishment > burnt.nourishment, true)

	var hot_fry := _fry(180.0, 300.0)
	var cold_fry := hot_fry.clone()
	cold_fry.core_temp_c = AMBIENT_TEMP_C
	cold_fry.surface_temp_c = AMBIENT_TEMP_C
	var hot := DishNourishment.feeding_result_of(_plate([hot_fry]))
	var cold := DishNourishment.feeding_result_of(_plate([cold_fry]))
	_expect_equal("hot food comforts more than cold", hot.calming > cold.calming, true)

	var nothing := DishNourishment.feeding_result_of(Dish.new())
	_expect_near("an empty plate feeds nothing", nothing.nourishment, 0.0)
	_expect_near("legacy feeding results carry full strength", FeedingResult.new().ascension_strength, 1.0)

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
	vessel.heat_loss_w_per_k = 4.0
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
	ingredient.cook_seconds = 400.0
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
	_expect_equal(
		"seasoning is gated behind the burner",
		LighthouseProgression.is_technique_unlocked(SEASONED),
		false
	)

	LighthouseProgression.add_light(100)
	LighthouseProgression.purchase(&"restored_burner")
	_expect_equal(
		"the burner unlocks seasoning",
		LighthouseProgression.is_technique_unlocked(SEASONED),
		true
	)
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

func _serve_tide_dish(spirit: SpiritController) -> bool:
	var dish := CraftedDish.new()
	dish.add_component(SEA_KELP, SIMMERED)
	dish.add_component(TIDE_POOL_CLAM, RAW)
	return _serving_station.serve(dish, spirit)

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
