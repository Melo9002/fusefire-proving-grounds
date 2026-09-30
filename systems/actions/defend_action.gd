class_name DefendAction
extends UnitAction

var unit: TacticalUnit
var ap_cost: int

func _init(p_unit: TacticalUnit, p_ap_cost: int = 1) -> void:
	unit = p_unit
	ap_cost = p_ap_cost

func is_valid() -> bool:
	if not is_instance_valid(unit) or not unit.stats or unit.stats.is_defeated:
		return false

	if unit.stats.current_ap < ap_cost:
		return false

	return true

func execute() -> bool:
	if not is_valid():
		return false
	unit.stats.consume_ap(ap_cost)
	unit.stats.is_defending = true

	print_rich("[color=green][DefendAction][/color] %s is now in Defend stance." % unit.name)
	return true
