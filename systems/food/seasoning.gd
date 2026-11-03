class_name Seasoning
extends RefCounted

## Pure rules for seasoning: a pinch of a spice scattered over food or into
## a pot. Spice is potent - gram for gram its flavour and essences count for
## far more than the food's (Ingredient.flavour_potency) - but how much of a
## pinch lands where it is meant to depends on the surface it falls on.
## Salt sticks to the oily skin of a fresh fry and bounces off a dry,
## cold one. Into a liquid, each flavour dissolves only as far as that
## liquid can carry it, so salt seasons water and not oil, and a chilli
## spice gives oil its heat.

## Share of a pinch that sticks to a perfectly dry, unoiled surface, and
## how much wetness and oil add to it.
const DRY_ADHESION: float = 0.15
const WET_ADHESION: float = 0.5
const OILY_ADHESION: float = 0.8
const FULLY_OILY_FRACTION: float = 0.15

## Share of a pinch that sticks to this piece.
static func adhesion(piece: FoodPiece) -> float:
	var wet: float = 1.0 - piece.surface_dryness()
	var oily: float = clampf(piece.oil_fraction() / FULLY_OILY_FRACTION, 0.0, 1.0)
	return clampf(DRY_ADHESION + WET_ADHESION * wet + OILY_ADHESION * oily, 0.0, 1.0)

## Scatters `grams` of a spice over pieces, shared by the area they show
## from above. Returns the grams that stuck; the rest falls away.
static func season_pieces(pieces: Array[FoodPiece], spice: Ingredient, grams: float) -> float:
	var areas: Array[float] = []
	var total_area: float = 0.0
	for piece in pieces:
		var size := piece.bulk_size_mm()
		areas.append(size.x * size.z)
		total_area += size.x * size.z
	if total_area <= 0.0 or grams <= 0.0:
		return 0.0
	var stuck_total: float = 0.0
	for index in pieces.size():
		var piece := pieces[index]
		var landed: float = grams * areas[index] / total_area
		var stuck: float = landed * adhesion(piece)
		# On a heap of grain, the spice is shared among its kernels.
		var per_kernel: float = stuck / piece.count
		var weight: float = per_kernel * spice.flavour_potency
		piece.flavour = FlavourProfile.mix_by_mass(piece.flavour, piece.mass_g(), spice.flavour, weight)
		piece.traits.mix_in(piece.mass_g(), spice.trait_doses(), weight)
		piece.solids_g += per_kernel
		piece.spices[spice] = piece.spices.get(spice, 0.0) + stuck
		stuck_total += stuck
	return stuck_total

## Stirs `grams` of a spice into a pot's liquid. Each flavour and essence
## dissolves as far as the liquid carries it. Into a pot with no pool, it
## falls on the food instead. Returns the grams that went in.
static func season_pot(pot: CookingPot, spice: Ingredient, grams: float) -> float:
	if not pot.has_pool():
		return season_pieces(pot.pieces, spice, grams) if not pot.pieces.is_empty() else 0.0
	var medium := pot.medium
	var mass: float = pot.medium_mass_g
	for axis in FlavourProfile.AXES:
		var weight: float = grams * spice.flavour_potency * FlavourProfile.solubility(axis, medium.fat_fraction, medium.water_fraction)
		var now: float = pot.medium_flavour.get(axis)
		pot.medium_flavour.set(axis, (now * mass + float(spice.flavour.get(axis)) * weight) / (mass + weight))
	var essences := spice.trait_doses()
	for mystic_trait in essences.traits():
		var solubility: float = clampf(medium.fat_fraction * mystic_trait.fat_solubility + medium.water_fraction * mystic_trait.water_solubility, 0.0, 1.0)
		var weight: float = grams * spice.flavour_potency * solubility
		var now: float = pot.medium_traits.get_dose(mystic_trait)
		pot.medium_traits.set_dose(mystic_trait, (now * mass + essences.get_dose(mystic_trait) * weight) / (mass + weight))
	return grams
