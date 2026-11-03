class_name PantryDresser
extends Node3D

## The pantry: a dresser behind the counter with one shelf for each kind of
## larder (Ingredient.Shelf), and on each shelf every ingredient of that
## kind the lighthouse has unlocked, each in a spot of its own (an
## IngredientSource). Nothing on it runs out.
##
## The spots are laid out from data, never by hand: a new ingredient
## authored for a shelf takes a spot on it, and a retrofit that unlocks one
## adds it the moment it is bought. The shelves bottom to top are garden
## (level with the counter, nearest to hand), catch on its ice, grains in
## their sacks and spices in their crocks; their heights and depths match
## the dresser model (tools/blender/build_models.py, DRESSER_SHELVES).

## A spot was made, for the Kitchen to listen to.
signal source_added(source: IngredientSource)

const SOURCE_SCENE: PackedScene = preload("res://scenes/kitchen/ingredient_source.tscn")

## Each shelf, bottom to top: which larder it holds (Ingredient.Shelf).
@export var shelf_kinds: PackedInt32Array = PackedInt32Array([
	Ingredient.Shelf.GARDEN, Ingredient.Shelf.CATCH, Ingredient.Shelf.GRAIN, Ingredient.Shelf.SPICE])
## Where its things rest, above this node, in metres (the garden's straw,
## the catch's ice, the shelf boards).
@export var floor_heights_m: PackedFloat32Array = PackedFloat32Array([0.003, 0.166, 0.29, 0.42])
## How deep it is, from the back of the dresser.
@export var depths_m: PackedFloat32Array = PackedFloat32Array([0.27, 0.24, 0.24, 0.21])
## Its clear height, up to the shelf above.
@export var clearances_m: PackedFloat32Array = PackedFloat32Array([0.13, 0.11, 0.12, 0.12])
## What its things are kept in (nothing for loose produce and the catch),
## and the height of that container's mouth.
@export var containers: Array[PackedScene] = []
@export var mouth_heights_m: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.082, 0.074])
## The width the spots share, and where the back of the shelves is.
@export var usable_width_m: float = 1.22
@export var back_z_m: float = -0.15

var sources: Array[IngredientSource] = []

func _ready() -> void:
	# The sun comes in low off the sea behind the dresser; its shadow would
	# fall across the whole counter. Its shelves still shade what is on them.
	for mesh: MeshInstance3D in $Dresser.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	IngredientCatalog.ensure_loaded()
	stock()
	LighthouseProgression.upgrade_purchased.connect(func(_id: StringName) -> void: stock())

## Centres along the shelf for `count` equal spots across `width_m`.
static func slot_centres(count: int, width_m: float) -> PackedFloat32Array:
	var centres := PackedFloat32Array()
	for index in count:
		centres.append(-width_m * 0.5 + width_m * (index + 0.5) / count)
	return centres

## What each shelf offers, in the order it is laid out: whole creatures
## first, then the rest by name.
static func offering(kind: Ingredient.Shelf) -> Array[Ingredient]:
	var items: Array[Ingredient] = []
	for item in IngredientCatalog.on_shelf(kind):
		if LighthouseProgression.is_ingredient_unlocked(item):
			items.append(item)
	items.sort_custom(func(a: Ingredient, b: Ingredient) -> bool:
		if (a.creature != null) != (b.creature != null):
			return a.creature != null
		return a.display_name < b.display_name)
	return items

## Lays out every shelf afresh.
func stock() -> void:
	for source in sources:
		source.queue_free()
	sources.clear()
	for shelf in shelf_kinds.size():
		var items := offering(shelf_kinds[shelf] as Ingredient.Shelf)
		var centres := slot_centres(items.size(), usable_width_m)
		var depth: float = depths_m[shelf]
		for index in items.size():
			var source: IngredientSource = SOURCE_SCENE.instantiate()
			source.name = "Spot_%s" % items[index].id
			source.ingredient = items[index]
			source.slot_size_m = Vector3(usable_width_m / items.size(), clearances_m[shelf], depth - 0.02)
			if shelf < containers.size():
				source.container = containers[shelf]
			source.mouth_height_m = mouth_heights_m[shelf] if shelf < mouth_heights_m.size() else 0.0
			source.position = Vector3(centres[index], floor_heights_m[shelf], back_z_m + depth * 0.5)
			add_child(source)
			sources.append(source)
			source_added.emit(source)

## The spot offering an ingredient, if the pantry has it.
func source_of(ingredient: Ingredient) -> IngredientSource:
	for source in sources:
		if source.ingredient == ingredient:
			return source
	return null
