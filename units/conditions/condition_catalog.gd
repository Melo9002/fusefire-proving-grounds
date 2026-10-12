class_name ConditionCatalog
extends RefCounted

const LEAKING := preload("res://units/conditions/leaking.tres")
const BLEEDING := preload("res://units/conditions/bleeding.tres")
const JAMMED := preload("res://units/conditions/jammed.tres")

static func resolve(condition_id: StringName) -> ConditionDefinition:
	match condition_id:
		&"leaking": return LEAKING
		&"bleeding": return BLEEDING
		&"jammed": return JAMMED
	return null
