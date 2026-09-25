class_name FoodHeating
extends RefCounted

## Pure physics of one FoodPiece in a HeatExposure for a short time step.
## Every visible outcome of cooking - cooked through or raw in the middle,
## pale or golden, crisp or soggy, greasy, burnt, fallen apart - emerges from
## these rules acting on the piece's physical state. There are no recipes.
##
## Per step:
##   1. Heat flows from the medium into the surface shell (convection, in
##      proportion to area) and from the shell into the core (conduction,
##      with conductance k A^2 / V, so cooking time grows with thickness
##      squared).
##   2. A shell above 100 degrees C that still holds water spends the excess
##      heat boiling it off, pinning the surface at 100 until it dries.
##   3. Water migrates from the wetter core back out to the shell.
##   4. In a fatty medium, food soaks up fat: some replaces the water that
##      boiled off, and more seeps in when the oil is too cool for steam to
##      push it back.
##   5. The core cooks once it passes the ingredient's cook temperature, and
##      keeps overcooking past done. Overcooked food with a wet surface
##      loses integrity.
##   6. A dry, hot surface browns (Maillard reactions and caramelisation,
##      driven by sugar, starch and protein), and a browned surface far too
##      hot chars. Browning adds aroma and savouriness; char adds bitterness.
##   7. Flavour diffuses between the food and a liquid medium, faster when
##      hot.
##
## Integration is explicit, split into substeps short enough for the
## thinnest slice's thermal time constant, so no step can overshoot.

const WATER_BOILING_POINT_C: float = 100.0
const WATER_LATENT_HEAT_J_PER_G: float = 2257.0
## The longest substep allowed, as a fraction of the fastest thermal time
## constant in the piece.
const MAX_SUBSTEP_FRACTION_OF_TAU: float = 0.2
## Floor on the substep so a degenerate piece can never stall the loop.
const MIN_SUBSTEP_S: float = 0.0001
const MAX_DONENESS: float = 3.0

## Core-to-shell water flow per second, per unit of moisture difference,
## as a fraction of the shell's mass.
const WATER_MIGRATION_PER_S: float = 0.002

## Doneness gained per cook_seconds when the core sits this far above the
## ingredient's cook temperature.
const COOK_REFERENCE_SPAN_C: float = 30.0

const BROWNING_ONSET_C: float = 120.0
const BROWNING_REFERENCE_C: float = 150.0
## Browning speed doubles with every this many degrees.
const BROWNING_DOUBLING_C: float = 10.0
## Browning per second at the reference temperature, per unit of reactivity,
## on a fully dry surface.
const BROWNING_RATE_AT_REFERENCE: float = 0.034
const SUGAR_REACTIVITY: float = 1.0
const STARCH_REACTIVITY: float = 0.1
const PROTEIN_REACTIVITY: float = 0.5
const BROWNING_AROMA_GAIN: float = 0.3
const BROWNING_UMAMI_GAIN: float = 0.15

const CHAR_ONSET_C: float = 190.0
const CHAR_REFERENCE_C: float = 200.0
const CHAR_DOUBLING_C: float = 10.0
## Char per second at the reference temperature on a fully dry, fully
## browned surface of an ingredient with char susceptibility 1.
const CHAR_RATE_AT_REFERENCE: float = 0.0005
const CHAR_BITTERNESS_GAIN: float = 0.8

## Degrees above boiling at which steam leaving a moist piece holds oil out
## completely. Cooler oil seeps in.
const STEAM_BARRIER_SPAN_C: float = 60.0
## Below this overall moisture a piece no longer steams enough to resist oil.
const STEAM_MIN_MOISTURE: float = 0.05
const OIL_SEEP_G_PER_M2_S: float = 1.0
## Grams of fat absorbed per gram of water boiled off.
const OIL_REPLACES_WATER_RATIO: float = 0.15

## Flavour carried across a square metre of surface per second, per unit of
## intensity difference, at 100 degrees C.
const FLAVOUR_TRANSFER_G_PER_M2_S_AT_100C: float = 12.0
const FLAVOUR_TRANSFER_DOUBLING_C: float = 20.0

## Advances the piece by dt seconds of exposure and reports what it took
## from and gave to the medium. Mutates the piece, and the exposure's
## flavour.
static func step(piece: FoodPiece, exposure: HeatExposure, dt: float) -> HeatExchange:
	var exchange := HeatExchange.new()
	var remaining: float = dt
	while remaining > 0.0:
		var substep: float = minf(remaining, maxf(_stable_substep(piece, exposure), MIN_SUBSTEP_S))
		_integrate(piece, exposure, substep, exchange)
		remaining -= substep
	return exchange

