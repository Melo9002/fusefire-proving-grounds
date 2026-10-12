class_name MissionIntent
extends RefCounted

enum Kind {
	NONE,
	ELIMINATE,
	REACH,
	EXTRACT,
	PROTECT,
	RESCUE,
	INTERACT_TERMINAL,
	SURVIVE,
}

var kind: Kind = Kind.NONE
var objective_id: StringName
var title := "No mission goal"
var zone_id: StringName
var target_ids: Array[StringName] = []
var required := false
var reason := "No active mission objective applies to this unit."

func _init(
	intent_kind: Kind = Kind.NONE,
	intent_objective_id: StringName = &"",
	intent_title := "No mission goal",
	intent_zone_id: StringName = &"",
	intent_target_ids: Array[StringName] = [],
	is_required := false,
	intent_reason := "No active mission objective applies to this unit."
) -> void:
	kind = intent_kind
	objective_id = intent_objective_id
	title = intent_title
	zone_id = intent_zone_id
	target_ids = intent_target_ids.duplicate()
	required = is_required
	reason = intent_reason

func is_actionable() -> bool:
	return kind != Kind.NONE

func get_debug_label() -> String:
	if not is_actionable():
		return "None"
	return "%s [%s]" % [title, Kind.keys()[kind]]
