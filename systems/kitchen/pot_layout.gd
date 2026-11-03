class_name PotLayout
extends RefCounted

## Pure placement of food in a pot: where each piece settles and how deep
## it lies in the liquid. Pieces stay axis-aligned, as everywhere in the
## kitchen.
##
## Per step:
##   1. Each piece's effective density is its weight (less what its
##      essences lift) over its volume plus the steam bubbles clinging to
##      it. Denser than the liquid, it sinks, to
##      the floor or onto food already lying where it is; lighter, it
##      floats, drawing as deep as Archimedes says. Raw potato sinks in oil;
##      a fry that is steaming hard, or has dried out, rises.
##   2. The liquid line is the liquid's volume plus everything submerged in
##      it, spread over the pot's floor - food displaces the oil.
##   3. A floating piece whose draft is deeper than the liquid grounds on
##      the floor. Anything taller than the liquid stands partly out of it.
##   4. Pieces lying at the same height push apart where they overlap, and
##      everything is kept inside the pot's wall. Food lying on other food
##      slides off it as hard as the liquid is bubbling or being stirred, so
##      a dropped heap spreads out over the floor as it fries.

## Volume of steam per gram at about 100 degrees C, in cm^3.
const STEAM_CM3_PER_G: float = 1670.0
## How long a bubble clings to food before it lets go, in s. With the steam
## rate, this sets how much lift bubbling gives.
const BUBBLE_RESIDENCE_S: float = 0.03
## Footprint overlap, as a share of the smaller footprint, at which a sunk
## piece lies on another rather than beside it.
const STACK_OVERLAP: float = 0.25
## Share of an overlap resolved per step, so pieces ease apart.
const SEPARATION_RATE: float = 0.5
## Share of a stacked overlap resolved per step at full agitation.
const STACK_SLIDE_RATE: float = 0.08
## Clearance kept from the wall, in mm.
const WALL_CLEARANCE_MM: float = 1.0
## Width of the blend between the base's middle and its rim, in mm.
const BURNER_EDGE_MM: float = 12.0

## Places every piece, and returns the liquid line in mm above the floor
## (0 with no liquid).
static func settle(
		placements: Array[PotPlacement], radius_mm: float, burner_radius_mm: float,
		liquid_volume_mm3: float, liquid_density_g_per_cm3: float, agitation: float = 0.0) -> float:
	_separate(placements, agitation)
	for placement in placements:
		_keep_inside(placement, radius_mm)
		placement.over_burner = 1.0 - smoothstep(
			burner_radius_mm - BURNER_EDGE_MM, burner_radius_mm + BURNER_EDGE_MM, placement.centre_mm.length())

	var floor_area: float = PI * radius_mm * radius_mm
	var level: float = liquid_volume_mm3 / floor_area
	if liquid_volume_mm3 <= 0.0:
		level = 0.0
	# The line depends on what is submerged, which depends on the line; two
	# passes settle it to well within a millimetre.
	for pass_index in 2:
		var submerged_mm3: float = _place_all(placements, level, liquid_density_g_per_cm3)
		if liquid_volume_mm3 <= 0.0:
			return 0.0
		level = (liquid_volume_mm3 + submerged_mm3) / floor_area
	_place_all(placements, level, liquid_density_g_per_cm3)
	return level

## The density the piece shows the liquid, with its clinging bubbles and
## whatever share of its weight its essences lift.
static func effective_density(placement: PotPlacement) -> float:
	var piece := placement.piece
	var bubbles_cm3: float = placement.steam_g_per_s * STEAM_CM3_PER_G * BUBBLE_RESIDENCE_S
	var weight: float = piece.mass_g() * maxf(1.0 - TraitEffects.lift_share(piece), 0.0)
	return weight / (piece.volume_mm3() / 1000.0 + bubbles_cm3)

