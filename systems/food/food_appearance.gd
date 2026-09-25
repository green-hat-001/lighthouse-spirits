class_name FoodAppearance
extends RefCounted

## Shader-facing view of a piece, each 0-1. The 3D layer feeds these to the
## cel-shaded food material so the player can judge doneness by eye.

## Golden-to-deep-brown tint over the ingredient's own colour.
var browning: float = 0.0
## Blackened patches.
var charring: float = 0.0
## Shine from oil or surface water.
var gloss: float = 0.0
## Cooked starch and flesh turning translucent.
var translucency: float = 0.0
## Ragged, broken edges from lost integrity.
var crumble: float = 0.0
