class_name MoveQueryResult
extends RefCounted

var validation: ActionValidationResult
var cost := ActionCost.new(1)
var actor_id: StringName
var start_cell := Vector3i(-1, -1, -1)
var target_cell := Vector3i(-1, -1, -1)
var state_revision: int
var actor_ap_before: int
var actor_ap_after: int
var movement_budget: int
var path_cost: float
var elevation_change: int
var blocking_actor_id: StringName = &""
var legal_destination_cells: Array[Vector3i] = []
var path_cells: Array[Vector3i] = []
var path := PackedVector3Array()
var presentation_path := PackedVector3Array()
var visual_segments: Array[StringName] = []

func is_legal() -> bool:
	return validation != null and validation.accepted

func has_destination() -> bool:
	return target_cell != Vector3i(-1, -1, -1)
