class_name Ingredient
extends Resource

## One foraged ingredient (tide pools, cliff gardens, drift nets). New
## ingredients are authored as new .tres instances - no new code required.

## How the kitchen handles the ingredient. SOLID ingredients become
## FoodPieces that can be cut; GRANULAR (seeds, grains) and LIQUID (oils,
## stocks) are handled in bulk, by mass.
enum PhysicalForm { SOLID, GRANULAR, LIQUID }

## Which pantry shelf offers it. NONE for things that only come from
## something else - the parts of a fish dressed at the board, oil from the
## press.
enum Shelf { NONE, GARDEN, CATCH, SPICE, GRAIN }

## Composition fractions may undershoot 1.0 by the unmodelled remainder
## (fibre, ash), but never exceed it beyond rounding.
const COMPOSITION_TOLERANCE: float = 0.0001

@export var id: StringName = &""
@export var display_name: String = ""
## Where it comes from and what it is, in the world's own words.
@export_multiline var lore: String = ""
## Colour of the outside - skin, peel, shell.
@export var tint_color: Color = Color.WHITE
## Colour of the inside, shown on fresh cut faces.
@export var flesh_color: Color = Color.WHITE
## The whole, uncut item as it appears in the kitchen: a .glb from the model
## kit, origin at the centre of its base. Cut pieces are drawn separately.
@export var whole_model: PackedScene

@export_group("Affinity")
@export var elemental_affinity: ElementalAffinity.Type = ElementalAffinity.Type.NONE

@export_group("Physical")
@export var physical_form: PhysicalForm = PhysicalForm.SOLID
## One whole item, modelled as a box, in mm. SOLID only.
@export var whole_size_mm: Vector3 = Vector3.ZERO
## Material density for SOLID; bulk density for GRANULAR and LIQUID.
@export var density_g_per_cm3: float = 1.0

@export_group("Composition")
## Mass fractions of the raw ingredient.
@export_range(0.0, 1.0) var water_fraction: float = 0.0
@export_range(0.0, 1.0) var starch_fraction: float = 0.0
@export_range(0.0, 1.0) var sugar_fraction: float = 0.0
@export_range(0.0, 1.0) var fat_fraction: float = 0.0
@export_range(0.0, 1.0) var protein_fraction: float = 0.0

@export_group("Texture")
## How firm it is raw, 0-1: a raw potato or carrot crunches (1); raw fish,
## liver and roe are soft (low). Cooking softens everything from there.
@export_range(0.0, 1.0) var raw_firmness: float = 1.0

@export_group("Handling")
## How well it stretches and drapes, 0 stiff to 1 like a wet hide: a pliable
## sheet laid over a pot seals it.
@export_range(0.0, 1.0) var pliability: float = 0.0

@export_group("Cutting")
## A piece cut thinner than this starts to crumble: its integrity scales
## down in proportion to how far below this thickness the cut went.
@export var stable_thickness_mm: float = 3.0
## Fraction of integrity lost by both pieces of a perpendicular cut made
## without holding the food steady.
@export_range(0.0, 1.0) var unsteadied_cut_integrity_loss: float = 0.0

@export_group("Thermal")
@export var specific_heat_j_per_g_k: float = 3.5
@export var thermal_conductivity_w_per_m_k: float = 0.5
## Core temperature at which cooking starts: starch gelatinising, proteins
## setting. SOLID only.
@export var cook_temp_c: float = 60.0
## Seconds to cook through once the core sits 30 degrees C above
## cook_temp_c. Cooking is proportionally slower closer to cook_temp_c and
## faster above it. SOLID only.
@export var cook_seconds: float = 120.0
## Integrity lost per second, per unit of overcooking, while the surface is
## wet. A dry crust holds an overcooked piece together; a wet one lets it
## fall apart. SOLID only.
@export var overcook_softening_per_s: float = 0.01
## The span of core doneness at which this ingredient is at its best: 1 is
## just cooked through, higher is softer and more tender. Below the span it
## is underdone, above it overcooked. SOLID only.
@export var ideal_doneness_min: float = 1.0
@export var ideal_doneness_max: float = 1.6
## How readily a browned surface burns, relative to a potato's (1.0). Thin,
## sugary skins like a chilli's burn far faster.
@export var char_susceptibility: float = 1.0
## How freely water, fat and flavour pass through the skin, relative to cut
## flesh (1.0). A potato's skin keeps a whole potato from drying out or
## soaking up oil the way cut faces do. SOLID only.
@export_range(0.0, 1.0) var skin_permeability: float = 1.0
## Volume lost per volume of water the food loses: 0 keeps its size, 1
## shrinks it by exactly the water that left. Fries shrink as they fry.
## SOLID only.
@export_range(0.0, 1.0) var shrinkage_per_water_lost: float = 0.0

