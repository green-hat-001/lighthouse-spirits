class_name Kitchen
extends Node3D

## Root of the kitchen scene. Wires pantry sources to the board and sets the
## kitchen's ambient temperature, which weather will drive later.

@export var ambient_temp_c: float = 15.0

@onready var board: CuttingBoard = $CuttingBoard

func _ready() -> void:
	board.ambient_temp_c = ambient_temp_c
	for source in find_children("*", "IngredientSource", true, false):
		(source as IngredientSource).taken.connect(func(ingredient: Ingredient) -> void: board.add_whole(ingredient))
