class_name CookingPot
extends RefCounted

## A vessel on a burner, with an optional liquid medium and the food in it,
## out in the open air. Three thermal masses carry the heat:
##
##   base   the disc of metal over the burner, heated by the flame
##   rim    the rest of the base and the walls, heated by the flame once it
##          spreads wide, and by conduction from the base; it loses heat to
##          the wind by convection and to the sky by radiation
##   medium the oil or water, heated by the metal it touches; its open
##          surface loses heat to the air, and water also evaporates from it
##
## Each piece of food sits where PotLayout puts it - on the floor, on other
## food or floating - and each of its faces is exposed to what it actually
## touches: hot metal (through a film of the liquid) under a piece on the
## floor, the liquid where it is wetted, and the air above the liquid line.
## So food in a shallow pan browns underneath and stays pale on top until
## it is turned, a piece over the burner browns before one by the wall, and
## a cold batch draws heat out of the oil and the metal both.
##
## Bubbles of steam from wet food stir the liquid and lift the food. The
## medium's chemistry (MediumChemistry) wears it as it is used. A liquid
## that reaches its boiling point stops heating and boils away instead.
## With no liquid, food cooks by contact with the hot, dry bottom and in
## the hot air inside the pot.
##
## The simulation advances in fixed steps, whatever the frame rate or time
## scale, so the same inputs always give the same food.

const FIXED_STEP_S: float = 0.05
const STEFAN_BOLTZMANN: float = 5.670e-8
## Heat transfer from the metal into the liquid, relative to the liquid's
## transfer into food: liquid over a hot plate convects hard.
const BASE_COUPLING: float = 3.0
## Further gain while the metal is hotter than the liquid's boiling point
## (nucleate boiling), reached over BOILING_SPAN_C of superheat.
const BOILING_ENHANCEMENT: float = 8.0
const BOILING_SPAN_C: float = 10.0
## Less liquid than this is a film on the metal, not a pool food sits in.
const MIN_POOL_G: float = 5.0
## Share of the flame that spills past the base and licks the walls; the
## rest of what misses the base is lost.
const FLAME_LICK_SHARE: float = 0.3
const LIQUID_EMISSIVITY: float = 0.95
## The air inside the pot is warmed this share of the way from the open air
## to the metal, and kept this share out of the wind.
const INTERIOR_AIR_WARMING: float = 0.35
const INTERIOR_SHELTER: float = 0.7
## The air just above a hot liquid, as a share of the way to it.
const ABOVE_LIQUID_WARMING: float = 0.3
## Liquid-to-food transfer from quiet liquid to a full rolling bubble.
const AGITATION_QUIET: float = 0.8
const AGITATION_BUSY: float = 1.25
## Steam per square metre of liquid surface per second that counts as a
## full, vigorous bubble.
const BUBBLING_REFERENCE_G_PER_M2_S: float = 20.0
## A stroke of the spoon stirs the pot this hard, and the stirring settles
## at this rate per second.
const STIR_AGITATION: float = 0.6
const STIR_DECAY_PER_S: float = 1.5
## Food lying on other food touches it through the liquid less freely.
const STACKED_CONTACT_SHARE: float = 0.5
## Most internal steps the metal and liquid may take per fixed step.
const MAX_THERMAL_SUBSTEPS: int = 40

var vessel: CookingVessel
## The burner the pot is on, or null when it is off the heat.
var burner: HeatSource
## 0 off through to 1 full, set directly by the player.
var flame_level: float = 0.0
var air: KitchenAir
## The liquid in the pot, or null when the pot is dry.
var medium: Ingredient
var medium_mass_g: float = 0.0
var medium_flavour: FlavourProfile
## How worn the medium is, 0 fresh to 1 spent. See MediumChemistry.
var medium_breakdown: float = 0.0
## The liquid's temperature; with no liquid, the temperature of the base.
var temp_c: float
var base_temp_c: float
var rim_temp_c: float
var pieces: Array[FoodPiece] = []
var placements: Array[PotPlacement] = []
## Height of the liquid line above the floor, in mm.
var liquid_level_mm: float = 0.0

