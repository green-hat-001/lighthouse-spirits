class_name Interactable
extends Area3D

## Anything in the kitchen the player can put their hand on: a piece of
## food, the board, a basket, a knob. The KitchenPointer finds it by
## raycast and reports what the mouse does to it; the owning node listens
## to these signals and decides what that means. Drag points are projected
## onto drag_plane so a drag keeps working after the mouse leaves the shape.

signal pressed(point: Vector3)
signal dragged(point: Vector3)
signal released(point: Vector3)
## Right mouse button.
signal secondary_pressed(point: Vector3)
## The hold ended without a release - the player stepped away mid-drag.
## Owners abandon whatever the drag was doing.
signal cancelled

## World-space plane drags are projected onto. Owners set it; the default
## is the counter surface.
var drag_plane: Plane = Plane(Vector3.UP, 0.0)
