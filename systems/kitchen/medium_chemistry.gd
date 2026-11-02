class_name MediumChemistry
extends RefCounted

## Pure chemistry of a cooking medium as it is used. Frying oil breaks down
## the hotter and longer it is held: oxidation and polymerisation all the
## time it is hot, hydrolysis whenever wet food steams through it, and fast
## decomposition once it passes its smoke point. Broken-down oil smokes at
## a lower temperature, darkens, tastes acrid, browns food faster and soaks
## into it more - so oil that has been abused makes worse fries, without
## any rule about fries.

## Reference temperature for breakdown_per_hour_at_180c, and how many
## degrees hotter double the rate.
const BREAKDOWN_REFERENCE_C: float = 180.0
const BREAKDOWN_DOUBLING_C: float = 10.0
## Smoke point lost by fully spent oil, as a share of the fresh smoke point.
const SPENT_SMOKE_POINT_DROP: float = 0.3
## Degrees past the smoke point at which smoke is at its thickest.
const SMOKE_FULL_SPAN_C: float = 25.0
## Breakdown per second at full smoke: oil smoking hard ruins within a few
## minutes.
const SMOKING_BREAKDOWN_PER_S: float = 0.002
## Bitterness the medium gains per unit of breakdown: acrid, rancid notes.
const ACRID_BITTERNESS: float = 0.6
## Food browning and oil uptake gained in fully spent oil.
const SPENT_BROWNING_BOOST: float = 1.5
const SPENT_UPTAKE_BOOST: float = 1.0

## The temperature this medium starts smoking at, worn as it is. 0 when it
## never smokes.
static func smoke_point_c(medium: Ingredient, breakdown: float) -> float:
	if medium == null or medium.smoke_point_c <= 0.0:
		return 0.0
	return medium.smoke_point_c * (1.0 - SPENT_SMOKE_POINT_DROP * clampf(breakdown, 0.0, 1.0))

## How thickly it smokes at this temperature, 0-1.
static func smoke_level(medium: Ingredient, breakdown: float, temp_c: float) -> float:
	var smoke_point: float = smoke_point_c(medium, breakdown)
	if smoke_point <= 0.0:
		return 0.0
	return clampf((temp_c - smoke_point) / SMOKE_FULL_SPAN_C, 0.0, 1.0)

## Breakdown gained over dt seconds at this temperature, with this much
## steam bubbling through the medium.
static func breakdown_gain(
		medium: Ingredient, breakdown: float, temp_c: float, medium_mass_g: float,
		steam_g: float, dt: float) -> float:
	if medium == null or medium_mass_g <= 0.0:
		return 0.0
	var gain: float = 0.0
	if medium.breakdown_per_hour_at_180c > 0.0:
		gain += medium.breakdown_per_hour_at_180c / 3600.0 \
			* pow(2.0, (temp_c - BREAKDOWN_REFERENCE_C) / BREAKDOWN_DOUBLING_C) * dt
	gain += medium.breakdown_per_g_steam_per_kg * steam_g / (medium_mass_g / 1000.0)
	gain += SMOKING_BREAKDOWN_PER_S * smoke_level(medium, breakdown, temp_c) * dt
	return minf(gain, 1.0 - breakdown)

## Applies breakdown to the medium's flavour.
static func sour_the_flavour(flavour: FlavourProfile, gained: float) -> void:
	if flavour:
		flavour.bitter = minf(flavour.bitter + gained * ACRID_BITTERNESS, 1.0)

static func browning_boost(breakdown: float) -> float:
	return 1.0 + SPENT_BROWNING_BOOST * clampf(breakdown, 0.0, 1.0)

static func uptake_boost(breakdown: float) -> float:
	return 1.0 + SPENT_UPTAKE_BOOST * clampf(breakdown, 0.0, 1.0)
