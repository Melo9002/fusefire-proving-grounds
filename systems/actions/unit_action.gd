class_name UnitAction
extends RefCounted

## Actions return false without spending AP when validation fails.
func is_valid() -> bool:
	push_error("UnitAction.is_valid() is a virtual method and must be overridden in child classes.")
	return false

func execute() -> bool:
	push_error("UnitAction.execute() is a virtual method and must be overridden in child classes.")
	return false
