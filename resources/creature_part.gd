class_name CreaturePart
extends Resource

## One part of a creature: what it is called, which tissue it is (which
## decides which essences from the creature's diet settle in it), the
## ingredient it becomes in the kitchen, how many the creature has, and
## what it is good for.

@export var part_name: String = ""
@export var tissue: MysticTrait.Tissue = MysticTrait.Tissue.MUSCLE
@export var ingredient: Ingredient
@export var count: int = 1
@export_multiline var uses: String = ""
