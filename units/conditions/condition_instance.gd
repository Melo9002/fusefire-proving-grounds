class_name ConditionInstance
extends RefCounted

var definition: ConditionDefinition
var remaining_beats := 0
var applied_beat := -1
var source_id: StringName

func _init(value: ConditionDefinition = null, beat := -1, source: StringName = &"") -> void:
	definition = value
	remaining_beats = value.duration_beats if value else 0
	applied_beat = beat
	source_id = source

func to_dictionary() -> Dictionary:
	return {
		"condition_id": String(definition.condition_id) if definition else "",
		"remaining_beats": remaining_beats,
		"applied_beat": applied_beat,
		"source_id": String(source_id),
	}
