class_name ManualProcessor
extends RefCounted

## A piece of hand-worked equipment - the oil press - loaded with a bulk
## ingredient and driven by the player's work. Each unit of work processes
## input according to the one Transformation that matches the equipment and
## what was loaded; outputs collect until the player takes them. There is no
## timer and nothing happens unless the player works it.

var equipment: KitchenEquipment
var loaded: Ingredient
var loaded_g: float = 0.0
## Collected output, by ingredient, in grams.
var outputs_g: Dictionary[Ingredient, float] = {}

var _transformations: Array[Transformation] = []
var _active: Transformation

## Only the transformations for this equipment are kept.
func _init(p_equipment: KitchenEquipment, catalog: Array[Transformation]) -> void:
	equipment = p_equipment
	for transformation in catalog:
		if transformation.equipment == equipment:
			_transformations.append(transformation)

## The transformation this equipment would apply to the ingredient, or null
## if the equipment cannot process it.
func transformation_for(ingredient: Ingredient) -> Transformation:
	for transformation in _transformations:
		if transformation.input == ingredient:
			return transformation
	return null

## Refused when the equipment cannot process the ingredient, or while a
## different ingredient is still loaded.
func load_input(ingredient: Ingredient, grams: float) -> bool:
	if grams <= 0.0:
		return false
	if loaded != null and loaded != ingredient:
		return false
	var transformation := transformation_for(ingredient)
	if transformation == null:
		return false
	_active = transformation
	loaded = ingredient
	loaded_g += grams
	return true

## Applies the player's work - crank turns, for a press - and returns the
## grams of input it processed. Work beyond what the load needs is wasted.
func work(amount: float) -> float:
	if _active == null or amount <= 0.0:
		return 0.0
	var processed_g: float = minf(amount / _active.work_per_gram, loaded_g)
	loaded_g -= processed_g
	for index in _active.outputs.size():
		var output: Ingredient = _active.outputs[index]
		outputs_g[output] = outputs_g.get(output, 0.0) + processed_g * _active.output_yields[index]
	if loaded_g <= 0.0:
		loaded_g = 0.0
		loaded = null
		_active = null
	return processed_g

## Hands over everything collected of one output and returns its grams.
func take_output(ingredient: Ingredient) -> float:
	var grams: float = outputs_g.get(ingredient, 0.0)
	outputs_g.erase(ingredient)
	return grams
