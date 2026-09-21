extends Node3D

## Manual play harness for the three foundational systems together.
##   F - craft a simmered-kelp + raw-clam dish and serve it to the spirit
##   U - spend kindled light on the cheapest available lighthouse retrofit
##   R - call in another spirit once the current one has departed

const SPIRIT_SCENE: PackedScene = preload("res://scenes/spirit.tscn")
const TEST_ARCHETYPE: SpiritArchetype = preload("res://data/archetypes/example_spirit_basic.tres")

const SEA_KELP: Ingredient = preload("res://data/ingredients/sea_kelp.tres")
const TIDE_POOL_CLAM: Ingredient = preload("res://data/ingredients/tide_pool_clam.tres")
const SIMMERED: PreparationTechnique = preload("res://data/techniques/simmered.tres")
const RAW: PreparationTechnique = preload("res://data/techniques/raw.tres")

const STATE_NAMES: Array[String] = [
	"ARRIVING", "SEEKING", "WAITING", "FED", "ASCENDING", "DISTRESSED", "DEPARTED"
]

@onready var _anchor: Marker3D = $ArrivalAnchor
@onready var _label: Label = $UI/DebugLabel

var _spirit: SpiritController
var _serving_station := DishServingStation.new()
var _last_action: String = "waiting for the first spirit"

func _ready() -> void:
	_spawn_spirit()
	SpiritEventBus.spirit_state_changed.connect(_on_spirit_state_changed)
	SpiritEventBus.spirit_lifecycle_complete.connect(_on_spirit_lifecycle_complete)
	LighthouseProgression.upgrade_purchased.connect(_on_upgrade_purchased)

func _process(_delta: float) -> void:
	_label.text = "%s\n\n%s\n\n%s" % [_spirit_report(), _lighthouse_report(), _last_action]

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F:
		_feed_active_spirit()
	elif event.keycode == KEY_U:
		_buy_cheapest_upgrade()
	elif event.keycode == KEY_R and not is_instance_valid(_spirit):
		_spawn_spirit()

# --- Reporting ----------------------------------------------------------------

func _spirit_report() -> String:
	if not is_instance_valid(_spirit):
		return "No spirit at the lantern.\nPress R to call another in."
	return "state: %s\nhunger: %.1f   instability: %.1f\nheight: %.2f\n[F] serve a dish" % [
		STATE_NAMES[_spirit.state_machine.current_state],
		_spirit.runtime.current_hunger,
		_spirit.runtime.current_instability,
		_spirit.global_position.y,
	]

func _lighthouse_report() -> String:
	var lines: Array[String] = []
	lines.append("kindled light: %d" % LighthouseProgression.light)
	lines.append("station: nourishment x%.2f  calming x%.2f" % [
		LighthouseProgression.station_nourishment_multiplier(),
		LighthouseProgression.station_calming_multiplier(),
	])
	var available := LighthouseProgression.available_upgrades()
	if available.is_empty():
		lines.append("no retrofits available")
	else:
		for upgrade in available:
			var affordable := "" if LighthouseProgression.light >= upgrade.light_cost else "  (need more light)"
			lines.append("  %s - %d light%s" % [upgrade.display_name, upgrade.light_cost, affordable])
		lines.append("[U] buy the cheapest affordable retrofit")
	return "\n".join(lines)

# --- Actions ------------------------------------------------------------------

func _spawn_spirit() -> void:
	_spirit = SPIRIT_SCENE.instantiate()
	_spirit.archetype = TEST_ARCHETYPE
	_spirit.arrival_anchor = _anchor
	_spirit.position = Vector3(3.0, 1.0, -2.0)
	add_child(_spirit)
	_last_action = "a spirit drifts in"

func _feed_active_spirit() -> void:
	if not is_instance_valid(_spirit):
		return
	var dish := CraftedDish.new()
	dish.add_component(SEA_KELP, SIMMERED)
	dish.add_component(TIDE_POOL_CLAM, RAW)
	if _serving_station.serve(dish, _spirit):
		_last_action = "served simmered kelp with clam"
	else:
		_last_action = "that dish cannot be served yet"

func _buy_cheapest_upgrade() -> void:
	var cheapest: LighthouseUpgrade = null
	for upgrade in LighthouseProgression.available_upgrades():
		if not LighthouseProgression.can_purchase(upgrade.id):
			continue
		if cheapest == null or upgrade.light_cost < cheapest.light_cost:
			cheapest = upgrade
	if cheapest == null:
		_last_action = "not enough light for any retrofit"
		return
	LighthouseProgression.purchase(cheapest.id)

# --- Signal handlers ----------------------------------------------------------

func _on_spirit_state_changed(spirit_id: StringName, old_state: int, new_state: int) -> void:
	print("[%s] %s -> %s" % [spirit_id, STATE_NAMES[old_state], STATE_NAMES[new_state]])

func _on_spirit_lifecycle_complete(spirit_id: StringName, outcome: StringName) -> void:
	print("[%s] lifecycle complete: %s" % [spirit_id, outcome])
	_last_action = "the spirit departed: %s" % outcome

func _on_upgrade_purchased(upgrade_id: StringName) -> void:
	var upgrade := LighthouseProgression.get_upgrade(upgrade_id)
	print("purchased upgrade: %s" % upgrade_id)
	_last_action = "retrofitted: %s" % upgrade.display_name
