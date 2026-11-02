class_name HeatSource
extends KitchenEquipment

## A burner the player controls by hand. The flame level is continuous and
## set directly by the player; there are no presets. A bigger flame
## spreads wider under the pot: a small flame heats only the middle of the
## base, and a flame wider than the pot wastes heat up its sides.

## Heat delivered into a vessel at full flame, in watts - burner output
## after the losses around the pot, not the burner's gross rating.
@export var max_power_w: float = 1400.0
## Lowest level a lit flame can burn at. Any level between off (0) and this
## burns at this level instead.
@export_range(0.0, 1.0) var min_flame_level: float = 0.15
## Radius of the burner head: the patch of base a low flame heats.
@export var burner_radius_mm: float = 35.0
## How far the flame reaches out from the centre at full.
@export var full_flame_radius_mm: float = 85.0

## Watts delivered at the given flame level (0 off, 1 full).
func power_at(flame_level: float) -> float:
	if flame_level <= 0.0:
		return 0.0
	return max_power_w * effective_level(flame_level)

## The level a lit flame actually burns at.
func effective_level(flame_level: float) -> float:
	if flame_level <= 0.0:
		return 0.0
	return clampf(maxf(flame_level, min_flame_level), 0.0, 1.0)

## How far out from the centre the flame reaches, in mm.
func flame_radius_mm(flame_level: float) -> float:
	if flame_level <= 0.0:
		return 0.0
	return lerpf(burner_radius_mm, full_flame_radius_mm, effective_level(flame_level))
