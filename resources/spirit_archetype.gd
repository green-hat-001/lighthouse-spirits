class_name SpiritArchetype
extends Resource

## Data definition for one Warawara "species". New varieties are authored
## as new .tres instances of this resource - no new code required.

enum ElementalAffinity { NONE, TIDE, WIND, EMBER, STONE }

@export var id: StringName = &""
@export var display_name: String = ""
@export var mesh_variant: PackedScene
@export var tint_color: Color = Color.WHITE

@export_group("Base Deficits")
@export_range(0.0, 100.0) var base_hunger: float = 70.0
@export_range(0.0, 100.0) var base_instability: float = 60.0
@export var base_weight: float = 1.0

@export_group("Timing")
@export var patience_seconds: float = 30.0
@export var settle_seconds: float = 1.5
@export var fed_feedback_seconds: float = 1.5
@export var ascension_seconds: float = 4.0
@export var recovery_window_seconds: float = 10.0
@export var despawn_seconds: float = 1.0

@export_group("Ascension Thresholds")
@export_range(0.0, 100.0) var ascension_hunger_threshold: float = 20.0
@export_range(0.0, 100.0) var ascension_instability_threshold: float = 20.0

@export_group("Visual Feedback")
@export var buoyancy_curve: Curve
@export var luminescence_curve: Curve

@export_group("Affinity")
@export var elemental_affinity: ElementalAffinity = ElementalAffinity.NONE
