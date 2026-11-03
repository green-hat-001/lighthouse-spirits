class_name FoodHeating
extends RefCounted

## Pure physics of one FoodPiece in a HeatExposure for a short time step.
## Every visible outcome of cooking - cooked through or raw in the middle,
## pale or golden, crisp or soggy, greasy, burnt, fallen apart, golden
## underneath and pale on top - emerges from these rules acting on the
## piece's physical state. There are no recipes.
##
## Per step, for each of the piece's six faces:
##   1. Heat flows into the face's share of the surface shell through each
##      channel it is exposed to (liquid, contact, air), in proportion to
##      its area, and from the shell into the core by conduction (core
##      conductance k A^2 / V, shared out by area, so cooking time grows
##      with thickness squared). A face that has dried to crust conducts
##      less, insulating the core.
##   2. A face above 100 degrees C that still holds water spends the excess
##      heat boiling it off, pinning it at 100 until it dries. A cooler wet
##      face in open air dries by evaporation, which cools it. The core
##      likewise cannot pass 100 while it holds water: the excess boils it.
## Then, for the piece:
##   3. Water migrates from the wetter core back out to each face.
##   4. In a fatty medium, wetted faces soak up fat: some replaces the water
##      that boiled off, and more seeps in when the oil is too cool for
##      steam to push it back. Skin lets less through than cut flesh.
##   5. The core cooks once it passes the ingredient's cook temperature, and
##      keeps overcooking past done. Overcooked food with a wet surface
##      loses integrity.
##   6. A dry, hot face browns (Maillard reactions and caramelisation,
##      driven by sugar, starch and protein), and a browned face far too
##      hot chars. Browning adds aroma and savouriness; char adds
##      bitterness.
##   7. Flavour diffuses between the food and a liquid medium across its
##      wetted faces, faster when hot, as far as the medium dissolves each
##      flavour (fat carries chilli heat and aroma; water carries salt,
##      sweetness, acidity and savouriness). Mystical essences infuse the
##      same way, by their own solubility.
##   8. The piece shrinks as it loses water, by the ingredient's shrinkage.
##   9. Awake essences act (TraitEffects): embers heat the core, frost
##      chills it, blooms draw out flavour; a char ward slows burning.
##  10. Fatty food renders: its fat melts out once hot enough.
##  11. Dry grain drinks water from a watery medium and swells, and cooks
##      only as far as it has drunk.
##
## Integration is explicit, split into substeps short enough for the
## fastest thermal time constant of any face or the core, so no step can
## overshoot.

const WATER_BOILING_POINT_C: float = 100.0
const WATER_LATENT_HEAT_J_PER_G: float = 2257.0
const WATER_SPECIFIC_HEAT_J_PER_G_K: float = 4.18
## Grain drinks twice as fast for every this many degrees hotter.
const HYDRATION_DOUBLING_C: float = 12.0
## Share of its full water a grain must hold before its starch cooks freely.
const HYDRATED_TO_COOK: float = 0.6
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
const BROWNING_RATE_AT_REFERENCE: float = 0.012
const SUGAR_REACTIVITY: float = 1.0
const STARCH_REACTIVITY: float = 0.1
const PROTEIN_REACTIVITY: float = 0.5
const BROWNING_AROMA_GAIN: float = 0.6
const BROWNING_UMAMI_GAIN: float = 0.3

## A dry crust conducts this share of what the moist flesh does: it is
## porous and full of air and oil.
const CRUST_CONDUCTIVITY_SHARE: float = 0.4

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
const OIL_REPLACES_WATER_RATIO: float = 0.08

## Flavour carried across a square metre of surface per second, per unit of
## intensity difference, at 100 degrees C.
const FLAVOUR_TRANSFER_G_PER_M2_S_AT_100C: float = 12.0
const FLAVOUR_TRANSFER_DOUBLING_C: float = 40.0

## Advances the piece by dt seconds of exposure and reports what it took
## from and gave to its surroundings. Mutates the piece, and the
## exposure's flavour.
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

## Share of the flesh's conductivity a face keeps as it dries into crust.
## A crust insulates: it slows heat into the core and lets the outside run
## hotter.
static func crust_factor(piece: FoodPiece, face: int) -> float:
	return lerpf(1.0, CRUST_CONDUCTIVITY_SHARE, piece.face_dryness(face))