## What the player can see and hear, refreshed every step.
## 0 still through to 1 a vigorous bubble or rolling boil.
var bubbling: float = 0.0
## 0 none through to 1 thick smoke off the oil.
var smoke: float = 0.0
## Steam rising from the pot, in g/s.
var steam_g_per_s: float = 0.0

## Running totals, for the player-facing readouts and for tests.
var energy_to_food_j: float = 0.0
var boiled_off_g: float = 0.0
## Ambient air temperature, kept for callers that set up the pot by it.
var ambient_temp_c: float

var _accumulator_s: float = 0.0
var _stirring: float = 0.0

func _init(p_vessel: CookingVessel, p_ambient_temp_c: float, p_air: KitchenAir = null) -> void:
	vessel = p_vessel
	ambient_temp_c = p_ambient_temp_c
	if p_air:
		air = p_air
	else:
		air = KitchenAir.new()
		air.temp_c = p_ambient_temp_c
	temp_c = p_ambient_temp_c
	base_temp_c = p_ambient_temp_c
	rim_temp_c = p_ambient_temp_c

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

	var incoming_flavour: FlavourProfile = liquid.flavour if liquid.flavour else FlavourProfile.new()
	if medium == null:
		medium = liquid
		medium_flavour = incoming_flavour.copy()
		medium_breakdown = 0.0
		# Liquid poured into an empty pot takes its own temperature; the
		# metal heats it from there.
		temp_c = liquid_temp_c
	else:
		var held: float = medium_mass_g * medium.specific_heat_j_per_g_k
		var added: float = grams * liquid.specific_heat_j_per_g_k
		temp_c = (temp_c * held + liquid_temp_c * added) / (held + added)
		medium_flavour = FlavourProfile.mix_by_mass(medium_flavour, medium_mass_g, incoming_flavour, grams)
		medium_breakdown *= medium_mass_g / (medium_mass_g + grams)
	medium_mass_g += grams
	_settle()
	return true

## Pours up to the given grams of liquid out, and returns how much left.
func pour_out(grams: float) -> float:
	if medium == null or grams <= 0.0:
		return 0.0
	var poured: float = minf(grams, medium_mass_g)
	medium_mass_g -= poured
	if medium_mass_g <= 0.0:
		_empty_medium()
	_settle()
	return poured

## Drops a piece in at a point on the pot's floor, in mm from its centre.
## Refused when the piece is already in the pot or would overflow it.
func add_piece(piece: FoodPiece, at_mm: Vector2 = Vector2.ZERO) -> bool:
	if piece == null or pieces.has(piece):
		return false
	if _contents_volume_ml() + piece.volume_mm3() / 1000.0 > vessel.capacity_ml:
		return false
	pieces.append(piece)
	placements.append(PotPlacement.new(piece, at_mm))
	_settle()
	return true

func remove_piece(piece: FoodPiece) -> bool:
	var index: int = pieces.find(piece)
	if index < 0:
		return false
	pieces.remove_at(index)
	placements.remove_at(index)
	_settle()
	return true

func placement_of(piece: FoodPiece) -> PotPlacement:
	var index: int = pieces.find(piece)
	return placements[index] if index >= 0 else null

## Pieces whose footprint lies within reach of a point, nearest first - what
## a slotted spoon pressed there would catch.
func pieces_near(at_mm: Vector2, reach_mm: float) -> Array[FoodPiece]:
	var near: Array[PotPlacement] = []
	for placement in placements:
		if placement.footprint().grow(reach_mm).has_point(at_mm):
			near.append(placement)
	near.sort_custom(func(a: PotPlacement, b: PotPlacement) -> bool:
		return a.centre_mm.distance_squared_to(at_mm) < b.centre_mm.distance_squared_to(at_mm))
	var found: Array[FoodPiece] = []
	for placement in near:
		found.append(placement.piece)
	return found

