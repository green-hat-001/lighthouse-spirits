class_name KitchenEquipment
extends Resource

## One piece of kitchen equipment: a stove, a pot, an oil press. Subclasses
## add the physical data their simulation needs. New equipment is authored
## as a new .tres instance - no new code required.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Availability")
## Installed from the start. Everything else is gated behind the lighthouse
## upgrade that installs it.
@export var available_from_start: bool = false
