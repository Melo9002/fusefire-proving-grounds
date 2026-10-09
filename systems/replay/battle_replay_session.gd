class_name BattleReplaySession
extends RefCounted

static var last_recording

static func store(recording) -> void:
	last_recording = recording

static func has_recording() -> bool:
	return last_recording != null and last_recording.is_playable()

static func save_last(path: String) -> Error:
	if not has_recording(): return ERR_DOES_NOT_EXIST
	return last_recording.save_json(path)

static func load_recording(path: String) -> BattleReplayRecording:
	var loaded := BattleReplayRecording.load_json(path)
	if loaded.is_playable(): last_recording = loaded
	return loaded
