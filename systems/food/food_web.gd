class_name FoodWeb
extends RefCounted

## Works out which mystical essences every creature carries from what it
## eats, the way a real food web passes on what is in the food: an animal
## takes in the essences of its diet (the mean over what it eats), and
## each essence that travels by diet settles, at its diet share, in the
## tissues it favours. A share above 1 concentrates it - grazers that eat
## a great deal of a herb end up with more of its essence in their fat
## than the herb itself had. Predators inherit from their prey's whole
## body, prey resolved first; a cycle in the web is broken where it is
## found.
##
## The result is written to each part ingredient's inherited_traits, and
## the whole-carcass ingredient gets the mass-weighted mean of its parts.

## Resolves every creature reachable from these ingredients.
static func resolve(ingredients: Array[Ingredient]) -> void:
	var creatures: Array[Creature] = []
	for ingredient in ingredients:
		if ingredient.creature and not creatures.has(ingredient.creature):
			creatures.append(ingredient.creature)
	for creature in creatures:
		for part in creature.parts:
			if part and part.ingredient:
				part.ingredient.inherited_traits.clear()
	for ingredient in ingredients:
		if ingredient.creature:
			ingredient.inherited_traits.clear()
	var resolved: Dictionary[Creature, TraitDoses] = {}
	var visiting: Array[Creature] = []
	for ingredient in ingredients:
		if ingredient.creature:
			var body := _body(ingredient.creature, resolved, visiting)
			for mystic_trait in body.traits():
				ingredient.inherited_traits[mystic_trait] = body.get_dose(mystic_trait)

## The essences in a creature's whole body, per gram, resolving its diet.
static func _body(creature: Creature, resolved: Dictionary[Creature, TraitDoses], visiting: Array[Creature]) -> TraitDoses:
	if resolved.has(creature):
		return resolved[creature]
	if visiting.has(creature):
		return TraitDoses.new()
	visiting.append(creature)

	var intake := TraitDoses.new()
	var eaten: int = 0
	for food in creature.diet:
		if food == null:
			continue
		eaten += 1
		var essences: TraitDoses = _body(food.creature, resolved, visiting) if food.creature else food.trait_doses()
		for mystic_trait in essences.traits():
			intake.add_dose(mystic_trait, essences.get_dose(mystic_trait))
	if eaten > 0:
		for mystic_trait in intake.traits():
			intake.set_dose(mystic_trait, intake.get_dose(mystic_trait) / eaten)

	for part in creature.parts:
		if part == null or part.ingredient == null:
			continue
		for mystic_trait in intake.traits():
			if mystic_trait.carried_by_diet and mystic_trait.tissues.has(part.tissue):
				var inherited: float = intake.get_dose(mystic_trait) * mystic_trait.diet_share
				part.ingredient.inherited_traits[mystic_trait] = part.ingredient.inherited_traits.get(mystic_trait, 0.0) + inherited

	var body := TraitDoses.new()
	var body_mass: float = 0.0
	for part in creature.parts:
		if part == null or part.ingredient == null:
			continue
		var mass: float = part.ingredient.whole_mass_g() * part.count
		body.mix_in(body_mass, part.ingredient.trait_doses(), mass)
		body_mass += mass
	visiting.erase(creature)
	resolved[creature] = body
	return body
