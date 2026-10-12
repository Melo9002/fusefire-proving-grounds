class_name ConditionComponent
extends Node

signal changed
signal condition_applied(condition_id: StringName, refreshed: bool)
signal condition_removed(condition_id: StringName)
signal condition_ticked(condition_id: StringName, damage: int, remaining_beats: int)

var active: Dictionary[StringName, ConditionInstance] = {}

func apply(definition: ConditionDefinition, beat: int, source_id: StringName = &"") -> Dictionary:
	if definition == null or not definition.validation_message().is_empty():
		return {"applied": false, "reason": "invalid_definition"}
	var refreshed := active.has(definition.condition_id)
	var instance: ConditionInstance = active.get(definition.condition_id)
	if refreshed:
		instance.remaining_beats = definition.duration_beats
		instance.applied_beat = beat
		instance.source_id = source_id
	else:
		instance = ConditionInstance.new(definition, beat, source_id)
		active[definition.condition_id] = instance
	condition_applied.emit(definition.condition_id, refreshed)
	changed.emit()
	return {"applied": true, "refreshed": refreshed, "remaining_beats": instance.remaining_beats}

func remove(condition_id: StringName) -> bool:
	if not active.erase(condition_id): return false
	condition_removed.emit(condition_id)
	changed.emit()
	return true

func has(condition_id: StringName) -> bool:
	return active.has(condition_id)

func restricts(action: StringName) -> bool:
	for instance: ConditionInstance in active.values():
		if instance.definition and instance.definition.restricted_action == action:
			return true
	return false

func tick(_beat: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ids: Array[StringName] = []
	ids.assign(active.keys())
	ids.sort_custom(func(a: StringName, b: StringName): return String(a) < String(b))
	for condition_id in ids:
		var instance: ConditionInstance = active.get(condition_id)
		if instance == null:
			continue
		var damage := instance.definition.recurring_damage
		instance.remaining_beats -= 1
		events.append({"condition_id": String(condition_id), "damage": damage, "remaining_beats": instance.remaining_beats})
		condition_ticked.emit(condition_id, damage, instance.remaining_beats)
		if instance.remaining_beats <= 0:
			active.erase(condition_id)
			condition_removed.emit(condition_id)
	changed.emit()
	return events

func snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array[StringName] = []
	ids.assign(active.keys())
	ids.sort_custom(func(a: StringName, b: StringName): return String(a) < String(b))
	for condition_id in ids:
		result.append((active[condition_id] as ConditionInstance).to_dictionary())
	return result

func clear() -> void:
	if active.is_empty(): return
	active.clear()
	changed.emit()