## Turns a piece over where it lies (a quarter roll, as on the board), and
## returns the axis it rolled about, or -1 if it isn't in the pot.
func turn(piece: FoodPiece) -> int:
	if not pieces.has(piece):
		return -1
	var axis: int = piece.roll()
	_settle()
	return axis

## A stroke of the spoon through the pot from one point to another, in mm:
## the pieces it passes through are carried along, and the liquid is
## stirred.
func stir(from_mm: Vector2, to_mm: Vector2, reach_mm: float) -> int:
	var stroke := to_mm - from_mm
	var moved: int = 0
	for placement in placements:
		var nearest := Geometry2D.get_closest_point_to_segment(placement.centre_mm, from_mm, to_mm)
		if nearest.distance_to(placement.centre_mm) <= reach_mm:
			placement.centre_mm += stroke
			moved += 1
	_stirring = minf(_stirring + STIR_AGITATION * clampf(stroke.length() / 50.0, 0.0, 1.0), 1.0)
	_settle()
	return moved

## The metal plus its liquid, in J/K.
func heat_capacity_j_per_k() -> float:
	return vessel.mass_g * vessel.specific_heat_j_per_g_k + _medium_capacity()

## Heat held by the metal and the liquid above 0 degrees C, in J - what the
## burner puts in and the food and the air take out.
func thermal_energy_j() -> float:
	var metal: float = vessel.mass_g * vessel.specific_heat_j_per_g_k
	var base_share: float = _base_disc_share()
	return metal * base_share * base_temp_c + metal * (1.0 - base_share) * rim_temp_c \
		+ _medium_capacity() * (temp_c if medium else 0.0)

func has_pool() -> bool:
	return medium != null and medium_mass_g >= MIN_POOL_G

## Runs every whole fixed step that fits in the time elapsed, carrying the
## remainder to the next call.
func advance(delta_s: float) -> void:
	_accumulator_s += delta_s
	while _accumulator_s >= FIXED_STEP_S:
		_accumulator_s -= FIXED_STEP_S
		_step(FIXED_STEP_S)

