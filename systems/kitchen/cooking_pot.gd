class_name CookingPot
extends RefCounted

## A vessel on a burner, with an optional liquid medium and the food in it.
## The vessel and its liquid share one temperature. Each step the burner
## adds heat, the kitchen takes some away, and the food draws heat from the
## medium - so a cold batch visibly drops the oil's temperature, and the
## player has to work the flame to bring it back. A liquid that reaches its
## boiling point stops heating and boils away instead. With no liquid, food
## cooks by contact with the hot, dry bottom of the vessel.
##
## The simulation advances in fixed steps, whatever the frame rate or time
## scale, so the same inputs always give the same food.

const FIXED_STEP_S: float = 0.05

var vessel: CookingVessel
## The burner the pot is on, or null when it is off the heat.
var burner: HeatSource
## 0 off through to 1 full, set directly by the player.
var flame_level: float = 0.0
## The liquid in the pot, or null when the pot is dry.
var medium: Ingredient
var medium_mass_g: float = 0.0
var medium_flavour: FlavourProfile
var temp_c: float
var ambient_temp_c: float
var pieces: Array[FoodPiece] = []
## Running totals, for the player-facing readouts and for tests.
var energy_to_food_j: float = 0.0
var boiled_off_g: float = 0.0

var _accumulator_s: float = 0.0

func _init(p_vessel: CookingVessel, p_ambient_temp_c: float) -> void:
	vessel = p_vessel
	ambient_temp_c = p_ambient_temp_c
	temp_c = p_ambient_temp_c

func set_flame(level: float) -> void:
	flame_level = clampf(level, 0.0, 1.0)

## Pours liquid into the pot at the given temperature, mixing its heat and
## flavour with anything already there. Refused for anything that is not a
## LIQUID, for a different liquid than the one already in the pot, or when
## it would overflow.
func add_medium(liquid: Ingredient, grams: float, liquid_temp_c: float) -> bool:
	if liquid == null or liquid.physical_form != Ingredient.PhysicalForm.LIQUID or grams <= 0.0:
		return false
	if medium != null and medium != liquid:
		return false
	if _contents_volume_ml() + grams / liquid.density_g_per_cm3 > vessel.capacity_ml:
		return false

	var capacity_before: float = heat_capacity_j_per_k()
	var added_capacity: float = grams * liquid.specific_heat_j_per_g_k
	temp_c = (temp_c * capacity_before + liquid_temp_c * added_capacity) / (capacity_before + added_capacity)
	var incoming_flavour: FlavourProfile = liquid.flavour if liquid.flavour else FlavourProfile.new()
	if medium == null:
		medium = liquid
		medium_flavour = incoming_flavour.copy()
	else:
		medium_flavour = FlavourProfile.mix_by_mass(medium_flavour, medium_mass_g, incoming_flavour, grams)
	medium_mass_g += grams
	return true

## Refused when the piece is already in the pot or would overflow it.
func add_piece(piece: FoodPiece) -> bool:
	if piece == null or pieces.has(piece):
		return false
	if _contents_volume_ml() + piece.volume_mm3() / 1000.0 > vessel.capacity_ml:
		return false
	pieces.append(piece)
	return true

func remove_piece(piece: FoodPiece) -> bool:
	var index: int = pieces.find(piece)
	if index < 0:
		return false
	pieces.remove_at(index)
	return true

## The vessel plus its liquid, in J/K.
func heat_capacity_j_per_k() -> float:
	var capacity: float = vessel.mass_g * vessel.specific_heat_j_per_g_k
	if medium:
		capacity += medium_mass_g * medium.specific_heat_j_per_g_k
	return capacity

## Runs every whole fixed step that fits in the time elapsed, carrying the
## remainder to the next call.
func advance(delta_s: float) -> void:
	_accumulator_s += delta_s
	while _accumulator_s >= FIXED_STEP_S:
		_accumulator_s -= FIXED_STEP_S
		_step(FIXED_STEP_S)

func _step(dt: float) -> void:
	var capacity: float = heat_capacity_j_per_k()
	var burner_w: float = burner.power_at(flame_level) if burner else 0.0
	var loss_w: float = vessel.heat_loss_w_per_k * (temp_c - ambient_temp_c)

	var exposure := HeatExposure.new()
	exposure.temp_c = temp_c
	if medium:
		exposure.heat_transfer_w_per_m2_k = medium.medium_heat_transfer_w_per_m2_k
		exposure.fat_fraction = medium.fat_fraction
		exposure.flavour = medium_flavour
		exposure.medium_mass_g = medium_mass_g

	var drawn_j: float = 0.0
	for piece in pieces:
		if medium == null:
			# Only the face resting on the bottom touches the hot metal.
			var contact_share: float = piece.cross_section_mm2(Vector3.AXIS_Y) / piece.surface_area_mm2()
			exposure.heat_transfer_w_per_m2_k = vessel.dry_contact_w_per_m2_k * contact_share
		var exchange := FoodHeating.step(piece, exposure, dt)
		drawn_j += exchange.energy_j
		if medium:
			medium_mass_g -= exchange.fat_absorbed_g
			exposure.medium_mass_g = medium_mass_g
	energy_to_food_j += drawn_j

	temp_c += ((burner_w - loss_w) * dt - drawn_j) / capacity
	_boil_off()

func _boil_off() -> void:
	if medium == null or medium.boiling_point_c <= 0.0 or temp_c <= medium.boiling_point_c:
		if medium and medium_mass_g <= 0.0:
			_empty_medium()
		return
	var excess_j: float = (temp_c - medium.boiling_point_c) * heat_capacity_j_per_k()
	var boiled_g: float = minf(excess_j / medium.latent_heat_j_per_g, medium_mass_g)
	medium_mass_g -= boiled_g
	boiled_off_g += boiled_g
	temp_c = medium.boiling_point_c + (excess_j - boiled_g * medium.latent_heat_j_per_g) / heat_capacity_j_per_k()
	if medium_mass_g <= 0.0:
		_empty_medium()

func _empty_medium() -> void:
	medium = null
	medium_mass_g = 0.0
	medium_flavour = null

func _contents_volume_ml() -> float:
	var volume: float = medium_mass_g / medium.density_g_per_cm3 if medium else 0.0
	for piece in pieces:
		volume += piece.volume_mm3() / 1000.0
	return volume
