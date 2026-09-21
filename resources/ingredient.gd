class_name Ingredient
extends Resource

## One foraged ingredient (tide pools, cliff gardens, drift nets). New
## ingredients are authored as new .tres instances - no new code required.

@export var id: StringName = &""
@export var display_name: String = ""
@export var tint_color: Color = Color.WHITE

@export_group("Base Restorative Properties")
@export var base_nourishment: float = 0.0
@export var base_calming: float = 0.0
@export var base_buoyancy_delta: float = 0.0

@export_group("Affinity")
@export var elemental_affinity: ElementalAffinity.Type = ElementalAffinity.Type.NONE
