class_name MoveQueryResult
extends RefCounted

var validation: ActionValidationResult
var cost := ActionCost.new(1)
var actor_id: StringName
var start_cell := Vector3i(-1, -1, -1)
var target_cell := Vector3i(-1, -1, -1)
var state_revision: int
var path := PackedVector3Array()
var presentation_path := PackedVector3Array()
var visual_segments: Array[StringName] = []

func is_legal() -> bool:
	return validation != null and validation.accepted
