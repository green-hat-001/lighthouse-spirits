class_name FoodPerception
extends RefCounted

## Pure mappings from a FoodPiece's physical state to what the player
## perceives: its texture, its look, and the sound of biting it. These are
## the only way the player learns how well something is cooked - there is
## no score on screen.

## Browning at which a dry crust counts as fully crisp.
const CRISP_BROWNING: float = 0.4
## Oil fraction at which food counts as fully greasy.
const GREASY_OIL_FRACTION: float = 0.2
## Loss of core moisture, relative to raw, at which food is fully leathery.
const LEATHERY_MOISTURE_LOSS: float = 0.5
## Surface wetness, relative to raw, that still reads as glossy.
const WET_GLOSS_WEIGHT: float = 0.4
## Pieces at least this thick bite at the lowest pitch.
const THICK_BITE_MM: float = 30.0
const LOWEST_BITE_PITCH: float = 0.85
const HIGHEST_BITE_PITCH: float = 1.25

static func texture_of(piece: FoodPiece) -> FoodTexture:
	var texture := FoodTexture.new()
	var dryness: float = piece.surface_dryness()
	var cooked: float = clampf(piece.core_doneness, 0.0, 1.0)
	texture.greasiness = clampf(piece.oil_fraction() / GREASY_OIL_FRACTION, 0.0, 1.0)
	texture.crispness = dryness * clampf(piece.surface_browning / CRISP_BROWNING, 0.0, 1.0) \
		* (1.0 - 0.5 * texture.greasiness)
	texture.wetness = 1.0 - dryness
	texture.softness = clampf(cooked * 0.8 + (1.0 - piece.integrity) * 0.4, 0.0, 1.0)
	texture.firmness = piece.integrity * (1.0 - cooked)

	var raw_moisture: float = piece.ingredient.water_fraction
	if raw_moisture > 0.0:
		var moisture_lost: float = 1.0 - piece.core_moisture() / raw_moisture
		texture.chewiness = clampf(moisture_lost / LEATHERY_MOISTURE_LOSS, 0.0, 1.0)
	return texture

static func appearance_of(piece: FoodPiece) -> FoodAppearance:
	var appearance := FoodAppearance.new()
	appearance.browning = piece.surface_browning
	appearance.char = piece.surface_char
	appearance.gloss = clampf(
		piece.oil_fraction() / GREASY_OIL_FRACTION + (1.0 - piece.surface_dryness()) * WET_GLOSS_WEIGHT,
		0.0, 1.0
	)
	appearance.translucency = clampf(piece.core_doneness, 0.0, 1.0)
	appearance.crumble = 1.0 - piece.integrity
	return appearance

## Crisp crusts crackle and raw vegetables crunch. Soft food is quiet
## unless it is soggy with oil or has fallen apart, when it squelches - but
## a tender boiled potato, wet as it is, just bites softly.
static func bite_of(piece: FoodPiece) -> BiteSound:
	var texture := texture_of(piece)
	var sogginess: float = maxf(texture.greasiness * (1.0 - texture.crispness), 1.0 - piece.integrity)
	var raw_weights: Dictionary[BiteSound.Layer, float] = {
		BiteSound.Layer.CRISP: texture.crispness,
		BiteSound.Layer.CRUNCH: texture.firmness * (1.0 - texture.softness),
		BiteSound.Layer.SOFT: texture.softness * (1.0 - texture.crispness) * (1.0 - sogginess),
		BiteSound.Layer.SQUELCH: texture.softness * sogginess,
		BiteSound.Layer.CHEW: texture.chewiness * (1.0 - texture.crispness),
	}
	var total: float = 0.0
	for layer in raw_weights:
		total += raw_weights[layer]

	var sound := BiteSound.new()
	if total <= 0.0:
		sound.weights[BiteSound.Layer.SOFT] = 1.0
	else:
		for layer in raw_weights:
			sound.weights[layer] = raw_weights[layer] / total
	var thinness: float = 1.0 - clampf(piece.min_dimension_mm() / THICK_BITE_MM, 0.0, 1.0)
	sound.pitch = lerpf(LOWEST_BITE_PITCH, HIGHEST_BITE_PITCH, thinness)
	return sound
