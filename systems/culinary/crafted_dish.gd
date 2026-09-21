class_name CraftedDish
extends RefCounted

## A dish assembled by the player from 1+ prepared ingredients, ready to be
## handed to CulinaryCraftingMatrix. Transient (built fresh per serving) -
## not a Resource.

var components: Array[DishComponent] = []

func add_component(ingredient: Ingredient, technique: PreparationTechnique) -> void:
	components.append(DishComponent.new(ingredient, technique))

func is_empty() -> bool:
	return components.is_empty()
