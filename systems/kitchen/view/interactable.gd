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
## The empty hand came over it, and moved off it again.
signal hover_entered
signal hover_exited

## World-space plane drags are projected onto. Owners set it; the default
## is the counter surface.
var drag_plane: Plane = Plane(Vector3.UP, 0.0)
## How the hand holds it, and where: a node the hand closes on (a handle)
## instead of the point under the mouse. Owners set these; the default is
## a grip wherever the mouse is.
var hand_pose: HandModel.Pose = HandModel.Pose.GRIP
var hand_anchor: Node3D
