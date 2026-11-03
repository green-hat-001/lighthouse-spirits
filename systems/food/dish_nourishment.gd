class_name DishNourishment
extends RefCounted

## Turns a Dish into the FeedingResult a spirit receives. Nothing here knows
## a recipe. Mystical essences awake in the food add their own effects:
## soothing ones calm, nourishing ones feed, glowing ones comfort, and food
## that lifts lightens the spirit and carries it more surely to the moon. Nourishment comes from the food's real energy content, calming
## from how it tastes and how warm it is, and every piece is judged against
## its own ingredient's ideal doneness, never against a named dish. Badly
## made food still feeds - it only carries the spirit less surely towards
## the moon.
##
## Affinity matching against a particular spirit is not done here; the
## serving station applies it.

const KCAL_PER_G_STARCH: float = 4.0
const KCAL_PER_G_SUGAR: float = 4.0
const KCAL_PER_G_PROTEIN: float = 4.0
const KCAL_PER_G_FAT: float = 9.0

## Spirit hunger relieved per kilocalorie. A whole potato's worth of good
## fries (about 300 kcal) all but stills a basic spirit's hunger.
const NOURISHMENT_PER_KCAL: float = 0.2
const CALMING_PER_GRAM: float = 0.35
const BUOYANCY_PER_DISH: float = 0.15
## Spirit weight lifted per gram of food lifted by its essences, and how
## much lifting food adds to how surely the spirit reaches the moon.
const LIFT_BUOYANCY_PER_GRAM: float = 0.004
const LIFT_ASCENSION: float = 0.25
## A piece lifting more than this many times its weight counts as this.
const MAX_LIFT_COUNTED: float = 2.0
## Calming per gram per unit of glow: a spirit is soothed by light it eats.
const GLOW_CALMING_PER_GRAM: float = 0.2

## Quality of completely raw food, rising to 1 at the ideal doneness.
const RAW_QUALITY: float = 0.3
## Quality of food overcooked to the limit.
const OVERCOOKED_QUALITY: float = 0.5
## How much of a piece's quality full char takes away.
const CHAR_PENALTY: float = 0.8
## Quality kept by a piece that has entirely fallen apart.
const CRUMBLED_QUALITY: float = 0.7
## Greasiness beyond this starts to cost quality.
const GREASE_TOLERANCE: float = 0.6
## Nothing served is ever worthless.
const QUALITY_FLOOR: float = 0.15

## Serving temperatures, in degrees C, between which warmth rises from none
## to full.
const COLD_SERVING_C: float = 20.0
const HOT_SERVING_C: float = 60.0
const COLD_CALMING: float = 0.8
const HOT_CALMING: float = 1.2

static func feeding_result_of(dish: Dish) -> FeedingResult:
	var result := FeedingResult.new()
	result.ascension_strength = 0.0
	if dish.is_empty():
		return result

	var weighted_quality: float = 0.0
	var piece_mass: float = 0.0
	var lifted_mass: float = 0.0
	for piece in dish.pieces:
		var quality: float = piece_quality(piece)
		# Only what can be eaten feeds: bones and horn on a plate are there
		# for what they gave the food, not to be eaten.
		var mass: float = piece.mass_g() * piece.ingredient.edible_share
		if mass <= 0.0:
			continue
		result.nourishment += piece_kcal(piece) * piece.ingredient.edible_share * quality * NOURISHMENT_PER_KCAL
		result.calming += mass * pleasantness(piece.flavour) * warmth_factor(piece) * quality * CALMING_PER_GRAM
		result.nourishment += mass * TraitEffects.strength(piece, MysticTrait.Effect.NOURISH)
		result.calming += mass * (TraitEffects.strength(piece, MysticTrait.Effect.SOOTHE)
			+ TraitEffects.strength(piece, MysticTrait.Effect.GLOW) * GLOW_CALMING_PER_GRAM)
		lifted_mass += mass * minf(TraitEffects.lift_share(piece), MAX_LIFT_COUNTED)
		weighted_quality += quality * mass
		piece_mass += mass
	for portion in dish.liquids:
		var edible: float = portion.grams * portion.ingredient.edible_share
		result.nourishment += liquid_kcal(portion) * portion.ingredient.edible_share * NOURISHMENT_PER_KCAL
		result.calming += edible * pleasantness(portion.flavour) * CALMING_PER_GRAM
		result.nourishment += edible * TraitEffects.liquid_strength(portion.traits, MysticTrait.Effect.NOURISH, portion.temp_c)
		result.calming += edible * (TraitEffects.liquid_strength(portion.traits, MysticTrait.Effect.SOOTHE, portion.temp_c)
			+ TraitEffects.liquid_strength(portion.traits, MysticTrait.Effect.GLOW, portion.temp_c) * GLOW_CALMING_PER_GRAM)
		lifted_mass += edible * minf(TraitEffects.liquid_strength(portion.traits, MysticTrait.Effect.LIFT, portion.temp_c), MAX_LIFT_COUNTED)

	var quality_mean: float = weighted_quality / piece_mass if piece_mass > 0.0 else QUALITY_FLOOR
	# Food that lifts lightens the spirit, and carries it more surely up.
	var lift_mean: float = lifted_mass / maxf(piece_mass, 1.0)
	result.ascension_strength = clampf(quality_mean + lift_mean * LIFT_ASCENSION, 0.0, 1.0)
	result.buoyancy_delta = quality_mean * BUOYANCY_PER_DISH + lifted_mass * LIFT_BUOYANCY_PER_GRAM
	return result

