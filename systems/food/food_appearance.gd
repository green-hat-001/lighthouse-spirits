class_name FoodAppearance
extends RefCounted

## Shader-facing view of a piece, each 0-1. The 3D layer feeds these to the
## cel-shaded food material so the player can judge doneness by eye. The
## per-face values are indexed by FoodPiece.Face; the single values are
## their means over the surface.

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
var face_browning := PackedFloat64Array()
var face_char := PackedFloat64Array()
## 1 skin, 0 cut flesh.
var face_skin := PackedFloat64Array()
## Surface wetness per face, 0 dry to 1 as wet as raw.
var face_wetness := PackedFloat64Array()
