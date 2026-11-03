class_name FeedingResult
extends Resource

## Data contract produced by the kitchen (DishNourishment, through the
## DishServingStation) and consumed by the Spirit FSM. The FSM has no
## knowledge of food or ingredients - it only reacts to this shape.

@export var nourishment: float = 0.0
@export var calming: float = 0.0
@export var buoyancy_delta: float = 0.0
@export var matched_affinity: bool = false
## How well the food was made, 0-1: how likely it is to carry the spirit all
## the way to the moon.
@export_range(0.0, 1.0) var ascension_strength: float = 1.0
