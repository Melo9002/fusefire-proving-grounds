extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	for outcome in [TurnManager.BattleResult.VICTORY, TurnManager.BattleResult.DEFEAT]:
		var terminal := AIMatchSimulator.classify_stop(outcome, 99, 20, 10, 4, 50, 30)
		check(terminal.status == AIMatchSimulationResult.Status.COMPLETED and terminal.reason.is_empty(), "Terminal outcome wins over every reached limit without stale reason")
	check(AIMatchSimulator.classify_stop(TurnManager.BattleResult.ONGOING, 20, 20, 3.9, 4, 29.9, 30).is_empty(), "Ongoing battle below limits continues")
	var timeout := AIMatchSimulator.classify_stop(TurnManager.BattleResult.ONGOING, 20, 20, 0, 4, 30, 30)
	check(timeout.status == AIMatchSimulationResult.Status.TIMEOUT and timeout.reason.contains("30"), "Actual ongoing deadline remains TIMEOUT")
	check(AIMatchSimulator.classify_stop(TurnManager.BattleResult.ONGOING, 20, 20, 4, 4, 10, 30).status == AIMatchSimulationResult.Status.STALLED, "Idle boundary remains STALLED")
	check(AIMatchSimulator.classify_stop(TurnManager.BattleResult.ONGOING, 21, 20, 0, 4, 10, 30).status == AIMatchSimulationResult.Status.ROUND_LIMIT, "Exceeded round limit remains distinct")
	print("AI simulation classification: %d failures" % failures)
	quit(1 if failures else 0)
