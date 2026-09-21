class_name SpiritRuntimeState
extends RefCounted

## Mutable per-spawn copy of an archetype's stats. The archetype resource
## itself is never mutated - it stays a reusable template.

var current_hunger: float
var current_instability: float
var current_weight: float
var patience_timer: float
var recovery_timer: float

func _init(archetype: SpiritArchetype) -> void:
	current_hunger = archetype.base_hunger
	current_instability = archetype.base_instability
	current_weight = archetype.base_weight
	patience_timer = archetype.patience_seconds
	recovery_timer = archetype.recovery_window_seconds

func apply_feeding(result: FeedingResult) -> void:
	current_hunger = clampf(current_hunger - result.nourishment, 0.0, 100.0)
	current_instability = clampf(current_instability - result.calming, 0.0, 100.0)
	current_weight = maxf(current_weight - result.buoyancy_delta, 0.0)

func meets_ascension(archetype: SpiritArchetype) -> bool:
	return current_hunger <= archetype.ascension_hunger_threshold \
		and current_instability <= archetype.ascension_instability_threshold