func _step(dt: float) -> void:
	var metal_capacity: float = vessel.mass_g * vessel.specific_heat_j_per_g_k
	var base_capacity: float = metal_capacity * _base_disc_share()
	var rim_capacity: float = metal_capacity - base_capacity
	var pool: bool = has_pool()

	# Food first, against the temperatures at the start of the step.
	var drawn_from_liquid_j: float = 0.0
	var drawn_from_base_j: float = 0.0
	var drawn_from_rim_j: float = 0.0
	var steam_through_liquid_g: float = 0.0
	var steam_total_g: float = 0.0
	var agitation: float = lerpf(AGITATION_QUIET, AGITATION_BUSY, maxf(bubbling, _stirring))
	for placement in placements:
		var exposure := _exposure_for(placement, pool, agitation)
		var exchange := FoodHeating.step(placement.piece, exposure, dt)
		drawn_from_liquid_j += exchange.liquid_energy_j
		drawn_from_base_j += exchange.contact_energy_j * placement.over_burner
		drawn_from_rim_j += exchange.contact_energy_j * (1.0 - placement.over_burner)
		steam_through_liquid_g += exchange.steam_through_liquid_g
		steam_total_g += exchange.evaporated_g
		placement.steam_g_per_s = exchange.steam_through_liquid_g / dt
		if medium:
			medium_mass_g = maxf(medium_mass_g - exchange.fat_absorbed_g, 0.0)
	energy_to_food_j += drawn_from_liquid_j + drawn_from_base_j + drawn_from_rim_j

	# Then the metal and the liquid, in as many internal steps as their own
	# time constants need.
	var flame_w: float = 0.0
	var flame_to_base: float = 0.0
	var flame_to_rim: float = 0.0
	if burner and flame_level > 0.0:
		flame_w = burner.power_at(flame_level) * air.flame_efficiency()
		var flame_radius: float = burner.flame_radius_mm(flame_level)
		var base_radius: float = _base_disc_radius_mm()
		var pot_radius: float = vessel.interior_radius_mm()
		var flame_area: float = flame_radius * flame_radius
		flame_to_base = minf(base_radius * base_radius / flame_area, 1.0)
		var on_rim: float = maxf(minf(flame_radius, pot_radius) ** 2 - base_radius * base_radius, 0.0) / flame_area
		var spilled: float = maxf(1.0 - flame_to_base - on_rim, 0.0)
		flame_to_rim = on_rim + spilled * FLAME_LICK_SHARE

	var medium_capacity: float = _medium_capacity()
	var lateral: float = _lateral_conductance_w_per_k()
	var base_to_liquid: float = 0.0
	var rim_to_liquid: float = 0.0
	if medium and medium_capacity > 0.0:
		var areas := _wetted_metal_areas_m2()
		base_to_liquid = areas.x
		rim_to_liquid = areas.y
	var steps: int = _thermal_substeps(dt, base_capacity, rim_capacity, medium_capacity, lateral, base_to_liquid, rim_to_liquid)
	var sub_dt: float = dt / steps
	var food_from_base_w: float = drawn_from_base_j / dt
	var food_from_rim_w: float = drawn_from_rim_j / dt
	var food_from_liquid_w: float = drawn_from_liquid_j / dt
	var evaporated_surface_g: float = 0.0
	for index in steps:
		var h_base: float = _metal_to_liquid_h(base_temp_c)
		var h_rim: float = _metal_to_liquid_h(rim_temp_c)
		var into_liquid_from_base: float = h_base * base_to_liquid * (base_temp_c - temp_c) if medium_capacity > 0.0 else 0.0
		var into_liquid_from_rim: float = h_rim * rim_to_liquid * (rim_temp_c - temp_c) if medium_capacity > 0.0 else 0.0
		var across: float = lateral * (base_temp_c - rim_temp_c)
		var rim_loss: float = _rim_loss_w(rim_temp_c)

		base_temp_c += (flame_w * flame_to_base - across - into_liquid_from_base - food_from_base_w) * sub_dt / base_capacity
		rim_temp_c += (flame_w * flame_to_rim + across - into_liquid_from_rim - rim_loss - food_from_rim_w) * sub_dt / rim_capacity
		if medium and medium_capacity > 0.0:
			var surface := _liquid_surface_loss(temp_c, sub_dt)
			evaporated_surface_g += surface.y
			temp_c += (into_liquid_from_base + into_liquid_from_rim - surface.x - food_from_liquid_w) * sub_dt / medium_capacity
			medium_capacity = _medium_capacity()
	if medium == null:
		temp_c = base_temp_c

	if evaporated_surface_g > 0.0 and medium:
		medium_mass_g = maxf(medium_mass_g - evaporated_surface_g, 0.0)
		boiled_off_g += evaporated_surface_g
	var boiled_g: float = _boil_off()

	# Chemistry, and what the player sees.
	if medium:
		var gained: float = MediumChemistry.breakdown_gain(
			medium, medium_breakdown, temp_c, medium_mass_g, steam_through_liquid_g, dt)
		medium_breakdown += gained
		MediumChemistry.sour_the_flavour(medium_flavour, gained)
		smoke = MediumChemistry.smoke_level(medium, medium_breakdown, temp_c)
	else:
		smoke = 0.0
	var floor_m2: float = vessel.floor_area_mm2() * 1e-6
	steam_g_per_s = (steam_total_g + boiled_g + evaporated_surface_g) / dt
	bubbling = clampf((steam_through_liquid_g + boiled_g) / dt / floor_m2 / BUBBLING_REFERENCE_G_PER_M2_S, 0.0, 1.0) \
		if pool else 0.0
	_stirring = maxf(_stirring - STIR_DECAY_PER_S * dt, 0.0)

	if medium and medium_mass_g <= 0.0:
		_empty_medium()
	_settle()

