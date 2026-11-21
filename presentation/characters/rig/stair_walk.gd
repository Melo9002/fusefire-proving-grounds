class_name StairWalk
extends RefCounted
## A stair walk in progress, as the rig holds it: the model of the treads, the direction, where along the stair the route enters and leaves (`enter_s`, `exit_s`, which shape the pose's weight), the tread interval
## the feet are currently planned at (`step`) with the holds planned for it, and the pose solved for the current place (`pose`, null until the first place is set). It lives from begin_stairs to end_stairs and is null
## on the rig when there is none.

var model: StairModel
var ascending := true
var enter_s := 0.0
var exit_s := 0.0
var step := 0
var holds: Array = []
var pose: StairPose

func _init(stair_model: StairModel = null, going_up := true, enter := 0.0, exit := 0.0) -> void:
	model = stair_model
	ascending = going_up
	enter_s = enter
	exit_s = exit
