class_name HeatExposure
extends RefCounted

## What surrounds a FoodPiece while it cooks: the temperature of the medium
## or surface it touches, how well heat crosses into the food, and - for a
## liquid - the fat and flavour the food can exchange with it. The owner of
## the medium (a pot) fills this in; FoodHeating reads it, and writes the
## flavour the food releases back into `flavour`.

var temp_c: float = 20.0
var heat_transfer_w_per_m2_k: float = 0.0
## Fat as a fraction of the medium. Food can soak up fat, never water.
var fat_fraction: float = 0.0
## The medium's own flavour, mutated as flavour moves in and out of food.
## Null when there is no liquid medium to exchange with.
var flavour: FlavourProfile
var medium_mass_g: float = 0.0
