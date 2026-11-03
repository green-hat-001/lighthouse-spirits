class_name TraitDoses
extends RefCounted

## The mystical essences something carries right now, as concentrations
## by trait - a piece of food, a pot of broth, a cup of oil. Mutable runtime
## state, always a copy, never the ingredient's authored doses. Mixed by
## mass like flavour.

var doses: Dictionary[MysticTrait, float] = {}

func get_dose(mystic_trait: MysticTrait) -> float:
	return doses.get(mystic_trait, 0.0)

func set_dose(mystic_trait: MysticTrait, concentration: float) -> void:
	if concentration <= 0.0:
		doses.erase(mystic_trait)
	else:
		doses[mystic_trait] = concentration

func add_dose(mystic_trait: MysticTrait, concentration: float) -> void:
	set_dose(mystic_trait, get_dose(mystic_trait) + concentration)

func is_empty() -> bool:
	return doses.is_empty()

func traits() -> Array[MysticTrait]:
	var found: Array[MysticTrait] = []
	found.assign(doses.keys())
	return found

func copy() -> TraitDoses:
	var copied := TraitDoses.new()
	copied.doses = doses.duplicate()
	return copied

## Blends another carrier into this one, weighting each by its mass.
func mix_in(own_mass: float, other: TraitDoses, other_mass: float) -> void:
	var total: float = maxf(own_mass, 0.0) + maxf(other_mass, 0.0)
	if total <= 0.0 or other == null:
		return
	var all_traits := traits()
	for mystic_trait in other.traits():
		if not all_traits.has(mystic_trait):
			all_traits.append(mystic_trait)
	for mystic_trait in all_traits:
		set_dose(mystic_trait, (get_dose(mystic_trait) * maxf(own_mass, 0.0) + other.get_dose(mystic_trait) * maxf(other_mass, 0.0)) / total)

static func mix_by_mass(a: TraitDoses, mass_a: float, b: TraitDoses, mass_b: float) -> TraitDoses:
	var mixed := a.copy() if a else TraitDoses.new()
	mixed.mix_in(mass_a, b, mass_b)
	return mixed
