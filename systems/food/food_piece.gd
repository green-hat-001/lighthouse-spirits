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
## boil water off and soak oil in without the fractions drifting.
##
## Thermally the piece is a core plus a thin surface shell (SHELL_DEPTH_MM
## deep, capped at MAX_SHELL_FRACTION of the volume). The shell is split
## into the box's six faces, each with its own temperature, moisture,
## browning and char, because the faces of one piece rarely see the same
## heat: in a shallow pan the bottom sits on hot metal, the sides are in
## oil and the top is in the air. Each face's share of the shell is its
## share of the surface area. The piece-wide surface values
## (surface_temp_c, surface_moisture, surface_browning, surface_char) are
## area-weighted means over the faces; setting one sets every face.
##
## A face is skin (the outside of the whole item) or flesh (a cut face).
## Cutting makes fresh flesh faces; rolling turns the faces with the piece.

const SHELL_DEPTH_MM: float = 1.0
const MAX_SHELL_FRACTION: float = 0.5

## Faces, by index: the face whose outward normal points along +X, -X, +Y
## (top), -Y (bottom), +Z, -Z.
enum Face { POS_X, NEG_X, POS_Y, NEG_Y, POS_Z, NEG_Z }
const FACE_COUNT: int = 6
const TOP: int = Face.POS_Y
const BOTTOM: int = Face.NEG_Y

var ingredient: Ingredient
var size_mm: Vector3
var solids_g: float
var water_g: float
var oil_g: float = 0.0
## The piece's own fat that has melted out of it (see Ingredient render
## fields), in g. Already taken out of solids_g.
var fat_rendered_g: float = 0.0
var core_temp_c: float
## 0 raw, 1 cooked all the way through. Keeps rising past 1 as the piece
## overcooks.
var core_doneness: float = 0.0
## 1 firm and whole through to 0 fallen apart.
var integrity: float = 1.0
var flavour: FlavourProfile
## The mystical essences it carries now (see MysticTrait).
var traits := TraitDoses.new()
## Spice stuck to its surface, in grams by spice (Seasoning). Its flavour
## is already in `flavour`; this is what the eye sees - the flecks.
var spices: Dictionary[Ingredient, float] = {}
## How many identical pieces this stands for: 1 for a piece of food, many
## for a handful of grain, where one kernel is simulated for them all.
## Every quantity on the piece is per kernel; total_mass_g() is the lot.
var count: int = 1
## Every axis (Vector3.AXIS_*) this piece, or any piece it was cut from,
## has been cut along. A cut along any other axis is a perpendicular cut.
var cut_axes: Array[int] = []

## Per face, indexed by Face.
var face_temp_c := PackedFloat64Array()
## Water as a fraction of the face's share of the shell. Evaporation dries
## it; water migrating out from the core wets it again.
var face_moisture := PackedFloat64Array()
## 0 pale through to 1 deeply browned.
var face_browning := PackedFloat64Array()
## 0 clean through to 1 blackened.
var face_char := PackedFloat64Array()
## 1 for the ingredient's own skin, 0 for cut flesh.
var face_skin := PackedFloat64Array()

## Area-weighted mean over the faces. Setting it sets every face.
var surface_temp_c: float:
	get:
		return _area_mean(face_temp_c)
	set(value):
		face_temp_c.fill(value)
var surface_moisture: float:
	get:
		return _area_mean(face_moisture)
	set(value):
		face_moisture.fill(value)
var surface_browning: float:
	get:
		return _area_mean(face_browning)
	set(value):
		face_browning.fill(value)
var surface_char: float:
	get:
		return _area_mean(face_char)
	set(value):
		face_char.fill(value)

func _init() -> void:
	face_temp_c.resize(FACE_COUNT)
	face_moisture.resize(FACE_COUNT)
	face_browning.resize(FACE_COUNT)
	face_char.resize(FACE_COUNT)
	face_skin.resize(FACE_COUNT)
	face_temp_c.fill(0.0)
	face_moisture.fill(0.0)
	face_browning.fill(0.0)
	face_char.fill(0.0)
	face_skin.fill(0.0)

## A whole, raw item at the given ambient temperature, or null (with an
## error) when the ingredient can't exist as a piece (a liquid, or a
## granule with no size).
static func from_ingredient(p_ingredient: Ingredient, ambient_temp_c: float) -> FoodPiece:
	# A granule - a grain, a seed, a fleck of spice - is a solid particle
	# too, sized by its whole_size_mm.
	if p_ingredient == null or p_ingredient.physical_form == Ingredient.PhysicalForm.LIQUID \
			or p_ingredient.whole_size_mm.x <= 0.0 or p_ingredient.whole_size_mm.y <= 0.0 or p_ingredient.whole_size_mm.z <= 0.0:
		push_error("FoodPiece: only SOLID ingredients, and granules with a size, can be made into pieces")
		return null
	var piece := FoodPiece.new()
	piece.ingredient = p_ingredient
	piece.size_mm = p_ingredient.whole_size_mm
	var mass: float = p_ingredient.whole_mass_g()
	piece.water_g = mass * p_ingredient.water_fraction
	piece.solids_g = mass - piece.water_g
	piece.core_temp_c = ambient_temp_c
	piece.face_temp_c.fill(ambient_temp_c)
	piece.face_moisture.fill(p_ingredient.water_fraction)
	piece.face_skin.fill(1.0)
	piece.flavour = p_ingredient.flavour.copy() if p_ingredient.flavour else FlavourProfile.new()
	IngredientCatalog.ensure_loaded()
	piece.traits = p_ingredient.trait_doses()
	return piece

