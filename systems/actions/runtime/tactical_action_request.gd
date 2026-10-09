class_name TacticalActionRequest
extends RefCounted

enum Source { PLAYER, AI, REPLAY, SYSTEM, DEBUG }

var kind: StringName
var actor_id: StringName
var target_id: StringName
var expected_revision: int
var source: Source

func _init(
	p_kind: StringName = &"",
	p_actor_id: StringName = &"",
	p_target_id: StringName = &"",
	p_expected_revision := 0,
	p_source: Source = Source.SYSTEM
) -> void:
	kind = p_kind
	actor_id = p_actor_id
	target_id = p_target_id
	expected_revision = p_expected_revision
	source = p_source

static func attack(actor: StringName, target: StringName, revision: int, request_source: Source) -> TacticalActionRequest:
	return TacticalActionRequest.new(&"attack", actor, target, revision, request_source)

func to_dictionary() -> Dictionary:
	return {
		"kind": String(kind),
		"actor_id": String(actor_id),
		"target_id": String(target_id),
		"expected_revision": expected_revision,
		"source": int(source),
	}

static func from_dictionary(data: Dictionary) -> TacticalActionRequest:
	return TacticalActionRequest.new(
		StringName(data.get("kind", "")),
		StringName(data.get("actor_id", "")),
		StringName(data.get("target_id", "")),
		int(data.get("expected_revision", 0)),
		int(data.get("source", Source.REPLAY)) as Source
	)

