class_name HeatExchange
extends RefCounted

## What one FoodPiece took from and gave to its surroundings over one
## heating step. The owner of the medium applies it so energy and mass are
## conserved.

## Heat that crossed from the medium into the food, in J. Negative when the
## food is hotter than its surroundings.
var energy_j: float = 0.0
## Fat the food soaked up from the medium.
var fat_absorbed_g: float = 0.0
## Water the food boiled off as steam.
var evaporated_g: float = 0.0
