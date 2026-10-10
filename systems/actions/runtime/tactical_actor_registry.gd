class_name TacticalActorRegistry
extends RefCounted

var _actors: Dictionary[StringName, WeakRef] = {}

func register_actor(actor: TacticalUnit) -> bool:
	if not is_instance_valid(actor) or actor.tactical_id.is_empty():
		push_error("TacticalActorRegistry: actor is invalid or has no tactical_id")
		return false
	var existing := resolve(actor.tactical_id)
	if is_instance_valid(existing) and existing != actor:
		push_error("TacticalActorRegistry: duplicate tactical_id '%s'" % actor.tactical_id)
		return false
	_actors[actor.tactical_id] = weakref(actor)
	return true

func unregister_actor(actor: TacticalUnit) -> void:
	if is_instance_valid(actor) and _actors.has(actor.tactical_id):
		_actors.erase(actor.tactical_id)

func resolve(actor_id: StringName) -> TacticalUnit:
	if actor_id.is_empty() or not _actors.has(actor_id):
		return null
	var actor_reference: WeakRef = _actors[actor_id]
	var actor := actor_reference.get_ref() as TacticalUnit
	if not is_instance_valid(actor):
		_actors.erase(actor_id)
		return null
	return actor

func get_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for actor_id: StringName in _actors.keys():
		if is_instance_valid(resolve(actor_id)):
			result.append(actor_id)
	result.sort()
	return result