## How one piece's faces are exposed where it lies.
func _exposure_for(placement: PotPlacement, pool: bool, agitation: float) -> HeatExposure:
	var piece := placement.piece
	var exposure := HeatExposure.new()
	exposure.use_per_face()
	exposure.air_vapour_kg_m3 = air.vapour_density_kg_m3()
	var contact_temp: float = lerpf(rim_temp_c, base_temp_c, placement.over_burner)
	var interior_air_h: float = air.convective_w_per_m2_k(INTERIOR_SHELTER)

	if not pool:
		# A dry pot, or one with only a film of liquid: the bottom sits on
		# the metal, everything else is in the warm air inside the pot.
		var metal_mean: float = lerpf(rim_temp_c, base_temp_c, _base_disc_share())
		exposure.air_temp_c = air.temp_c + INTERIOR_AIR_WARMING * (metal_mean - air.temp_c)
		exposure.temp_c = exposure.air_temp_c
		var film: bool = medium != null
		var contact_h: float = vessel.wet_contact_w_per_m2_k if film else vessel.dry_contact_w_per_m2_k
		if film:
			exposure.fat_fraction = medium.fat_fraction
			exposure.water_fraction = medium.water_fraction
			exposure.flavour = medium_flavour
			exposure.medium_mass_g = medium_mass_g
			exposure.temp_c = temp_c
		for face in FoodPiece.FACE_COUNT:
			if face == FoodPiece.BOTTOM and placement.bottom_mm <= 0.0:
				exposure.set_face(face, 1.0 if film else 0.0, 0.0, contact_h, contact_temp, 0.0)
			else:
				exposure.set_face(face, 0.0, 0.0, 0.0, 0.0, interior_air_h)
		return exposure

	exposure.temp_c = temp_c
	exposure.fat_fraction = medium.fat_fraction
	exposure.water_fraction = medium.water_fraction
	exposure.flavour = medium_flavour
	exposure.medium_mass_g = medium_mass_g
	exposure.browning_boost = MediumChemistry.browning_boost(medium_breakdown)
	exposure.uptake_boost = MediumChemistry.uptake_boost(medium_breakdown)
	exposure.air_temp_c = air.temp_c + ABOVE_LIQUID_WARMING * (temp_c - air.temp_c)
	var liquid_h: float = medium.medium_heat_transfer_w_per_m2_k * agitation
	var immersed: float = placement.immersion
	var bottom_wet: bool = immersed > 0.0
	for face in FoodPiece.FACE_COUNT:
		if face == FoodPiece.BOTTOM:
			match placement.resting:
				PotPlacement.Resting.FLOOR:
					exposure.set_face(face, 1.0, 0.0, vessel.wet_contact_w_per_m2_k, contact_temp, 0.0)
				PotPlacement.Resting.ON_FOOD:
					if bottom_wet:
						exposure.set_face(face, STACKED_CONTACT_SHARE, liquid_h * STACKED_CONTACT_SHARE, 0.0, 0.0, 0.0)
					else:
						exposure.set_face(face, 0.0, 0.0, 0.0, 0.0, interior_air_h)
				_:
					exposure.set_face(face, 1.0, liquid_h, 0.0, 0.0, 0.0)
		elif face == FoodPiece.TOP:
			if immersed >= 1.0:
				exposure.set_face(face, 1.0, liquid_h, 0.0, 0.0, 0.0)
			else:
				exposure.set_face(face, 0.0, 0.0, 0.0, 0.0, interior_air_h)
		else:
			exposure.set_face(face, immersed, liquid_h * immersed, 0.0, 0.0, interior_air_h * (1.0 - immersed))
	return exposure

