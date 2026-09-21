extends Node3D

## Automated headless integration test for the full pipeline:
##   CulinaryCraftingMatrix -> DishServingStation -> SpiritEventBus -> Spirit FSM
##
## Run with:
##   godot --headless --path . res://scenes/integration_test.tscn
##
## Exits with code 0 on pass, 1 on failure, so it can be wired into CI.

const SPIRIT_SCENE: PackedScene = preload("res://scenes/spirit.tscn")
const TEST_ARCHETYPE: SpiritArchetype = preload("res://data/archetypes/example_spirit_basic.tres")

const SEA_KELP: Ingredient = preload("res://data/ingredients/sea_kelp.tres")
const TIDE_POOL_CLAM: Ingredient = preload("res://data/ingredients/tide_pool_clam.tres")
const CLIFF_GARDEN_HERB: Ingredient = preload("res://data/ingredients/cliff_garden_herb.tres")
const SIMMERED: PreparationTechnique = preload("res://data/techniques/simmered.tres")
const RAW: PreparationTechnique = preload("res://data/techniques/raw.tres")

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
var _feed_cooldown: float = 0.0
var _elapsed: float = 0.0
var _finished: bool = false

var _failures: Array[String] = []

func _ready() -> void:
	Engine.time_scale = TIME_SCALE

	_test_crafting_math()
	_test_dominant_affinity()

	SpiritEventBus.spirit_state_changed.connect(_on_state_changed)
	SpiritEventBus.spirit_lifecycle_complete.connect(_on_lifecycle_complete)

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
		_serve_tide_dish(_fed_spirit)
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

# --- Scene plumbing -----------------------------------------------------------

func _spawn(spawn_position: Vector3) -> SpiritController:
	var spirit: SpiritController = SPIRIT_SCENE.instantiate()
	spirit.archetype = TEST_ARCHETYPE
	spirit.arrival_anchor = $ArrivalAnchor
	spirit.position = spawn_position
	add_child(spirit)
	return spirit

func _serve_tide_dish(spirit: SpiritController) -> void:
	var dish := CraftedDish.new()
	dish.add_component(SEA_KELP, SIMMERED)
	dish.add_component(TIDE_POOL_CLAM, RAW)
	_serving_station.serve(dish, spirit)

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

	print("")
	print("fed path:       ", _fed_transitions, " -> ", _fed_outcome)
	print("neglected path: ", _neglected_transitions, " -> ", _neglected_outcome)
	print("servings needed: ", _feed_count)
	print("")
	if _failures.is_empty():
		print("RESULT: PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			print("FAIL: ", failure)
		print("RESULT: FAIL (%d)" % _failures.size())
		get_tree().quit(1)

func _expect_equal(what: String, actual: Variant, expected: Variant) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [what, expected, actual])

func _expect_near(what: String, actual: float, expected: float) -> void:
	if absf(actual - expected) > EPSILON:
		_failures.append("%s: expected %s, got %s" % [what, expected, actual])