## 0-1: how well this piece was made for what it is.
static func piece_quality(piece: FoodPiece) -> float:
	var ingredient: Ingredient = piece.ingredient
	var doneness: float = piece.core_doneness
	var doneness_quality: float = 1.0
	if doneness < ingredient.ideal_doneness_min:
		doneness_quality = lerpf(RAW_QUALITY, 1.0, doneness / ingredient.ideal_doneness_min)
	elif doneness > ingredient.ideal_doneness_max:
		var overcooked: float = (doneness - ingredient.ideal_doneness_max) \
			/ maxf(FoodHeating.MAX_DONENESS - ingredient.ideal_doneness_max, 0.001)
		doneness_quality = lerpf(1.0, OVERCOOKED_QUALITY, clampf(overcooked, 0.0, 1.0))

	var texture := FoodPerception.texture_of(piece)
	var quality: float = doneness_quality \
		* (1.0 - piece.surface_char * CHAR_PENALTY) \
		* lerpf(CRUMBLED_QUALITY, 1.0, piece.integrity) \
		* (1.0 - maxf(texture.greasiness - GREASE_TOLERANCE, 0.0))
	return maxf(quality, QUALITY_FLOOR)

## Energy in the piece. Nutrients are fixed by the raw ingredient's
## composition; cooking boils off water but not food, and adds fat.
static func piece_kcal(piece: FoodPiece) -> float:
	var ingredient: Ingredient = piece.ingredient
	var raw_mass: float = piece.solids_g / maxf(1.0 - ingredient.water_fraction, 0.001)
	return raw_mass * _kcal_per_raw_gram(ingredient) + piece.oil_g * KCAL_PER_G_FAT

static func liquid_kcal(portion: LiquidPortion) -> float:
	return portion.grams * _kcal_per_raw_gram(portion.ingredient)

## How comforting a flavour is, 0 and up. Aroma, savouriness and a little
## sweetness, salt and chilli warmth are welcome; bitterness and too much
## chilli are not. Plain food still comforts a little.
static func pleasantness(flavour: FlavourProfile) -> float:
	var comfort: float = 0.2 \
		+ flavour.aroma * 0.8 + flavour.umami * 0.8 + flavour.sweet * 0.5 + flavour.salty * 0.4 \
		+ minf(flavour.heat, 0.3) - maxf(flavour.heat - 0.6, 0.0) \
		- flavour.bitter * 1.5
	return maxf(comfort, 0.0)

## Hot food comforts more than food left to go cold.
static func warmth_factor(piece: FoodPiece) -> float:
	var warmth: float = clampf((piece.core_temp_c - COLD_SERVING_C) / (HOT_SERVING_C - COLD_SERVING_C), 0.0, 1.0)
	return lerpf(COLD_CALMING, HOT_CALMING, warmth)

static func _kcal_per_raw_gram(ingredient: Ingredient) -> float:
	return ingredient.starch_fraction * KCAL_PER_G_STARCH + ingredient.sugar_fraction * KCAL_PER_G_SUGAR \
		+ ingredient.protein_fraction * KCAL_PER_G_PROTEIN + ingredient.fat_fraction * KCAL_PER_G_FAT