## Conductance from surface shell to core, in W/K.
static func core_conductance_w_per_k(piece: FoodPiece) -> float:
	var area_m2: float = piece.surface_area_mm2() * 1e-6
	var volume_m3: float = piece.volume_mm3() * 1e-9
	return piece.ingredient.thermal_conductivity_w_per_m_k * area_m2 * area_m2 / volume_m3

static func browning_reactivity(ingredient: Ingredient) -> float:
	return ingredient.sugar_fraction * SUGAR_REACTIVITY \
		+ ingredient.starch_fraction * STARCH_REACTIVITY \
		+ ingredient.protein_fraction * PROTEIN_REACTIVITY

static func _stable_substep(piece: FoodPiece, exposure: HeatExposure) -> float:
	var specific_heat: float = piece.ingredient.specific_heat_j_per_g_k
	var convection: float = exposure.heat_transfer_w_per_m2_k * piece.surface_area_mm2() * 1e-6
	var conduction: float = core_conductance_w_per_k(piece)
	var shell_tau: float = piece.shell_mass_g() * specific_heat / maxf(convection + conduction, 1e-9)
	var core_tau: float = piece.core_mass_g() * specific_heat / maxf(conduction, 1e-9)
	return MAX_SUBSTEP_FRACTION_OF_TAU * minf(shell_tau, core_tau)

static func _integrate(piece: FoodPiece, exposure: HeatExposure, dt: float, exchange: HeatExchange) -> void:
	var specific_heat: float = piece.ingredient.specific_heat_j_per_g_k
	var area_m2: float = piece.surface_area_mm2() * 1e-6
	var shell_capacity: float = piece.shell_mass_g() * specific_heat
	var core_capacity: float = piece.core_mass_g() * specific_heat

	var heat_in_w: float = exposure.heat_transfer_w_per_m2_k * area_m2 * (exposure.temp_c - piece.surface_temp_c)
	var heat_to_core_w: float = core_conductance_w_per_k(piece) * (piece.surface_temp_c - piece.core_temp_c)
	exchange.energy_j += heat_in_w * dt
	piece.core_temp_c += heat_to_core_w * dt / core_capacity

	var surface_temp: float = piece.surface_temp_c + (heat_in_w - heat_to_core_w) * dt / shell_capacity
	var evaporated_g: float = 0.0
	if surface_temp > WATER_BOILING_POINT_C and piece.surface_water_g() > 0.0:
		var excess_j: float = (surface_temp - WATER_BOILING_POINT_C) * shell_capacity
		evaporated_g = minf(excess_j / WATER_LATENT_HEAT_J_PER_G, piece.surface_water_g())
		surface_temp -= evaporated_g * WATER_LATENT_HEAT_J_PER_G / shell_capacity
		_remove_surface_water(piece, evaporated_g)
		exchange.evaporated_g += evaporated_g
	piece.surface_temp_c = surface_temp

	_migrate_water(piece, dt)
	_absorb_fat(piece, exposure, area_m2, evaporated_g, dt, exchange)
	_cook_core(piece, dt)
	_brown_and_char(piece, dt)
	_exchange_flavour(piece, exposure, area_m2, dt)

static func _remove_surface_water(piece: FoodPiece, grams: float) -> void:
	var surface_water: float = piece.surface_water_g() - grams
	piece.water_g -= grams
	piece.surface_moisture = surface_water / piece.shell_mass_g()
	piece.clamp_surface_moisture()

static func _migrate_water(piece: FoodPiece, dt: float) -> void:
	var gradient: float = piece.core_moisture() - piece.surface_moisture
	if gradient <= 0.0:
		return
	piece.surface_moisture += WATER_MIGRATION_PER_S * gradient * dt
	piece.clamp_surface_moisture()

