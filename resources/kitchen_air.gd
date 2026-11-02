class_name KitchenAir
extends Resource

## The open air around the outdoor kitchen on the cliff top. Everything
## left out in it - a pot's walls, the oil's surface, fries resting on the
## board - loses heat to it by convection, and wet food dries into it. Wind
## strips heat faster and pulls the burner's flame about, so a blustery day
## cooks differently from a still one. Weather is authored as instances of
## this resource, never as code.

## Convective heat transfer to still air, in W/(m^2 K), and the extra per
## m/s of wind (the Watmuff correlation, h = 5.7 + 3.8 v).
const STILL_AIR_W_PER_M2_K: float = 5.7
const WIND_W_PER_M2_K_PER_MPS: float = 3.8
## Share of the burner's heat the wind blows away from under the pot, per
## m/s, and the most it can ever take.
const FLAME_LOSS_PER_MPS: float = 0.03
const MAX_FLAME_LOSS: float = 0.5

@export var temp_c: float = 15.0
@export_range(0.0, 40.0) var wind_mps: float = 4.0
@export_range(0.0, 1.0) var relative_humidity: float = 0.8

## Convective coefficient for a surface in this air. `shelter` (0-1) is how
## much of the wind is kept off it - the inside of a pot is sheltered, the
## board is not.
func convective_w_per_m2_k(shelter: float = 0.0) -> float:
	return STILL_AIR_W_PER_M2_K + WIND_W_PER_M2_K_PER_MPS * wind_mps * (1.0 - clampf(shelter, 0.0, 1.0))

## Water vapour already in the air, in kg/m^3. Wet food dries only while
## the vapour at its surface is denser than this.
func vapour_density_kg_m3() -> float:
	return relative_humidity * WaterVapour.saturation_density_kg_m3(temp_c)

## Share of a burner's output that reaches the pot in this wind.
func flame_efficiency() -> float:
	return 1.0 - minf(FLAME_LOSS_PER_MPS * wind_mps, MAX_FLAME_LOSS)

static func still(p_temp_c: float) -> KitchenAir:
	var air := KitchenAir.new()
	air.temp_c = p_temp_c
	air.wind_mps = 0.0
	air.relative_humidity = 0.5
	return air
