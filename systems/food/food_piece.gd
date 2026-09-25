class_name FoodPiece
extends RefCounted

## Physical state of one piece of a SOLID ingredient on its way through the
## kitchen: a whole potato, a plank, a single fry. Cooking processes evolve
## this state over time; the player reads it back by looking, tasting and
## listening. Nothing here is a recipe or a score.
##
## The piece is a box in its own local frame. Local Y is height, so X and Z
## are its footprint on a board or the bottom of a pan - the same
## convention as Godot, so the 3D layer can map a piece straight onto a
## mesh.
##
## Units: mm, g, degrees C. Fractions and 0-1 levels are unitless.
##
## Mass is tracked as grams of solids, water and absorbed oil, so cooking can
## boil water off and soak oil in without the fractions drifting. The piece
## has two thermal nodes: a thin surface shell (SHELL_DEPTH_MM deep, capped
## at MAX_SHELL_FRACTION of the volume) and the core. Surface quantities
## (browning, char, surface temperature and moisture) belong to the shell;
## a fresh cut face dilutes them with interior values.

const SHELL_DEPTH_MM: float = 1.0
const MAX_SHELL_FRACTION: float = 0.5

var ingredient: Ingredient
var size_mm: Vector3
var solids_g: float
var water_g: float
var oil_g: float = 0.0
## Water as a fraction of the shell's mass. Evaporation dries it; water
## migrating out from the core wets it again.
var surface_moisture: float
var core_temp_c: float
var surface_temp_c: float
## 0 raw, 1 cooked all the way through. Keeps rising past 1 as the piece
## overcooks.
var core_doneness: float = 0.0
## 0 pale through to 1 deeply browned.
var surface_browning: float = 0.0
## 0 clean through to 1 blackened.
var surface_char: float = 0.0
## 1 firm and whole through to 0 fallen apart.
var integrity: float = 1.0
var flavour: FlavourProfile
## Every axis (Vector3.AXIS_*) this piece, or any piece it was cut from,
## has been cut along. A cut along any other axis is a perpendicular cut.
var cut_axes: Array[int] = []

## A whole, raw item at the given ambient temperature, or null (with an
## error) when the ingredient is not a SOLID that can exist as a piece.
static func from_ingredient(p_ingredient: Ingredient, ambient_temp_c: float) -> FoodPiece:
	if p_ingredient == null or p_ingredient.physical_form != Ingredient.PhysicalForm.SOLID:
		push_error("FoodPiece: only SOLID ingredients can be made into pieces")
		return null
	var piece := FoodPiece.new()
	piece.ingredient = p_ingredient
	piece.size_mm = p_ingredient.whole_size_mm
	var mass: float = p_ingredient.whole_mass_g()
	piece.water_g = mass * p_ingredient.water_fraction
	piece.solids_g = mass - piece.water_g
	piece.surface_moisture = p_ingredient.water_fraction
	piece.core_temp_c = ambient_temp_c
	piece.surface_temp_c = ambient_temp_c
	piece.flavour = p_ingredient.flavour.copy() if p_ingredient.flavour else FlavourProfile.new()
	return piece

func mass_g() -> float:
	return solids_g + water_g + oil_g

## Water as a fraction of the whole piece's mass.
func moisture() -> float:
	return water_g / mass_g()

func oil_fraction() -> float:
	return oil_g / mass_g()

func volume_mm3() -> float:
	return size_mm.x * size_mm.y * size_mm.z

func surface_area_mm2() -> float:
	return 2.0 * (size_mm.x * size_mm.y + size_mm.y * size_mm.z + size_mm.x * size_mm.z)

## Area of the face perpendicular to the given axis - the face a cut along
## that axis exposes, and for AXIS_Y the face the piece rests on.
func cross_section_mm2(axis: int) -> float:
	return volume_mm3() / size_mm[axis]

func min_dimension_mm() -> float:
	return minf(size_mm.x, minf(size_mm.y, size_mm.z))

func shell_fraction() -> float:
	return minf(surface_area_mm2() * SHELL_DEPTH_MM / volume_mm3(), MAX_SHELL_FRACTION)

func shell_mass_g() -> float:
	return mass_g() * shell_fraction()

func core_mass_g() -> float:
	return mass_g() - shell_mass_g()

func surface_water_g() -> float:
	return surface_moisture * shell_mass_g()

## Water as a fraction of the core's mass.
func core_moisture() -> float:
	return maxf(water_g - surface_water_g(), 0.0) / core_mass_g()

## How dry the surface is relative to the raw ingredient: 0 as wet as when
## raw (or wetter), 1 bone dry. Browning and crisping need a dry surface.
func surface_dryness() -> float:
	var raw_moisture: float = ingredient.water_fraction
	if raw_moisture <= 0.0:
		return 1.0
	return clampf(1.0 - surface_moisture / raw_moisture, 0.0, 1.0)

## Keeps the shell from holding more water than the piece has. Called after
## anything that changes the shell's size or the piece's water.
func clamp_surface_moisture() -> void:
	var shell_mass: float = shell_mass_g()
	if shell_mass <= 0.0:
		surface_moisture = 0.0
		return
	surface_moisture = clampf(surface_moisture, 0.0, minf(water_g / shell_mass, 1.0))

## Tips the piece 90 degrees onto its side, rolling it like a log about its
## longer horizontal axis - how a cook lays a plank flat to cut it into
## sticks. Its cut history turns with it, so a cut that was vertical before
## the roll is horizontal after it. Returns the axis it rolled about.
func roll() -> int:
	if size_mm.x >= size_mm.z:
		_swap_axes(Vector3.AXIS_Y, Vector3.AXIS_Z)
		return Vector3.AXIS_X
	_swap_axes(Vector3.AXIS_X, Vector3.AXIS_Y)
	return Vector3.AXIS_Z

func _swap_axes(first: int, second: int) -> void:
	var size := size_mm
	var first_length: float = size[first]
	size[first] = size[second]
	size[second] = first_length
	size_mm = size
	for index in cut_axes.size():
		if cut_axes[index] == first:
			cut_axes[index] = second
		elif cut_axes[index] == second:
			cut_axes[index] = first

## Independent deep copy: the clone's flavour and cut history can change
## without touching this piece.
func clone() -> FoodPiece:
	var copy := FoodPiece.new()
	copy.ingredient = ingredient
	copy.size_mm = size_mm
	copy.solids_g = solids_g
	copy.water_g = water_g
	copy.oil_g = oil_g
	copy.surface_moisture = surface_moisture
	copy.core_temp_c = core_temp_c
	copy.surface_temp_c = surface_temp_c
	copy.core_doneness = core_doneness
	copy.surface_browning = surface_browning
	copy.surface_char = surface_char
	copy.integrity = integrity
	copy.flavour = flavour.copy()
	copy.cut_axes = cut_axes.duplicate()
	return copy
