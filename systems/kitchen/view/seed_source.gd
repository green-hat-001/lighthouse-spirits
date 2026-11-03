class_name SeedSource
extends Node3D

## A source of a bulk ingredient the player takes a scoop of at a time -
## the sunflower head, rubbed for its seeds. Unlimited until foraging
## exists. The ingredient and scoop size are data.

signal taken(ingredient: Ingredient, grams: float)

@export var ingredient: Ingredient
@export var scoop_g: float = 50.0

@onready var _grip: Interactable = $Grip

func _ready() -> void:
	_grip.hand_pose = HandModel.Pose.PINCH
	_grip.pressed.connect(func(_point: Vector3) -> void: taken.emit(ingredient, scoop_g))