## How freely water and flavour pass through a face: 1 for cut flesh, the
## ingredient's skin permeability for skin.
static func face_permeability(piece: FoodPiece, face: int) -> float:
	return lerpf(1.0, piece.ingredient.skin_permeability, piece.face_skin[face])

## How wet one face is for evaporation into air: its free water relative to
## the raw ingredient, through the skin if it is skin.
static func face_wetness(piece: FoodPiece, face: int) -> float:
	return (1.0 - piece.face_dryness(face)) * face_permeability(piece, face)

static func _stable_substep(piece: FoodPiece, exposure: HeatExposure) -> float:
	var specific_heat: float = piece.ingredient.specific_heat_j_per_g_k
	var area_m2: float = piece.surface_area_mm2() * 1e-6
	var conduction: float = core_conductance_w_per_k(piece)
	var worst_h: float = 0.0
	for face in FoodPiece.FACE_COUNT:
		var h: float = exposure.liquid_h(face) + exposure.contact_h(face)
		var air_h: float = exposure.air_h(face)
		if air_h > 0.0:
			h += air_h + WaterVapour.evaporative_w_per_m2_k(air_h, piece.face_temp_c[face], face_wetness(piece, face))
		worst_h = maxf(worst_h, h)
	var shell_tau: float = piece.shell_mass_g() * specific_heat / maxf(worst_h * area_m2 + conduction, 1e-9)
	var core_tau: float = piece.core_mass_g() * specific_heat / maxf(conduction, 1e-9)
	return MAX_SUBSTEP_FRACTION_OF_TAU * minf(shell_tau, core_tau)