@export_group("Hydration")
## For dry grains and pulses: the water they can drink in, in grams per
## gram of their solids, once fully cooked (rice about 2.3). 0 for food that
## never takes up water.
@export var water_uptake_capacity: float = 0.0
## Share of what they could still take up that they drink per second in
## boiling water, while wetted. Slower in cooler water.
@export var hydration_rate_per_s: float = 0.0

@export_group("Seasoning")
## How strongly its flavour and essences count, gram for gram, when it
## seasons food or a pot - a pinch of salt tastes of far more than a pinch
## of potato.
@export var flavour_potency: float = 1.0
## Grams the caretaker takes at a time from the pantry: a pinch of spice, a
## handful of grain.
@export var scoop_g: float = 0.0

@export_group("As a Cooking Medium")
## For LIQUID ingredients food can be cooked in. 0 means the liquid does not
## boil within kitchen temperatures (oils).
@export var boiling_point_c: float = 0.0
@export var latent_heat_j_per_g: float = 0.0
## Heat transfer from this liquid into food submerged in it, in W/(m^2 K).
@export var medium_heat_transfer_w_per_m2_k: float = 0.0
## Temperature at which fresh oil starts to smoke and break down fast. 0
## for a liquid that does not (water). Worn oil smokes sooner.
@export var smoke_point_c: float = 0.0
## Breakdown (0 fresh to 1 spent) per hour held at 180 degrees C, from
## oxidation and polymerisation. Doubles every 10 degrees hotter.
@export var breakdown_per_hour_at_180c: float = 0.0
## Breakdown per gram of steam bubbled through each kilogram of the medium,
## from hydrolysis - wet food wears frying oil out.
@export var breakdown_per_g_steam_per_kg: float = 0.0
## Colour of the medium when it is spent: fresh oil darkens toward this.
@export var spent_color: Color = Color(0.35, 0.2, 0.08, 1.0)

## Share of it that can be eaten. Bones, shell and horn are 0: they give
## their flavour and essence to what they cook with, and feed no one
## themselves.
@export_range(0.0, 1.0) var edible_share: float = 1.0

@export_group("Flavour")
@export var flavour: FlavourProfile

@export_group("Pantry")
@export var pantry_shelf: Shelf = Shelf.NONE

@export_group("Creature")
## For the whole carcass of a creature: the species, whose parts it opens
## into when it is dressed on the board.
@export var creature: Creature

@export_group("Rendering")
## Fat that melts out of the food once it is hot enough - tallow from ram
## fat, schmaltz from a bird's skin - and the liquid it becomes. 0 or no
## liquid: nothing renders.
@export var render_temp_c: float = 0.0
@export var renders_into: Ingredient
## Grams of fat rendered per second per gram of fat left, per degree above
## the rendering temperature.
@export var render_rate_per_s_per_k: float = 0.0

@export_group("Mystical")
## The essences this ingredient carries of itself.
@export var traits: Array[TraitDose] = []

## Essences it carries from what it ate, worked out from the food web by
## FoodWeb at load time. Not authored.
var inherited_traits: Dictionary[MysticTrait, float] = {}

@export_group("Availability")
## Foraged from the start. Everything else is gated behind the lighthouse
## upgrade that opens its foraging zone.
@export var available_from_start: bool = false

## Everything it carries, authored and inherited, as a fresh copy.
func trait_doses() -> TraitDoses:
	var doses := TraitDoses.new()
	for dose in traits:
		if dose and dose.mystic_trait:
			doses.add_dose(dose.mystic_trait, dose.concentration)
	for mystic_trait in inherited_traits:
		doses.add_dose(mystic_trait, inherited_traits[mystic_trait])
	return doses

