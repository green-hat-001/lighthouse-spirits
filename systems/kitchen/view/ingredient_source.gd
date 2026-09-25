class_name IngredientSource
extends Node3D

## A basket or crate in the pantry. Pressing it takes one whole item of its
## ingredient. The ingredient is data; a new basket is a new instance with a
## different Ingredient, never new code.

signal taken(ingredient: Ingredient)

@export var ingredient: Ingredient

@onready var _grip: Interactable = $Grip
@onready var _label: Label3D = $Label

func _ready() -> void:
	_label.text = ingredient.display_name
	_grip.pressed.connect(func(_point: Vector3) -> void: taken.emit(ingredient))
