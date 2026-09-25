extends Node

## Meta-progression for the lighthouse itself. Spirits that ascend leave
## behind kindled light; light pays for retrofits; retrofits open foraging
## zones and make the kitchen's dishes more potent - which is what lets the
## caretaker handle needier spirits later on.
##
## Unlike SpiritEventBus (a pure hub for many transient spirit instances),
## this singleton owns both the state and the signals about it - there is
## exactly one lighthouse, so the indirection would buy nothing.

signal light_changed(total: int)
signal upgrade_purchased(upgrade_id: StringName)

const UPGRADE_DIR: String = "res://data/upgrades"
const SAVE_PATH: String = "user://progression.cfg"
const LIGHT_PER_ASCENSION: int = 3

var light: int = 0

var _catalog: Dictionary = {}
var _purchased: Dictionary = {}

func _ready() -> void:
	_load_catalog()
	SpiritEventBus.spirit_lifecycle_complete.connect(_on_spirit_lifecycle_complete)

# --- Queries ------------------------------------------------------------------

func get_upgrade(upgrade_id: StringName) -> LighthouseUpgrade:
	return _catalog.get(upgrade_id)

func is_purchased(upgrade_id: StringName) -> bool:
	return _purchased.has(upgrade_id)

func prerequisites_met(upgrade_id: StringName) -> bool:
	var upgrade: LighthouseUpgrade = _catalog.get(upgrade_id)
	if not upgrade:
		return false
	for prerequisite in upgrade.prerequisites:
		if not is_purchased(prerequisite):
			return false
	return true

func can_purchase(upgrade_id: StringName) -> bool:
	var upgrade: LighthouseUpgrade = _catalog.get(upgrade_id)
	if not upgrade or is_purchased(upgrade_id):
		return false
	return prerequisites_met(upgrade_id) and light >= upgrade.light_cost

## Upgrades whose prerequisites are met and that have not been bought yet -
## i.e. what the retrofit menu should be offering right now.
func available_upgrades() -> Array[LighthouseUpgrade]:
	var available: Array[LighthouseUpgrade] = []
	for upgrade_id in _catalog:
		if not is_purchased(upgrade_id) and prerequisites_met(upgrade_id):
			available.append(_catalog[upgrade_id])
	return available

func is_ingredient_unlocked(ingredient: Ingredient) -> bool:
	if ingredient.available_from_start:
		return true
	for upgrade_id in _purchased:
		if _catalog[upgrade_id].unlocked_ingredients.has(ingredient):
			return true
	return false

func is_technique_unlocked(technique: PreparationTechnique) -> bool:
	if technique.available_from_start:
		return true
	for upgrade_id in _purchased:
		if _catalog[upgrade_id].unlocked_techniques.has(technique):
			return true
	return false

func is_equipment_unlocked(equipment: KitchenEquipment) -> bool:
	if equipment.available_from_start:
		return true
	for upgrade_id in _purchased:
		if _catalog[upgrade_id].unlocked_equipment.has(equipment):
			return true
	return false

## Product of every purchased upgrade's bonus, applied to served dishes.
func station_nourishment_multiplier() -> float:
	var multiplier: float = 1.0
	for upgrade_id in _purchased:
		multiplier *= _catalog[upgrade_id].nourishment_multiplier
	return multiplier

func station_calming_multiplier() -> float:
	var multiplier: float = 1.0
	for upgrade_id in _purchased:
		multiplier *= _catalog[upgrade_id].calming_multiplier
	return multiplier

# --- Mutations ----------------------------------------------------------------

func add_light(amount: int) -> void:
	if amount == 0:
		return
	light = maxi(light + amount, 0)
	light_changed.emit(light)

func purchase(upgrade_id: StringName) -> bool:
	if not can_purchase(upgrade_id):
		return false
	var upgrade: LighthouseUpgrade = _catalog[upgrade_id]
	light -= upgrade.light_cost
	_purchased[upgrade_id] = true
	light_changed.emit(light)
	upgrade_purchased.emit(upgrade_id)
	return true

## Wipes runtime progression. Used by tests and by starting a new game.
func reset() -> void:
	light = 0
	_purchased.clear()
	light_changed.emit(light)

# --- Persistence --------------------------------------------------------------

func save() -> Error:
	var config := ConfigFile.new()
	config.set_value("progression", "light", light)
	config.set_value("progression", "purchased", _purchased.keys())
	return config.save(SAVE_PATH)

func load_saved() -> bool:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return false
	light = config.get_value("progression", "light", 0)
	_purchased.clear()
	for upgrade_id in config.get_value("progression", "purchased", []):
		var key := StringName(upgrade_id)
		if _catalog.has(key):
			_purchased[key] = true
	light_changed.emit(light)
	return true

# --- Internals ----------------------------------------------------------------

func _on_spirit_lifecycle_complete(_spirit_id: StringName, outcome: StringName) -> void:
	if outcome == &"ASCENDED":
		add_light(LIGHT_PER_ASCENSION)

func _load_catalog() -> void:
	_catalog.clear()
	for file_name in DirAccess.get_files_at(UPGRADE_DIR):
		var resource_name := file_name.trim_suffix(".remap")
		if not resource_name.ends_with(".tres"):
			continue
		var upgrade: LighthouseUpgrade = load(UPGRADE_DIR.path_join(resource_name))
		if upgrade and upgrade.id != &"":
			_catalog[upgrade.id] = upgrade
