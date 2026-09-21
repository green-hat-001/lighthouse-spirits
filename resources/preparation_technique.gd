class_name PreparationTechnique
extends Resource

## One prep method (chopping, simmering, seasoning...) applied to a single
## ingredient within a dish. New techniques are authored as new .tres
## instances - no new code required.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Modifiers")
@export var nourishment_multiplier: float = 1.0
@export var calming_multiplier: float = 1.0
@export var buoyancy_multiplier: float = 1.0
@export var nourishment_flat_bonus: float = 0.0
@export var calming_flat_bonus: float = 0.0
