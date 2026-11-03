class_name IngredientCatalog
extends RefCounted

## Every ingredient authored under res://data/ingredients/ (folders and
## all), loaded once, with the food web resolved over them so each
## creature's parts carry what its diet gave them. New ingredients,
## species and parts are picked up by dropping .tres files in.

const ROOT: String = "res://data/ingredients"
const CREATURES: String = "res://data/creatures"

static var _all: Array[Ingredient] = []
static var _creatures: Array[Creature] = []
static var _loaded: bool = false

static func all() -> Array[Ingredient]:
	ensure_loaded()
	return _all

static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_all.clear()
	_collect(ROOT)
	_all.sort_custom(func(a: Ingredient, b: Ingredient) -> bool: return a.display_name < b.display_name)
	_creatures.clear()
	if DirAccess.dir_exists_absolute(CREATURES):
		for file_name in DirAccess.get_files_at(CREATURES):
			var resource_name := file_name.trim_suffix(".remap")
			if resource_name.ends_with(".tres"):
				var creature := load(CREATURES.path_join(resource_name)) as Creature
				if creature:
					_creatures.append(creature)
	FoodWeb.resolve(_all, _creatures)

## Every species authored under res://data/creatures/.
static func creatures() -> Array[Creature]:
	ensure_loaded()
	return _creatures

## The ingredients on one pantry shelf, alphabetical.
static func on_shelf(shelf: Ingredient.Shelf) -> Array[Ingredient]:
	var found: Array[Ingredient] = []
	for ingredient in all():
		if ingredient.pantry_shelf == shelf:
			found.append(ingredient)
	return found

static func by_id(id: StringName) -> Ingredient:
	for ingredient in all():
		if ingredient.id == id:
			return ingredient
	return null

static func _collect(folder: String) -> void:
	for sub in DirAccess.get_directories_at(folder):
		_collect(folder.path_join(sub))
	for file_name in DirAccess.get_files_at(folder):
		var resource_name := file_name.trim_suffix(".remap")
		if not resource_name.ends_with(".tres"):
			continue
		var ingredient := load(folder.path_join(resource_name)) as Ingredient
		if ingredient and not _all.has(ingredient):
			_all.append(ingredient)
