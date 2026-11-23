class_name LadderClimb
extends RefCounted
## A ladder traversal in progress, as the rig holds it: what is being climbed (`kind`, `length` the ladder's rise, `direction` +1 climbing and -1 descending), how far the character's floor level is above the
## ladder's bottom floor (`climbed`), and the pose solved for that height (`pose`, null until the first height is set). It lives from begin_traversal to end_traversal and is null on the rig when there is none.

var kind: StringName = &"ladder"
var length := 0.0
## The ladder this climb is on (the shared layout) and the body's measurements it is planned for.
var geometry: LadderGeometry
var body: LadderBody
var direction := 1
var climbed := 0.0
var pose: LadderPose

func _init(climb_kind: StringName = &"ladder", rise := 0.0, travel_direction := 1) -> void:
	kind = climb_kind
	length = rise
	direction = travel_direction
	geometry = LadderGeometry.for_rise(rise)
