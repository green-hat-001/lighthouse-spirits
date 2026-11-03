class_name WaterVapour
extends RefCounted

## Water vapour physics shared by everything that dries, steams or boils in
## the kitchen. Evaporation from a wet surface into air is driven by the
## difference between the vapour density at the surface (saturated at the
## surface's temperature, scaled by how wet it is) and in the air, carried
## by a mass-transfer coefficient that follows from the convective heat
## transfer coefficient by the Lewis analogy.

const MOLAR_MASS_KG_PER_MOL: float = 0.018015
const GAS_CONSTANT_J_PER_MOL_K: float = 8.314
const LATENT_HEAT_J_PER_G: float = 2257.0
## Density times specific heat of air, in J/(m^3 K), for the Lewis analogy:
## mass transfer coefficient (m/s) = heat transfer coefficient / this.
const AIR_VOLUMETRIC_HEAT_J_PER_M3_K: float = 1206.0
## Saturation is evaluated no hotter than boiling: above it the surface
## boils instead, and that is handled as boiling.
const BOILING_C: float = 100.0

## Saturation vapour pressure over water (Magnus formula), in Pa.
static func saturation_pressure_pa(temp_c: float) -> float:
	var t: float = minf(temp_c, BOILING_C)
	return 610.94 * exp(17.625 * t / (t + 243.04))

## Saturated vapour density, in kg/m^3.
static func saturation_density_kg_m3(temp_c: float) -> float:
	var t: float = minf(temp_c, BOILING_C)
	return saturation_pressure_pa(t) * MOLAR_MASS_KG_PER_MOL / (GAS_CONSTANT_J_PER_MOL_K * (t + 273.15))

## Rate of change of saturated vapour density with temperature, in
## kg/(m^3 K). Evaporative cooling gets stronger this fast as a surface
## warms, which the integrators need to keep their steps stable.
static func saturation_density_slope(temp_c: float) -> float:
	var t: float = minf(temp_c, BOILING_C - 0.5)
	return (saturation_density_kg_m3(t + 0.5) - saturation_density_kg_m3(t - 0.5))

## Evaporation from a wet surface into air, in g/s. `wetness` (0-1) scales
## the surface's vapour density: a crisp crust holds almost no free water.
## Never negative - condensation onto food is not modelled.
static func evaporation_g_per_s(
		convective_w_per_m2_k: float, area_m2: float, surface_temp_c: float,
		wetness: float, air_vapour_kg_m3: float) -> float:
	var surface_vapour: float = saturation_density_kg_m3(surface_temp_c) * clampf(wetness, 0.0, 1.0)
	var driving: float = surface_vapour - air_vapour_kg_m3
	if driving <= 0.0:
		return 0.0
	return convective_w_per_m2_k / AIR_VOLUMETRIC_HEAT_J_PER_M3_K * area_m2 * driving * 1000.0

## Water moving between a surface and the air around it, in g/s: positive
## when the surface dries into the air, negative when vapour condenses onto
## a surface colder than the air's dew point - how food steams in a covered
## pot, picking up water and heat at once.
static func exchange_g_per_s(
		convective_w_per_m2_k: float, area_m2: float, surface_temp_c: float,
		wetness: float, air_vapour_kg_m3: float) -> float:
	var saturated: float = saturation_density_kg_m3(surface_temp_c)
	# Condensing onto a surface doesn't depend on how wet it already is.
	var surface_vapour: float = saturated * clampf(wetness, 0.0, 1.0) if air_vapour_kg_m3 < saturated else saturated
	return convective_w_per_m2_k / AIR_VOLUMETRIC_HEAT_J_PER_M3_K * area_m2 * (surface_vapour - air_vapour_kg_m3) * 1000.0

## The extra effective heat transfer coefficient, in W/(m^2 K), that
## evaporation adds to a wet surface at this temperature.
static func evaporative_w_per_m2_k(convective_w_per_m2_k: float, surface_temp_c: float, wetness: float) -> float:
	return LATENT_HEAT_J_PER_G * 1000.0 * convective_w_per_m2_k / AIR_VOLUMETRIC_HEAT_J_PER_M3_K \
		* saturation_density_slope(surface_temp_c) * clampf(wetness, 0.0, 1.0)