## A handful of a bulk ingredient - grain, seeds - as one kernel standing
## for all of them. The kernel is the ingredient's whole item.
static func handful(p_ingredient: Ingredient, grams: float, ambient_temp_c: float) -> FoodPiece:
	var kernel := from_ingredient(p_ingredient, ambient_temp_c)
	if kernel:
		kernel.count = maxi(roundi(grams / kernel.mass_g()), 1)
	return kernel

## Share of a heap's floor a loose heap of kernels covers.
const HEAP_PACKING: float = 0.55

func is_heap() -> bool:
	return count > 1

func total_mass_g() -> float:
	return mass_g() * count

## The box a piece takes up: itself, or for a heap, the kernels spread in
## an even layer no wider than `widest_mm` across, as deep as they need.
func bulk_size_mm(widest_mm: float = 120.0) -> Vector3:
	if count <= 1:
		return size_mm
	var area: float = size_mm.x * size_mm.z * count / HEAP_PACKING
	var side: float = minf(sqrt(area), widest_mm)
	var layers: float = maxf(area / (side * side), 1.0)
	return Vector3(side, size_mm.y * layers, side)

## The axis (Vector3.AXIS_*) a face is perpendicular to.
static func face_axis(face: int) -> int:
	return face >> 1

## +1 for a face on the positive side of its axis, -1 for the negative.
static func face_sign(face: int) -> float:
	return 1.0 if face % 2 == 0 else -1.0

## The face with the given axis and side.
static func face_of(axis: int, positive: bool) -> int:
	return axis * 2 + (0 if positive else 1)

## Outward normal of a face in the piece's local frame.
static func face_normal(face: int) -> Vector3:
	var normal := Vector3.ZERO
	normal[face_axis(face)] = face_sign(face)
	return normal

func mass_g() -> float:
	return solids_g + water_g + oil_g

## Water as a fraction of the whole piece's mass.
func moisture() -> float:
	return water_g / mass_g()

func oil_fraction() -> float:
	return oil_g / mass_g()

## Grams of its own fat still in it that could melt out.
func renderable_fat_g() -> float:
	var solids_share: float = 1.0 - ingredient.water_fraction
	if solids_share <= 0.0:
		return 0.0
	var fat_in_solids: float = (solids_g + fat_rendered_g) * ingredient.fat_fraction / solids_share
	return maxf(fat_in_solids - fat_rendered_g, 0.0)

## Overall density, in g/cm^3.
func density_g_per_cm3() -> float:
	return mass_g() / (volume_mm3() / 1000.0)

func volume_mm3() -> float:
	return size_mm.x * size_mm.y * size_mm.z

func surface_area_mm2() -> float:
	return 2.0 * (size_mm.x * size_mm.y + size_mm.y * size_mm.z + size_mm.x * size_mm.z)

## Area of the face perpendicular to the given axis - the face a cut along
## that axis exposes, and for AXIS_Y the face the piece rests on.
func cross_section_mm2(axis: int) -> float:
	return volume_mm3() / size_mm[axis]

func face_area_mm2(face: int) -> float:
	return cross_section_mm2(face_axis(face))

## The face's share of the whole surface, and so of the shell.
func face_share(face: int) -> float:
	return face_area_mm2(face) / surface_area_mm2()

func min_dimension_mm() -> float:
	return minf(size_mm.x, minf(size_mm.y, size_mm.z))

func shell_fraction() -> float:
	return minf(surface_area_mm2() * SHELL_DEPTH_MM / volume_mm3(), MAX_SHELL_FRACTION)

func shell_mass_g() -> float:
	return mass_g() * shell_fraction()

func core_mass_g() -> float:
	return mass_g() - shell_mass_g()

func face_shell_mass_g(face: int) -> float:
	return shell_mass_g() * face_share(face)

func face_water_g(face: int) -> float:
	return face_moisture[face] * face_shell_mass_g(face)

func surface_water_g() -> float:
	var total: float = 0.0
	var shell: float = shell_mass_g()
	var area: float = surface_area_mm2()
	for face in FACE_COUNT:
		total += face_moisture[face] * shell * face_area_mm2(face) / area
	return total

## Every face's water in grams, to restore after something changes the
## shell's mass (oil soaking in, the piece shrinking) without moving water.
func face_waters_g() -> PackedFloat64Array:
	var waters := PackedFloat64Array()
	waters.resize(FACE_COUNT)
	for face in FACE_COUNT:
		waters[face] = face_water_g(face)
	return waters