static func _absorb_fat(
		piece: FoodPiece, exposure: HeatExposure, area_m2: float, evaporated_g: float,
		dt: float, exchange: HeatExchange) -> void:
	if exposure.fat_fraction <= 0.0:
		return
	var steam_barrier: float = 0.0
	if piece.moisture() > STEAM_MIN_MOISTURE:
		steam_barrier = clampf((exposure.temp_c - WATER_BOILING_POINT_C) / STEAM_BARRIER_SPAN_C, 0.0, 1.0)
	var seeped_g: float = OIL_SEEP_G_PER_M2_S * area_m2 * (1.0 - steam_barrier) * dt
	var replaced_g: float = evaporated_g * OIL_REPLACES_WATER_RATIO
	var available_g: float = exposure.medium_mass_g * exposure.fat_fraction - exchange.fat_absorbed_g
	var absorbed_g: float = minf((seeped_g + replaced_g) * exposure.fat_fraction, maxf(available_g, 0.0))
	if absorbed_g <= 0.0:
		return

	# The shell grows by the oil it takes in; its water stays where it is.
	var surface_water: float = piece.surface_water_g()
	if exposure.flavour:
		piece.flavour = FlavourProfile.mix_by_mass(piece.flavour, piece.mass_g(), exposure.flavour, absorbed_g)
	piece.oil_g += absorbed_g
	piece.surface_moisture = surface_water / piece.shell_mass_g()
	piece.clamp_surface_moisture()
	exchange.fat_absorbed_g += absorbed_g

static func _cook_core(piece: FoodPiece, dt: float) -> void:
	var ingredient: Ingredient = piece.ingredient
	var above_cook_temp: float = piece.core_temp_c - ingredient.cook_temp_c
	if above_cook_temp > 0.0:
		var rate: float = above_cook_temp / COOK_REFERENCE_SPAN_C / ingredient.cook_seconds
		piece.core_doneness = minf(piece.core_doneness + rate * dt, MAX_DONENESS)

	var overcooked: float = piece.core_doneness - 1.0
	if overcooked > 0.0:
		var wetness: float = 1.0 - piece.surface_dryness()
		piece.integrity = maxf(piece.integrity - ingredient.overcook_softening_per_s * overcooked * wetness * dt, 0.0)

static func _brown_and_char(piece: FoodPiece, dt: float) -> void:
	var dryness: float = piece.surface_dryness()
	if dryness <= 0.0:
		return
	var temp: float = piece.surface_temp_c
	if temp > BROWNING_ONSET_C and piece.surface_browning < 1.0:
		var rate: float = BROWNING_RATE_AT_REFERENCE * browning_reactivity(piece.ingredient) \
			* pow(2.0, (temp - BROWNING_REFERENCE_C) / BROWNING_DOUBLING_C) * dryness
		var browned: float = minf(rate * dt, 1.0 - piece.surface_browning)
		piece.surface_browning += browned
		piece.flavour.aroma = minf(piece.flavour.aroma + browned * BROWNING_AROMA_GAIN, 1.0)
		piece.flavour.umami = minf(piece.flavour.umami + browned * BROWNING_UMAMI_GAIN, 1.0)
	if temp > CHAR_ONSET_C and piece.surface_char < 1.0:
		var char_rate: float = CHAR_RATE_AT_REFERENCE * pow(2.0, (temp - CHAR_REFERENCE_C) / CHAR_DOUBLING_C) \
			* dryness * piece.surface_browning * piece.ingredient.char_susceptibility
		var charred: float = minf(char_rate * dt, 1.0 - piece.surface_char)
		piece.surface_char += charred
		piece.flavour.bitter = minf(piece.flavour.bitter + charred * CHAR_BITTERNESS_GAIN, 1.0)

static func _exchange_flavour(piece: FoodPiece, exposure: HeatExposure, area_m2: float, dt: float) -> void:
	if exposure.flavour == null or exposure.medium_mass_g <= 0.0:
		return
	var piece_mass: float = piece.mass_g()
	var medium_mass: float = exposure.medium_mass_g
	var conductance: float = FLAVOUR_TRANSFER_G_PER_M2_S_AT_100C * area_m2 \
		* pow(2.0, (exposure.temp_c - WATER_BOILING_POINT_C) / FLAVOUR_TRANSFER_DOUBLING_C)
	for axis in FlavourProfile.AXES:
		var in_piece: float = piece.flavour.get(axis)
		var in_medium: float = exposure.flavour.get(axis)
		var equilibrium: float = (in_piece * piece_mass + in_medium * medium_mass) / (piece_mass + medium_mass)
		# Never carry more than it takes to reach equilibrium in one substep.
		var carried: float = conductance * (in_piece - in_medium) * dt
		var limit: float = absf(in_piece - equilibrium) * piece_mass
		carried = clampf(carried, -limit, limit)
		piece.flavour.set(axis, in_piece - carried / piece_mass)
		exposure.flavour.set(axis, in_medium + carried / medium_mass)
