class_name TasteNote
extends RefCounted

## What the caretaker notices on biting a piece of food, in plain words:
## how it feels, how it tastes, how hot it is. Read entirely from the
## piece's physical state through FoodPerception. It describes, it never
## scores - the player decides what that means for the dish.

const SCALDING_C: float = 70.0
const HOT_C: float = 50.0
const WARM_C: float = 32.0
## A texture or taste below this barely registers.
const NOTICEABLE: float = 0.3
const STRONG: float = 0.6
## Aroma reads at lower intensities: browning builds it slowly, and even a
## little toastiness is the first thing the nose finds.
const AROMA_NOTICEABLE: float = 0.2
const AROMA_STRONG: float = 0.4

static func describe(piece: FoodPiece) -> String:
	var parts: PackedStringArray = []
	var feel := _feel(piece)
	if feel != "":
		parts.append(feel)
	var taste := _taste(piece)
	if taste != "":
		parts.append(taste)
	parts.append(_warmth(piece))
	return " ".join(parts)

static func _feel(piece: FoodPiece) -> String:
	var texture := FoodPerception.texture_of(piece)
	var outside: String
	if piece.surface_char > 0.25:
		outside = "Burnt and brittle outside"
	elif texture.crispness >= STRONG:
		outside = "Shatteringly crisp outside"
	elif texture.crispness >= NOTICEABLE:
		outside = "Crisp outside"
	elif texture.greasiness >= STRONG:
		outside = "Soft and oily outside"
	elif texture.wetness >= STRONG:
		outside = "Wet outside"
	else:
		outside = "Soft outside"

	var inside: String
	if piece.integrity < 0.4:
		inside = "falling apart to mush"
	elif texture.chewiness >= STRONG:
		inside = "dry and leathery inside"
	elif piece.core_doneness < 0.4:
		inside = "raw and crunchy inside"
	elif piece.core_doneness < piece.ingredient.ideal_doneness_min:
		inside = "still firm in the middle"
	elif piece.core_doneness <= piece.ingredient.ideal_doneness_max:
		inside = "fluffy and tender inside" if piece.ingredient.starch_fraction > 0.1 else "tender inside"
	else:
		inside = "very soft inside"
	return "%s, %s." % [outside, inside]

## Browning this deep tastes toasted, whatever else the food tastes of.
const TOASTED_BROWNING: float = 0.25
const DEEPLY_TOASTED_BROWNING: float = 0.6

static func _taste(piece: FoodPiece) -> String:
	var flavour := piece.flavour
	var notes: PackedStringArray = []
	if piece.surface_char < 0.25:
		if piece.surface_browning >= DEEPLY_TOASTED_BROWNING:
			notes.append("deeply toasted")
		elif piece.surface_browning >= TOASTED_BROWNING:
			notes.append("toasty")
	if flavour.bitter >= NOTICEABLE:
		notes.append("bitter" if flavour.bitter >= STRONG else "a little bitter")
	if flavour.heat >= NOTICEABLE:
		notes.append("fiery" if flavour.heat >= STRONG else "warm with chilli")
	if flavour.aroma >= AROMA_STRONG:
		notes.append("toasty and fragrant")
	elif flavour.aroma >= AROMA_NOTICEABLE:
		notes.append("nutty")
	if flavour.umami >= NOTICEABLE:
		notes.append("savoury")
	if flavour.salty >= NOTICEABLE:
		notes.append("salty")
	if flavour.sweet >= NOTICEABLE:
		notes.append("sweet")
	if flavour.sour >= NOTICEABLE:
		notes.append("sharp")
	if notes.is_empty():
		return "Plain."
	var sentence := ", ".join(notes)
	return sentence.substr(0, 1).to_upper() + sentence.substr(1) + "."

static func _warmth(piece: FoodPiece) -> String:
	var temp: float = maxf(piece.core_temp_c, piece.surface_temp_c)
	if temp >= SCALDING_C:
		return "Scalding hot."
	if temp >= HOT_C:
		return "Hot."
	if temp >= WARM_C:
		return "Warm."
	return "Cold."
