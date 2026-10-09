class_name BattleReplayRecording
extends RefCounted

const CURRENT_SCHEMA_VERSION := 2

var schema_version := CURRENT_SCHEMA_VERSION
var configuration: Dictionary = {}
var actions: Array[Dictionary] = []
var expected_result := TurnManager.BattleResult.ONGOING

func append_action(record: Dictionary) -> void:
	actions.append(record.duplicate(true))

func is_playable() -> bool:
	return schema_version == CURRENT_SCHEMA_VERSION and not configuration.is_empty() and not actions.is_empty()
