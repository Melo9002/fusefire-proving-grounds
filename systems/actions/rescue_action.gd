class_name RescueAction
extends UnitAction

var rescuer: TacticalUnit
var target: TacticalUnit
var objective_manager: ObjectiveManager

func _init(p_rescuer: TacticalUnit, p_target: TacticalUnit, p_objective_manager: ObjectiveManager) -> void:
	rescuer = p_rescuer
	target = p_target
	objective_manager = p_objective_manager

func is_valid() -> bool:
	return objective_manager != null and objective_manager.can_rescue(rescuer, target)

func execute() -> bool:
	if not is_valid():
		return false
	return objective_manager.complete_rescue(rescuer, target)
