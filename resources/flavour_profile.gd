class_name FlavourProfile
extends Resource

## Taste as intensities (0-1) on a fixed set of axes. Authored on an
## Ingredient, and carried as mutable runtime state by every FoodPiece -
## always on its own copy, never on the ingredient's, which stays a
## reusable template. The axes are fixed so flavour can be mixed, compared
## and transferred generically, with no per-ingredient code.

const AXES: Array[StringName] = [&"sweet", &"salty", &"sour", &"bitter", &"umami", &"heat", &"aroma"]

@export_range(0.0, 1.0) var sweet: float = 0.0
@export_range(0.0, 1.0) var salty: float = 0.0
@export_range(0.0, 1.0) var sour: float = 0.0
@export_range(0.0, 1.0) var bitter: float = 0.0
@export_range(0.0, 1.0) var umami: float = 0.0
## Chilli heat (capsaicin), not temperature.
@export_range(0.0, 1.0) var heat: float = 0.0
@export_range(0.0, 1.0) var aroma: float = 0.0

## Blend of two profiles weighted by the mass each one comes from, as when
## two foods are combined. Zero total mass yields a flavourless profile.
static func mix_by_mass(a: FlavourProfile, mass_a: float, b: FlavourProfile, mass_b: float) -> FlavourProfile:
	var mixed := FlavourProfile.new()
	var weight_a: float = maxf(mass_a, 0.0)
	var weight_b: float = maxf(mass_b, 0.0)
	var total: float = weight_a + weight_b
	if total <= 0.0:
		return mixed
	for axis in AXES:
		mixed.set(axis, (float(a.get(axis)) * weight_a + float(b.get(axis)) * weight_b) / total)
	return mixed

func copy() -> FlavourProfile:
	return duplicate() as FlavourProfile

## Hand-written .tres files bypass the editor's range clamp, so validation
## re-checks it.
func is_in_range() -> bool:
	for axis in AXES:
		var value: float = get(axis)
		if value < 0.0 or value > 1.0:
			return false
	return true
