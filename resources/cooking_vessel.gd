class_name CookingVessel
extends KitchenEquipment

## A pot or pan, as a physical object. The simulation splits its metal into
## two thermal masses: the disc of base directly over the burner, and the
## rest of the base together with the walls. Steel conducts sideways
## poorly, so the middle of the base runs hotter than its rim and food
## resting in the middle browns first.

@export var mass_g: float = 1500.0
@export var specific_heat_j_per_g_k: float = 0.5
@export var capacity_ml: float = 3000.0
## Inside of the pot.
@export var interior_diameter_mm: float = 180.0
@export var interior_height_mm: float = 120.0
@export var wall_thickness_mm: float = 3.0
## Thickness of the base. A heavy, clad base spreads the flame's heat
## sideways and evens out the hot spot over the burner.
@export var base_thickness_mm: float = 5.0
## Share of the vessel's metal that is in its base.
@export_range(0.05, 0.95) var base_mass_share: float = 0.4
## Thermal conductivity of the base, in W/(m K): about 50 for carbon
## steel, 16 for stainless, 200 for aluminium, between for a clad base.
@export var conductivity_w_per_m_k: float = 120.0
## Thermal emissivity of the outside: about 0.85 for enamel, 0.3 for bare
## steel. Hot enamel sheds a lot of heat by radiation.
@export_range(0.0, 1.0) var emissivity: float = 0.85
## Heat transfer from the hot, dry bottom of the vessel into food resting on
## it, in W/(m^2 K), applied over the face the food rests on.
@export var dry_contact_w_per_m2_k: float = 400.0
## The same through a film of oil or water, which fills the gaps between
## food and metal.
@export var wet_contact_w_per_m2_k: float = 500.0

func interior_radius_mm() -> float:
	return interior_diameter_mm * 0.5

func floor_area_mm2() -> float:
	return PI * interior_radius_mm() * interior_radius_mm()