static func _integrate(piece: FoodPiece, exposure: HeatExposure, dt: float, exchange: HeatExchange) -> void:
	var ingredient: Ingredient = piece.ingredient
	var specific_heat: float = ingredient.specific_heat_j_per_g_k
	var surface_mm2: float = piece.surface_area_mm2()
	var area_m2: float = surface_mm2 * 1e-6
	var shell_capacity: float = piece.shell_mass_g() * specific_heat
	var core_capacity: float = piece.core_mass_g() * specific_heat
	var conduction: float = core_conductance_w_per_k(piece)

	var steam_barrier: float = 0.0
	if piece.moisture() > STEAM_MIN_MOISTURE:
		steam_barrier = clampf((exposure.temp_c - WATER_BOILING_POINT_C) / STEAM_BARRIER_SPAN_C, 0.0, 1.0)

	var heat_to_core_w: float = 0.0
	var evaporated := PackedFloat64Array()
	evaporated.resize(FoodPiece.FACE_COUNT)
	var total_evaporated_g: float = 0.0
	var seeped_g: float = 0.0
	var replaced_g: float = 0.0
	var wetted_area_m2: float = 0.0
	var outer_temps := PackedFloat64Array()
	outer_temps.resize(FoodPiece.FACE_COUNT)
	var shell_mass: float = piece.shell_mass_g()
	var volume: float = piece.volume_mm3()
	for face in FoodPiece.FACE_COUNT:
		var share: float = volume / piece.size_mm[face >> 1] / surface_mm2
		var face_m2: float = area_m2 * share
		var capacity: float = shell_capacity * share
		var temp: float = piece.face_temp_c[face]
		var liquid_share: float = exposure.liquid_share(face)
		var permeability: float = face_permeability(piece, face)

		var from_liquid_w: float = exposure.liquid_h(face) * face_m2 * (exposure.temp_c - temp)
		var from_contact_w: float = exposure.contact_h(face) * face_m2 * (exposure.contact_temp_c(face) - temp)
		var air_h: float = exposure.air_h(face)
		var from_air_w: float = air_h * face_m2 * (exposure.air_temp_c - temp)
		var to_core_w: float = conduction * share * crust_factor(piece, face) * (temp - piece.core_temp_c)
		exchange.liquid_energy_j += from_liquid_w * dt
		exchange.contact_energy_j += from_contact_w * dt
		exchange.air_energy_j += from_air_w * dt
		heat_to_core_w += to_core_w

		var new_temp: float = temp + (from_liquid_w + from_contact_w + from_air_w - to_core_w) * dt / capacity
		var face_water: float = piece.face_moisture[face] * shell_mass * share
		var lost_g: float = 0.0
		if face_water > 0.0:
			if new_temp > WATER_BOILING_POINT_C:
				lost_g = minf((new_temp - WATER_BOILING_POINT_C) * capacity / WATER_LATENT_HEAT_J_PER_G, face_water)
				replaced_g += lost_g * liquid_share * OIL_REPLACES_WATER_RATIO
				exchange.steam_through_liquid_g += lost_g * liquid_share
			elif air_h > 0.0:
				var rate: float = WaterVapour.evaporation_g_per_s(
					air_h, face_m2, new_temp, face_wetness(piece, face), exposure.air_vapour_kg_m3)
				lost_g = minf(rate * dt, face_water)
			new_temp -= lost_g * WATER_LATENT_HEAT_J_PER_G / capacity
		evaporated[face] = lost_g
		total_evaporated_g += lost_g
		piece.face_temp_c[face] = new_temp
		outer_temps[face] = _outer_temp_c(piece, face, exposure, new_temp,
			(from_liquid_w + from_contact_w + from_air_w) / face_m2)

		seeped_g += OIL_SEEP_G_PER_M2_S * face_m2 * liquid_share * permeability * (1.0 - steam_barrier) * dt
		wetted_area_m2 += face_m2 * liquid_share * permeability

	exchange.energy_j = exchange.liquid_energy_j + exchange.contact_energy_j + exchange.air_energy_j
	piece.core_temp_c += heat_to_core_w * dt / core_capacity
	var core_boiled_g: float = _boil_core(piece, core_capacity, exposure, exchange)
	total_evaporated_g += core_boiled_g

	if total_evaporated_g > core_boiled_g:
		_remove_face_water(piece, evaporated, total_evaporated_g - core_boiled_g)
	exchange.evaporated_g += total_evaporated_g
	_migrate_water(piece, dt)
	_absorb_fat(piece, exposure, (seeped_g + replaced_g) * exposure.uptake_boost, exchange)
	_render_fat(piece, dt, exchange)
	_hydrate(piece, exposure, dt, exchange)
	_cook_core(piece, dt)
	_brown_and_char(piece, exposure, outer_temps, dt)
	_exchange_flavour(piece, exposure, wetted_area_m2, dt)
	TraitEffects.act(piece, dt, core_capacity)
	if total_evaporated_g > 0.0 and ingredient.shrinkage_per_water_lost > 0.0:
		_shrink(piece, total_evaporated_g)

## Temperature of the very outside of a face, where browning happens. The
## shell's temperature is the mean over its depth; heat flowing in has to
## cross half of it to reach that mean, and a dry crust conducts poorly,
## so the outside of a crisping fry runs well above the millimetre under
## it. Never hotter than the hottest thing the face touches.
static func _outer_temp_c(
		piece: FoodPiece, face: int, exposure: HeatExposure, shell_temp_c: float, flux_w_per_m2: float) -> float:
	if flux_w_per_m2 <= 0.0:
		return shell_temp_c
	var conductivity: float = piece.ingredient.thermal_conductivity_w_per_m_k * crust_factor(piece, face)
	var rise: float = flux_w_per_m2 * FoodPiece.SHELL_DEPTH_MM * 0.0005 / conductivity
	var hottest: float = -INF
	if exposure.liquid_h(face) > 0.0:
		hottest = maxf(hottest, exposure.temp_c)
	if exposure.contact_h(face) > 0.0:
		hottest = maxf(hottest, exposure.contact_temp_c(face))
	if exposure.air_h(face) > 0.0:
		hottest = maxf(hottest, exposure.air_temp_c)
	return minf(shell_temp_c + rise, maxf(hottest, shell_temp_c))

