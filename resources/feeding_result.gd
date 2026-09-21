class_name FeedingResult
extends Resource

## Data contract produced by the (future) Culinary Crafting module and
## consumed by the Spirit FSM. The FSM has no knowledge of recipes or
## ingredients - it only reacts to this shape.

@export var nourishment: float = 0.0
@export var calming: float = 0.0
@export var buoyancy_delta: float = 0.0
@export var matched_affinity: bool = false
