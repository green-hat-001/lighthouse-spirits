class_name HeatSource
extends KitchenEquipment

## A burner the player controls by hand. The flame level is continuous and
## set directly by the player; there are no presets.

## Heat delivered into a vessel at full flame, in watts - burner output
## after the losses around the pot, not the burner's gross rating.
@export var max_power_w: float = 1400.0
## Lowest level a lit flame can burn at. Any level between off (0) and this
## burns at this level instead.
@export_range(0.0, 1.0) var min_flame_level: float = 0.15

## Watts delivered at the given flame level (0 off, 1 full).
func power_at(flame_level: float) -> float:
	if flame_level <= 0.0:
		return 0.0
	return max_power_w * clampf(maxf(flame_level, min_flame_level), 0.0, 1.0)
