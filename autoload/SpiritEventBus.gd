extends Node

# Decoupled signal hub. External systems (kitchen/plating UI, future
# progression/save systems) talk to spirits only through these signals -
# never by reaching into a SpiritController directly.

signal feed_spirit_requested(spirit_id: StringName, feeding_result: FeedingResult)
signal spirit_state_changed(spirit_id: StringName, old_state: int, new_state: int)
signal spirit_fed_fully(spirit_id: StringName)
signal spirit_ascended(spirit_id: StringName)
signal spirit_departed_unfed(spirit_id: StringName)
signal spirit_lifecycle_complete(spirit_id: StringName, outcome: StringName)
