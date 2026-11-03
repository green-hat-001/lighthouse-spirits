class_name Creature
extends Resource

## A species living on this coast, as the kitchen meets it: where it lives,
## what it eats, and every part of it the caretaker can use - flesh, fat,
## skin, bone, horn, eyes, teeth, organs. What it eats decides what it
## carries: mystical essences in its diet settle into its tissues
## (FoodWeb), so a bream that grazes buoyant kelp has buoyant flesh, and an
## eel that eats the bream inherits some of it in turn. New species are new
## instances of this resource.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var lore: String = ""
## Where on the coast it lives.
@export var habitat: String = ""
## What it eats: plants, or the whole-carcass ingredient of other
## creatures.
@export var diet: Array[Ingredient] = []
@export var parts: Array[CreaturePart] = []
## Too big for the counter: it is dressed where it is caught, and the
## pantry offers its parts. Otherwise it comes whole, to be dressed on the
## board.
@export var dressed_in_field: bool = false

## Total mass of all its parts, in grams.
func parts_mass_g() -> float:
	var total: float = 0.0
	for part in parts:
		if part and part.ingredient:
			total += part.ingredient.whole_mass_g() * part.count
	return total

## Every problem with this species, or an empty array.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("id is empty")
	if parts.is_empty():
		problems.append("a creature needs parts")
	for part in parts:
		if part == null or part.ingredient == null:
			problems.append("a part names no ingredient")
			continue
		if part.count < 1:
			problems.append("part %s needs a count of at least 1" % part.part_name)
		if part.ingredient.physical_form != Ingredient.PhysicalForm.SOLID:
			problems.append("part %s must be a SOLID ingredient" % part.part_name)
		for problem in part.ingredient.validate():
			problems.append("part %s: %s" % [part.part_name, problem])
	for food in diet:
		if food == null:
			problems.append("a diet entry is empty")
	return problems
