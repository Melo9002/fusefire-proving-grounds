class_name DoorActionQueryResult
extends RefCounted
## The read-only answer to "may this unit open or close this door now?": one validation shared by the player preview, the AI and execution. A free action: no AP.

var kind: StringName
var actor_id: StringName
var door_id: StringName
var validation: ActionValidationResult
var cost := ActionCost.new(0, false, false, true)
var state_revision := 0
var door_state: StringName = &""
var desired_state: StringName = &""
var door_cell := Vector3i(-1, -1, -1)


func is_legal() -> bool:
	return validation != null and validation.accepted


func reason() -> String:
	return validation.message if validation != null else "Door availability was not evaluated"
