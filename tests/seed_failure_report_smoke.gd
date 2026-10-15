extends SceneTree

const FailureReporter := preload("res://systems/simulation/seed_failure_reporter.gd")

func _init() -> void:
	var result := AIMatchSimulationResult.new()
	result.seed = 8675309
	result.mission_id = &"rescue_test"
	result.mission_title = "Rescue Test"
	result.status = AIMatchSimulationResult.Status.STALLED
	result.map_source = "generated_cover"
	result.map_size = Vector2i(32, 24)
	result.reason = "Synthetic failure used to verify report serialization."
	result.final_state = "round=4|actor=AllyUnit1"
	result.configuration = {"seed": result.seed, "map_size": [32, 24], "mission_kind": "RESCUE"}
	result.decision_records = [{"actor": "AllyUnit1", "action": "Move", "destination": [12, 0, 8]}]
	result.decision_count = result.decision_records.size()
	result.validation_errors = ["Synthetic validation detail"]
	var test_output := OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR")
	var directory := test_output.path_join("ai_sim_failure_report_smoke") if not test_output.is_empty() else "user://ai_sim_failure_report_smoke"
	var path: String = FailureReporter.save(result, directory)
	var failures := 0
	if path.is_empty() or not FileAccess.file_exists(path):
		failures += 1
		push_error("Failure report was not written.")
	else:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary or int(parsed.get("seed", 0)) != result.seed:
			failures += 1
			push_error("Failure report did not retain its seed.")
		elif parsed.get("decisions", []).size() != 1 or parsed.get("final_state", "") != result.final_state:
			failures += 1
			push_error("Failure report did not retain reproduction details.")
	print("[AISim] Seed failure report serialization — %s" % ("PASSED" if failures == 0 else "FAILED"))
	quit(1 if failures else 0)
