class_name HeatExchange
extends RefCounted

## What one FoodPiece took from and gave to its surroundings over one
## heating step, by channel, so the owner of each source can conserve
## energy and mass.

## Heat that crossed into the food, in J, over all channels. Negative when
## the food is hotter than its surroundings.
var energy_j: float = 0.0
var liquid_energy_j: float = 0.0
var contact_energy_j: float = 0.0
var air_energy_j: float = 0.0
## Fat the food soaked up from the medium.
var fat_absorbed_g: float = 0.0
## Water the food lost as steam or vapour, by boiling or drying.
var evaporated_g: float = 0.0
## The part of that steam boiled off faces wetted by the liquid: it bubbles
## up through the medium, stirring it and, in oil, breaking the oil down.
var steam_through_liquid_g: float = 0.0
