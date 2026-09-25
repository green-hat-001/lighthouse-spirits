class_name FoodTexture
extends RefCounted

## How a piece of food feels in the mouth, each 0-1. Derived from physical
## state by FoodPerception; never stored or authored.

## A dry, browned crust that shatters: a good fry.
var crispness: float = 0.0
## Holds its shape and resists the teeth: raw vegetables.
var firmness: float = 0.0
## Yields easily: cooked starch, and mush when overcooked.
var softness: float = 0.0
## Dried out and leathery inside: over-fried.
var chewiness: float = 0.0
## A wet surface: raw, boiled, or never dried by the heat.
var wetness: float = 0.0
## Oil soaked into it.
var greasiness: float = 0.0