## Mass of one whole SOLID item, from its box volume and density.
func whole_mass_g() -> float:
	return whole_size_mm.x * whole_size_mm.y * whole_size_mm.z / 1000.0 * density_g_per_cm3

## Every problem with this ingredient's physical data, or an empty array
## if it is fit for the kitchen simulation.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("id is empty")
	if density_g_per_cm3 <= 0.0:
		problems.append("density must be positive")

	var composition: Array[float] = [
		water_fraction, starch_fraction, sugar_fraction, fat_fraction, protein_fraction
	]
	var composition_total: float = 0.0
	for fraction in composition:
		if fraction < 0.0 or fraction > 1.0:
			problems.append("composition fractions must each be within 0-1")
			break
		composition_total += fraction
	if composition_total > 1.0 + COMPOSITION_TOLERANCE:
		problems.append("composition fractions sum to %.3f, above 1" % composition_total)

	if specific_heat_j_per_g_k <= 0.0:
		problems.append("specific heat must be positive")

	if physical_form == PhysicalForm.SOLID:
		if whole_size_mm.x <= 0.0 or whole_size_mm.y <= 0.0 or whole_size_mm.z <= 0.0:
			problems.append("a SOLID ingredient needs a positive whole size on every axis")
		if stable_thickness_mm <= 0.0:
			problems.append("stable thickness must be positive")
		if thermal_conductivity_w_per_m_k <= 0.0:
			problems.append("a SOLID ingredient needs a positive thermal conductivity")
		if cook_seconds <= 0.0:
			problems.append("a SOLID ingredient needs a positive cook time")
		if overcook_softening_per_s < 0.0:
			problems.append("overcook softening cannot be negative")
		if ideal_doneness_min <= 0.0 or ideal_doneness_max < ideal_doneness_min:
			problems.append("ideal doneness needs 0 < min <= max")
		if char_susceptibility < 0.0:
			problems.append("char susceptibility cannot be negative")
		if skin_permeability < 0.0 or skin_permeability > 1.0:
			problems.append("skin permeability must be within 0-1")
		if shrinkage_per_water_lost < 0.0 or shrinkage_per_water_lost > 1.0:
			problems.append("shrinkage must be within 0-1")
	elif physical_form == PhysicalForm.LIQUID:
		if medium_heat_transfer_w_per_m2_k <= 0.0:
			problems.append("a LIQUID needs a positive heat transfer into food")
		if boiling_point_c > 0.0 and latent_heat_j_per_g <= 0.0:
			problems.append("a LIQUID that boils needs a latent heat")
		if smoke_point_c < 0.0 or breakdown_per_hour_at_180c < 0.0 or breakdown_per_g_steam_per_kg < 0.0:
			problems.append("smoke point and breakdown rates cannot be negative")
	if water_uptake_capacity < 0.0 or hydration_rate_per_s < 0.0:
		problems.append("hydration cannot be negative")
	if water_uptake_capacity > 0.0 and hydration_rate_per_s <= 0.0:
		problems.append("food that takes up water needs a hydration rate")
	if flavour_potency <= 0.0:
		problems.append("flavour potency must be positive")
	if (pantry_shelf == Shelf.SPICE or pantry_shelf == Shelf.GRAIN) and scoop_g <= 0.0:
		problems.append("spices and grains need a scoop size")
	if render_temp_c > 0.0 and (renders_into == null or render_rate_per_s_per_k <= 0.0):
		problems.append("a fat that renders needs the liquid it renders into and a rate")
	if renders_into and renders_into.physical_form != PhysicalForm.LIQUID:
		problems.append("fat can only render into a LIQUID")
	if unsteadied_cut_integrity_loss < 0.0 or unsteadied_cut_integrity_loss > 1.0:
		problems.append("unsteadied cut integrity loss must be within 0-1")

	for dose in traits:
		if dose == null or dose.mystic_trait == null:
			problems.append("a trait dose names no trait")
		elif dose.concentration < 0.0:
			problems.append("trait doses cannot be negative")
		elif not dose.mystic_trait.validate().is_empty():
			problems.append("trait %s is invalid: %s" % [dose.mystic_trait.id, ", ".join(dose.mystic_trait.validate())])
	if flavour == null:
		problems.append("flavour profile is missing")
	elif not flavour.is_in_range():
		problems.append("flavour intensities must each be within 0-1")
	return problems
