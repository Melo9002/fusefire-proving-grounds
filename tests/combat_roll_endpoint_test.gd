extends SceneTree
## randf is inclusive: a displayed 100% shot must hit even at roll 100.
func _initialize() -> void:
	var failures := 0
	var cases := [[0.0, 0, false], [100.0, 100, true], [99.999, 100, true], [100.0, 99, false], [95.0, 95, false], [94.999, 95, true], [0.0, 1, true], [100.0, 1, false]]
	for sample in cases:
		if AttackActionResult.roll_hits(sample[0], sample[1]) != sample[2]:
			failures += 1
			push_error("Roll %s at chance %s must resolve %s" % sample)
	var old_recording := BattleReplayRecording.new()
	old_recording.simulation_version = "prototype-1.5-defense-direction-10"
	if old_recording.is_playable() or not old_recording.validation_message().contains("Incompatible replay simulation"):
		failures += 1
		push_error("The previous hit-resolution identity must reject explicitly")
	print("Combat roll endpoints: %d checks, %d failure(s)" % [cases.size() + 1, failures])
	quit(1 if failures else 0)
