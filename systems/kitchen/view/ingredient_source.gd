class_name IngredientSource
extends Node3D

## A basket in the pantry. Pressing it takes one whole item of its
## ingredient; the pantry is unlimited until foraging exists. The ingredient
## is data, and the basket shows a few of its whole models, so a new basket
## is a new instance with a different Ingredient, never new code.

signal taken(ingredient: Ingredient)

## Where the items shown in the basket sit, as (x, z, turn about Y), in
## metres and radians on the basket floor.
const DISPLAY_SPOTS: Array[Vector3] = [Vector3(-0.022, -0.015, 0.4), Vector3(0.024, 0.012, 2.1), Vector3(0.0, 0.03, -0.9)]
const BASKET_FLOOR_M: float = 0.012

@export var ingredient: Ingredient

@onready var _grip: Interactable = $Grip
@onready var _label: Label3D = $Label
@onready var _contents: Node3D = $Contents

func _ready() -> void:
	_label.text = ingredient.display_name
	_grip.pressed.connect(func(_point: Vector3) -> void: taken.emit(ingredient))
	if ingredient.whole_model:
		for spot in DISPLAY_SPOTS:
			var item: Node3D = ingredient.whole_model.instantiate()
			item.position = Vector3(spot.x, BASKET_FLOOR_M, spot.y)
			item.rotation.y = spot.z
			_contents.add_child(item)