static func _place_all(placements: Array[PotPlacement], level: float, liquid_density: float) -> float:
	var submerged_mm3: float = 0.0
	var sunk: Array[PotPlacement] = []
	for placement in placements:
		var piece := placement.piece
		var height: float = piece.size_mm.y
		var density: float = effective_density(placement)
		var floats: bool = level > 0.0 and density < liquid_density
		if floats:
			var draft: float = height * density / liquid_density
			if draft < level:
				placement.resting = PotPlacement.Resting.FLOATING
				placement.bottom_mm = level - draft
			else:
				placement.resting = PotPlacement.Resting.FLOOR
				placement.bottom_mm = 0.0
		else:
			var support: float = 0.0
			for below in sunk:
				if _overlap_share(placement, below) >= STACK_OVERLAP:
					support = maxf(support, below.top_mm())
			placement.bottom_mm = support
			placement.resting = PotPlacement.Resting.FLOOR if support <= 0.0 else PotPlacement.Resting.ON_FOOD
			sunk.append(placement)
		placement.immersion = clampf((level - placement.bottom_mm) / height, 0.0, 1.0) if level > 0.0 else 0.0
		submerged_mm3 += piece.volume_mm3() * placement.immersion
	return submerged_mm3

static func _overlap_share(a: PotPlacement, b: PotPlacement) -> float:
	var overlap := a.footprint().intersection(b.footprint())
	if overlap.size.x <= 0.0 or overlap.size.y <= 0.0:
		return 0.0
	var smaller: float = minf(a.footprint().get_area(), b.footprint().get_area())
	return overlap.get_area() / smaller if smaller > 0.0 else 0.0

## Pieces lying at overlapping heights ease apart along whichever axis
## they overlap least on.
static func _separate(placements: Array[PotPlacement], agitation: float) -> void:
	for i in placements.size():
		for j in range(i + 1, placements.size()):
			var a := placements[i]
			var b := placements[j]
			var rate: float = SEPARATION_RATE
			if a.top_mm() <= b.bottom_mm + 0.01 or b.top_mm() <= a.bottom_mm + 0.01:
				# One lies on the other: it only slides off when jostled.
				rate = STACK_SLIDE_RATE * clampf(agitation, 0.0, 1.0)
				if rate <= 0.0:
					continue
			var overlap := a.footprint().intersection(b.footprint())
			if overlap.size.x <= 0.0 or overlap.size.y <= 0.0:
				continue
			var push := Vector2.ZERO
			var apart := b.centre_mm - a.centre_mm
			if overlap.size.x < overlap.size.y:
				push.x = overlap.size.x * (1.0 if apart.x >= 0.0 else -1.0)
			else:
				push.y = overlap.size.y * (1.0 if apart.y >= 0.0 else -1.0)
			push *= 0.5 * rate
			a.centre_mm -= push
			b.centre_mm += push

static func _keep_inside(placement: PotPlacement, radius_mm: float) -> void:
	var half := Vector2(placement.piece.size_mm.x, placement.piece.size_mm.z) * 0.5
	var limit: float = radius_mm - WALL_CLEARANCE_MM
	var corner := Vector2(absf(placement.centre_mm.x) + half.x, absf(placement.centre_mm.y) + half.y)
	if corner.length() <= limit:
		return
	# Too long to lie anywhere but across the middle: centre it.
	if half.length() >= limit:
		placement.centre_mm = Vector2.ZERO
		return
	# Pull it straight in until its far corner clears the wall.
	var direction := placement.centre_mm.normalized() if placement.centre_mm.length() > 0.0 else Vector2.RIGHT
	var low: float = 0.0
	var high: float = placement.centre_mm.length()
	for iteration in 12:
		var middle: float = (low + high) * 0.5
		var centre := direction * middle
		if Vector2(absf(centre.x) + half.x, absf(centre.y) + half.y).length() <= limit:
			low = middle
		else:
			high = middle
	placement.centre_mm = direction * low
