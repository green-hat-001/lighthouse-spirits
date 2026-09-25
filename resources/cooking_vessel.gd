class_name CookingVessel
extends KitchenEquipment

## A pot or pan. The vessel and any liquid in it are simulated as a single
## heat mass sharing one temperature.

@export var mass_g: float = 1500.0
@export var specific_heat_j_per_g_k: float = 0.5
## Heat lost to the kitchen per degree above ambient, in W/K.
@export var heat_loss_w_per_k: float = 4.0
@export var capacity_ml: float = 3000.0
## Heat transfer from the hot, dry bottom of the vessel into food resting on
## it, in W/(m^2 K), applied over the face the food rests on.
@export var dry_contact_w_per_m2_k: float = 400.0
