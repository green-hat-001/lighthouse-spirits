class_name TraitDose
extends Resource

## How much of a mystical essence an ingredient carries, as authored. 1 is a
## full dose; doses add, so a creature's diet can push a tissue past 1.

@export var mystic_trait: MysticTrait
@export var concentration: float = 1.0