## Places the food for the current contents.
func _settle() -> void:
	var volume_mm3: float = 0.0
	var density: float = 1.0
	if has_pool():
		volume_mm3 = medium_mass_g / medium.density_g_per_cm3 * 1000.0
		density = medium.density_g_per_cm3
	var burner_radius: float = _base_disc_radius_mm()
	liquid_level_mm = PotLayout.settle(placements, vessel.interior_radius_mm(), burner_radius, volume_mm3, density,
		maxf(bubbling, _stirring) if has_pool() else _stirring)

## Radius of the base disc over the burner, in mm.
func _base_disc_radius_mm() -> float:
	var radius: float = burner.burner_radius_mm if burner else vessel.interior_radius_mm() * 0.4
	return minf(radius, vessel.interior_radius_mm() * 0.9)

## The base disc's share of the vessel's metal.
func _base_disc_share() -> float:
	var ratio: float = _base_disc_radius_mm() / vessel.interior_radius_mm()
	return vessel.base_mass_share * ratio * ratio

## Conduction from the base disc out through the steel to the rim, in W/K:
## radial conduction through an annulus, k t 2 pi / ln(r_out / r_in).
func _lateral_conductance_w_per_k() -> float:
	var thickness_m: float = vessel.base_thickness_mm * 0.001
	return vessel.conductivity_w_per_m_k * thickness_m * TAU / log(vessel.interior_radius_mm() / _base_disc_radius_mm())

## Metal area wetted by the liquid, in m^2, as (base disc, rim). Food lying
## on the floor covers the metal under it.
func _wetted_metal_areas_m2() -> Vector2:
	var radius: float = vessel.interior_radius_mm()
	var disc_radius: float = _base_disc_radius_mm()
	var disc_mm2: float = PI * disc_radius * disc_radius
	var ring_mm2: float = vessel.floor_area_mm2() - disc_mm2
	var covered_disc: float = 0.0
	var covered_ring: float = 0.0
	for placement in placements:
		if placement.resting == PotPlacement.Resting.FLOOR:
			var footprint_mm2: float = placement.piece.cross_section_mm2(Vector3.AXIS_Y)
			covered_disc += footprint_mm2 * placement.over_burner
			covered_ring += footprint_mm2 * (1.0 - placement.over_burner)
	var cover: float = 1.0
	if medium_mass_g < MIN_POOL_G:
		cover = medium_mass_g / MIN_POOL_G
	var wall_mm2: float = TAU * radius * minf(liquid_level_mm, vessel.interior_height_mm)
	return Vector2(
		maxf(disc_mm2 - covered_disc, disc_mm2 * 0.1) * cover,
		(maxf(ring_mm2 - covered_ring, ring_mm2 * 0.1) + wall_mm2) * cover
	) * 1e-6

func _metal_to_liquid_h(metal_temp_c: float) -> float:
	if medium == null:
		return 0.0
	var h: float = medium.medium_heat_transfer_w_per_m2_k * BASE_COUPLING
	if medium.boiling_point_c > 0.0 and metal_temp_c > medium.boiling_point_c:
		h *= 1.0 + BOILING_ENHANCEMENT * clampf((metal_temp_c - medium.boiling_point_c) / BOILING_SPAN_C, 0.0, 1.0)
	return h

## Heat the walls lose to the open air, in W: convection in the wind and
## radiation.
func _rim_loss_w(metal_temp_c: float) -> float:
	var outside_m2: float = (TAU * (vessel.interior_radius_mm() + vessel.wall_thickness_mm) * vessel.interior_height_mm) * 1e-6
	var convection: float = air.convective_w_per_m2_k() * outside_m2 * (metal_temp_c - air.temp_c)
	return convection + _radiation_w(vessel.emissivity, outside_m2, metal_temp_c, air.temp_c)