## Water held inside food cannot rise past boiling: heat conducted into a
## wet core beyond 100 degrees C turns its water to steam, which escapes
## through the surface, so the inside of a frying piece sits at 100 until
## it dries. Returns the grams boiled.
static func _boil_core(piece: FoodPiece, core_capacity: float, exposure: HeatExposure, exchange: HeatExchange) -> float:
	if piece.core_temp_c <= WATER_BOILING_POINT_C:
		return 0.0
	var core_water: float = maxf(piece.water_g - piece.surface_water_g(), 0.0)
	if core_water <= 0.0:
		return 0.0
	var boiled_g: float = minf((piece.core_temp_c - WATER_BOILING_POINT_C) * core_capacity / WATER_LATENT_HEAT_J_PER_G, core_water)
	piece.core_temp_c -= boiled_g * WATER_LATENT_HEAT_J_PER_G / core_capacity
	var waters := piece.face_waters_g()
	piece.water_g -= boiled_g
	piece.restore_face_waters(waters)
	# The steam leaves through whichever faces it can; what leaves under
	# the liquid bubbles through it.
	var wetted: float = 0.0
	for face in FoodPiece.FACE_COUNT:
		wetted += exposure.liquid_share(face) * piece.face_share(face)
	exchange.steam_through_liquid_g += boiled_g * wetted
	return boiled_g

static func _remove_face_water(piece: FoodPiece, evaporated: PackedFloat64Array, total_g: float) -> void:
	var waters := piece.face_waters_g()
	for face in FoodPiece.FACE_COUNT:
		waters[face] -= evaporated[face]
	piece.water_g -= total_g
	piece.restore_face_waters(waters)

static func _migrate_water(piece: FoodPiece, dt: float) -> void:
	var core_moisture: float = piece.core_moisture()
	var changed := false
	for face in FoodPiece.FACE_COUNT:
		var gradient: float = core_moisture - piece.face_moisture[face]
		if gradient > 0.0:
			piece.face_moisture[face] += WATER_MIGRATION_PER_S * gradient * dt
			changed = true
	if changed:
		piece.clamp_surface_moisture()

static func _absorb_fat(piece: FoodPiece, exposure: HeatExposure, offered_g: float, exchange: HeatExchange) -> void:
	if exposure.fat_fraction <= 0.0 or offered_g <= 0.0:
		return
	# Fat that is melting out of a piece holds other fat out.
	if piece.ingredient.render_temp_c > 0.0 and piece.surface_temp_c > piece.ingredient.render_temp_c:
		return
	var available_g: float = exposure.medium_mass_g * exposure.fat_fraction - exchange.fat_absorbed_g
	var absorbed_g: float = minf(offered_g * exposure.fat_fraction, maxf(available_g, 0.0))
	if absorbed_g <= 0.0:
		return

	# The shell grows by the oil it takes in; its water stays where it is.
	var waters := piece.face_waters_g()
	if exposure.flavour:
		piece.flavour = FlavourProfile.mix_by_mass(piece.flavour, piece.mass_g(), exposure.flavour, absorbed_g)
	if exposure.traits:
		piece.traits.mix_in(piece.mass_g(), exposure.traits, absorbed_g)
	piece.oil_g += absorbed_g
	piece.restore_face_waters(waters)
	exchange.fat_absorbed_g += absorbed_g

## Fat melts out of fatty food once its surface passes the fat's rendering
## temperature, faster the hotter it is and the more fat is left, and the
## piece shrinks by the fat's volume.
static func _render_fat(piece: FoodPiece, dt: float, exchange: HeatExchange) -> void:
	var ingredient: Ingredient = piece.ingredient
	if ingredient.render_temp_c <= 0.0 or ingredient.renders_into == null:
		return
	var above: float = piece.surface_temp_c - ingredient.render_temp_c
	if above <= 0.0:
		return
	var rendered: float = minf(ingredient.render_rate_per_s_per_k * above * piece.renderable_fat_g() * dt, piece.renderable_fat_g())
	if rendered <= 0.0:
		return
	var waters := piece.face_waters_g()
	piece.solids_g -= rendered
	piece.fat_rendered_g += rendered
	piece.restore_face_waters(waters)
	exchange.fat_rendered_g += rendered
	var fat_density: float = maxf(ingredient.renders_into.density_g_per_cm3, 0.5)
	piece.shrink_to_volume(maxf(piece.volume_mm3() - rendered / fat_density * 1000.0, piece.volume_mm3() * 0.3))

