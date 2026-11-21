class_name RigAxes
extends RefCounted
## The anatomical axes of a skeleton (skeleton space), measured once from its rest pose: up the spine, the way the toes point, and the hip hinge. Typed replacement for the {up, forward, hinge} dictionary the
## locomotion modifier used to be configured with.

var up := Vector3.UP
var forward := Vector3.FORWARD
var hinge := Vector3.RIGHT

func _init(axis_up := Vector3.UP, axis_forward := Vector3.FORWARD, axis_hinge := Vector3.RIGHT) -> void:
	up = axis_up
	forward = axis_forward
	hinge = axis_hinge