## Heat (W) and water (g over dt) the liquid's open surface loses, as
## Vector2(heat, water).
func _liquid_surface_loss(liquid_temp_c: float, dt: float) -> Vector2:
	var open_mm2: float = vessel.floor_area_mm2()
	for placement in placements:
		if placement.resting == PotPlacement.Resting.FLOATING:
			open_mm2 -= placement.piece.cross_section_mm2(Vector3.AXIS_Y)
	var open_m2: float = maxf(open_mm2, vessel.floor_area_mm2() * 0.1) * 1e-6
	var h: float = air.convective_w_per_m2_k(0.5)
	var heat_w: float = h * open_m2 * (liquid_temp_c - air.temp_c) \
		+ _radiation_w(LIQUID_EMISSIVITY, open_m2, liquid_temp_c, air.temp_c)
	var water_g: float = 0.0
	if medium.water_fraction > 0.0 and (medium.boiling_point_c <= 0.0 or liquid_temp_c < medium.boiling_point_c):
		water_g = minf(WaterVapour.evaporation_g_per_s(h, open_m2, liquid_temp_c, medium.water_fraction, air.vapour_density_kg_m3()) * dt, medium_mass_g)
		heat_w += water_g * medium.latent_heat_j_per_g / dt
	return Vector2(heat_w, water_g)

## How fast the walls' losses grow per degree, in W/K, for step sizing.
func _rim_loss_conductance_w_per_k() -> float:
	var outside_m2: float = (TAU * (vessel.interior_radius_mm() + vessel.wall_thickness_mm) * vessel.interior_height_mm) * 1e-6
	var kelvin: float = rim_temp_c + 273.15
	return (air.convective_w_per_m2_k() + 4.0 * vessel.emissivity * STEFAN_BOLTZMANN * kelvin * kelvin * kelvin) * outside_m2

static func _radiation_w(emissivity: float, area_m2: float, temp_c: float, surroundings_c: float) -> float:
	var hot: float = temp_c + 273.15
	var cold: float = surroundings_c + 273.15
	return emissivity * STEFAN_BOLTZMANN * area_m2 * (hot * hot * hot * hot - cold * cold * cold * cold)

func _thermal_substeps(
		dt: float, base_capacity: float, rim_capacity: float, medium_capacity: float,
		lateral: float, base_wet_m2: float, rim_wet_m2: float) -> int:
	var h_base: float = _metal_to_liquid_h(base_temp_c)
	var h_rim: float = _metal_to_liquid_h(rim_temp_c)
	var tau: float = base_capacity / maxf(lateral + h_base * base_wet_m2, 1e-6)
	tau = minf(tau, rim_capacity / maxf(lateral + h_rim * rim_wet_m2 + _rim_loss_conductance_w_per_k(), 1e-6))
	if medium_capacity > 0.0:
		tau = minf(tau, medium_capacity / maxf(h_base * base_wet_m2 + h_rim * rim_wet_m2, 1e-6))
	return clampi(ceili(dt / (0.3 * tau)), 1, MAX_THERMAL_SUBSTEPS)

func _medium_capacity() -> float:
	return medium_mass_g * medium.specific_heat_j_per_g_k if medium else 0.0

## Boils off whatever heat the liquid holds past its boiling point, and
## returns the grams boiled.
func _boil_off() -> float:
	if medium == null or medium.boiling_point_c <= 0.0 or temp_c <= medium.boiling_point_c:
		return 0.0
	var capacity: float = _medium_capacity()
	var excess_j: float = (temp_c - medium.boiling_point_c) * capacity
	var boiled_g: float = minf(excess_j / medium.latent_heat_j_per_g, medium_mass_g)
	medium_mass_g -= boiled_g
	boiled_off_g += boiled_g
	temp_c = medium.boiling_point_c
	if medium_mass_g > 0.0:
		temp_c += (excess_j - boiled_g * medium.latent_heat_j_per_g) / _medium_capacity()
	return boiled_g

func _empty_medium() -> void:
	medium = null
	medium_mass_g = 0.0
	medium_flavour = null
	medium_breakdown = 0.0
	temp_c = base_temp_c

func _contents_volume_ml() -> float:
	var volume: float = medium_mass_g / medium.density_g_per_cm3 if medium else 0.0
	for piece in pieces:
		volume += piece.volume_mm3() / 1000.0
	return volume
