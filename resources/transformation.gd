class_name Transformation
extends Resource

## Turns one bulk ingredient into others with a piece of equipment and the
## player's own work: sunflower seeds through the oil press become oil and
## seed cake. Transformations are the only authored "recipes" in the
## kitchen, and they describe what equipment physically does to a single
## ingredient - never a finished dish. New ones are authored as .tres files
## in res://data/transformations/.

const CATALOG_DIR: String = "res://data/transformations"
## Outputs may not contain more of any component than the input had, beyond
## rounding.
const CONSERVATION_TOLERANCE: float = 0.0001

@export var id: StringName = &""
@export var equipment: KitchenEquipment
@export var input: Ingredient
@export var outputs: Array[Ingredient] = []
## Grams of each output per gram of input, in the same order as outputs.
## Whatever the yields leave short of 1.0 is lost (husk dust, steam).
@export var output_yields: Array[float] = []
## Work the player puts in per gram of input: crank turns, for a press.
@export var work_per_gram: float = 1.0

## Every transformation authored in CATALOG_DIR.
static func load_catalog() -> Array[Transformation]:
	var catalog: Array[Transformation] = []
	for file_name in DirAccess.get_files_at(CATALOG_DIR):
		var resource_name := file_name.trim_suffix(".remap")
		if not resource_name.ends_with(".tres"):
			continue
		var transformation := load(CATALOG_DIR.path_join(resource_name)) as Transformation
		if transformation:
			catalog.append(transformation)
	return catalog

## Every problem with this transformation, or an empty array. Beyond shape
## checks, the outputs together may not hold more water, starch, sugar, fat
## or protein than the input did - a press cannot make fat out of nothing.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("id is empty")
	if equipment == null:
		problems.append("equipment is missing")
	if input == null:
		problems.append("input is missing")
		return problems
	if outputs.is_empty():
		problems.append("there are no outputs")
	if outputs.size() != output_yields.size():
		problems.append("every output needs exactly one yield")
		return problems
	if work_per_gram <= 0.0:
		problems.append("work per gram must be positive")

	var total_yield: float = 0.0
	for index in outputs.size():
		if outputs[index] == null:
			problems.append("output %d is missing" % index)
			return problems
		if output_yields[index] < 0.0:
			problems.append("yields cannot be negative")
		total_yield += output_yields[index]
	if total_yield > 1.0 + CONSERVATION_TOLERANCE:
		problems.append("yields sum to %.3f, above 1" % total_yield)

	for component in [&"water_fraction", &"starch_fraction", &"sugar_fraction", &"fat_fraction", &"protein_fraction"]:
		var produced: float = 0.0
		for index in outputs.size():
			produced += output_yields[index] * float(outputs[index].get(component))
		if produced > float(input.get(component)) + CONSERVATION_TOLERANCE:
			problems.append("outputs hold more %s than the input" % str(component).trim_suffix("_fraction"))
	return problems
