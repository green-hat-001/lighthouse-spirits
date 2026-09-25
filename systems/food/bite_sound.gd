class_name BiteSound
extends RefCounted

## Which recorded bite layers to play when the player tastes a piece, how
## loudly each, and at what pitch. Layer weights sum to 1. The audio layer
## (Section 6.8) mixes recorded samples by these weights.

enum Layer { CRISP, CRUNCH, SOFT, SQUELCH, CHEW }

var weights: Dictionary[Layer, float] = {}
## 1.0 is the recording's own pitch. Thin pieces sound higher.
var pitch: float = 1.0

func weight(layer: Layer) -> float:
	return weights.get(layer, 0.0)

## The loudest layer, the one the player mostly hears.
func dominant_layer() -> Layer:
	var best: Layer = Layer.SOFT
	var best_weight: float = -1.0
	for layer in weights:
		if weights[layer] > best_weight:
			best_weight = weights[layer]
			best = layer
	return best
