class_name ExtractAction
extends UnitAction

var unit: TacticalUnit
var objective_manager: ObjectiveManager

func _init(p_unit: TacticalUnit, p_objective_manager: ObjectiveManager) -> void:
	unit = p_unit
	objective_manager = p_objective_manager

func is_valid() -> bool:
	return objective_manager != null and objective_manager.can_extract(unit)

func execute() -> bool:
	if not is_valid():
		return false
	return objective_manager.complete_extraction(unit)
