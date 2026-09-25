class_name Ingredient
extends Resource

## One foraged ingredient (tide pools, cliff gardens, drift nets). New
## ingredients are authored as new .tres instances - no new code required.

## How the kitchen handles the ingredient. SOLID ingredients become
## FoodPieces that can be cut; GRANULAR (seeds, grains) and LIQUID (oils,
## stocks) are handled in bulk, by mass.
enum PhysicalForm { SOLID, GRANULAR, LIQUID }

## Composition fractions may undershoot 1.0 by the unmodelled remainder
## (fibre, ash), but never exceed it beyond rounding.
const COMPOSITION_TOLERANCE: float = 0.0001

@export var id: StringName = &""
@export var display_name: String = ""
## Colour of the outside - skin, peel, shell.
@export var tint_color: Color = Color.WHITE
## Colour of the inside, shown on fresh cut faces.
@export var flesh_color: Color = Color.WHITE

@export_group("Base Restorative Properties")
@export var base_nourishment: float = 0.0
@export var base_calming: float = 0.0
@export var base_buoyancy_delta: float = 0.0

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

@export_group("As a Cooking Medium")
## For LIQUID ingredients food can be cooked in. 0 means the liquid does not
## boil within kitchen temperatures (oils).
@export var boiling_point_c: float = 0.0
@export var latent_heat_j_per_g: float = 0.0
## Heat transfer from this liquid into food submerged in it, in W/(m^2 K).
@export var medium_heat_transfer_w_per_m2_k: float = 0.0

@export_group("Flavour")
@export var flavour: FlavourProfile

@export_group("Availability")
## Foraged from the start. Everything else is gated behind the lighthouse
## upgrade that opens its foraging zone.
@export var available_from_start: bool = false

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
	elif physical_form == PhysicalForm.LIQUID:
		if medium_heat_transfer_w_per_m2_k <= 0.0:
			problems.append("a LIQUID needs a positive heat transfer into food")
		if boiling_point_c > 0.0 and latent_heat_j_per_g <= 0.0:
			problems.append("a LIQUID that boils needs a latent heat")
	if unsteadied_cut_integrity_loss < 0.0 or unsteadied_cut_integrity_loss > 1.0:
		problems.append("unsteadied cut integrity loss must be within 0-1")

	if flavour == null:
		problems.append("flavour profile is missing")
	elif not flavour.is_in_range():
		problems.append("flavour intensities must each be within 0-1")
	return problems
