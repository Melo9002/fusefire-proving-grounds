extends SceneTree

var failures := 0

func _initialize() -> void:
	var player := BattleReplayPlayer.new()
	# The production recording exposes actions as a property; use the actual
	# lightweight recording type so this remains representative without a battle.
	var recording := BattleReplayRecording.new()
	recording.actions = [
		{"kind": "move", "actor": "PlayerUnit1"},
		{"kind": "aim", "actor": "PlayerUnit1"},
		{"kind": "attack", "actor": "PlayerUnit1"},
		{"kind": "move", "actor": "PlayerUnit2"},
		{"kind": "end_turn", "actor": "PlayerUnit2"},
	]
	player.recording = recording
	check(player.call("_continues_actor_at", 0), "Move into Aim is continuous for the same actor")
	check(player.call("_continues_actor_at", 1), "Aim into Attack is continuous for the same actor")
	check(not player.call("_continues_actor_at", 2), "Changing actors restores the normal replay interval")
	check(not player.call("_continues_actor_at", 3), "End Turn remains a visual sequence boundary")
	check(not player.call("_continues_actor_at", 4), "The last replay record cannot continue")
	player.free()
	print("Replay actor continuity: %d failure(s)" % failures)
	quit(1 if failures else 0)

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