## Dry grain drinks in the water it is wetted by, faster the hotter the
## water, until it holds what it can; it swells by the water's volume. The
## water comes at the medium's temperature.
static func _hydrate(piece: FoodPiece, exposure: HeatExposure, dt: float, exchange: HeatExchange) -> void:
	var ingredient: Ingredient = piece.ingredient
	if ingredient.water_uptake_capacity <= 0.0 or exposure.water_fraction <= 0.0:
		return
	var wetted: float = 0.0
	for face in FoodPiece.FACE_COUNT:
		wetted += exposure.liquid_share(face) * piece.face_share(face)
	var room_g: float = ingredient.water_uptake_capacity * piece.solids_g - piece.water_g
	if wetted <= 0.0 or room_g <= 0.0:
		return
	var warmth: float = pow(2.0, (exposure.temp_c - WATER_BOILING_POINT_C) / HYDRATION_DOUBLING_C)
	var available: float = maxf(exposure.medium_mass_g * exposure.water_fraction - exchange.water_absorbed_g, 0.0)
	var drunk_g: float = minf(minf(ingredient.hydration_rate_per_s * room_g * wetted * warmth * dt, room_g), available)
	if drunk_g <= 0.0:
		return
	var capacity_before: float = piece.mass_g() * ingredient.specific_heat_j_per_g_k
	var waters := piece.face_waters_g()
	piece.water_g += drunk_g
	piece.restore_face_waters(waters)
	piece.core_temp_c = (piece.core_temp_c * capacity_before + exposure.temp_c * drunk_g * WATER_SPECIFIC_HEAT_J_PER_G_K) \
		/ (capacity_before + drunk_g * WATER_SPECIFIC_HEAT_J_PER_G_K)
	var volume: float = piece.volume_mm3()
	piece.size_mm *= pow((volume + drunk_g * 1000.0) / volume, 1.0 / 3.0)
	exchange.water_absorbed_g += drunk_g

## For food that cooks only once it has drunk water (dry grain), how far it
## has: its starch can't gelatinise dry.
static func hydration_readiness(piece: FoodPiece) -> float:
	var capacity: float = piece.ingredient.water_uptake_capacity
	if capacity <= 0.0:
		return 1.0
	return clampf(piece.water_g / (capacity * piece.solids_g * HYDRATED_TO_COOK), 0.0, 1.0)

static func _cook_core(piece: FoodPiece, dt: float) -> void:
	var ingredient: Ingredient = piece.ingredient
	var above_cook_temp: float = piece.core_temp_c - ingredient.cook_temp_c
	if above_cook_temp > 0.0:
		var rate: float = above_cook_temp / COOK_REFERENCE_SPAN_C / ingredient.cook_seconds * hydration_readiness(piece)
		piece.core_doneness = minf(piece.core_doneness + rate * dt, MAX_DONENESS)

	var overcooked: float = piece.core_doneness - 1.0
	if overcooked > 0.0:
		var wetness: float = 1.0 - piece.surface_dryness()
		piece.integrity = maxf(piece.integrity - ingredient.overcook_softening_per_s * overcooked * wetness * dt, 0.0)

static func _brown_and_char(piece: FoodPiece, exposure: HeatExposure, outer_temps: PackedFloat64Array, dt: float) -> void:
	var reactivity: float = browning_reactivity(piece.ingredient) * exposure.browning_boost
	var unwarded: float = 1.0 - TraitEffects.char_ward(piece)
	var surface_mm2: float = piece.surface_area_mm2()
	var browned_total: float = 0.0
	var charred_total: float = 0.0
	for face in FoodPiece.FACE_COUNT:
		var dryness: float = piece.face_dryness(face)
		if dryness <= 0.0:
			continue
		var temp: float = outer_temps[face]
		var share: float = piece.face_area_mm2(face) / surface_mm2
		var browning: float = piece.face_browning[face]
		if temp > BROWNING_ONSET_C and browning < 1.0:
			var rate: float = BROWNING_RATE_AT_REFERENCE * reactivity \
				* pow(2.0, (temp - BROWNING_REFERENCE_C) / BROWNING_DOUBLING_C) * dryness
			var browned: float = minf(rate * dt, 1.0 - browning)
			browning += browned
			piece.face_browning[face] = browning
			browned_total += browned * share
		var char_amount: float = piece.face_char[face]
		if temp > CHAR_ONSET_C and char_amount < 1.0:
			var char_rate: float = CHAR_RATE_AT_REFERENCE * pow(2.0, (temp - CHAR_REFERENCE_C) / CHAR_DOUBLING_C) \
				* dryness * browning * piece.ingredient.char_susceptibility * unwarded
			var charred: float = minf(char_rate * dt, 1.0 - char_amount)
			piece.face_char[face] = char_amount + charred
			charred_total += charred * share
	if browned_total > 0.0:
		piece.flavour.aroma = minf(piece.flavour.aroma + browned_total * BROWNING_AROMA_GAIN, 1.0)
		piece.flavour.umami = minf(piece.flavour.umami + browned_total * BROWNING_UMAMI_GAIN, 1.0)
	if charred_total > 0.0:
		piece.flavour.bitter = minf(piece.flavour.bitter + charred_total * CHAR_BITTERNESS_GAIN, 1.0)