func restore_face_waters(waters: PackedFloat64Array) -> void:
	for face in FACE_COUNT:
		var shell: float = face_shell_mass_g(face)
		face_moisture[face] = waters[face] / shell if shell > 0.0 else 0.0
	clamp_surface_moisture()

## Water as a fraction of the core's mass.
func core_moisture() -> float:
	return maxf(water_g - surface_water_g(), 0.0) / core_mass_g()

## How dry one face is relative to the raw ingredient: 0 as wet as when raw
## (or wetter), 1 bone dry. Browning and crisping need a dry surface.
func face_dryness(face: int) -> float:
	var raw_moisture: float = ingredient.water_fraction
	if raw_moisture <= 0.0:
		return 1.0
	return clampf(1.0 - face_moisture[face] / raw_moisture, 0.0, 1.0)

## Area-weighted dryness of the whole surface.
func surface_dryness() -> float:
	var raw_moisture: float = ingredient.water_fraction
	if raw_moisture <= 0.0:
		return 1.0
	return clampf(1.0 - surface_moisture / raw_moisture, 0.0, 1.0)

## Area share of the surface that is still skin.
func skin_share() -> float:
	return _area_mean(face_skin)

## Keeps every face's moisture within 0-1 and the shell from holding more
## water than the piece has. Called after anything that changes the
## shell's size or the piece's water.
func clamp_surface_moisture() -> void:
	var shell_mass: float = shell_mass_g()
	if shell_mass <= 0.0:
		face_moisture.fill(0.0)
		return
	for face in FACE_COUNT:
		face_moisture[face] = clampf(face_moisture[face], 0.0, 1.0)
	var surface_water: float = surface_water_g()
	if surface_water > water_g and surface_water > 0.0:
		var scale: float = maxf(water_g, 0.0) / surface_water
		for face in FACE_COUNT:
			face_moisture[face] *= scale

## Shrinks the piece uniformly to a new volume, keeping its mass and every
## face's water where they are. Food shrinks as it loses water.
func shrink_to_volume(new_volume_mm3: float) -> void:
	var volume: float = volume_mm3()
	if new_volume_mm3 >= volume or new_volume_mm3 <= 0.0:
		return
	var waters := face_waters_g()
	size_mm *= pow(new_volume_mm3 / volume, 1.0 / 3.0)
	restore_face_waters(waters)

## Tips the piece 90 degrees onto its side, rolling it like a log about its
## longer horizontal axis - how a cook lays a plank flat to cut it into
## sticks, or turns a fry in the pan. Its cut history and its faces turn
## with it, so a cut that was vertical before the roll is horizontal after
## it, and the face that was on top is now a side. Returns the axis it
## rolled about.
func roll() -> int:
	if size_mm.x >= size_mm.z:
		_rotate_quarter(Vector3.AXIS_X)
		return Vector3.AXIS_X
	_rotate_quarter(Vector3.AXIS_Z)
	return Vector3.AXIS_Z

## Turns the piece a quarter turn (right-handed, +90 degrees) about one
## horizontal axis: about X, +Y goes to +Z; about Z, +X goes to +Y.
func _rotate_quarter(about: int) -> void:
	var first: int = Vector3.AXIS_Y if about == Vector3.AXIS_X else Vector3.AXIS_X
	var second: int = Vector3.AXIS_Z if about == Vector3.AXIS_X else Vector3.AXIS_Y
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
	# +first -> +second, +second -> -first, -first -> -second, -second -> +first.
	var mapping := {
		face_of(first, true): face_of(second, true),
		face_of(second, true): face_of(first, false),
		face_of(first, false): face_of(second, false),
		face_of(second, false): face_of(first, true),
	}
	for array_name in [&"face_temp_c", &"face_moisture", &"face_browning", &"face_char", &"face_skin"]:
		var old: PackedFloat64Array = get(array_name)
		var turned := old.duplicate()
		for from_face in mapping:
			turned[mapping[from_face]] = old[from_face]
		set(array_name, turned)

## Independent deep copy: the clone's flavour, faces and cut history can
## change without touching this piece.
func clone() -> FoodPiece:
	var copy := FoodPiece.new()
	copy.ingredient = ingredient
	copy.size_mm = size_mm
	copy.solids_g = solids_g
	copy.water_g = water_g
	copy.oil_g = oil_g
	copy.fat_rendered_g = fat_rendered_g
	copy.count = count
	copy.core_temp_c = core_temp_c
	copy.core_doneness = core_doneness
	copy.integrity = integrity
	copy.flavour = flavour.copy()
	copy.traits = traits.copy()
	copy.spices = spices.duplicate()
	copy.cut_axes = cut_axes.duplicate()
	copy.face_temp_c = face_temp_c.duplicate()
	copy.face_moisture = face_moisture.duplicate()
	copy.face_browning = face_browning.duplicate()
	copy.face_char = face_char.duplicate()
	copy.face_skin = face_skin.duplicate()
	return copy

func _area_mean(values: PackedFloat64Array) -> float:
	var area: float = surface_area_mm2()
	if area <= 0.0:
		return 0.0
	var total: float = 0.0
	for face in FACE_COUNT:
		total += values[face] * face_area_mm2(face)
	return total / area
