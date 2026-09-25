class_name LighthouseUpgrade
extends Resource

## One retrofit of the lighthouse (machinery, brewing gear, kitchen tools,
## expanded foraging zones). New upgrades are authored as new .tres
## instances dropped into res://data/upgrades/ - the progression singleton
## scans that directory, so no code changes are needed to add content.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var light_cost: int = 0

## ids of upgrades that must be purchased before this one becomes available.
@export var prerequisites: Array[StringName] = []

@export_group("Unlocked Content")
@export var unlocked_ingredients: Array[Ingredient] = []
@export var unlocked_techniques: Array[PreparationTechnique] = []
## Kitchen equipment this retrofit installs.
@export var unlocked_equipment: Array[KitchenEquipment] = []

@export_group("Station Quality")
## Multiplicative bonuses applied to every dish served once this upgrade is
## purchased. They stack across all purchased upgrades.
@export var nourishment_multiplier: float = 1.0
@export var calming_multiplier: float = 1.0