static func _exchange_flavour(piece: FoodPiece, exposure: HeatExposure, wetted_area_m2: float, dt: float) -> void:
	if exposure.flavour == null or exposure.medium_mass_g <= 0.0 or wetted_area_m2 <= 0.0:
		return
	var piece_mass: float = piece.mass_g()
	var medium_mass: float = exposure.medium_mass_g
	var conductance: float = FLAVOUR_TRANSFER_G_PER_M2_S_AT_100C * wetted_area_m2 \
		* pow(2.0, (exposure.temp_c - WATER_BOILING_POINT_C) / FLAVOUR_TRANSFER_DOUBLING_C)
	for axis in FlavourProfile.AXES:
		var solubility: float = FlavourProfile.solubility(axis, exposure.fat_fraction, exposure.water_fraction)
		if solubility <= 0.0:
			continue
		var in_piece: float = piece.flavour.get(axis)
		var in_medium: float = exposure.flavour.get(axis)
		var equilibrium: float = (in_piece * piece_mass + in_medium * medium_mass) / (piece_mass + medium_mass)
		# Never carry more than it takes to reach equilibrium in one substep.
		var carried: float = conductance * solubility * (in_piece - in_medium) * dt
		var limit: float = absf(in_piece - equilibrium) * piece_mass
		carried = clampf(carried, -limit, limit)
		piece.flavour.set(axis, in_piece - carried / piece_mass)
		exposure.flavour.set(axis, in_medium + carried / medium_mass)
	if exposure.traits == null or (exposure.traits.is_empty() and piece.traits.is_empty()):
		return
	# Essences infuse the same way, as far as the medium dissolves each.
	var all_traits := piece.traits.traits()
	for mystic_trait in exposure.traits.traits():
		if not all_traits.has(mystic_trait):
			all_traits.append(mystic_trait)
	for mystic_trait in all_traits:
		var solubility: float = clampf(exposure.fat_fraction * mystic_trait.fat_solubility
			+ exposure.water_fraction * mystic_trait.water_solubility, 0.0, 1.0)
		if solubility <= 0.0:
			continue
		var in_piece: float = piece.traits.get_dose(mystic_trait)
		var in_medium: float = exposure.traits.get_dose(mystic_trait)
		var equilibrium: float = (in_piece * piece_mass + in_medium * medium_mass) / (piece_mass + medium_mass)
		var carried: float = conductance * solubility * (in_piece - in_medium) * dt
		var limit: float = absf(in_piece - equilibrium) * piece_mass
		carried = clampf(carried, -limit, limit)
		piece.traits.set_dose(mystic_trait, in_piece - carried / piece_mass)
		exposure.traits.set_dose(mystic_trait, in_medium + carried / medium_mass)

## Water leaving food lets its structure close up: the piece loses volume
## in proportion to the water's own volume, never below what its solids
## and oil take up.
static func _shrink(piece: FoodPiece, evaporated_g: float) -> void:
	var lost_mm3: float = piece.ingredient.shrinkage_per_water_lost * evaporated_g * 1000.0
	var floor_mm3: float = (piece.solids_g + piece.oil_g) * 1000.0 / maxf(piece.ingredient.density_g_per_cm3, 0.1)
	piece.shrink_to_volume(maxf(piece.volume_mm3() - lost_mm3, floor_mm3))
