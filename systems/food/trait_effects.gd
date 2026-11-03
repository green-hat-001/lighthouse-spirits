class_name TraitEffects
extends RefCounted

## Pure rules for the mystical essences food carries (see MysticTrait):
## when each one wakes, from the food's physical state, and what it does
## once awake. The heat model calls act() every step, the pot's layout and
## the board read lift_share(), the view reads glow(), and the kitchen's
## nourishment reads the spirit effects. No rule here names a trait.

## How far below a HOT trigger's temperature the essence starts to stir.
const HOT_RAMP_C: float = 15.0
## The coldest a FROST essence can pull food, in degrees C.
const FROST_FLOOR_C: float = -10.0

## 0 asleep to 1 fully awake, for a trait in this piece as it is now.
static func activation(mystic_trait: MysticTrait, piece: FoodPiece) -> float:
	var threshold: float = maxf(mystic_trait.trigger_threshold, 0.0001)
	match mystic_trait.trigger:
		MysticTrait.Trigger.RAW:
			return 1.0 - smoothstep(0.0, threshold, piece.core_doneness)
		MysticTrait.Trigger.COOKED:
			return smoothstep(threshold * 0.5, threshold, piece.core_doneness)
		MysticTrait.Trigger.BROWNED:
			return smoothstep(threshold * 0.5, threshold, piece.surface_browning)
		MysticTrait.Trigger.HOT:
			return smoothstep(mystic_trait.trigger_threshold - HOT_RAMP_C, mystic_trait.trigger_threshold,
				maxf(piece.core_temp_c, piece.surface_temp_c))
		MysticTrait.Trigger.CHARRED:
			return smoothstep(threshold * 0.5, threshold, piece.surface_char)
	return 1.0

## The same for an essence dissolved in a liquid, which has no doneness of
## its own: it was woken in the food it came out of, so only the
## temperature-bound triggers still apply.
static func activation_in_liquid(mystic_trait: MysticTrait, temp_c: float) -> float:
	if mystic_trait.trigger == MysticTrait.Trigger.HOT:
		return smoothstep(mystic_trait.trigger_threshold - HOT_RAMP_C, mystic_trait.trigger_threshold, temp_c)
	return 1.0

## Total awake strength of one effect in a piece, per unit of its mass.
static func strength(piece: FoodPiece, effect: MysticTrait.Effect) -> float:
	var total: float = 0.0
	if piece.traits.is_empty():
		return total
	for mystic_trait in piece.traits.doses:
		if mystic_trait.effect == effect:
			total += piece.traits.get_dose(mystic_trait) * mystic_trait.magnitude * activation(mystic_trait, piece)
	return total

## The same for a liquid at a temperature.
static func liquid_strength(doses: TraitDoses, effect: MysticTrait.Effect, temp_c: float) -> float:
	var total: float = 0.0
	if doses == null:
		return total
	for mystic_trait in doses.traits():
		if mystic_trait.effect == effect:
			total += doses.get_dose(mystic_trait) * mystic_trait.magnitude * activation_in_liquid(mystic_trait, temp_c)
	return total

## Share of the piece's weight its essences lift. Above 1 it floats on
## anything and rises off whatever it rests on.
static func lift_share(piece: FoodPiece) -> float:
	return strength(piece, MysticTrait.Effect.LIFT)

## Share of burning held off.
static func char_ward(piece: FoodPiece) -> float:
	return clampf(strength(piece, MysticTrait.Effect.CHAR_WARD), 0.0, 1.0)

## The light the piece gives off: its strength, in the colour of the
## brightest essence.
static func glow(piece: FoodPiece) -> Color:
	var total: float = 0.0
	var brightest: float = 0.0
	var color := Color.BLACK
	if piece.traits.is_empty():
		color.a = 0.0
		return color
	for mystic_trait in piece.traits.traits():
		if mystic_trait.effect != MysticTrait.Effect.GLOW:
			continue
		var amount: float = piece.traits.get_dose(mystic_trait) * mystic_trait.magnitude * activation(mystic_trait, piece)
		total += amount
		if amount > brightest:
			brightest = amount
			color = mystic_trait.glow_color
	color.a = total
	return color

## Lets every awake essence act on the piece for dt seconds: embers heat
## its core and frost chills it (spending their fuel), and blooms draw out
## their flavour (spending themselves).
static func act(piece: FoodPiece, dt: float, core_capacity_j_per_k: float) -> void:
	if piece.traits.is_empty():
		return
	var mass: float = piece.mass_g()
	for mystic_trait in piece.traits.traits():
		var dose: float = piece.traits.get_dose(mystic_trait)
		var awake: float = activation(mystic_trait, piece)
		if awake <= 0.0 or dose <= 0.0:
			continue
		match mystic_trait.effect:
			MysticTrait.Effect.EMBER, MysticTrait.Effect.FROST:
				var sign: float = 1.0 if mystic_trait.effect == MysticTrait.Effect.EMBER else -1.0
				var joules: float = mystic_trait.magnitude * dose * awake * mass * dt
				var new_temp: float = piece.core_temp_c + sign * joules / core_capacity_j_per_k
				if sign < 0.0:
					new_temp = maxf(new_temp, FROST_FLOOR_C)
				piece.core_temp_c = new_temp
				if mystic_trait.fuel_j_per_g > 0.0:
					piece.traits.set_dose(mystic_trait, dose - joules / (mystic_trait.fuel_j_per_g * mass))
			MysticTrait.Effect.BLOOM:
				if mystic_trait.bloom_flavour == null:
					continue
				var step: float = minf(mystic_trait.magnitude * dose * awake * dt, dose)
				for axis in FlavourProfile.AXES:
					var now: float = piece.flavour.get(axis)
					var target: float = maxf(now, float(mystic_trait.bloom_flavour.get(axis)))
					piece.flavour.set(axis, lerpf(now, target, clampf(step, 0.0, 1.0)))
				piece.traits.set_dose(mystic_trait, dose - step)
