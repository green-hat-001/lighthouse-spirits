extends Node3D

## Manual verification harness for the Spirit FSM + Culinary Crafting
## Matrix together. Spawns one spirit and lets you drive it through the
## full lifecycle by hand:
##   F - craft a simmered-kelp + raw-clam dish and serve it to the spirit
##   R - respawn a spirit once the current one has departed

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

func _ready() -> void:
	_spawn_spirit()
	SpiritEventBus.spirit_state_changed.connect(_on_spirit_state_changed)
	SpiritEventBus.spirit_lifecycle_complete.connect(_on_spirit_lifecycle_complete)

func _process(_delta: float) -> void:
	if not is_instance_valid(_spirit):
		_label.text = "No active spirit.\nPress R to respawn."
		return
	_label.text = "state: %s\nhunger: %.1f  instability: %.1f\nposition.y: %.2f\npress F to feed" % [
		STATE_NAMES[_spirit.state_machine.current_state],
		_spirit.runtime.current_hunger,
		_spirit.runtime.current_instability,
		_spirit.global_position.y,
	]

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F:
		_feed_active_spirit()
	elif event.keycode == KEY_R and not is_instance_valid(_spirit):
		_spawn_spirit()

func _spawn_spirit() -> void:
	_spirit = SPIRIT_SCENE.instantiate()
	_spirit.archetype = TEST_ARCHETYPE
	_spirit.arrival_anchor = _anchor
	_spirit.position = Vector3(3.0, 1.0, -2.0)
	add_child(_spirit)

func _feed_active_spirit() -> void:
	if not is_instance_valid(_spirit):
		return
	var dish := CraftedDish.new()
	dish.add_component(SEA_KELP, SIMMERED)
	dish.add_component(TIDE_POOL_CLAM, RAW)
	_serving_station.serve(dish, _spirit)

func _on_spirit_state_changed(spirit_id: StringName, old_state: int, new_state: int) -> void:
	print("[%s] %s -> %s" % [spirit_id, STATE_NAMES[old_state], STATE_NAMES[new_state]])

func _on_spirit_lifecycle_complete(spirit_id: StringName, outcome: StringName) -> void:
	print("[%s] lifecycle complete: %s" % [spirit_id, outcome])
