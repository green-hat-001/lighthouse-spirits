class_name MysticTrait
extends Resource

## A mystical property something in this world carries: kelp whose bladders
## lift it once cooked, a root that keeps burning inside, a moss that glows.
## A trait is a dose of an essence, carried by food as a concentration
## (TraitDoses), and it acts through one of a fixed set of effects the
## physics understands, once its trigger is met. New mystical properties
## are new instances of this resource, never new code.
##
## Like flavour, an essence dissolves into a cooking medium as far as the
## medium can carry it (fat_solubility, water_solubility): boil bones and
## the broth takes their essence with it. And like a contaminant in a real
## food web, it passes up from what an animal eats into the tissues it
## settles in (carried_by_diet, diet_share, tissues): a bream that grazes
## buoyant kelp has buoyant flesh.

## What the essence does, and what `magnitude` measures for it, per unit of
## concentration at full activation:
##   LIFT       share of the food's weight it lifts. Above 1 it floats in
##              anything and hovers off a board. A spirit that eats it is
##              lightened and rises more surely.
##   GLOW       light given off. A spirit warmed by it is calmed.
##   EMBER      heat released inside the food, in W per gram.
##   FROST      heat drawn into the food, in W per gram.
##   CHAR_WARD  share of burning it holds off, 0-1.
##   BLOOM      how fast its bloom_flavour comes out, per second.
##   SOOTHE     calming a spirit receives per gram eaten.
##   NOURISH    nourishment a spirit receives per gram eaten.
enum Effect { LIFT, GLOW, EMBER, FROST, CHAR_WARD, BLOOM, SOOTHE, NOURISH }

## When the essence wakes, judged from the food's state, with
## trigger_threshold as the point it is fully awake:
##   ALWAYS   always
##   RAW      while uncooked; fades as core doneness reaches the threshold
##   COOKED   once core doneness reaches the threshold
##   BROWNED  once surface browning reaches the threshold
##   HOT      once the food is this hot, in degrees C
##   CHARRED  once surface char reaches the threshold
enum Trigger { ALWAYS, RAW, COOKED, BROWNED, HOT, CHARRED }

## Where in an animal an essence from its diet settles.
enum Tissue { MUSCLE, FAT, SKIN, BONE, ORGAN, EYE, KERATIN, ROE, BLOOD }

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var lore: String = ""
## What the caretaker notices biting food where it is awake.
@export var taste_note: String = ""

@export_group("Effect")
@export var effect: Effect = Effect.LIFT
@export var magnitude: float = 1.0
@export var trigger: Trigger = Trigger.ALWAYS
@export var trigger_threshold: float = 1.0
## Colour of its light (GLOW) or of the tint it gives a liquid.
@export var glow_color: Color = Color(1.0, 0.9, 0.6)
## The flavour it blooms into (BLOOM only).
@export var bloom_flavour: FlavourProfile
## Energy a full concentration holds per gram of food before it is spent
## (EMBER, FROST), in J. 0 never runs out.
@export var fuel_j_per_g: float = 0.0

@export_group("Infusion")
@export_range(0.0, 1.0) var fat_solubility: float = 0.0
@export_range(0.0, 1.0) var water_solubility: float = 0.0

@export_group("Food Web")
@export var carried_by_diet: bool = false
## Share of the concentration in what an animal eats that reaches its
## tissues.
@export_range(0.0, 2.0) var diet_share: float = 0.5
@export var tissues: Array[Tissue] = []

## Every problem with this trait, or an empty array.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("id is empty")
	if magnitude < 0.0:
		problems.append("magnitude cannot be negative")
	if fuel_j_per_g < 0.0:
		problems.append("fuel cannot be negative")
	if effect == Effect.BLOOM and bloom_flavour == null:
		problems.append("a BLOOM trait needs a bloom flavour")
	if effect == Effect.CHAR_WARD and magnitude > 1.0:
		problems.append("char ward is a share, at most 1")
	if carried_by_diet and tissues.is_empty():
		problems.append("a trait carried by diet needs tissues to settle in")
	return problems
