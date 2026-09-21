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
